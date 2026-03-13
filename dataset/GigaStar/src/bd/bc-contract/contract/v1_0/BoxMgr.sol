// SPDX-License-Identifier: UNLICENSED
// Copyright 2025, GigaStar Technologies LLC, All Rights Reserved, https://gigastar.io
pragma solidity ^0.8.29;

import '@openzeppelin/contracts/proxy/Clones.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';

import './ContractUser.sol';
import './IBox.sol';
import './IBoxMgr.sol';
import './IVault.sol';
import './LibraryAC.sol';
import './LibraryBI.sol';
import './LibraryCU.sol';
import './LibraryEMAP.sol';
import './LibraryUtil.sol';
import './LibraryString.sol';
import './LibraryTI.sol';
import './Types.sol';

/// @title BoxMgr: A revenue stream multiplexer
/// @author Jason Aubrey, GigaStar
/// @notice Manages box CRUD and approvals, allows many revenue streams with separate inbound addresses
/// @dev Uses EIP-1167 minimal proxy clones for a 1:N between this factory contract and Box instances
/// - Upgradeable via UUPS. See PROXY_OPTIONS for more.
/// - Reentrancy: A reentrant call would need to pass the access control function at the top of each external function.
///   For unauthorized callers, the access control functions would block a reentrant attempt. For authorized callers,
///   repeated calls are allowed so there's no need to guard against reentrancy with them.
/// @custom:api public
/// @custom:deploy uups
// prettier-ignore
contract BoxMgr is Initializable, UUPSUpgradeable, IBoxMgr, ContractUser {
    // ────────────────────────────────────────────────────────────────────────────
    // Constants
    // ────────────────────────────────────────────────────────────────────────────
    uint constant VERSION = 10; // BoxMgr version, 123 => Major: 12, Minor: 3 (always 1 digit)
    uint private constant USE_LATEST_BOX_VERSION = 0;  // Box version

    // ────────────────────────────────────────────────────────────────────────────
    // Types
    // ────────────────────────────────────────────────────────────────────────────

    /// @dev Box logic/implementation version: Deployment related info
    /// - This is for the Box only (not related to the BoxMgr version)
    /// - Upgradability provides backwards compatibility in storage
    /// @custom:api private
    struct BoxLogicVer {
        uint version;  /// Contract version
        address logic; /// Logic/Impl contract

        // slither-disable-next-line unused-state (Space reserved for future use - upgradability)
        uint[5] __gap; /// Always last field, for upgradeability, reduce size by slots used for new fields
    }

    // ────────────────────────────────────────────────────────────────────────────
    // Fields
    // ────────────────────────────────────────────────────────────────────────────
    BI.Emap _boxes;                     // Active boxes, keyed by both name and addr: Box Proxy Addr
    BI.Emap _inactive;                  // Allows boxes to exist off the critical path
    uint _latestBoxVer;                 // Latest version to use in `_boxLogicVers`
    uint _probeAddrMax;                 // Upper bound to prevent address squatters, can be increased
    mapping(uint => BoxLogicVer) _boxLogicVers; // Key: version; Used during deploy, potentially later

    // New fields should be inserted immediately above this line to preserve layout

    // slither-disable-next-line unused-state (Space reserved for future use - upgradability)
    uint[20] __gap; // Always last field, for upgradeability, reduce size by slots used for new fields

    // ────────────────────────────────────────────────────────────────────────────
    // Functions
    // ────────────────────────────────────────────────────────────────────────────

    // ───────────────────────────────────────
    // Access control
    // ───────────────────────────────────────

    /// @dev Access control
    function _requireInstRevMgrOrCreator(address caller) private view {
        if (caller == _contracts[CU.InstRevMgr]) return;
        if (caller == _contracts[CU.Creator]) return;
        revert AC.AccessDenied(caller);
    }

    // ───────────────────────────────────────
    // BoxMgr Setup
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
    /// @custom:api protected
    function initialize(address creator, UUID reqId) external override initializer {
        __ContractUser_init(creator, reqId);
        BI.Emap_init(_boxes);
        BI.Emap_init(_inactive);
        _probeAddrMax = 10_000;
    }

    /// @dev Upgrade hook to enforce permissions
    /// - Ensure `preUpgrade` is called before this function to stage required params
    function _authorizeUpgrade(address newImpl) internal override(UUPSUpgradeable) {
        _authorizeUpgradeImpl(msg.sender, newImpl);
    }

    /// @dev Get the current version
    function getVersion() external pure override virtual returns(uint) { return VERSION; }

    /// @dev Get the upper bound for probing addresses during a deploy
    function getProbeAddrMax() external view override returns(uint) { return _probeAddrMax; }

    /// @dev Set the upper bound for probing addresses during a deploy
    /// @param seqNumEx =0 for on-chain caller, else expected sequence number for determinism, etc; See `CallTracker`
    /// @param reqId Request ID, unique amongst requests across all callers
    /// @param value New probe address max value
    function setProbeAddrMax(uint40 seqNumEx, UUID reqId, uint value) external override {
        address caller = msg.sender;
        _requireAgentOrCreator(caller); // Access control

        // If using sequence number protocol (off-chain caller) then enforce idempotency
        if (_isReqReplay(caller, seqNumEx, reqId)) return;

        uint old = _probeAddrMax;
        bool success = value > 0;
        if (value > 0) {
            _probeAddrMax = value;
            emit ProbeAddrMaxChange(value, old);
        }

        _setCallRes(caller, seqNumEx, reqId, success);
    }

    /// @dev Add a new logic contract. New boxes will use this version by default
    /// - No remove function as it's unlikely this will be called many times
    /// @param seqNumEx =0 for on-chain caller, else expected sequence number for determinism, etc; See `CallTracker`
    /// @param reqId Request ID, unique amongst requests across all callers
    /// @param version Version label for the logic, must be unique. 0 not allowed as a sentinel for 'use latest'
    /// @param logic Implementation contract address
    /// @custom:api public
    function addBoxLogic(uint40 seqNumEx, UUID reqId, uint version, address logic) external override {
        address caller = msg.sender;
        _requireAgentOrCreator(caller); // Access control

        // If using sequence number protocol (off-chain caller) then enforce idempotency
        if (_isReqReplay(caller, seqNumEx, reqId)) return;

        if (!_isValidBoxLogic(logic)) revert BoxLogicInvalid(logic);
        if (version <= _latestBoxVer) revert BoxLogicVersionInvalid(version, _latestBoxVer);
        if (_boxLogicVers[version].logic != AddrZero) revert BoxLogicVersionExists(version);

        // Store implementation version info
        _boxLogicVers[version] = BoxLogicVer({version: version, logic: logic, __gap: Util.gap5()});

        _latestBoxVer = version;
        emit BoxLogicContractAdded(version, logic);

        _setCallRes(caller, seqNumEx, reqId, true);
    }

    /// @dev Return whether the address supports IBox
    function _isValidBoxLogic(address logic) internal view returns (bool) {
        checkZeroAddr(logic);
        bytes4 iid = type(IBox).interfaceId;
        try IERC165(logic).supportsInterface(iid) returns (bool ok) { return ok; } catch { return false; }
    }

    /// @dev Get the latest box logic info
    /// @return version Contract version
    /// @return logic Contract address (implementation)
    function getLatestBoxLogic() external view override returns(uint version, address logic) {
        version = _latestBoxVer;
        return (version, _boxLogicVers[version].logic);
    }

    // ───────────────────────────────────────
    // Box Setup / Management
    // ───────────────────────────────────────

    /// @dev Add a Box Proxy, each is a minimal clone that shares a logic contract and has minimal state
    /// - Caller must page inputs if necessary (eg spenders, tokens)
    /// - Conditionally deploys a new instance based on `deployed` (used in a migration)
    /// - Deployed boxes do not support logic upgrades. To upgrade a box, deploy a new box (with a new address)
    /// - Addresses are predictable unless squatted then unpredictable but progress effectively guaranteed
    /// @param seqNumEx =0 for on-chain caller, else expected seqNum for determinism; See `CallTracker`
    /// @param reqId Request ID, unique amongst requests across all callers
    /// @param req See struct definition
    /// @custom:api public
    function addBox(uint40 seqNumEx, UUID reqId, AddBoxReq calldata req) external {
        address caller = msg.sender;
        _requireAgentOrCreator(msg.sender); // Access control

        // If using sequence number protocol (off-chain caller) then enforce idempotency
        if (_isReqReplay(caller, seqNumEx, reqId)) return;

        bytes32 nameKey = String.toBytes32(req.name);
        if (nameKey == bytes32(0)) revert BoxNameEmpty();

        // Ensure name is unique
        { // var scope to reduce stack pressure
            (bool found, BI.BoxInfo storage info) = BI.tryGetBoxByName(_boxes, nameKey);
            if (found) revert BoxNameInUse(info.name, info.boxProxy, true);
            (found, info) = BI.tryGetBoxByName(_inactive, nameKey);
            if (found) revert BoxNameInUse(info.name, info.boxProxy, false);
        }

        // Determine if it should be deployed
        address boxProxy;
        { // var scope to reduce stack pressure
            uint version = req.version;
            address logic = AddrZero;
            bytes32 salt = 0;
            if (req.deployedProxy == AddrZero) { // then deploy it
                if (version == USE_LATEST_BOX_VERSION) version = _latestBoxVer;

                logic = _boxLogicVers[version].logic;
                if (logic == AddrZero) revert BoxLogicVersionNotFound(version);

                // Since `cloneDeterministic` requires an unused addr, it is probed before deploy:
                // - First pass is likely sufficient (~100 gas) but more easily front-run, future passes engage in a war
                //   of gas-attrition vs squatters where `block.prevrandao` limits the battle-space to 1 tx
                // - See NO_SQUATTERS for more
                address predicted = AddrZero;
                uint probeAddrMax = _probeAddrMax; // Cache value for faster search
                for (uint i = 0; i < probeAddrMax; ++i) { // UBOUND: Practical as low gas/iter, 10k =~ 7M gas
                    salt = i == 0
                        ? keccak256(abi.encodePacked(req.name, version, req.nonce)) // deterministic
                        : keccak256(abi.encodePacked(req.name, version, req.nonce,
                            block.timestamp, block.prevrandao, i)); // Good entropy unless miner bot in same block
                    predicted = Clones.predictDeterministicAddress(logic, salt);
                    if (predicted.code.length == 0) {
                        if (i > 0) emit ProbeAddrResult(i); // Not relevant in normal case
                        break; // addr unused
                    }
                }
                if (predicted.code.length != 0) {
                    revert BoxAddFail(address(this), req.name, block.timestamp, block.prevrandao, salt);
                }

                // Deploy proxy from logic, See CREATE2
                boxProxy = Clones.cloneDeterministic(logic, salt);
                IBox(boxProxy).initialize(address(this), req.name);
            } else {
                // Previous deploy/init: Migrating from a another manager, caller's `version` used
                boxProxy = req.deployedProxy;
                logic = req.deployedLogic;
            }

            // Add box to storage
            { // var scope to reduce stack pressure
                // slither-disable-next-line uninitialized-local (Allows easy init without `__gap` sensitivity)
                BI.addBoxNoCheck(req.active ? _boxes : _inactive, nameKey,
                    BI.BoxInfo({ boxProxy: boxProxy, name: req.name, nameKey: nameKey,
                        version: version, __gap: Util.gap5()
                    })
                ); // no existance check (see `found`)
                emit BoxAdded(req.name, boxProxy, version, req.name,
                    req.deployedProxy == AddrZero, req.active, logic, salt);
            }
        }

        // Approve each spender to direct all tokens, avoids the need for `IBox.approve` in most cases
        { // var scope to reduce stack pressure
            // slither-disable-next-line uninitialized-local (zero-init is ok)
            ICallTracker.CallRes memory cr; // Zero-init
            uint spendersLen = req.spenders.length;
            uint tokensLen = req.tokens.length;
            uint approvalsLen = spendersLen * tokensLen;
            if (approvalsLen > 0) {
                cr.count = uint16(approvalsLen);
                for (uint s = 0; s < spendersLen; ++s) {    // Ubound: Caller defined likely 1-2
                    for (uint t = 0; t < tokensLen; ++t) {  // Ubound: Caller defined likely 1-2
                        IBox.ApproveRc arc = IBox(boxProxy).approve(req.spenders[s], req.tokens[t], MAX_ALLOWANCE);
                        // storeApprovals.push(arc);
                        if (arc == IBox.ApproveRc.Success) ++cr.lrc; // Track approved
                    }
                }
            }
            cr.rc = 1;
            _setCallRes(caller, seqNumEx, reqId, cr);
        }
    }

    /// @dev Rotate the box status within [active,inactive] based on `activate`
    /// @param seqNumEx =0 for on-chain caller, else expected sequence number for determinism, etc; See `CallTracker`
    /// @param reqId Request ID, unique amongst requests across all callers
    /// @param name Unique box identifier
    /// @param activate true: move box to active list, false: move to inactive
    /// @custom:api public
    function rotateBox(uint40 seqNumEx, UUID reqId, string calldata name, bool activate) external override {
        address caller = msg.sender;
        _requireOnlyAgent(caller); // Access control

        // If using sequence number protocol (off-chain caller) then enforce idempotency
        if (_isReqReplay(caller, seqNumEx, reqId)) return;

        bool ok = false;
        bytes32 nameKey = String.toBytes32(name);
        if (nameKey != bytes32(0)) {
            // Get the source and destination maps
            BI.Emap storage src = activate ? _inactive : _boxes;
            BI.Emap storage dst = activate ? _boxes : _inactive;

            // Ensure it exists
            (bool found, BI.BoxInfo storage info) = BI.tryGetBoxByName(src, nameKey);
            if (found) {
                // Add to dst boxes without recreating it
                address boxProxy = info.boxProxy;
                BI.addBoxNoCheck(dst, nameKey, info); // info is copied; no existance check (see `found`)

                // Remove from src boxes
                BI.removeBoxByName(src, nameKey);
                emit BoxActivation(name, boxProxy, name, activate);
                ok = true;
            }
        }
        _setCallRes(caller, seqNumEx, reqId, ok);
    }

    /// @dev Rename an existing box, possible use cases:
    /// - Prevent a conflict during `deactivateBox`
    /// - Allow a name to have a new version deployed
    /// @param seqNumEx =0 for on-chain caller, else expected sequence number for determinism, etc; See `CallTracker`
    /// @param reqId Request ID, unique amongst requests across all callers
    /// @param oldName Current name
    /// @param newName New name
    /// @custom:api public
    function renameBox(uint40 seqNumEx, UUID reqId, string calldata oldName, string calldata newName) external override
    {
        address caller = msg.sender;
        _requireOnlyAgent(caller); // Access control

        // If using sequence number protocol (off-chain caller) then enforce idempotency
        if (_isReqReplay(caller, seqNumEx, reqId)) return;

        bool ok = false;
        bytes32 oldNameKey = String.toBytes32(oldName);
        bytes32 newNameKey = String.toBytes32(newName);
        if (newNameKey != bytes32(0)
            && ( _renameBox(_boxes, oldNameKey, newNameKey, oldName, newName, true)
            ||   _renameBox(_inactive, oldNameKey, newNameKey, oldName, newName, false) ))
        {
            ok = true;
        }
        _setCallRes(caller, seqNumEx, reqId, ok);
    }

    /// @dev utility for reuse
    function _renameBox(BI.Emap storage boxes, bytes32 oldNameKey, bytes32 newNameKey,
        string calldata oldName, string calldata newName, bool active) private returns(bool ok)
    {
        ok = BI.renameBox(boxes, oldNameKey, newNameKey, newName);
        if (ok) emit BoxRenamed(oldName, newName, oldName, newName, active);
        return ok;
    }

    // ───────────────────────────────────────
    // Box Actions
    // ───────────────────────────────────────

    /// @notice Set requested token to max approval for transfer by the spender (revenue manager or vault)
    /// @dev Allows spender to call transfer on a token directly
    /// - CallResult.rc Return code indicating if call was successful or error context, see `IBox.ApproveRc`
    /// @param seqNumEx =0 for on-chain caller, else expected seqNum for determinism; See `CallTracker`
    /// @param reqId Request ID, unique amongst requests across all callers
    /// @param tokenInfo Token to approve
    /// @param boxName Box to approve
    /// @param spender The account to approve
    /// @param qty Aggregate transfer limit for `spender`
    /// @custom:api public
    function approve(uint40 seqNumEx, UUID reqId, TI.TokenInfo calldata tokenInfo, string calldata boxName,
        address spender, uint qty) external override
    {
        address caller = msg.sender;
        _requireInstRevMgrOrCreator(caller); // Caller access control

        // If using sequence number protocol (off-chain caller) then enforce idempotency
        if (_isReqReplay(caller, seqNumEx, reqId)) return;

        // Spender access control
        IBox.ApproveRc rc;
        if (spender != _contracts[CU.InstRevMgr] && spender != _contracts[CU.Vault]) {
            rc = IBox.ApproveRc.NotAuth;
        } else {
            (bool found, BI.BoxInfo storage info) = BI.tryGetBoxByName(_boxes, String.toBytes32(boxName));
            rc = found ? IBox(info.boxProxy).approve(spender, tokenInfo, qty) : IBox.ApproveRc.NoBox;
        }

        _setCallRes(caller, seqNumEx, reqId, uint16(rc), 0, 1);
    }

    /// @notice Push `qty` units of token from `boxName` to the `to` address
    /// @dev Allows caller to use this contract's access control rather than approval per token
    /// - No `_isReqReplay` since this call cannot be executed directly from off-chain
    /// @param boxName Box to push token from (token source)
    /// @param to Xfer recipient
    /// @param ti Token info for a single transfer
    /// @param qty Quantity to push; =0 to push entire balance
    /// @return result See struct definition
    /// @custom:api private
    function push(string calldata boxName, address to, TI.TokenInfo calldata ti, uint qty) external override
        returns(IBox.PushResult memory result) // Return value used by Vault
    {
        _requireOnlyVault(msg.sender); // Access control

        (bool found, BI.BoxInfo storage info) = BI.tryGetBoxByName(_boxes, String.toBytes32(boxName));
        if (found) {
            result = IBox(info.boxProxy).push(to, ti, qty);
        } else {
            result.rc = IBox.PushRc.NoBox;
        }
    }

    // ───────────────────────────────────────
    // Box Getters
    // ───────────────────────────────────────

    /// @notice Determine if a box exists by name
    /// @param name search key
    /// @param active Target active boxes when true, else inactive boxes
    /// @return Whether the box exists
    function boxExists(string calldata name, bool active) external view override returns(bool) {
        bytes32 nameKey = String.toBytes32(name);
        return BI.exists(active ? _boxes : _inactive, nameKey);
    }

    /// @notice Get a range of active Boxes
    /// @param iBegin Index in the array to start processing
    /// @param count Items to get, 0 = [iBegin:] (may exceed gas), See `getBoxLen` and PAGE_REQUESTS
    /// @param active Target active boxes when true, else inactive boxes
    /// @return results requested range of items
    function getBoxes(uint iBegin, uint count, bool active) external view override
        returns(BI.BoxInfo[] memory results)
     { unchecked {
        BI.BoxInfo[] storage values = (active ? _boxes : _inactive).values;

        // Calculate results length
        iBegin += BI.FIRST_INDEX; // to ignore sentinel value
        uint resultsLen = Util.getRangeLen(values.length, iBegin, count);
        if (resultsLen == 0) return results;

        // Get results slice
        results = new BI.BoxInfo[](resultsLen);
        for (uint i = 0; i < resultsLen; ++i) { // Ubound: Caller must page
            results[i] = values[iBegin + i];
        }
    } }

    /// @dev Get the count of Boxes
    function getBoxLen(bool active) external view override returns(uint) {
        return BI.length(active ? _boxes : _inactive);
    }

    /// @notice Get a Box by name
    /// @param name search key
    /// @param active Target active boxes when true, else inactive boxes
    /// @return found Whether the box was found
    /// @return box Only valid if `found`=true
    function getBoxByName(string calldata name, bool active) external view override
        returns(bool found, BI.BoxInfo memory box)
    {
        bytes32 nameKey = String.toBytes32(name);
        if (nameKey == bytes32(0)) return (found, box);
        (found, box) = BI.tryGetBoxByName(active ? _boxes : _inactive, nameKey);
    }

    /// @notice Get a Box by proxy address
    /// @param proxyBox search key
    /// @return found Whether the box was found
    /// @param active Target active boxes when true, else inactive boxes
    /// @return box Only valid if `found`=true
    function getBoxByAddr(address proxyBox, bool active) external view override
        returns(bool found, BI.BoxInfo memory box)
    {
        (found, box) = BI.tryGetBoxByAddr(active ? _boxes : _inactive, proxyBox);
    }

    // ───────────────────────────────────────
    // Deploy Getters
    // ───────────────────────────────────────

    /// @notice Get info about whether a contract is deployed
    /// @param name A box name
    /// @param version The logic contract version
    /// @param nonce May be used to resolve a conflict (address already used), if =0 then uses timestamp
    /// @return exists Whether a contract is deployed
    /// @return boxProxy Contract address
    /// @return nonceUsed Nonce used in generation, only relevant if nonce=0
    /// @return salt Salt used in generation
    function getBoxProxyDeployInfo(string calldata name, uint version, uint nonce) external view override
        returns(bool exists, address boxProxy, uint nonceUsed, bytes32 salt)
    {
        (boxProxy, nonceUsed, salt) = getBoxProxyAddress(name, version, nonce);
        exists = boxProxy.code.length > 0;
    }

    /// @notice Get a deterministic Box proxy address
    /// @param name A box name
    /// @param version The logic contract version to use, if =0 then use latest
    /// @param nonce May be used to resolve a conflict (address already used), if =0 then uses timestamp
    /// @return boxProxy Box proxy address
    /// @return nonceUsed Nonce used in generation, only relevant if nonce=0
    /// @return salt Salt used in generation
    function getBoxProxyAddress(string calldata name, uint version, uint nonce) public view override
        returns(address boxProxy, uint nonceUsed, bytes32 salt)
    {
        if (version == USE_LATEST_BOX_VERSION) version = _latestBoxVer;

        address logic = _boxLogicVers[version].logic;
        if (logic == AddrZero) revert BoxLogicVersionNotFound(version);

        // Get a deterministic address based on salt inputs. See CREATE2
        if (nonce == 0) nonce = block.timestamp; // Arbitrarily unique, high entropy not required
        nonceUsed = nonce;

        salt = keccak256(abi.encodePacked(name, version, nonce));
        boxProxy = Clones.predictDeterministicAddress(logic, salt);
    }
}
