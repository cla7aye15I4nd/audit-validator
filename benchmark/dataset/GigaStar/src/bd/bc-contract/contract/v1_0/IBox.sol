// SPDX-License-Identifier: UNLICENSED
// Copyright 2025, GigaStar Technologies LLC, All Rights Reserved, https://gigastar.io
pragma solidity ^0.8.29;

import '@openzeppelin/contracts/interfaces/IERC1155Receiver.sol';

import './IVersion.sol';
import './LibraryTI.sol';

/// @dev Deposit box interactions
/// @custom:deploy clone
// prettier-ignore
interface IBox is IERC1155Receiver {
    // ────────────────────────────────────────────────────────────────────────────
    // Types
    // ────────────────────────────────────────────────────────────────────────────

    // ───────────────────────────────────────
    // Enums
    // ───────────────────────────────────────
    enum ApproveRc  { Success, AllowanceFail, ApproveFail, BadToken, NoBox, NotAuth }
    enum PushRc     { Success, LowBalance, BalanceFail, XferFail, BadToken, NoBox }

    // ───────────────────────────────────────
    // Errors
    // ───────────────────────────────────────
    error OwnerRequired(address caller);

    event OwnerAdded(address indexed owner);

    event OwnerRemoved(address indexed owner);

    event ApprovalUpdated(string indexed boxNameHash,
        string boxName, string tokSym, address token, address indexed spender, uint oldAllowance, uint newAllowance);

    event TokenPushed(string indexed boxNameHash, string boxName, string tokSym, uint qty);

    event ApprovalErr(string indexed boxNameHash, string indexed tokSymHash,
        string boxName, string tokSym, TI.TokenType tokType, address token, address owner,
        address spender, uint allowance, ApproveRc rc);

    // ───────────────────────────────────────
    // Structs (See MEM_LAYOUT)
    // ───────────────────────────────────────

    /// @dev Tracks active approvals
    /// - Upgradability is not a concern for this fundamental type
    struct Approval {
        address tokAddr;        /// Token to be transfered
        address spender;        /// Account allowed to transfer
        uint allowance;         /// Qty account is allowed to transfer
        uint updatedAt;         /// block.timestamp when updated, can trace to a tx for more info
    }

    /// @dev Push result info
    /// - Upgradability is not a concern for this ephemeral type
    struct PushResult {
        uint qty;               /// Quantity pushed
        PushRc rc;              /// Return code
    }

    // ────────────────────────────────────────────────────────────────────────────
    // Functions
    // ────────────────────────────────────────────────────────────────────────────

    // ───────────────────────────────────────
    // Setup
    // ───────────────────────────────────────

    function initialize(address owner, string calldata name) external;

    function getVersion() external pure returns(uint);

    // ───────────────────────────────────────
    // Access control
    // ───────────────────────────────────────

    function addOwner(address owner) external returns(bool);

    function removeOwner(address owner) external returns(bool);

    // ───────────────────────────────────────
    // Getters
    // ───────────────────────────────────────

    function getName() external view returns(string memory);
    function setName(string calldata name) external;

    function isOwner(address addr) external view returns(bool);
    function getOwnersLen() external view returns(uint);
    function getOwners(uint iBegin, uint count) external view returns(address[] memory owners);

    function getAllowance(address token, address spender) external view returns(uint allowance);
    function getApprovalsLen() external view returns(uint);
    function getApprovals(uint iBegin, uint count) external view returns(Approval[] memory approvals);

    // ───────────────────────────────────────
    // Operations
    // ───────────────────────────────────────

    function approve(address spender, TI.TokenInfo calldata info, uint qty) external returns(ApproveRc result);

    function approveAll(address spender, TI.TokenInfo[] calldata infos, uint qty) external
        returns(ApproveRc[] memory results);

    function push(address to, TI.TokenInfo calldata info, uint qty) external returns(PushResult memory result);

    function pushAll(address to, TI.TokenInfo[] calldata infos, uint qty) external returns(PushResult[] memory results);
}
