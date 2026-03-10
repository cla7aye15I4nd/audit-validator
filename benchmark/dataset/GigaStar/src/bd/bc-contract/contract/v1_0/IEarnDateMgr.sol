// SPDX-License-Identifier: UNLICENSED
// Copyright 2025, GigaStar Technologies LLC, All Rights Reserved, https://gigastar.io
pragma solidity ^0.8.29;

import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';

import './IContractUser.sol';
import './IRevMgr.sol';
import './Types.sol';
import './IVersion.sol';

/// @dev Earn Date tracking and management
interface IEarnDateMgr is IVersion, IContractUser {
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

    // ───────────────────────────────────────
    // Operations
    // ───────────────────────────────────────

    function addInstEarnDate(uint40 seqNumEx, UUID reqId, string calldata instName, uint earnDate) external;

    function removeInstEarnDate(uint40 seqNumEx, UUID reqId, string calldata instName, uint earnDate) external;

    // ───────────────────────────────────────
    // Getters: Instrument Names
    // ───────────────────────────────────────

    function getInstNamesLen() external view returns(uint);
    function getInstNames(uint iBegin, uint count) external view returns(string[] memory results);

    function getInstNamesForDateLen(uint earnDate) external view returns(uint);
    function getInstNamesForDate(uint earnDate, uint iBegin, uint count) external view
        returns(string[] memory results);

    // ───────────────────────────────────────
    // Getters: Earn Dates
    // ───────────────────────────────────────

    function getEarnDatesLen() external view returns(uint);
    function getEarnDates(uint iBegin, uint count) external view returns(uint[] memory results);

    function getEarnDatesForInstLen(string calldata instName) external view returns(uint);
    function getEarnDatesForInst(string calldata instName, uint iBegin, uint count) external view
        returns(uint[] memory results);
}
