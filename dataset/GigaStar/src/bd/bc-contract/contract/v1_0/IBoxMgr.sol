// SPDX-License-Identifier: UNLICENSED
// Copyright 2025, GigaStar Technologies LLC, All Rights Reserved, https://gigastar.io
pragma solidity ^0.8.29;

import './IBox.sol';
import './IContractUser.sol';
import './LibraryBI.sol';
import './LibraryTI.sol';
import './Types.sol';

/// @dev Deposit box management
// prettier-ignore
interface IBoxMgr is IContractUser {
    // ────────────────────────────────────────────────────────────────────────────
    // Types
    // ────────────────────────────────────────────────────────────────────────────

    // ───────────────────────────────────────
    // Structs (See MEM_LAYOUT)
    // ───────────────────────────────────────

    /// @dev Input to `addBox`
    /// - Bundles vars to reduce stack pressure
    /// - Upgradability is not a concern for this ephemeral type
    struct AddBoxReq {
        string name;             /// Unique box identifier
        uint version;            /// Logic contract version to use, =0 then latest, see `addBoxLogic`
        bool active;             /// Add to active boxes when true, else inactive boxes (eg reserved)
        uint nonce;              /// For determinism and/or conflict res. (address in use), =0 then block.timestamp
        address deployedProxy;   /// If =0 ignored, else skips deploy and uses this existing `IBox` proxy address
        address deployedLogic;   /// Used conditionally with `deployedProxy`
        address[] spenders;      /// Addresses to approve for directing all `tokens`
        TI.TokenInfo[] tokens;   /// Tokens to be directed by `spenders` (1:1)
    }

    // ───────────────────────────────────────
    // Events
    // ───────────────────────────────────────

    event BoxAdded(string indexed boxNameHash, address indexed boxProxy, uint indexed version,
        string boxName, bool deploy, bool active, address boxLogic, bytes32 salt);

    event BoxRenamed(string indexed oldNameHash, string indexed newNameHash,
        string oldName, string newName, bool active);

    event BoxActivation(string indexed boxNameHash, address indexed boxProxy,
        string boxName, bool active);

    event BoxLogicContractAdded(uint version, address logic);

    event ProbeAddrResult(uint index);
    event ProbeAddrMaxChange(uint value, uint old);

    // ───────────────────────────────────────
    // Errors
    // ───────────────────────────────────────
    error BoxAddFail(address mgr, string boxName, uint ts, uint prevrandao, bytes32 salt);
    error BoxNameEmpty();
    error BoxNameInUse(string boxName, address boxProxy, bool active);
    error BoxLogicInvalid(address logic);
    error BoxLogicVersionInvalid(uint version, uint latest);
    error BoxLogicVersionExists(uint version);
    error BoxLogicVersionNotFound(uint version);

    // ────────────────────────────────────────────────────────────────────────────
    // Functions
    // ────────────────────────────────────────────────────────────────────────────

    // ───────────────────────────────────────
    // BoxMgr Setup
    // ───────────────────────────────────────

    function initialize(address creator, UUID reqId) external;

    function getProbeAddrMax() external view returns(uint);
    function setProbeAddrMax(uint40 seqNumEx, UUID reqId, uint value) external;

    function addBoxLogic(uint40 seqNumEx, UUID reqId, uint version, address logic) external;

    function getLatestBoxLogic() external view returns(uint version, address logic);

    // ───────────────────────────────────────
    // Box Setup / Management
    // ───────────────────────────────────────

    function addBox(uint40 seqNumEx, UUID reqId, AddBoxReq calldata req) external;

    function rotateBox(uint40 seqNumEx, UUID reqId, string calldata name, bool activate) external;

    function renameBox(uint40 seqNumEx, UUID reqId, string calldata oldName, string calldata newName) external;

    // ───────────────────────────────────────
    // Box Actions
    // ───────────────────────────────────────

    function approve(uint40 seqNumEx, UUID reqId, TI.TokenInfo calldata tokenInfo, string calldata boxName,
        address spender, uint qty) external;

    function push(string calldata boxName, address to, TI.TokenInfo calldata info, uint qty)
        external returns(IBox.PushResult memory result);

    // ───────────────────────────────────────
    // Box Getters
    // ───────────────────────────────────────

    function boxExists(string calldata name, bool active) external view returns(bool);

    function getBoxes(uint iBegin, uint count, bool active) external view returns(BI.BoxInfo[] memory results);

    function getBoxLen(bool active) external view returns(uint);

    function getBoxByName(string calldata name, bool active) external view
        returns(bool found, BI.BoxInfo memory box);

    function getBoxByAddr(address proxyBox, bool active) external view
        returns(bool found, BI.BoxInfo memory box);

    // ───────────────────────────────────────
    // Deploy Getters
    // ───────────────────────────────────────
    function getBoxProxyDeployInfo(string calldata name, uint version, uint nonce) external view
        returns(bool exists, address boxProxy, uint nonceUsed, bytes32 salt);

    function getBoxProxyAddress(string calldata name, uint version, uint nonce) external view
        returns(address boxProxy, uint nonceUsed, bytes32 salt);
}
