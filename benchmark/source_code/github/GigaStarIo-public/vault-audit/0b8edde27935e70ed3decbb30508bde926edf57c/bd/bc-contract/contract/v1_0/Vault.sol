// SPDX-License-Identifier: UNLICENSED
// Copyright 2025, GigaStar Technologies LLC, All Rights Reserved, https://gigastar.io
pragma solidity ^0.8.29;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol';

import './ContractUser.sol';
import './IBox.sol';
import './IBoxMgr.sol';
import './IRevMgr.sol';
import './IVault.sol';
import './IXferMgr.sol';
import './LibraryAC.sol';
import './LibraryARI.sol';
import './LibraryBI.sol';
import './LibraryCU.sol';
import './LibraryString.sol';
import './LibraryTI.sol';
import './LibraryUtil.sol';
import './Types.sol';

/// @title Vault: A Governance-controlled manager of instrument revenue and token distribution
/// @author Jason Aubrey, GigaStar
/// @notice Provides a proposal process for instrument revenue tracking, batch token transfers, etc.
/// @dev Governance via proposals with quorum consensus of voters
/// - Voters cast votes via on-chain signing or off-chain via EIP-712
/// - Access control via required roles: admin, voter, agent.
/// - May receive and send native coins as well as ERC-20 and ERC-1155
/// - Upgradeable via UUPS. See PROXY_OPTIONS for more.
/// - Proposals should be built by a single account to prevent race conditions
/// - Revenue flow protocol: REV_FLOW_PROTOCOL
///   1) `InstRevMgr` controls revenue transfers from (normal) deposit addresses and to (correction/fix)
///   2) `XferMgr` controls transfers from the vault to owners
/// - Solidity contracts have competing requirements of being primarily below the max size (24 KB) and secondarily
///   (gas efficient and code quality). While limits can be expanded via utility contracts and dynamic libraries,
///   the complexity is avoided to reduce dev time/maintenance.
/// - Endeavors to support many features despite the previous limitations
/// @custom:api public
/// @custom:deploy uups
// prettier-ignore
contract Vault is Initializable, UUPSUpgradeable, EIP712Upgradeable, IVault, ContractUser {
    // ────────────────────────────────────────────────────────────────────────────
    // Constants
    // ────────────────────────────────────────────────────────────────────────────
    uint constant VERSION = 10;    // 123 => Major: 12, Minor: 3 (always 1 digit)

    string private constant EIP_712_VOTE_DOMAIN_NAME = "Vault";
    string private constant EIP_712_VOTE_DOMAIN_VERSION = "10"; // Sync with VoteTypeHash and clients

    // uint private constant MIN_ALLOWANCE = MAX_ALLOWANCE / 2; // A large value with a large margin after max approval

    // Error codes
    uint constant INVALID_PROP_EXPIRED          = 1;
    uint constant INVALID_PROP_REQ_ID           = 2;
    uint constant INVALID_FIX_DEP_PROP_MISC     = 3;
    uint constant INVALID_FIX_DEP_PROP_TOK_TYPE = 4;
    uint constant INVALID_FIX_DEP_PROP_NO_BOX   = 5;
    uint constant INVALID_INST_REV_PROP_CCY     = 6;
    uint constant INVALID_QUORUM_PROP           = 7;
    uint constant INVALID_ROLE_PROP_LEN         = 8;
    uint constant INVALID_ROLE_PROP_ITEM        = 9;
    uint constant INVALID_XFER_PROP_TOK_TYPE    = 10;
    uint constant INVALID_XFER_PROP_REV_DIST    = 11;

    // `uint` in the func def is ok as long as this string has `uint256` as the ABI replaces `uint` with `uint256`
    bytes32 public constant EIP_712_VOTE_TYPE_HASH
        = 0x2bd3d0368e7d0f01f28c7322350af0251c3832170f540e316dd12128c60b3bf9; // Hardcoded to reduce SIZE
        // = keccak256("ProposalVote(uint256 pid,uint256 expiredAt,uint256 nonce,bool approve,address voter)");

    // ────────────────────────────────────────────────────────────────────────────
    // Fields (See MEM_LAYOUT), default visibility is 'internal'
    // ────────────────────────────────────────────────────────────────────────────
    AC.AccountMgr _accountMgr;                          // Enumerable roles, account->role, etc
    uint _propsCreated;                                 // Seed for next proposal id and count created
    mapping(uint => Prop) _proposals;                   // Key: pid; General proposal info used by all `PropType`
    mapping(uint => FixDepositReq[]) _fixDepositReqs;   // Key: pid; Proposal info specific to `PropType.FixDeposit`
    mapping(uint => AC.RoleRequest[]) _roleReqs;        // Key: pid; Proposal info specific to `PropType.Role`
    mapping(uint => mapping(address => Vote)) _votes;   // Keys: pid, account; Vote
    bool _paused;                                       // Enables only admin actions, for a fix/upgrade

    // New fields should be inserted immediately above this line to preserve layout

    // slither-disable-next-line unused-state (Space reserved for future use - upgradability)
    uint[20] __gap; // Always last field, for upgradeability, reduce size by slots used for new fields

    // ────────────────────────────────────────────────────────────────────────────
    // Functions
    // ────────────────────────────────────────────────────────────────────────────

    // ───────────────────────────────────────
    // Access control
    // ───────────────────────────────────────

    function _requireAdminOrCreator(address caller) private view {
        if (_getRole(caller) == AC.Role.Admin) return;
        if (caller == _contracts[CU.Creator]) return; // Checked last as mostly =0
        revert AC.AccessDenied(caller);
    }

    function _requireVoter(address caller, bool allowAgent, bool allowAdmin) private view {
        AC.Role role = _getRole(caller);
        if (role == AC.Role.Voter) return;
        if (allowAgent && role == AC.Role.Agent) return;
        if (allowAdmin && role == AC.Role.Admin) return;
        revert AC.AccessDenied(caller);
    }

    /// @dev This does not use the base impl to simplfy the callstack
    function _requireOnlyAgent(address caller) internal view override(ContractUser) {
        if (AC.Role.Agent == _getRole(caller)) return;
        revert AC.AccessDenied(caller);
    }

    // ───────────────────────────────────────
    // Payable
    // ───────────────────────────────────────

    /// @dev Accepts plain ETH transfers (no data)
    receive() external payable {
        // No event or forwarding here to ensure gas issues do not block a payment
    }

    /// @dev Accepts ETH with data (e.g. from .call)
    fallback() external payable {
        // No event or forwarding here to ensure gas issues do not block a payment
    }

    // ───────────────────────────────────────
    // Setup
    // ───────────────────────────────────────

    /// @dev Ensures the logic contract cannot be hijacked before the `initializer` runs
    /// - Sets version to `type(uint64).max` + `emit Initialized(version)` to prevent future initialization
    /// - `initialize` is where the business logic is initialized on proxies
    /// - For more info see comments in 'Initializable.sol'
    /// @custom:api private
    constructor() { _disableInitializers(); } // Do not add code to cstr

    /// @dev Basically replaces the constructor in a proxy oriented contract
    /// - `initializer` modifier ensures this function can only be called once during deploy
    /// - See UUPS_UPGRADE_SEQ for details on how to upgrade this contract
    /// @param creator Creator's address for access control during setup
    /// @param reqId Request ID, unique amongst requests across all callers
    /// @param quorum Yays required for a consensus to pass a proposal, also minimum voters
    /// @param roleReqs Must contain adds for >=1 Admin, >=1 Agent, >=`quorum` Voters, only action `Add` allowed
    /// @custom:api protected
    function initialize(address creator, UUID reqId, uint quorum, AC.RoleRequest[] calldata roleReqs)
        external override initializer
    {
        __EIP712_init(EIP_712_VOTE_DOMAIN_NAME, EIP_712_VOTE_DOMAIN_VERSION);
        __ContractUser_init(creator, reqId);
        AC._AccountMgr_init(_accountMgr, quorum, roleReqs);
    }

    /// @dev Upgrade hook to enforce permissions
    /// - Ensure `preUpgrade` is called before this function to stage required params
    function _authorizeUpgrade(address newImpl) internal override(UUPSUpgradeable) {
        _authorizeUpgradeImpl(msg.sender, newImpl);
    }

    /// @notice Accept an admin role after a successfully executed role proposal to add an admin.
    /// A 2 step add intends to reveal a bad address/control as early as possible.
    /// @dev Admin roles go through a 2-step grant process with:
    /// - Step 1) An executed proposal to add an admin marks the action as pending
    /// - Step 2) The new admin calls `acceptAdmin`.
    ///   On failure, a role proposal to Remove the new Admin should be considered ASAP depending on the problem.
    ///   On success, an add will yield a new admin
    /// Throughout the process, errors and events exist to provide feedback and diagnostics
    /// @param seqNumEx =0 for on-chain caller, else expected sequence number for determinism, etc; See `CallTracker`
    /// @param reqId Request ID, unique amongst requests across all callers
    /// @param accept Whether the account is accepting or rejecting the access
    /// @custom:api public
    function acceptAdmin(uint40 seqNumEx, UUID reqId, bool accept) external override {
        address caller = msg.sender;

        // If using sequence number protocol (off-chain caller) then enforce idempotency
        if (_isReqReplay(caller, seqNumEx, reqId)) return;

        AC.adminGrantStep2(_accountMgr, msg.sender, accept); // Access control within call

        _setCallRes(caller, seqNumEx, reqId, true);
    }

    /// @param seqNumEx =0 for on-chain caller, else expected sequence number for determinism, etc; See `CallTracker`
    /// @param reqId Request ID, unique amongst requests across all callers

    /// @dev Approve the manager to direct a token from Vault
    /// @param seqNumEx =0 for on-chain caller, else expected sequence number for determinism, etc; See `CallTracker`
    /// @param reqId Request ID, unique amongst requests across all callers
    /// @param ccy Revenue currency address
    /// @param contractId Manager contract id
    /// @custom:api public
    function approveMgr(uint40 seqNumEx, UUID reqId, address ccy, uint8 contractId) external override {
        address caller = msg.sender;
        _requireAdminOrCreator(caller); // Access control

        if (_paused) revert ContractPaused(); // Occurs after seqNum check for idempotence

        // If using sequence number protocol (off-chain caller) then enforce idempotency
        if (_isReqReplay(caller, seqNumEx, reqId)) return;

        address mgr = _contracts[contractId];
        bool ok = IERC20(ccy).approve(mgr, MAX_ALLOWANCE);
        emit ApprovedMgr(mgr, ccy, MAX_ALLOWANCE);

        _setCallRes(caller, seqNumEx, reqId, ok);
    }

    // ───────────────────────────────────────
    // Getters
    // ───────────────────────────────────────

    /// @dev Get the current version
    function getVersion() external pure override virtual returns(uint) { return VERSION; }

    function _getRole(address account) internal view returns(AC.Role) {
        return _accountMgr.aris.map[account].role; // A shortcut not possible with `getNonce`
    }

    /// @notice Get current quorum
    /// @return quorum Number of `Yay` votes required to pass a proposal
    function getQuorum() external view returns(uint quorum) {
        quorum = _accountMgr.quorum;
    }

    // slither-disable-start uninitialized-state (Accessing items in arrays/maps, zero-value is ok if not found)

    /// @notice Gets current signature (sig) nonce for a given account, used in EIP-712 off-chain signing, this
    /// value is effectively a sequence number
    /// @dev The nonce monotonically increments ONLY when a sig is successfully verified on-chain and call succeeds.
    /// This function returns the next nonce expected by the contract for an off-chain signature.
    ///
    /// Clients must ensure that:
    /// - Signatures are submitted in nonce order
    /// - Either only have a single in-flight sig or ensure a proper sequence for each sig sent
    /// - See NONCE_EXAMPLE for more
    ///
    /// Return value is unchanged when an off-chain sig has not successfully verified since the prev call, eg:
    /// - No sigs were submitted
    /// - Only invalid sigs were submitted
    /// - Sigs are in-flight, delayed, dropped, or mis-ordered
    /// - In-flight issues occurred at client, server, relay, chain gateway, chain (or anywhere between)
    /// - Sig was good but business logic failed and state reverted
    /// - On-chain delays/outages issues occurred due to caller low-gas, high-gas vs limits, congestion, network, etc
    ///
    /// @param account The address to lookup
    function getNonce(address account) external view override returns(uint) {
        if (_getRole(account) == AC.Role.None) return 0;
        return ARI.get(_accountMgr.aris, account).nonce;
    }

    /// @notice Get the last proposal id created
    /// @param pid Proposal ID, identifies an existing proposal
    function getLastPropId() external view override returns(uint pid) {
        return _propsCreated;
    }

    /// @notice Get general proposal info, details should be accessed conditionally:
    /// - PropType.Role: call `getRoleRequests` to get all requests
    /// - PropType.Xfer: call `XferMgr.getProp` and `XferMgr.getXfers`
    /// @param pid Proposal ID, identifies an existing proposal
    function getProp(uint pid) external view override returns(Prop memory) {
        return _proposals[pid];
    }

    // SIZE: ~67 B
    /// @notice Get a proposal's status, a lightweight alternative to `getProp`
    /// @param pid Proposal ID, identifies an existing proposal
    function getPropStatus(uint pid) external view override returns(PropStatus) {
        return _proposals[pid].status;
    }

    /// @notice Get a role proposal's requests
    /// @param pid Proposal ID, identifies an existing proposal
    function getRoleRequests(uint pid) external view override returns(AC.RoleRequest[] memory) {
        return _roleReqs[pid]; // Upper bound: RoleReqLenMax
    }

    /// @notice Get proposal vote info
    /// @param pid Proposal ID, identifies an existing proposal
    /// @return voters Current voters, indexes are aligned with `votes`
    /// @return votes Current votes, indexes are aligned with `voters`
    function getVotes(uint pid) external view override returns(address[] memory voters, Vote[] memory votes)
    { unchecked {
        // Cache vars before loop
        mapping(address => Vote) storage votesByAccount = _votes[pid];
        uint votersLen = _accountMgr.aris.voters.length;

        // Transform storage to results
        voters = new address[](votersLen);
        votes = new Vote[](votersLen);
        for (uint i = 0; i < votersLen; ++i) { // Upper bound: RoleLenMax
            address account = _accountMgr.aris.voters[i].account;
            voters[i] = account;
            votes[i] = votesByAccount[account];
        }
    } }

    /// @notice Get accounts with roles
    /// @return AccountInfo list
    function getAccountInfos() external view override returns(ARI.AccountInfo[] memory) {
        return ARI.getAccountInfos(_accountMgr.aris);
    }

    /// @notice Get Fix Deposit Requests from proposal details (beyond those in `Proposal`)
    /// @param pid Proposal ID, identifies an existing proposal
    /// @return reqs FixDepositReq list
    function getFixDepositReqs(uint pid) external view override returns(FixDepositReq[] memory reqs) {
        // Copy from storage to memory
        FixDepositReq[] storage stored = _fixDepositReqs[pid];
        reqs = new FixDepositReq[](stored.length);
        for (uint i = 0; i < stored.length; ++i) { // Ubound: Stored request length
            reqs[i] = stored[i];
        }
    }

    /// @dev Helper for off-chain clients to reduce the chance of expectation slippage
    /// - EIP-712 defines a bool via uint256(approve ? 1 : 0), `abi.encode` does this already
    function getVoteDigest(uint pid, uint expiredAt, uint nonce, bool approve, address voter)
        public view override returns(bytes32 digest)
    {
        // Inner hash from external params and storage (to ensure caller sync)
        // Following arg types and order must match `EIP_712_VOTE_TYPE_HASH` value
        bytes32 structHash = keccak256(abi.encode(
            EIP_712_VOTE_TYPE_HASH, // Constant input: Hash of struct definition in EIP-712 struct format
            pid,                    // Proposal field: Proposal ID
            expiredAt,              // Proposal field: When the proposal expires, UTC epoch seconds
            nonce,                  // Contract state: Voter's nonce in his contract, to prevent replay
            approve,                // External input: Approval decision
            voter                   // External input: Signer/account/voter
        ));
        // Outer hash from contract params
        digest = EIP712Upgradeable._hashTypedDataV4(structHash);
    }

    // ───────────────────────────────────────
    // Manager contracts (SIZE: ~0.3 KB) - Removed due to size limit
    // ───────────────────────────────────────

    // /// @return An IBoxMgr instance address
    // function getBoxMgr() external view override returns(address) { return _contracts[CU.BoxMgr]; }

    // /// @return An IEarnDateMgr instance address
    // function getEarnDateMgr() external view override returns(address) { return _contracts[CU.EarnDateMgr]; }

    // /// @return An IRevMgr instance address
    // function getRevMgr() external view override returns(address) { return _contracts[CU.RevMgr]; }

    // /// @return An IInstRevMgr instance address
    // function getInstRevMgr() external view override returns(address) { return _contracts[CU.InstRevMgr]; }

    // /// @return An IXferMgr instance address
    // function getXferMgr() external view override returns(address) { return _contracts[CU.XferMgr]; }

    // slither-disable-end uninitialized-state

    // ───────────────────────────────────────
    // Proposal management
    // ───────────────────────────────────────

    /// @notice Creates a new role proposal to add/delete an account in a role
    /// - Next: Approve and inline-execution
    /// - Prop Inspect: `getProp` + `getRoleRequests`
    /// - Success: emits PropCreated, PropSealed, returns pid > 0
    /// - Failure: revert
    /// - Access by role: Agent, Admin or Voter
    /// @dev Normally an agent will make proposals but voters are allowed to resolve a compromised agent
    /// @param seqNumEx =0 for on-chain caller, else expected sequence number for determinism, etc; See `CallTracker`
    /// @param reqId Request ID, unique amongst requests across all callers
    /// @param expiredAt When expired, epoch seconds UTC, no significant activity after this time
    /// @param roleReqs Role changes
    /// @custom:api public
    function createRoleProp(uint40 seqNumEx, UUID reqId, uint expiredAt, AC.RoleRequest[] calldata roleReqs) external {
        uint len = roleReqs.length;
        if (len < 1 || AC.RoleReqLenMax < len) revert InvalidInput(INVALID_ROLE_PROP_LEN);
        for (uint i = 0; i < len; ++i) { // Ubound: Caller must page
            AC.RoleRequest calldata rr = roleReqs[i];
            if (rr.account == AddrZero || rr.role <= AC.Role.None || AC.Role.Count <= rr.role) {
                revert InvalidInput(INVALID_ROLE_PROP_ITEM);
            }
        }
        // Access controlled
        uint pid = _createProp(msg.sender, seqNumEx, reqId, expiredAt, PropType.Role, true);
        _roleReqs[pid] = roleReqs;
    }

    /// @notice Creates a new fix deposit proposal to resolve an incorrect deposit (wrong qty or address).
    /// - Balance and approval are not checked (SIZE), can be checked out-of-band during approval
    /// - Next: Approve and inline-execution
    /// - Prop Inspect: `getProp` + `getFixDepositReq`
    /// - Success: emits PropCreated, PropSealed, returns pid > 0
    /// - Failure: revert
    /// - Access by role: Agent
    /// @param seqNumEx =0 for on-chain caller, else expected sequence number for determinism, etc; See `CallTracker`
    /// @param reqId Request ID, unique amongst requests across all callers
    /// @param expiredAt When expired, epoch seconds UTC, no significant activity after this time
    /// @param reqs Fix deposit requests, see struct definition
    /// @custom:api public
    function createFixDepositProp(uint40 seqNumEx, UUID reqId, uint expiredAt, FixDepositReq[] calldata reqs) external
    {
        // Access controlled
        uint pid = _createProp(msg.sender, seqNumEx, reqId, expiredAt, PropType.FixDeposit, true);
        FixDepositReq[] storage propReqs = _fixDepositReqs[pid];

        for (uint i = 0; i < reqs.length; ++i) { // Ubound: Caller must page
            FixDepositReq calldata req = reqs[i];
            if (req.to == AddrZero || req.qty == 0 || req.ti.tokAddr == AddrZero) {
                revert InvalidInput(INVALID_FIX_DEP_PROP_MISC);
            }
            if (req.ti.tokType >= TI.TokenType.Count) {
                revert InvalidInput(INVALID_FIX_DEP_PROP_TOK_TYPE);
            }
            if (!IBoxMgr(_contracts[CU.BoxMgr]).boxExists(req.instName, true)) {
                revert InvalidInput(INVALID_FIX_DEP_PROP_NO_BOX);
            }

            // Store requests
            propReqs.push(req);
            propReqs[i].instNameKey = String.toBytes32Mem(req.instName);
        }
    }

    /// @notice Creates a new transfer proposal
    /// - Next: `IXferMgr.propAddXfers` + `sealXferProp` + approve + `propExecute`
    ///     - `IXferMgr.propPruneXfers` can be used to skip transfers in an approved prop (escape hatch)
    /// - Prop Inspect: `getProp` + `IXferMgr.getPropHdr` + `IXferMgr.getXfer*`
    /// - Success: emits PropCreated, returns pid > 0
    /// - Failure: revert
    /// - Access by role: Agent
    /// @dev `appendXfers` is `external` for less gas/code
    /// @param seqNumEx =0 for on-chain caller, else expected sequence number for determinism, etc; See `CallTracker`
    /// @param reqId Request ID, unique amongst requests across all callers
    /// @param expiredAt When expired, epoch seconds UTC, no significant activity after this time
    /// @param ti TokenInfo, see struct definition
    /// @param isRevDist Whether this transfer is a revenue distribution
    /// @custom:api public
    function createXferProp(uint40 seqNumEx, UUID reqId, uint expiredAt, TI.TokenInfo calldata ti, bool isRevDist)
        external
    {
        bool validTokenAddr = (ti.tokAddr == AddrZero) == (ti.tokType == TI.TokenType.NativeCoin);
        if (ti.tokType >= TI.TokenType.Count || !validTokenAddr) revert InvalidInput(INVALID_XFER_PROP_TOK_TYPE);
        if (isRevDist && ti.tokType != TI.TokenType.Erc20) revert InvalidInput(INVALID_XFER_PROP_REV_DIST);

        // Access controlled
        uint pid = _createProp(msg.sender, seqNumEx, reqId, expiredAt, PropType.Xfer, false);

        IXferMgr(_contracts[CU.XferMgr]).propCreate(pid, reqId, ti, isRevDist);
    }

    /// @notice Creates a new instrument revenue proposal
    /// - Next: `IInstRevMgr.propAddInstRev` + `IRevMgr.propAddOwners` + `sealInstRevProp` + approve + `propExecute`
    /// - Prop Inspect: `getProp` + `IInstRevMgr.getPropHdr` + `IInstRevMgr.getInstRev*`
    /// - Success: emits PropCreated, returns pid > 0
    /// - Failure: revert
    /// - Access by role: Agent
    /// @param seqNumEx =0 for on-chain caller, else expected sequence number for determinism, etc; See `CallTracker`
    /// @param reqId Request ID, unique amongst requests across all callers
    /// @param expiredAt When expired, epoch seconds UTC, no significant activity after this time
    /// @param ccyAddr Revenue currency address
    /// @param correction Whether the proposal is a correction
    /// @custom:api public
    function createInstRevProp(uint40 seqNumEx, UUID reqId, uint expiredAt, address ccyAddr, bool correction) external
    {
        if (ccyAddr == AddrZero) revert InvalidInput(INVALID_INST_REV_PROP_CCY);

        // Access controlled
        uint pid = _createProp(msg.sender, seqNumEx, reqId, expiredAt, PropType.InstRev, false);

        IRevMgr(_contracts[CU.RevMgr]).propCreate(pid, reqId, ccyAddr, correction);
    }

    /// @notice Creates a new quorum proposal
    /// - Next: Approve and inline-execution
    /// - Prop Inspect: `getProp`
    /// - Success: emits PropCreated, PropSealed, returns pid > 0
    /// - Failure: revert
    /// - Access by role: Agent
    /// @dev CallRes.rc >0 on success (pid), else 0
    /// @param seqNumEx =0 for on-chain caller, else expected sequence number for determinism, etc; See `CallTracker`
    /// @param reqId Request ID, unique amongst requests across all callers
    /// @param expiredAt When expired, epoch seconds UTC, no significant activity after this time
    /// @param quorum Votes required to approve a proposal
    /// @custom:api public
    function createQuorumProp(uint40 seqNumEx, UUID reqId, uint expiredAt, uint quorum) external {
        uint votersLen = _accountMgr.aris.voters.length;
        if (quorum == _accountMgr.quorum || quorum < 1 || quorum > AC.RoleLenMax || quorum > votersLen) {
            revert InvalidInput(INVALID_QUORUM_PROP);
        }

        // Access controlled
        uint pid = _createProp(msg.sender, seqNumEx, reqId, expiredAt, PropType.Quorum, true);

        _proposals[pid].quorum = quorum;
    }

    /// @dev Create proposal helper to reduce SIZE
    function _createProp(address caller, uint40 seqNumEx, UUID reqId, uint expiredAt, PropType propType, bool isSealed)
        private returns(uint pid)
    {
        _requireOnlyAgent(caller);            // Access control
        if (_paused) revert ContractPaused(); // Occurs before seqNum check for idempotence

        // General input validation

        // If using sequence number protocol (off-chain caller) then enforce idempotency
        if (_isReqReplay(caller, seqNumEx, reqId)) return pid;

        if (block.timestamp >= expiredAt) revert InvalidInput(INVALID_PROP_EXPIRED);
        if (isEmpty(reqId)) revert InvalidInput(INVALID_PROP_REQ_ID);

        // General proposal init
        pid = ++_propsCreated;  // See UINT_ROLLOVER
        Prop storage prop = _proposals[pid];
        prop.pid = pid;
        prop.creator = caller;
        prop.createdAt = block.timestamp;
        prop.expiredAt = expiredAt;
        prop.eid = reqId;
        prop.propType = propType;
        prop.status = isSealed ? PropStatus.Sealed : PropStatus.Pending;

        // While not completely initialized, emit + CallRes here saves SIZE and functionally equiv vs happening later
        emit PropCreated(pid, reqId, caller, isSealed);
        _setCallRes(caller, seqNumEx, reqId, uint16(pid), 0, 0);

        // Proposal specific init happens next
    }

    /// @notice Seals an instrument revenue proposal
    /// - Success: `ok=true`, conditionally emits PropSealed
    /// - Access by role: Agent
    /// @dev CallRes.rc Indicates progress:
    ///     - Ok        : Proposal upload complete
    ///     - NoProp    : No proposal found by pid
    ///     - DiffLens  : Different count of instrument revenues and owner snapshots
    /// @param seqNumEx =0 for on-chain caller, else expected sequence number for determinism, etc; See `CallTracker`
    /// @param reqId Request ID, unique amongst requests across all callers
    /// @custom:api public
    function sealInstRevProp(uint40 seqNumEx, UUID reqId, uint pid) external override {
        address caller = msg.sender;
        _requireOnlyAgent(caller); // Access control

        if (_paused) revert ContractPaused(); // Occurs after seqNum check for idempotence

        // If using sequence number protocol (off-chain caller) then enforce idempotency
        if (_isReqReplay(caller, seqNumEx, reqId)) return;

        (IRevMgr.PropRevFinalRc rc, PropStatus status) = _sealInstRevProp(pid);

        _setCallRes(caller, seqNumEx, reqId, uint16(rc), uint16(status), 0);
    }

    function _sealInstRevProp(uint pid) internal returns(IRevMgr.PropRevFinalRc rc, PropStatus status) {
        Prop storage prop = _proposals[pid];
        bool expired;
        (expired, status) = _lazySetExpired(pid, prop);
        if (expired || status == PropStatus.Sealed || prop.propType != PropType.InstRev) return (rc, status);

        // Finalize an instrument revenue proposal
        rc = IRevMgr(_contracts[CU.RevMgr]).propFinalize(pid);
        if (rc != IRevMgr.PropRevFinalRc.Ok) return (rc, status);

        status = PropStatus.Sealed;
        prop.status = status;
        emit PropSealed(pid, prop.eid);
    }

    /// @notice Seals a transfer proposal
    /// - Success: `ok=true`, conditionally emits PropSealed
    /// - Access by role: Agent
    /// @dev CallRes.rc Indicates progress:
    ///     - Ok       : Proposal upload complete
    ///     - NoProp   : No proposal found by pid
    ///     - BadTotal : Total qty in header differs from the sum of transfers
    /// @param seqNumEx =0 for on-chain caller, else expected sequence number for determinism, etc; See `CallTracker`
    /// @param reqId Request ID, unique amongst requests across all callers
    /// @custom:api public
    function sealXferProp(uint40 seqNumEx, UUID reqId, uint pid) external override {
        address caller = msg.sender;
        _requireOnlyAgent(caller); // Access control

        if (_paused) revert ContractPaused(); // Occurs after seqNum check for idempotence

        // If using sequence number protocol (off-chain caller) then enforce idempotency
        if (_isReqReplay(caller, seqNumEx, reqId)) return;

        (IXferMgr.PropXferFinalRc rc, PropStatus status) = _sealXferProp(pid);

        _setCallRes(caller, seqNumEx, reqId, uint16(rc), uint16(status), 0);
    }

    function _sealXferProp(uint pid) internal
        returns(IXferMgr.PropXferFinalRc rc, PropStatus status)
    {
        Prop storage prop = _proposals[pid];
        { // var scope to reduce stack pressure
            bool expired;
            (expired, status) = _lazySetExpired(pid, prop);
            if (expired || status == PropStatus.Sealed || prop.propType != PropType.Xfer) return (rc, status);
        }

        address xferMgrAddr = _contracts[CU.XferMgr];
        IXferMgr xferMgr = IXferMgr(xferMgrAddr);

        // Removed due to size limit (SIZE: ~1.3 KB)
        // // Block to ensure XferMgr is authorized to transfer from the Vault, this is defensive as the maximum
        // // allowance should be granted during contract setup and should be sufficient to never require an increase
        // IXferMgr.PropHdr memory ph = xferMgr.getPropHdr(pid);
        // if (ph.ti.tokType != TI.TokenType.NativeCoin) { // NativeCoin xfers are delegated, no approval needed
        //     address vaultAddr = address(this);
        //     // Ensure XferMgr is allowed to transfer token from vault
        //     if (ph.ti.tokType == TI.TokenType.Erc20) {
        //         IERC20 ccy = IERC20(ph.ti.tokAddr);
        //         uint allowance = ccy.allowance(vaultAddr, xferMgrAddr);
        //         if (allowance < MIN_ALLOWANCE) { // then increase transferMgr allowance to spend from Vault
        //             if (!ccy.approve(xferMgrAddr, MAX_ALLOWANCE)) return (IXferMgr.PropXferFinalRc.LowAllow, status);
        //         }
        //     } else { // Erc1155 || Erc1155Crt
        //         IERC1155 token = IERC1155(ph.ti.tokAddr);
        //         if (!token.isApprovedForAll(vaultAddr, xferMgrAddr)) {
        //             bool ok = true;
        //             try token.setApprovalForAll(xferMgrAddr, true) {} catch { ok = false; }
        //             if (!ok) return (IXferMgr.PropXferFinalRc.LowAllow, status);
        //         }
        //     }
        // }

        // Finalize an instrument revenue proposal
        rc = xferMgr.propFinalize(pid);
        if (rc != IXferMgr.PropXferFinalRc.Ok) return (rc, status);

        status = PropStatus.Sealed;
        prop.status = status;
        emit PropSealed(pid, prop.eid);
    }

    /// @notice Withdraw a proposal, moves the proposal into a final state
    /// - Success: `status = PropStatus.Withdrawn`, emits PropWithdrawn
    /// @param seqNumEx =0 for on-chain caller, else expected sequence number for determinism, etc; See `CallTracker`
    /// @param reqId Request ID, unique amongst requests across all callers
    /// @param pid Proposal ID, identifies an existing proposal created by the caller
    /// @custom:api public
    function withdrawProp(uint40 seqNumEx, UUID reqId, uint pid) external override {
        address caller = msg.sender;

        // If using sequence number protocol (off-chain caller) then enforce idempotency
        if (_isReqReplay(caller, seqNumEx, reqId)) return;

        Prop storage prop = _proposals[pid];
        if (prop.pid != pid) return;

        // Access control: Allow the PROPOSAL creator or Admin, prevents a rogue agent DoS
        if (prop.creator != caller && _getRole(caller) != AC.Role.Admin) revert AC.AccessDenied(caller);

        PropStatus status = prop.status;
        if (!_isFinal(status)) {
            status = (status == PropStatus.Executing) ? PropStatus.WithdrawnExec : PropStatus.Withdrawn;
            prop.status = status;
            emit PropWithdrawn(pid, prop.eid, status == PropStatus.Executing);
        }

        _setCallRes(caller, seqNumEx, reqId, uint16(status), 0, 0);
    }

    // ───────────────────────────────────────
    // Proposal exercise
    // ───────────────────────────────────────

    /// @notice Cast a vote on a sealed proposal by signing an on-chain tx
    /// A proposal is decided when a quorum of approvals occurs or becomes impossible.
    /// - Success: emits PropVoted, conditionally PropDecided or inline proposal events + PropExecuted
    /// - Access by role: Voter
    /// - See `_castVote` for more
    /// @param seqNumEx =0 for on-chain caller, else expected sequence number for determinism, etc; See `CallTracker`
    /// @param reqId Request ID, unique amongst requests across all callers
    /// @param pid Proposal ID, identifies an existing proposal
    /// @param approve Whether the voter authorizes the proposal, true=Yay, false=Nay
    /// @custom:api public
    function castVote(uint40 seqNumEx, UUID reqId, uint pid, bool approve) external override {
        address caller = msg.sender;
        _requireVoter(caller, false, false); // Access control

        if (_paused) revert ContractPaused(); // Occurs after seqNum check for idempotence

        // If using sequence number protocol (off-chain caller) then enforce idempotency
        if (_isReqReplay(caller, seqNumEx, reqId)) return;

        // slither-disable-next-line uninitialized-local (zero-init is ok)
        CastVoteRes memory result;
        Prop storage prop = _proposals[pid];
        if (prop.pid != pid) { result.rc = CastVoteRc.NoProp;
        } else {
            _updateNonce(ARI.get(_accountMgr.aris, caller));
            result = _castVote(prop, pid, approve, caller);
        }

        _setCallRes(caller, seqNumEx, reqId, uint16(result.rc), uint16(result.vote), 0);
    }

    /// @notice Cast a vote on a sealed proposal by signing an off-chain tx and relaying it via the agent (EIP-721)
    /// - Success: emits PropVoted, conditionally PropDecided or inline-execution events + PropExecuted
    /// - Access by role: Agent relay (off-chain signed by Voter)
    /// - See `_castVote` for more
    /// @param seqNumEx =0 for on-chain caller, else expected sequence number for determinism, etc; See `CallTracker`
    /// @param reqId Request ID, unique amongst requests across all callers
    /// @param req See struct definition
    /// @custom:api public
    function castVoteRelay(uint40 seqNumEx, UUID reqId, CastVoteRelayReq memory req) external override {
        address caller = msg.sender;
        _requireOnlyAgent(caller); // Access control 1: Only agent may relay

        if (_paused) revert ContractPaused(); // Occurs after seqNum check for idempotence

        // If using sequence number protocol (off-chain caller) then enforce idempotency
        if (_isReqReplay(caller, seqNumEx, reqId)) return;

        // Cache state before analysis
        // slither-disable-next-line uninitialized-local (zero-init is ok)
        CastVoteRes memory result;
        Prop storage prop = _proposals[req.pid];
        if (prop.pid != req.pid) {
            result.rc = CastVoteRc.NoProp;
        } else {
            { // var scope to reduce stack pressure
                // Access control 2: Off-chain signature matches `voter` which has voter role

                // Recover the signer
                ARI.AccountInfo storage aiVoter = ARI.get(_accountMgr.aris, req.voter);
                address signer = ECDSA.recover(
                    getVoteDigest(req.pid, prop.expiredAt, aiVoter.nonce, req.approve, req.voter),
                        req.v, req.r, req.s);

                // Ensure `signer` matches the `voter` claim (no delgation/impersonation)
                if (signer != req.voter) {
                    // Event provides context to analyze failure
                    emit SignerErr(req.pid, req.approve, req.voter, aiVoter.nonce, prop.expiredAt, signer);
                    result.rc = CastVoteRc.SigSigner;
                } else {
                    // Ensure `signer` has the Voter role
                    if (aiVoter.role == AC.Role.Voter) {
                        _updateNonce(aiVoter);
                    } else {
                        result.rc = CastVoteRc.SigRole;
                    }
                }
            }
            if (result.rc == CastVoteRc.Success) {
                result = _castVote(prop, req.pid, req.approve, req.voter);
            }
        }
        _setCallRes(caller, seqNumEx, reqId, uint16(result.rc), uint16(result.vote), 0);
    }

    function _updateNonce(ARI.AccountInfo storage ai) internal {
        uint nonce = ai.nonce + 1;
        ai.nonce = nonce;
        if (nonce > _accountMgr.peakNonce) _accountMgr.peakNonce = nonce;
    }

    /// @dev Centralized vote casting, entered via on-chain or off-chain signing
    /// - A proposal is decided in a multiple ways:
    ///     1) if count(Yay) == quorum then status is `Passed`
    ///     2) if (count(NoVote) - count(Nay)) < quorum then status is `Rejected`
    ///     3) CONCURRENT_QUORUM: `quorum` may change while props are `Pending`. For example, if a pending prop has
    ///        2 Yay votes and then quorum changes 3 => 2, the pending prop now has enough votes to pass but a
    ///        voter needs to vote again (a new or duplicate vote) to nudge/trigger it into a `Passed` state.
    ///        This nudge/trigger is unlikely to ever be needed but it ensures a quorum update is O(1).
    function _castVote(Prop storage prop, uint pid, bool approve, address voter) internal
        returns(CastVoteRes memory result)
    {
        mapping(address => Vote) storage votes = _votes[pid];
        // Voting only allowed while proposal is Sealed
        (bool expired, PropStatus status) = _lazySetExpired(pid, prop);
        if (expired || status != PropStatus.Sealed) { result.rc = CastVoteRc.Status; return result; }

        // Another vote for the same proposal? Proposal is not sealed so change is ok
        uint countYay = prop.countYay;
        uint countNay = prop.countNay;
        result.vote = votes[voter];
        if (result.vote != Vote.None) { // then already voted
            // Allow the vote to be changed (only when proposal is not final to avoid a zombie proposal apocalypse)
            if ((approve && result.vote == Vote.Yay) || (!approve && result.vote == Vote.Nay)) {
                result.rc = CastVoteRc.NoChange;
                return result;
            }

            // Reverse the previous vote
            if (result.vote == Vote.Yay) { --countYay; } else { --countNay; }
        }

        // Tally and record the vote
        if (approve) {
            ++countYay;
            result.vote = Vote.Yay;
        } else {
            ++countNay;
            result.vote = Vote.Nay;
        }
        prop.countYay = countYay;
        prop.countNay = countNay;
        votes[voter] = result.vote;
        UUID reqId = prop.eid;
        uint quorum = _accountMgr.quorum;

        // CONCURRENT_QUORUM: `quorum` may change while proposals are `Pending` hence the defensive '>= quorum'
        Vote propResult = countYay >= quorum ? Vote.Yay
            : (_accountMgr.aris.voters.length - countNay < quorum ? Vote.Nay : Vote.None);
        emit PropVoted(pid, reqId, voter, approve, propResult);

        if (propResult == Vote.Yay) {
            prop.status = PropStatus.Passed;

            // Execute proposals inline to:
            // 1) Provide a no-agent-veto path via on-chain sig, otherwise agent has potential for an
            //    implicit veto (ignore prop) if off-chain sig as the Agent does the relay
            // 2) Reduce bytecode by avoiding another execution function - This is a big motivation
            // NOTE: an execution that reverts will require another `Yay` vote to re-run after resolving the error
            if (prop.propType == PropType.Role) {
                AC.roleApplyRequestsFromStore(_accountMgr, _roleReqs[pid]); // may revert and uncast vote
                _onPropExecuted(pid, reqId, prop);
            } else if (prop.propType == PropType.Quorum) {
                uint newQuorum = prop.quorum;
                AC.setQuorum(_accountMgr, newQuorum); // may revert and uncast vote
                _onPropExecuted(pid, reqId, prop);
            } else if (prop.propType == PropType.FixDeposit) {
                // Xfer funds from deposit box(s) to corrected address(s)
                { // var scope to reduce stack pressure
                    FixDepositReq[] storage reqs = _fixDepositReqs[pid];
                    for (uint i = 0; i < reqs.length; ++i) {
                        FixDepositReq memory req = reqs[i];
                        IBox.PushResult memory pr =
                            IBoxMgr(_contracts[CU.BoxMgr]).push(req.instName, req.to, req.ti, req.qty);

                        if (pr.rc != IBox.PushRc.Success ) revert FixDepositFailed(pid, reqId, pr.rc); // Allow retry
                    }
                }
                _onPropExecuted(pid, reqId, prop);
            }
        } else if (propResult == Vote.Nay) { // then insufficient pending votes to pass
            prop.status = PropStatus.Rejected;
        }
        // result = CastVoteRc.Success; set implicitly via zero-value init
    }

    /// @dev Execute an instrument revenue proposal as gas allows, progress given by return code
    /// - This wrapper around `propExecute` ensures the proposal status is respected and updated
    /// - See `RevMgr.propExecute` for more details
    /// @param seqNumEx =0 for on-chain caller, else expected sequence number for determinism, etc; See `CallTracker`
    /// @param reqId Request ID, unique amongst requests across all callers
    /// @param pid Proposal ID
    /// @custom:callresult result Indicates progress where `rc` is set from `ExecRevRc`
    /// - Progress: Partial progress
    /// - Done: Proposal is complete
    /// - NoProp: No proposal found by pid
    /// - PartProp: Partial proposal found, not fully uploaded
    /// - LowFunds: Insufficient funds at instrument's deposit address
    /// @custom:api public
    function execInstRevProp(uint40 seqNumEx, UUID reqId, uint pid) external override {
        address caller = msg.sender;
        _requireOnlyAgent(caller); // Access control

        if (_paused) revert ContractPaused(); // Occurs after seqNum check for idempotence

        // If using sequence number protocol (off-chain caller) then enforce idempotency
        if (_isReqReplay(caller, seqNumEx, reqId)) return;

        ICallTracker.CallRes memory result = _execInstRevProp(pid);

        _setCallRes(caller, seqNumEx, reqId, result.rc, result.lrc, result.count); // See SET_CR_LESS_SIGS
    }

    /// @dev Helper simplifies caller via early returns
    function _execInstRevProp(uint pid) internal returns(CallRes memory result) {
        Prop storage prop = _proposals[pid];
        (bool expired, PropStatus status) = _lazySetExpired(pid, prop);
        if (status == PropStatus.Executed) {
            result.rc = uint16(IRevMgr.ExecRevRc.Done);
            return result;
        }
        if (expired || !(status == PropStatus.Executing || status == PropStatus.Passed)) {
            result.rc = uint16(IRevMgr.ExecRevRc.PropStat);
            return result;
        }

        // Delegate the execution, (necessary to reduce contract size)
        result = IRevMgr(_contracts[CU.RevMgr]).propExecute(pid);

        if (result.rc == uint16(IRevMgr.ExecRevRc.Done)) {
            _onPropExecuted(pid, prop.eid, prop);
        } else if (status == PropStatus.Passed) {
            prop.status = PropStatus.Executing; // Value in a proposal after 1st page exec and before done
        }
    }

    /// @dev Execute a transfer proposal as gas allows, progress given by return code
    /// - This wrapper around `propExecute` ensures the proposal status is respected and updated
    /// - See `RevMgr.propExecute` for more details
    /// @param seqNumEx =0 for on-chain caller, else expected sequence number for determinism, etc; See `CallTracker`
    /// @param reqId Request ID, unique amongst requests across all callers
    /// @param pid Proposal ID
    /// @custom:callresult Indicates progress where `rc` is set from `ExecXferRc`
    /// - Progress: Partial progress
    /// - Done: Proposal is complete
    /// - NoProp: No proposal found by pid
    /// @custom:api public
    function execXferProp(uint40 seqNumEx, UUID reqId, uint pid) external override {
        address caller = msg.sender;
        _requireOnlyAgent(caller); // Access control

        if (_paused) revert ContractPaused(); // Occurs after seqNum check for idempotence

        // If using sequence number protocol (off-chain caller) then enforce idempotency
        if (_isReqReplay(caller, seqNumEx, reqId)) return;

        Prop storage prop = _proposals[pid];
        (bool expired, PropStatus status) = _lazySetExpired(pid, prop);
        IXferMgr xferMgr = IXferMgr(_contracts[CU.XferMgr]);

        // slither-disable-next-line uninitialized-local (zero-init is ok)
        ICallTracker.CallRes memory result;
        if (status == PropStatus.Executed) {
            result.count = uint16(xferMgr.getXfersLen(pid));
            result.rc = uint16(IXferMgr.ExecXferRc.Done);
        } else if (expired || !(status == PropStatus.Executing || status == PropStatus.Passed)) {
            result.rc = uint16(IXferMgr.ExecXferRc.PropStat);
        } else {
            // Delegate the execution to reduce contract size
            result = xferMgr.propExecute(pid);
            if (result.rc == uint16(IXferMgr.ExecXferRc.Done)) {
                _onPropExecuted(pid, prop.eid, prop);
            } else if (status == PropStatus.Passed) {
                prop.status = PropStatus.Executing; // Value in a proposal after 1st page exec and before done
            }
        }
        _setCallRes(caller, seqNumEx, reqId, result.rc, result.lrc, result.count); // See SET_CR_LESS_SIGS
    }

    /// @dev Native coins may only be sent by the owner, so the XferMgr must callback to send from Vault
    /// - Validation happens upstream; try catch not possible
    /// @param to new owner
    /// @param qty value to be transfered
    /// @return sent Whether the transfer was successful
    /// @custom:api private
    function xferNative(address to, uint qty) external override returns(bool sent) {
        _requireOnlyXferMgr(msg.sender); // Access control

        checkZeroAddr(to); // Validation happens upstream, but double-checking this for sanity

        // slither-disable-start low-level-calls (A native coin operation requires a low-level call)

        // See TRANSFER_FAILURE, `.call` is low-level, no try/catch guard allowed
        (sent, ) = payable(to).call{ value: qty }('');

        // slither-disable-end low-level-calls
    }

    // ───────────────────────────────────────
    // Proposal Status
    // ───────────────────────────────────────

    /// @dev Returns whether a status is in a final/terminal state. See PROP_STATUS.
    /// @param status: subject of the test
    /// @return Whether the status is a final state
    function _isFinal(PropStatus status) private pure returns(bool) {
        return status < PropStatus.FinalPartition;
    }

    /// @dev Called when a proposal is fully executed
    /// @param pid Proposal ID, identifies an existing proposal
    /// @param reqId Request ID
    /// @param prop Proposal to be updated
    function _onPropExecuted(uint pid, UUID reqId, Prop storage prop) private {
        prop.executedAt = block.timestamp;
        prop.status = PropStatus.Executed;
        emit PropExecuted(pid, reqId);
    }

    /// @dev The status is set lazily to remove the need (and lack of) a periodic tick/hook
    /// @param pid Proposal ID, identifies an existing proposal
    /// @param prop: Subject of the query/action
    /// @return expired Whether the proposal status is PropStatus.Expired
    /// @return status Proposal status
    function _lazySetExpired(uint pid, Prop storage prop) private returns(bool expired, PropStatus status) {
        status = prop.status;
        expired = prop.expiredAt <= block.timestamp; // See BLOCK_TIMESTAMP
        if (expired && !_isFinal(status)) {
            prop.status = status = PropStatus.Expired;
            emit PropExpired(pid, prop.eid, prop.expiredAt);
        }
    }

    // ───────────────────────────────────────
    // IPausable
    // ───────────────────────────────────────

    /// @notice Enable/Disable significant contract activity
    /// @param seqNumEx =0 for on-chain caller, else expected sequence number for determinism, etc; See `CallTracker`
    /// @param reqId Request ID, unique amongst requests across all callers
    function pause(uint40 seqNumEx, UUID reqId, bool value) external override {
        address caller = msg.sender;
        _requireAdminOrCreator(caller); // Access control

        // If using sequence number protocol (off-chain caller) then enforce idempotency
        if (_isReqReplay(caller, seqNumEx, reqId)) return;

        _paused = value;
        emit Paused(value, caller);

        _setCallRes(caller, seqNumEx, reqId, true);
    }

    /// @notice Returns whether the contract is paused
    function paused() external view override returns(bool) { return _paused; }

    // ───────────────────────────────────────
    // IRoleMgr
    // ───────────────────────────────────────

    /// @notice Get account's role, zero-value if not found
    function getRole(address account) public view override returns(AC.Role) {
        return _getRole(account);
    }
}
