// SPDX-License-Identifier: UNLICENSED
// Copyright 2025, GigaStar Technologies LLC, All Rights Reserved, https://gigastar.io
pragma solidity ^0.8.29;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC1155/IERC1155.sol';
import '@openzeppelin/contracts/interfaces/IERC1155Receiver.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';

import './IBox.sol';
import './LibraryUtil.sol';
import './LibraryString.sol';
import './LibraryTI.sol';
import './Types.sol';

/// @title Box: A receiving address/wallet with management via BoxMgr
/// @author Jason Aubrey, GigaStar
/// @notice Allows a separate deposit address per revenue stream managed by the owner
/// @dev Access control via owner
/// - No seq num tracking as calls are only expected via contracts: BoxMgr, InstRevMgr, Vault
/// - Designed for use with EIP-1167 minimal proxy clones (Not upgradeable)
/// - Minimal clones do not support logic upgrades per Box. To upgrade a box, deploy a new box (with a new address)
/// - No concern about reentrant behavior from tokens since:
///     - It would need to cooperate with an owner contract
///     - A token already has control of its ledger
/// - Agents can poll balances on/off-chain and emit an event with more context/gas as hooks can block payments
/// @custom:api public
/// @custom:deploy clone
// prettier-ignore
contract Box is Initializable, IBox {
    // ────────────────────────────────────────────────────────────────────────────
    // Constants
    // ────────────────────────────────────────────────────────────────────────────
    uint constant VERSION = 10;         // 123 => Major: 12, Minor: 3 (always 1 digit), Used outside this contract
    uint constant SENTINEL_INDEX = 0;   // Index 0 and not found in map both resolve to no item
    uint constant FIRST_INDEX = 1;      // First actual item begins after the sentinel

    // ────────────────────────────────────────────────────────────────────────────
    // Fields
    // ────────────────────────────────────────────────────────────────────────────

    string _name;                           // Identifer, uniqueness enforced by BoxMgr
    bytes32 _nameKey;                       // Key version of `_name`

    // Fields allow enumeration of owners and O(1) add/remove
    address[] _owners;                      // Contract owners - access control
    mapping(address => uint) _idxOwners;    // map: address -> `_owners` index

    // Fields allow enumeration of approvals and O(1) add/remove
    Approval[] _approvals;                  // Spending access control
    mapping(address => mapping(address => uint)) _idxApprovals; // map: token -> spender -> `_approvals` index

    // ────────────────────────────────────────────────────────────────────────────
    // Functions
    // ────────────────────────────────────────────────────────────────────────────

    // ───────────────────────────────────────
    // Payable - Low level calls to receive native coin
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
    /// - This contract is not upgradeable. A new contract can be deployed and then migrate to it.
    /// @custom:api protected
    function initialize(address owner, string calldata name) external override initializer {
        // Add sentinel values to allow index lookups to know if item was found
        _owners.push();     // Empty sentinel item, see `SENTINEL_INDEX`
        _approvals.push();  // Empty sentinel item, see `SENTINEL_INDEX`

        _addOwner(owner);
        _name = name;
        _nameKey = String.toBytes32(name);
    }

    /// @dev Get the current version
    function getVersion() external pure returns(uint) { return VERSION; }

    /// @dev Set the name
    /// @custom:api private
    function setName(string calldata name) external {
        _requireOwner(msg.sender); // Access control
        _name = name;
    }

    // ───────────────────────────────────────
    // Access control
    // ───────────────────────────────────────
    function _requireOwner(address caller) internal view {
        if (_idxOwners[caller] == SENTINEL_INDEX) revert OwnerRequired(caller);
    }

    /// @dev Add a contract owner for access control
    /// @return added Whether the owner was added (may already exist)
    /// @custom:api private
    function addOwner(address owner) public override returns(bool added) {
        _requireOwner(msg.sender); // Access control
        added = _addOwner(owner);
    }

    /// @dev Like `addOwner` but without access control on the caller
    function _addOwner(address owner) private returns(bool added) {
        checkZeroAddr(owner);

        uint i = _idxOwners[owner];             // Get value's index
        if (i != SENTINEL_INDEX) return added;  // Already added
        _idxOwners[owner] = _owners.length;     // New value's index
        _owners.push(owner);                    // Add new value
        emit OwnerAdded(owner);
        added = true;
        return added;
    }

    /// @dev Remove a contract owner for access control
    /// @custom:api private
    function removeOwner(address owner) external override returns(bool removed) {
        _requireOwner(msg.sender); // Access control
        removed = _removeOwner(owner);
    }

    function _removeOwner(address owner) internal returns(bool removed) {
        checkZeroAddr(owner);

        uint i = _idxOwners[owner];                 // Get value's index
        if (i == SENTINEL_INDEX) return removed;    // Already removed
        uint ownersLen = _owners.length;
        if (ownersLen == 2) {                       // Is last owner? _owners[0] is sentinel
            return removed;                         // Cannot remove last owner
        }
        uint iLast = ownersLen - 1;
        if (i != iLast) {
            address item = _owners[iLast];          // Cache last item
            _owners[i] = item;                      // Copy last item
            _idxOwners[item] = i;                   // Update index for moved item
        }
        _owners.pop();                              // Pop: last=0; --length; (remove item)
        delete _idxOwners[owner];                   // Remove mapped index for removed item

        emit OwnerRemoved(owner);
        removed = true;
        return removed;
    }

    // ───────────────────────────────────────
    // IERC165
    // ───────────────────────────────────────
    function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
        return
            interfaceId == type(IBox).interfaceId ||
            interfaceId == type(IERC165).interfaceId ||
            interfaceId == type(IERC1155Receiver).interfaceId;
    }

    // ───────────────────────────────────────
    // IERC1155Receiver
    // ───────────────────────────────────────
    /// @dev Handles receipt of a single ERC-1155 token type, called by `safeTransferFrom` after a balance update
    /// - Params are ignored as this is a passive receiver that neither validates nor acts on the params
    /// param from   Ignored, see description
    /// param to     Ignored, see description
    /// param ids    Ignored, see description
    /// param values Ignored, see description
    /// param data   Ignored, see description
    /// @custom:api private
    function onERC1155Received(address, address, uint256, uint256, bytes calldata)
        external override pure returns (bytes4)
    {
        return this.onERC1155Received.selector;
    }

    /// @dev Handles receipt of multiple ERC-1155 token types, called by `safeBatchTransferFrom` after a balance update
    /// - Params are ignored as this is a passive receiver that neither validates nor acts on the params
    /// param from   Ignored, see description
    /// param to     Ignored, see description
    /// param ids    Ignored, see description
    /// param values Ignored, see description
    /// param data   Ignored, see description
    /// @custom:api private
    function onERC1155BatchReceived(address, address, uint[] calldata, uint[] calldata, bytes calldata)
        external override pure returns (bytes4)
    {
        return this.onERC1155BatchReceived.selector;
    }

    // ───────────────────────────────────────
    // Getters
    // ───────────────────────────────────────

    /// @dev Return the name
    function getName() external view override returns(string memory) { return _name; }

    /// @dev Return whether the address is an owner
    function isOwner(address addr) external view override returns(bool) {
        return _idxOwners[addr] != SENTINEL_INDEX;
    }

    /// @dev Return the owners count; facilitates enumeration
    function getOwnersLen() external view override returns(uint) {
        uint len = _owners.length;
        return len >= FIRST_INDEX ? len - 1 : 0;
    }

    /// @dev Get a slice of owners
    /// @param iBegin Index in the array to begin processing
    /// @param count Items to get, 0 = [iBegin:]
    /// @return owners Requested range of items
    function getOwners(uint iBegin, uint count) external view override returns(address[] memory owners)
    { unchecked {
        iBegin += FIRST_INDEX;
        uint len = Util.getRangeLen(_owners.length, iBegin, count);
        if (len == 0) return owners;
        owners = new address[](len);
        uint k = iBegin;
        for (uint i = 0; i < len; ++i) { // Ubound: Caller must page
            owners[i] = _owners[k];
            ++k;
        }
    } }

    /// @dev Get a spender's allowance for a token
    function getAllowance(address tokAddr, address spender) external view override returns(uint allowance) {
        uint i = _idxApprovals[tokAddr][spender];
        return i != SENTINEL_INDEX ? _approvals[i].allowance : 0;
    }

    /// @dev Return the approvals count; facilitates enumeration
    function getApprovalsLen() external view override returns(uint) {
        uint len = _approvals.length;
        return len >= FIRST_INDEX ? len - 1 : 0;
    }

    /// @dev Get a slice of approvals
    /// @param iBegin Index in the array to begin processing
    /// @param count Items to get, 0 = [iBegin:]
    /// @return approvals Requested range of items
    function getApprovals(uint iBegin, uint count) external view override returns(Approval[] memory approvals)
    { unchecked {
        iBegin += FIRST_INDEX;
        uint len = Util.getRangeLen(_approvals.length, iBegin, count);
        if (len == 0) return approvals;
        approvals = new Approval[](len);
        uint k = iBegin;
        for (uint i = 0; i < len; ++i) { // Ubound: Caller must page
            approvals[i] = _approvals[k];
            ++k;
        }
    } }

    // ───────────────────────────────────────
    // Operations
    // ───────────────────────────────────────

    /// @notice Set requested token to max approval for transfer by `spender`
    /// @dev Allows `spender` to call transfer on a token directly
    /// @param spender Address to approve for transfers
    /// @param newAllowance Qty to approve; =0 to unapprove
    /// @param info Token to grant approval
    /// @return rc Return code indicating if call was successful or error context
    /// @custom:api private
    function approve(address spender, TI.TokenInfo calldata info, uint newAllowance) external override
        returns(ApproveRc rc)
    {
        _requireOwner(msg.sender); // Access control
        rc = _approve(spender, info, newAllowance);
    }

    /// @notice Set requested tokens to max approval for transfer by `spender`
    /// @dev Allows `spender` to call transfer on a token directly
    /// @param spender Address to approve for transfers
    /// @param infos The tokens to grant approval
    /// @param newAllowance Qty to approve; =0 to unapprove
    /// @return rcs Return codes indicating if call was successful or error context
    /// @custom:api private
    function approveAll(address spender, TI.TokenInfo[] calldata infos, uint newAllowance) external override
        returns(ApproveRc[] memory rcs)
    { unchecked {
        _requireOwner(msg.sender); // Access control

        uint approved = 0;
        uint infosLen = infos.length;
        if (infosLen == 0) return rcs;
        rcs = new ApproveRc[](infosLen);
        for (uint i = 0; i < infosLen; ++i) { // Ubound: Caller must page
            ApproveRc rc = _approve(spender, infos[i], newAllowance);
            if (rc == ApproveRc.Success) ++approved;
            rcs[i] = rc;
        }
    } }

    // slither-disable-start costly-loop (costly calls are ok when the caller is bounded; cost of doing business)

    /// @dev helper for code reuse
    /// - No concern about reentrant behavior, reentry effects would be limited to wasted gas
    /// - Non-standard tokens that do not allow an approval transition from non-zero to non-zero in a single tx
    ///   would require multiple calls to this function as like "tx1: _approve(0); tx2: _approve(x)" as there's
    ///   no good way to handle it here and their usage is unlikely
    function _approve(address spender, TI.TokenInfo calldata ti, uint newAllowance) private returns(ApproveRc rc)
    { unchecked {
        checkZeroAddr(spender);
        checkZeroAddr(ti.tokAddr);
        uint oldAllowance = 0;
        // Handle approval in token contract (for access control)
        if (ti.tokType == TI.TokenType.Erc20) {
            // Approve spender for transfers on behalf of Proxy

            // Get current allowance
            IERC20 token = IERC20(ti.tokAddr);
            try token.allowance(address(this), spender) returns(uint allowResult) {
                oldAllowance = allowResult;
                // NOTE: Cannot nest a try/catch here as slither's parser would fail
            } catch { rc = ApproveRc.AllowanceFail; }

            if (rc == ApproveRc.Success && oldAllowance != newAllowance) {
                // Approve a new allowance
                try token.approve(spender, newAllowance) returns(bool ok) {
                    if (!ok) rc = ApproveRc.ApproveFail;
                } catch { rc = ApproveRc.ApproveFail; }
            }
        } else if (ti.tokType == TI.TokenType.Erc1155) {
            try
                IERC1155(ti.tokAddr).setApprovalForAll(spender, newAllowance >0)
            {} catch { rc = ApproveRc.ApproveFail; }
        } else {
            // NativeCoin: Only owner can send, no approvals
            // Erc1155Crt: No approvals, only the allowed roles
            rc = ApproveRc.BadToken;
        }
        if (rc != ApproveRc.Success) {
            emit ApprovalErr(_name, ti.tokSym, _name,
                ti.tokSym, ti.tokType, ti.tokAddr, address(this), spender, newAllowance, rc);
            return rc;
        }
        // Track approvals in this contract (for enumeration)
        oldAllowance = newAllowance > 0
            ? _upsertApproval(ti.tokAddr, spender, newAllowance)
            : _removeApproval(ti.tokAddr, spender);
        emit ApprovalUpdated(_name, ti.tokSym, _name, ti.tokAddr, spender, oldAllowance, newAllowance);
        // rc = ApproveRc.Success occurs implicitly via zero-value
    } }

    /// @dev Add a contract approval for access control
    /// - Addresses validated upstream
    function _upsertApproval(address tokAddr, address spender, uint newAllowance) internal returns(uint oldAllowance) {
        uint i = _idxApprovals[tokAddr][spender];                // Get value's index
        if (i == SENTINEL_INDEX) {                                // New?
            _idxApprovals[tokAddr][spender] = _approvals.length; // New value's index
            _approvals.push(Approval({                           // Add new value
                tokAddr: tokAddr,
                spender: spender,
                allowance: newAllowance,
                updatedAt: block.timestamp
            }));
        } else {                                                // Update existing
            Approval storage app = _approvals[i];               // Existing value
            oldAllowance = app.allowance;                       // Capture old
            app.allowance = newAllowance;                       // Update allowance
            app.updatedAt = block.timestamp;
        }
    }

    /// @dev Remove a contract approval for access control
    /// - Addresses validated upstream
    function _removeApproval(address tokAddr, address spender) internal returns(uint oldAllowance) {
        uint i = _idxApprovals[tokAddr][spender];               // Get value's index
        if (i != SENTINEL_INDEX) { // then existing item
            uint iLast = _approvals.length - 1;
            if (i != iLast) { // then do swap-n-pop and update index
                Approval storage toReplace = _approvals[i];     // Item to remove/overwrite
                Approval storage toMove = _approvals[iLast];    // Last item
                oldAllowance = toReplace.allowance;             // Capture old allowance

                // Swap-n-pop part 1
                toReplace.tokAddr = toMove.tokAddr;
                toReplace.spender = toMove.spender;
                toReplace.allowance = toMove.allowance;

                // Update index mapping for moved item
                _idxApprovals[toMove.tokAddr][toMove.spender] = i;
            }

            // Remove last item
            _approvals.pop();                                   // Pop: last=0; --length; (remove item)
            delete _idxApprovals[tokAddr][spender];             // Delete index for removed item
        }
    }

    // slither-disable-end costly-loop

    /// @notice Push `qty` units of token to the `to`
    /// @dev Allows caller to use this contract's access control rather than approval per token
    /// - Caller can log the event consistently upon either forward or pull
    /// @param to Transfer recipient
    /// @param info Token info for a single transfer
    /// @param qty Quantity to push; =0 to push entire balance
    /// @return result Indicates progress where `rc` is set from `PushRc`
    /// @custom:api private
    function push(address to, TI.TokenInfo calldata info, uint qty) external override
        returns(PushResult memory result)
    { unchecked {
        _requireOwner(msg.sender); // Access control

        result = _push(to, info, qty);
    }}

    /// @notice Push `qty` units of each token to the `to`
    /// @dev Allows caller to use this contract's access control rather than approval per token
    /// - Caller can log the event consistently upon either forward or pull
    /// @param to Transfer recipient
    /// @param infos Token info for each transfer
    /// @param qty Quantity to push; =0 to push entire balance
    /// @return results Items indicates progress where `rc` is set from `PushRc`
    /// @custom:api private
    function pushAll(address to, TI.TokenInfo[] calldata infos, uint qty) external override
        returns(PushResult[] memory results)
    { unchecked {
        _requireOwner(msg.sender); // Access control

        uint pushed = 0;
        uint infosLen = infos.length;
        results = new PushResult[](infosLen);
        for (uint i = 0; i < infosLen; ++i) { // Ubound: Caller must page
            PushResult memory result = _push(to, infos[i], qty);
            if (result.rc == PushRc.Success) ++pushed;
            results[i] = result;
        }
    } }

    // slither-disable-start arbitrary-send-eth (Send is parameterized and caller is access controlled)

    /// @dev helper for code reuse
    /// - No concern about reentrant behavior, reentry effects would be limited to wasted gas
    /// @param to Transfer recipient
    /// @param ti Token info for a single transfer
    /// @param qty Quantity to push; =0 to push entire balance
    /// @return result Indicates progress where `rc` is set from `PushRc`
    function _push(address to, TI.TokenInfo calldata ti, uint qty) private returns(PushResult memory result)
    { unchecked {
        checkZeroAddr(to); // Prevent burn; See Erc1155Crt comment below
        address boxProxy = address(this);

        // Handle each token type:
        if (ti.tokType == TI.TokenType.Erc20) {
            // Get token balance
            IERC20 token = IERC20(ti.tokAddr);
            try token.balanceOf(boxProxy) returns(uint balance) {
                if (qty == 0) qty = balance;
                if (balance < qty) return _resultWith(PushRc.LowBalance);
                if (balance == 0) return result; // Success; noop

                // NOTE: Cannot nest a try/catch here as slither's parser would fail
            } catch {
                return _resultWith(PushRc.BalanceFail);
            }

            // Forward token qty
            try token.transfer(to, qty) returns(bool ok) {
                if (ok) {
                    result.qty = qty;
                    emit TokenPushed(_name, _name, ti.tokSym, qty);
                    return result; // Success
                }
            } catch {}
            return _resultWith(PushRc.XferFail);
        }
        if (ti.tokType == TI.TokenType.NativeCoin) {
            // Get token balance
            uint balance = address(this).balance;
            if (qty == 0) qty = balance;
            if (balance < qty) return _resultWith(PushRc.LowBalance);
            if (balance == 0) return result; // Success; noop

            // slither-disable-start low-level-calls (A native coin operation requires a low-level call)

            // Forward token qty
            //  `.call` is low-level, no try/catch guard allowed
            (bool ok, ) = payable(to).call{ value: qty }("");

            // slither-disable-end low-level-calls

            if (ok) {
                result.qty = qty;
                emit TokenPushed(_name, _name, ti.tokSym, qty);
                return result; // Success
            }
            return _resultWith(PushRc.XferFail);
        }
        if (ti.tokType == TI.TokenType.Erc1155) {
            // Get token balance
            IERC1155 token = IERC1155(ti.tokAddr);
            uint tokenId = ti.tokenId;
            try token.balanceOf(boxProxy, tokenId) returns(uint balance) {
                if (qty == 0) qty = balance;
                if (balance < qty) return _resultWith(PushRc.LowBalance);
                if (balance == 0) return result; // Success; noop

                // NOTE: Cannot nest a try/catch here as slither's parser would fail
            } catch {
                return _resultWith(PushRc.BalanceFail);
            }

            // Forward token qty
            try token.safeTransferFrom(boxProxy, to, tokenId, qty, '') {
                result.qty = qty;
                emit TokenPushed(_name, _name, ti.tokSym, qty);
                return result; // Success
            } catch {
                return _resultWith(PushRc.XferFail);
            }
        }
        // Erc1155Crt: Should be done directly, not via this call
        return _resultWith(PushRc.BadToken);
    } }

    // slither-disable-end arbitrary-send-eth

    function _resultWith(PushRc rc) private pure returns (PushResult memory r) { r.rc = rc; }
}
