// SPDX-License-Identifier: UNLICENSED
// Copyright 2025, GigaStar Technologies LLC, All Rights Reserved, https://gigastar.io
pragma solidity ^0.8.29;

import './IContractUser.sol';
import './Types.sol';

/// @dev Ownership balance management
// prettier-ignore
interface IBalanceMgr is IContractUser {
    // ────────────────────────────────────────────────────────────────────────────
    // Types
    // ────────────────────────────────────────────────────────────────────────────

    // ───────────────────────────────────────
    // Events
    // ───────────────────────────────────────

    // ────────────────────────────────────────────────────────────────────────────
    // Functions
    // ────────────────────────────────────────────────────────────────────────────

    // ───────────────────────────────────────
    // Setup
    // ───────────────────────────────────────

    function initialize(address creator, UUID reqId) external;

    function setOwnerBalances(uint40 seqNumEx, UUID reqId, address tokAddr,
        UUID[] calldata ownerEids, int[] calldata balances, bool relative) external;

    function getOwnerBalance(address tokAddr, UUID ownerEid) external view returns(int);

    function getOwnerBalances(address tokAddr, UUID[] calldata ownerEids) external view
        returns(int[] memory balances);

    // ───────────────────────────────────────
    // Operations: Xfer Revenue Proposal
    // ───────────────────────────────────────

    function updateBalance(address tokAddr, UUID ownerEid, int qty, bool relative) external;

    function claimQty(address tokAddr, UUID ownerEid, uint qty) external returns(bool);

    function unclaimQty(address tokAddr, UUID ownerEid, uint qty) external;
}
