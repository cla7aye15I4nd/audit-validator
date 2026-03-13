// SPDX-License-Identifier: UNLICENSED
// Copyright 2025, GigaStar Technologies LLC, All Rights Reserved, https://gigastar.io
pragma solidity ^0.8.29;

import './Types.sol';

/// @dev Allows a set of features to be paused
// prettier-ignore
interface IPausable {
    // ───────────────────────────────────────
    // Events
    // ───────────────────────────────────────
    event Paused(bool paused, address caller);

    // ───────────────────────────────────────
    // Errors
    // ───────────────────────────────────────
    error ContractPaused();

    // ───────────────────────────────────────
    // Functions
    // ───────────────────────────────────────
    function pause(uint40 seqNumEx, UUID reqId, bool value) external;

    function paused() external view returns(bool);
}
