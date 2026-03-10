// SPDX-License-Identifier: UNLICENSED
// Copyright 2025, GigaStar Technologies LLC, All Rights Reserved, https://gigastar.io
pragma solidity ^0.8.29;

import './ICallTracker.sol';
import './IVersion.sol';

/// @dev Unifies contract boilerplate to get/set contracts, call tracking, and version
interface IContractUser is ICallTracker, IVersion {
    // ────────────────────────────────────────────────────────────────────────────
    // Types
    // ────────────────────────────────────────────────────────────────────────────

    // ───────────────────────────────────────
    // Events
    // ───────────────────────────────────────
    event ContractUpdated(uint8 contractId, address oldProxy, address newProxy);

    // ────────────────────────────────────────────────────────────────────────────
    // Functions
    // ────────────────────────────────────────────────────────────────────────────
    function preUpgrade(uint40 seqNumEx, UUID reqId, UUID reqIdStage) external;

    // ───────────────────────────────────────
    // Setup
    // ───────────────────────────────────────
    function setContract(uint40 seqNumEx, UUID reqId, uint8 contractId, address newProxy) external;

    // ───────────────────────────────────────
    // Getters
    // ───────────────────────────────────────
    function getContract(uint8 contractId) external view returns(address);
}
