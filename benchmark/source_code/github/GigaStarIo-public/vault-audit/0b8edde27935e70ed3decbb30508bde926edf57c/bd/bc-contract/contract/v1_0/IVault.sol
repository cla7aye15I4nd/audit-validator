// SPDX-License-Identifier: UNLICENSED
// Copyright 2025, GigaStar Technologies LLC, All Rights Reserved, https://gigastar.io
pragma solidity ^0.8.29;

import './IBox.sol';
import './IContractUser.sol';
import './IPausable.sol';
import './IRevMgr.sol';
import './IRoleMgr.sol';
import './IVersion.sol';
import './IXferMgr.sol';
import './LibraryAC.sol';
import './LibraryARI.sol';
import './LibraryTI.sol';
import './Types.sol';

/// @dev Governance via proposals with quorum consensus of voters, a primary contract for off-chain usage
// prettier-ignore
interface IVault is IPausable, IRoleMgr, IContractUser {
    // ────────────────────────────────────────────────────────────────────────────
    // Types
    // ────────────────────────────────────────────────────────────────────────────

    // ───────────────────────────────────────
    // Enums
    // ───────────────────────────────────────
    // Every first enum item must be a suitable zero-value
    enum Vote       { None, Yay, Nay }
    enum CastVoteRc { Success, NoProp, Role, SigSigner, SigRole, Status, NoChange }
    enum PropType   { None, InstRev, FixDeposit, Xfer, Role, Quorum,
                      Count // Metadata: Used for input validation; Must remain last item
                    }
    enum PropStatus { NoProp, Executed, Expired, Rejected, Withdrawn, WithdrawnExec,
                      Reserved1, Reserved2, Reserved3, // Reserved items to make higher values stable
                      FinalPartition, // Metadata: Preceding are final/terminal. See PROP_STATUS.
                      Executing, Passed, Sealed, Pending }
    enum FixDepositRc { Done, PropStat, NoBox, NoXfer }

    // ───────────────────────────────────────
    // Events
    // ───────────────────────────────────────

    // Proposal
    event PropCreated(uint indexed pid, UUID indexed eid, address indexed creator, bool isSealed);
    event PropSealed(uint indexed pid, UUID indexed eid);
    event PropVoted(uint indexed pid, UUID indexed eid, address indexed voter, bool voteApprove, Vote propResult);
    event PropExecuted(uint indexed pid, UUID indexed eid);
    event PropWithdrawn(uint indexed pid, UUID indexed eid, bool partialExec);
    event PropExpired(uint indexed pid, UUID indexed eid, uint expiredAt);

    event SignerErr(uint pid, bool approve, address voter, uint nonce, uint expiredAt, address signer);
    event ApprovedMgr(address mgr, address ccy, uint allowance);

    // ───────────────────────────────────────
    // Errors
    // ───────────────────────────────────────
    error FixDepositFailed(uint pid, UUID eid, IBox.PushRc rc);
    error InvalidInput(uint input); // Generic to save SIZE

    // ───────────────────────────────────────
    // Aliases
    // ───────────────────────────────────────

    // ───────────────────────────────────────
    // Structs (See MEM_LAYOUT)
    // ───────────────────────────────────────

    /// @dev Generic proposal info, tracks core state for all proposals
    /// - The most simple proposals only use this type, otherwise supplemental info is linked by `pid`
    /// - Upgradability provides backwards compatibility in storage
    struct Prop { //                Slot, Bytes: Description
        uint pid;                  /// 0,   all: Proposal ID
        uint createdAt;            /// 1,   all: When created, epoch seconds UTC
        uint expiredAt;            /// 2,   all: When expired, epoch seconds UTC (no activity after this time)
        uint executedAt;           /// 3,   all: When proposal was executed, epoch seconds UTC (may always be 0)
        uint countYay;             /// 4,   all: Votes approving
        uint countNay;             /// 5,   all: Votes rejecting
        uint quorum;               /// 6,   all: Quorum; Conditionally used
        address creator;           /// 7,  0-20: Proposal Author
        PropType propType;         /// 7,    21: Determines how proposal is set and used
        PropStatus status;         /// 7,    22: Current status
        UUID eid;                  /// 8,  0-15: External ID, Request ID during create, unique amongst proposals

        // slither-disable-next-line unused-state (Space reserved for future use - upgradability)
        uint[5] __gap; // Always last field, for upgradeability, reduce size by slots used for new fields
    }

    /// @dev Tracks state for a Fix Deposit Proposal (`PropType.FixDeposit`)
    /// - Upgradability provides backwards compatibility in storage
    struct FixDepositReq {
        address to;                /// Xfer destination
        string instName;           /// Xfer source: Deposit box identifier, max len 32 chars
        bytes32 instNameKey;       /// (Set on-chain) String converted to bytes
        uint qty;                  /// Transfer quantity
        TI.TokenInfo ti;           /// Token information

        // slither-disable-next-line unused-state (Space reserved for future use - upgradability)
        uint[5] __gap; // Always last field, for upgradeability, reduce size by slots used for new fields
    }

    /// @dev `castVote` and `castVoteRelay` call result
    /// - Upgradability is not a concern for this ephemeral type
    struct CastVoteRes {
        CastVoteRc rc;     /// Return code
        Vote vote;         /// Resulting vote, `Vote.None` on error
    }

    /// @dev Input to `castVoteRelay`
    /// - Args (v,r,s) comprise an ECDSA signature to prevent a vote replay or spoof
    /// - Non (v,r,s) fields are used to recreate the hash when the contract receives these values, other fields
    ///   used in the hash (eg expiredAt, nonce) are used from contract state (prevents nonce reuse)
    /// - Upgradability provides backwards compatibility during relay
    struct CastVoteRelayReq {
        uint pid;          /// Proposal ID, identifies an existing proposal
        bool approve;      /// Whether the voter authorizes the proposal, true=Yay, false=Nay
        address voter;     /// Account casting a vote, only required for off-chain signatures
        uint8 v;           /// See ECDSA comment above
        bytes32 r;         /// See ECDSA comment above
        bytes32 s;         /// See ECDSA comment above

        // slither-disable-next-line unused-state (Space reserved for future use - upgradability)
        uint[5] __gap; // Always last field, for upgradeability, reduce size by slots used for new fields
    }

    // ────────────────────────────────────────────────────────────────────────────
    // Functions
    // ────────────────────────────────────────────────────────────────────────────

    // ───────────────────────────────────────
    // Setup
    // ───────────────────────────────────────
    function initialize(address creator, UUID reqId, uint quorum, AC.RoleRequest[] calldata roleRequests) external;

    function acceptAdmin(uint40 seqNumEx, UUID reqId, bool accept) external;

    function approveMgr(uint40 seqNumEx, UUID reqId, address ccy, uint8 contractId) external;

    // ───────────────────────────────────────
    // Getters
    // ───────────────────────────────────────
    // function getEip712Domain() external view // Removed due to size limit
    //     returns(string memory name, string memory version, uint256 chainId, address verifier);

    function getQuorum() external view returns(uint);

    function getNonce(address account) external view returns(uint);

    function getLastPropId() external view returns(uint pid);

    function getProp(uint pid) external view returns(Prop memory);

    function getPropStatus(uint pid) external view returns(PropStatus);

    function getRoleRequests(uint pid) external view returns(AC.RoleRequest[] memory);

    function getVotes(uint pid) external view returns(address[] memory voters, Vote[] memory votes);

    function getAccountInfos() external view returns(ARI.AccountInfo[] memory accounts);

    function getFixDepositReqs(uint pid) external view returns(FixDepositReq[] memory);

    function getVoteDigest(uint pid, uint expiredAt, uint nonce, bool approve, address signer) external view
        returns(bytes32 digest);

    // ───────────────────────────────────────
    // Manager contracts (SIZE: ~0.3 KB) - Removed due to size limit
    // ───────────────────────────────────────
    // function getBoxMgr() external view returns(address);

    // function getEarnDateMgr() external view returns(address);

    // function getRevMgr() external view returns(address);

    // function getInstRevMgr() external view returns(address);

    // function getXferMgr() external view returns(address);

    // ───────────────────────────────────────
    // Proposal management
    // ───────────────────────────────────────
    function createQuorumProp(uint40 seqNumEx, UUID reqId, uint expiredAt, uint quorum) external;

    function createRoleProp(uint40 seqNumEx, UUID reqId, uint expiredAt, AC.RoleRequest[] calldata requests) external;

    function createInstRevProp(uint40 seqNumEx, UUID reqId, uint expiredAt, address ccyAddr, bool correction) external;

    function createXferProp(uint40 seqNumEx, UUID reqId, uint expiredAt, TI.TokenInfo calldata ti,
        bool isRevDist) external;

    function createFixDepositProp(uint40 seqNumEx, UUID reqId, uint expiredAt, FixDepositReq[] calldata reqs) external;

    function sealInstRevProp(uint40 seqNumEx, UUID reqId, uint pid) external;

    function sealXferProp(uint40 seqNumEx, UUID reqId,uint pid) external;

    function withdrawProp(uint40 seqNumEx, UUID reqId, uint pid) external;

    // ───────────────────────────────────────
    // Proposal exercise
    // ───────────────────────────────────────
    function castVote(uint40 seqNumEx, UUID reqId, uint pid, bool approve) external;

    function castVoteRelay(uint40 seqNumEx, UUID reqId, CastVoteRelayReq memory arg) external;

    function execInstRevProp(uint40 seqNumEx, UUID reqId, uint pid) external;

    function execXferProp(uint40 seqNumEx, UUID reqId, uint pid) external;

    function xferNative(address to, uint qty) external returns(bool sent);
}
