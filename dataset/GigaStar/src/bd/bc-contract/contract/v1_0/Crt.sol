// SPDX-License-Identifier: UNLICENSED
// Copyright 2025, GigaStar Technologies LLC, All Rights Reserved, https://gigastar.io
pragma solidity ^0.8.29;

import '@openzeppelin/contracts/token/ERC1155/extensions/IERC1155MetadataURI.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';

import './ContractUser.sol';
import './ICrt.sol';
import './IVault.sol';
import './LibraryEMAP.sol';
import './LibraryAC.sol';
import './LibraryCU.sol';
import './Types.sol';

/// @title CRT: A channel revenue token
/// @author Jason Aubrey, GigaStar
/// @notice Provides an ERC-1155 token interface with securities oriented customizations
/// @dev Access control via the Vault contract.
/// - Upgradeable via UUPS. See PROXY_OPTIONS for more.
/// - Token create/delete is implicit via transfers that increase the supply
/// @custom:api public
/// @custom:deploy uups
// prettier-ignore
contract Crt is Initializable, UUPSUpgradeable, ICrt, ContractUser {
    // ────────────────────────────────────────────────────────────────────────────
    // Constants
    // ────────────────────────────────────────────────────────────────────────────
    uint constant VERSION = 10;             // 123 => Major: 12, Minor: 3 (always 1 digit)
    uint constant INDEX_SINGLE = 12648430;  // HEX: 0xC0FFEE; Differentiates single and batch calls

    // ───────────────────────────────────────
    // Structs
    // ───────────────────────────────────────

    // ────────────────────────────────────────────────────────────────────────────
    // Fields (See MEM_LAYOUT), default visibility is 'internal'
    // ────────────────────────────────────────────────────────────────────────────

    string _uri;                                                // See `uri` function
    EMAP.UintUint _tokenIds;                                    // Key: TokenId; TokenId enumeration and count
    mapping(uint => uint) _supplies;                            // Key: tokenId; Qty in circulation
    mapping(uint => mapping(address => uint)) _tokenAccBals;    // Keys: (tokenId,account); Balance
    mapping(address => bool) _xferAgents;                       // Key: account; Transfer Authorization

    // New fields should be inserted immediately above this line to preserve layout

    // slither-disable-next-line unused-state (Space reserved for future use - upgradability)
    uint[20] __gap; // Always last field, for upgradeability, reduce size by slots used for new fields

    // ────────────────────────────────────────────────────────────────────────────
    // Functions
    // ────────────────────────────────────────────────────────────────────────────

    // ───────────────────────────────────────
    // Access control
    // ───────────────────────────────────────

    /// @dev Access control: Allow XferMgr, Vault, Admin, or Creator
    function _requireXferAuth(address caller) internal view {
        if (!_hasXferAuth(caller)) revert AC.AccessDenied(caller);
    }

    /// @dev Access control: Allow XferMgr, Vault, Admin, Creator, or dynamic transfer agents
    /// - Transfer control is restricted to authorized roles to align with regulatory guidelines
    ///   and thus owner-specific approvals are not required
    function _hasXferAuth(address account) internal view returns(bool) {
        // Fixed accounts
        if (account == _contracts[CU.XferMgr]) return true;
        address vault = _contracts[CU.Vault];
        if (account == vault) return true;
        if (vault != AddrZero && _getRoleView(vault, account) == AC.Role.Admin) return true;
        if (account == _contracts[CU.Creator]) return true; // Last as only during deploy

        // Dynamic accounts
        return _xferAgents[account];
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
    /// @param url The generic URL to token metadata for all tokens
    /// @custom:api protected
    function initialize(address creator, UUID reqId, string memory url) external override initializer {
        __Crt_init(creator, reqId, url);
    }

    /// @dev Allows non-proxy initialization in Foundry
    function __Crt_init(address creator, UUID reqId, string memory url) internal {
        _uri = url;
        __ContractUser_init(creator, reqId);
        EMAP.UintUint_init(_tokenIds);
    }

    /// @dev Upgrade hook to enforce permissions
    /// - Ensure `preUpgrade` is called before this function to stage required params
    function _authorizeUpgrade(address newImpl) internal override(UUPSUpgradeable) {
        _authorizeUpgradeImpl(msg.sender, newImpl);
    }

    /// @dev Get the current version
    function getVersion() external pure override virtual returns(uint) { return VERSION; }

    // ───────────────────────────────────────
    // Getters
    // ───────────────────────────────────────

    /// @notice Get the count of token ids with a supply
    function getTokenCount() external view override returns(uint) {
        return EMAP.length(_tokenIds);
    }

    /// @dev Get a slice of token IDs in circulation
    /// @param iBegin Index in the array to start processing
    /// @param count Items to get, 0 = [iBegin:] (may exceed gas), See PAGE_REQUESTS.
    /// @return tokenIds A slice of token ids in circulation
    function getTokenIds(uint iBegin, uint count) external view override returns(uint[] memory tokenIds)
    { unchecked {
        EMAP.UintUintValue[] storage values = _tokenIds.values;

        // Calculate results length
        iBegin += EMAP.FIRST_INDEX; // to ignore sentinel value
        uint resultsLen = Util.getRangeLen(values.length, iBegin, count);
        if (resultsLen == 0) return tokenIds;

        // Get slice
        tokenIds = new uint[](resultsLen);
        for (uint i = 0; i < resultsLen; ++i) { // Ubound: Caller must page
            tokenIds[i] = values[iBegin + i].value;
        }
    } }

    /// @notice Get a token's supply (units in circulation)
    function getTokenSupply(uint tokenId) external view override returns(uint) { return _supplies[tokenId]; }

    // ───────────────────────────────────────
    // IERC165
    // ───────────────────────────────────────

    /// @dev Implements ERC-165 so that contracts/wallets can discover ERC-1155 compatibility
    function supportsInterface(bytes4 interfaceId) external pure override returns(bool) {
        return interfaceId == type(IERC1155).interfaceId
            || interfaceId == type(IERC1155MetadataURI).interfaceId
            || interfaceId == type(ICrt).interfaceId;
    }

    // ───────────────────────────────────────
    // IERC1155MetadataURI
    // ───────────────────────────────────────

    /// @dev Set the uri/url for all tokenIds, such as https://token-cdn-domain/{id}.json
    /// - Clients must replace the literal '{id}' substring with the actual token id
    /// - See METADATA_FILE for more, like file content
    /// param id Ignored per the ERC-1155 standard as the 'id' is a placeholder in the result
    /// @return The same result for all inputs based upon https://eips.ethereum.org/EIPS/eip-1155#metadata
    function uri(uint) public view override returns(string memory) {
        return _uri;
    }

    // ───────────────────────────────────────
    // IERC1155
    // ───────────────────────────────────────

    /// @notice Get the balance for the account,tokenId
    /// @param account Ownership being inspected
    /// @param id (tokenId) The security within the contract
    /// @return balance Account balance per (account,tokenId)
    function balanceOf(address account, uint id) external view override returns(uint balance) {
        account = Util.resolveAddr(account, _contracts[CU.Vault]);
        return _tokenAccBals[id][account];
    }

    /// @notice Get the balance for each (account,tokenId), a batch version of `balanceOf`
    /// @param accounts Ownership being inspected
    /// @param ids (tokenIds) The securities within the contract
    /// @return balances Account balance per (account,tokenId)
    function balanceOfBatch(address[] calldata accounts, uint[] calldata ids) external view override
        returns(uint[] memory balances)
    { unchecked {
        address vaultAddr = _contracts[CU.Vault];
        uint len = Util.requireSameArrayLength(accounts.length, ids.length);
        balances = new uint[](len);
        for (uint i = 0; i < len; ++i) { // Ubound: Caller must page
            address account = Util.resolveAddr(accounts[i], vaultAddr);
            balances[i] = _tokenAccBals[ids[i]][account];
        }
    } }

    /// @notice Whether `spender` may direct tokens owned by `account`?
    /// @dev See `setApprovalForAll`, this reflects the governance
    /// Param `account` (arg 1) is omitted since it is ignored in the query, see `setApprovalForAll` notes
    /// param account Ignored as all accounts are subject to the same policies
    /// @param spender See above
    /// @return bool Answer to the question
    function isApprovedForAll(address, address spender) external view override returns(bool) {
        spender = Util.resolveAddr(spender, _contracts[CU.Vault]);
        return _hasXferAuth(spender);
    }

    /// @notice Grants/revokes an account approval for transfering all tokens
    /// @dev While this function often allows owner-to-owner transfers, here it is centrally controlled to enforce
    ///   regulator mandates such as resolving lost ownership issues and a good control location
    /// @param spender The account on which to grant/revoke the transfer permission
    /// @param approved Whether the account may transfer tokens
    /// @custom:api private
    function setApprovalForAll(address spender, bool approved) external override {
        _setApprovalForAll(msg.sender, spender, approved); // Access control within
    }

    /// @notice Xfer a single token `from` sender `to` recipient for token `id` and `value`
    /// @dev Call does not invoke code in `to` wallet (no ROI for this token), so more 'safe'/efficient than spec
    ///   with respect to this contract, less safe for wallets incapable of handling the token but it can be reversed
    /// - Does not call `onERC1155Received` on `to` wallet
    /// @custom:api private
    function safeTransferFrom(address from, address to, uint id, uint value, bytes calldata) external override {
        _safeTransferFrom(msg.sender, from, to, id, value); // Access control within
    }

    /// @notice Xfer tokens `from` sender `to` recipient for each pair in: token `id` and `value`
    /// - This is an awkward func in the ERC-1155 spec since neither `from` nor `to` are arrays
    /// @dev Call does not invoke code in `to` wallet (no ROI for this token), so more 'safe'/efficient than spec
    /// - Does not call `onERC1155BatchReceived` on `to` wallet
    /// @custom:api private
    function safeBatchTransferFrom(address from, address to,
        uint[] calldata ids, uint[] calldata values, bytes calldata) external
    {
        _safeBatchTransferFrom(msg.sender, from, to, ids, values); // Access control within
    }

    // ───────────────────────────────────────
    // Variants of IERC1155 write calls with seq nums
    // ───────────────────────────────────────

    /// @notice Grants/revokes an account approval for transfering all tokens
    /// @dev Not in the ERC-1155 spec but mimics `setApprovalForAll` + seq num tracking
    /// - While this function often allows owner-to-owner transfers, here it is centrally controlled to enforce
    ///   regulator mandates such as resolving lost ownership issues and a good control location
    /// @param seqNumEx =0 for on-chain caller, else expected sequence number for determinism, etc; See `CallTracker`
    /// @param reqId Request ID, unique amongst requests across all callers
    /// @param spender The account on which to grant/revoke the transfer permission
    /// @param approved Whether the account may transfer tokens
    /// @custom:api public
    function setApprovalForAllEx(uint40 seqNumEx, UUID reqId, address spender, bool approved) external override {
        address caller = msg.sender;
        // If using sequence number protocol (off-chain caller) then enforce idempotency
        if (_isReqReplay(caller, seqNumEx, reqId)) return;

        _setApprovalForAll(caller, spender, approved); // Access control within

        _setCallRes(caller, seqNumEx, reqId, true);
    }

    /// @notice Xfer a single token `from` sender `to` recipient for token `id` and `value`
    /// @dev Not in the ERC-1155 spec but mimics `safeTransferFrom` + seq num tracking
    /// - Call does not invoke code in `to` wallet (no ROI for this token), so more 'safe'/efficient than spec
    ///   with respect to this contract, less safe for wallets incapable of handling the token but it can be reversed
    /// - Does not call `onERC1155Received` on `to` wallet
    /// @param seqNumEx =0 for on-chain caller, else expected sequence number for determinism, etc; See `CallTracker`
    /// @param reqId Request ID, unique amongst requests across all callers
    /// @custom:api public
    function safeTransferFromEx(uint40 seqNumEx, UUID reqId, address from, address to, uint id, uint value) external override {
        address caller = msg.sender;
        // If using sequence number protocol (off-chain caller) then enforce idempotency
        if (_isReqReplay(caller, seqNumEx, reqId)) return;

        _safeTransferFrom(caller, from, to, id, value); // Access control within

        _setCallRes(caller, seqNumEx, reqId, true);
    }

    /// @notice Xfer tokens `from` sender `to` recipient for each pair in: token `id` and `value`
    /// - This is an awkward func in the ERC-1155 spec since neither `from` nor `to` are arrays
    /// @dev Not in the ERC-1155 spec but mimics `safeBatchTransferFrom` + seq num tracking
    /// - Call does not invoke code in `to` wallet (no ROI for this token), so more 'safe'/efficient than spec
    /// - Does not call `onERC1155BatchReceived` on `to` wallet
    /// @param seqNumEx =0 for on-chain caller, else expected sequence number for determinism, etc; See `CallTracker`
    /// @param reqId Request ID, unique amongst requests across all callers
    /// @custom:api public
    function safeBatchTransferFromEx(uint40 seqNumEx, UUID reqId, address from, address to,
        uint[] calldata ids, uint[] calldata values) external
    { unchecked {
        address caller = msg.sender;
        // If using sequence number protocol (off-chain caller) then enforce idempotency
        if (_isReqReplay(caller, seqNumEx, reqId)) return;

        _safeBatchTransferFrom(caller, from, to, ids, values); // Access control within

        _setCallRes(caller, seqNumEx, reqId, true);
    } }

    /// @dev Set the metadata URL, counterpart of `uri()` in ERC-1155 spec
    /// @param seqNumEx =0 for on-chain caller, else expected sequence number for determinism, etc; See `CallTracker`
    /// @param reqId Request ID, unique amongst requests across all callers
    /// @param newUri Metadata URL
    /// @custom:api public
    function setUri(uint40 seqNumEx, UUID reqId, string calldata newUri) external override {
        address caller = msg.sender;
        _requireVaultOrAdminOrCreator(caller); // Access control

        // If using sequence number protocol (off-chain caller) then enforce idempotency
        if (_isReqReplay(caller, seqNumEx, reqId)) return;

        _uri = newUri;
        emit URI(newUri, 0);

        _setCallRes(caller, seqNumEx, reqId, true);
    }

    /// @notice A batch version of `safeTransferFrom`
    /// @dev Provides more flexibility and gas efficiency than ERC-1155 transfer functions
    /// @param seqNumEx =0 for on-chain caller, else expected sequence number for determinism, etc; See `CallTracker`
    /// @param reqId Request ID, unique amongst requests across all callers
    /// @param eventMode Controls event emission, `EventMode.PerXfer` is most compliant with downstream viewers
    ///     by following the ERC-1155 protocol for event consumers. A call to `balanceOf` works after all options
    /// @custom:api public
    function transferBatch(uint40 seqNumEx, UUID reqId, EventMode eventMode,
        address[] calldata froms,
        address[] calldata tos,
        uint[] calldata ids,
        uint[] calldata values
    ) external override
    { unchecked {
        address caller = msg.sender;
        _requireXferAuth(caller); // Access control

        // If sequence number passed and previously seen
        if (_isReqReplay(caller, seqNumEx, reqId)) return; // Prior call, no-op

        address vaultAddr = _contracts[CU.Vault];
        uint len = Util.requireSameArrayLength(
            Util.requireSameArrayLength(froms.length, tos.length),
            Util.requireSameArrayLength(ids.length, values.length));
        address from;
        address to;
        uint id;
        uint value;
        for (uint i = 0; i < len; ++i) { // Ubound: Caller must page
            // Translate addresses from sentinel to native
            from = Util.resolveAddr(froms[i], vaultAddr);
            to = Util.resolveAddr(tos[i], vaultAddr);
            if (eventMode == EventMode.PerXfer) {
                id = ids[i];
                value = values[i];
                _xferFrom(from, to, id, value, i);
                emit TransferSingle(caller, from, to, id, value); // ERC-1155 event
            } else {
                _xferFrom(from, to, ids[i], values[i], i);
            }
        }
        if (eventMode == EventMode.PerBatch) emit TransferMany(caller, froms, tos, ids, values); // Not an ERC-1155
    } }

    /// @dev Do a single transfer
    /// - Access by role: Agent
    /// @param from Xfer source
    /// @param to Xfer destination
    /// @param id The security within the contract (aka token id or collection)
    /// @param value Xfer quantities
    function _xferFrom(address from, address to, uint id, uint value, uint index) private {
        if (value == 0) return; // No-op
        mapping(address => uint) storage balances = _tokenAccBals[id];
        if (from != Util.NativeMint) {              // Debit 'from' balance
            uint balance = balances[from];          // Cache value
            if (balance < value) revert ICrt.BalanceUnderflow(from, balance, value, id, index);
            balances[from] = balance - value;       // Update storage; Underflow not possible, implicit delete if = 0
        } else {                                    // Mint - increase supply
            uint supply = _supplies[id];            // Cache value
            if (supply == 0) {                      // No existing supply
                EMAP.addNoCheck(_tokenIds, id, id); // Add token
            }
            _supplies[id] = supply + value;         // Update storage; Increase supply
        }

        if (to != Util.NativeBurn) {                // Credit 'to' balance
            balances[to] += value;                  // Increase owner balance
        } else {                                    // Burn - reduce supply
            uint supply = _supplies[id];            // Cache value
            if (supply < value) revert ICrt.SupplyUnderflow(from, supply, value, id, index); // Revert not possible
            supply -= value;                        // Underflow not possible
            _supplies[id] = supply;                 // Update storage; `delete` is implicit if =0
            if (supply == 0) EMAP.remove(_tokenIds, id);
            // No need to adjust `balances` here, reduced above and implicitly deleted when =0
        }
    }

    /// @dev Provides consistent behavior for each func variant
    function _setApprovalForAll(address caller, address spender, bool approved) private {
        _requireVaultOrAdminOrCreator(caller); // Access control

        spender = Util.resolveAddr(spender, _contracts[CU.Vault]);
        _xferAgents[spender] = approved;
        emit ApprovalForAll(caller, spender, approved); // Arg1 satisfies iface but permission is for all accounts
    }

    /// @dev Provides consistent behavior for each func variant
    function _safeTransferFrom(address caller, address from, address to, uint id, uint value) private {
        _requireXferAuth(caller); // Access control

        // Translate addresses from sentinel to native
        address vaultAddr = _contracts[CU.Vault];
        from = Util.resolveAddr(from, vaultAddr);
        to = Util.resolveAddr(to, vaultAddr);

        _xferFrom(from, to, id, value, INDEX_SINGLE);

        // A gas limiting factor on throughput (3 indexed fields and emit per transfer). A non-standard alternative
        // to emit XferMany once after a batch would likely see ~3x throughput improvement for transfers/tx.
        // Unfortunately, wallets monitor standard events so it would have to refresh/reindex to see updates.
        emit TransferSingle(caller, from, to, id, value); // ERC-1155 event
    }

    /// @dev Provides consistent behavior for each func variant
    function _safeBatchTransferFrom(address caller, address from, address to,
        uint[] calldata ids, uint[] calldata values) private
    { unchecked {
        _requireXferAuth(caller); // Access control

        // Translate addresses from sentinel to native
        address vaultAddr = _contracts[CU.Vault];
        from = Util.resolveAddr(from, vaultAddr);
        to = Util.resolveAddr(to, vaultAddr);

        uint len = Util.requireSameArrayLength(ids.length, values.length);
        for (uint i = 0; i < len; ++i) { // Ubound: Caller must page
            _xferFrom(from, to, ids[i], values[i], i);
        }
        emit TransferBatch(caller, from, to, ids, values); // ERC-1155 event
    } }
}
