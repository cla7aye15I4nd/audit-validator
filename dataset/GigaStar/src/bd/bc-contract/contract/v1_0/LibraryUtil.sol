// SPDX-License-Identifier: UNLICENSED
// Copyright 2025, GigaStar Technologies LLC, All Rights Reserved, https://gigastar.io
pragma solidity ^0.8.29;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC1155/IERC1155.sol';

import './Types.sol';

/// @dev Utility library for reuse and modularity
/// @custom:api public
// prettier-ignore
library Util {
    // ────────────────────────────────────────────────────────────────────────────
    // Constants
    // ────────────────────────────────────────────────────────────────────────────

    // For address constants, see SENTINEL_ADDRESS
    address internal constant MaxAddress = address(uint160(type(uint160).max)); // 40 hex chars, 20 bytes, 160 bits
    address internal constant ExplicitMint = MaxAddress; // Clients use to mint, translated to `NativeMint`
    address internal constant ExplicitBurn = MaxAddress; // Clients use to burn, translated to `NativeBurn`
    address internal constant ContractHeld = address(1); // Clients use as the contract address for to/from
    address internal constant NativeMint = AddrZero;   // Code clarity
    address internal constant NativeBurn = AddrZero;   // Code clarity

    // For Gas* constants, see GAS_TARGET
    uint internal constant GasTargetDefault = 5_000_000; // Relates to `maxGas` param; softMax=5M, hardMax=45M
    uint internal constant GasCleanupDefault =  200_000; // Threshold for a func to begin cleanup, Not for all cases

    // ────────────────────────────────────────────────────────────────────────────
    // Types
    // ────────────────────────────────────────────────────────────────────────────

    // ───────────────────────────────────────
    // Events
    // ───────────────────────────────────────
    // Do not declare events here as then multiple contracts will emit with duplicate definitions

    // ───────────────────────────────────────
    // Errors
    // ───────────────────────────────────────
    error ArrayLengths(uint len1, uint len2);

    // ────────────────────────────────────────────────────────────────────────────
    // Functions
    // ────────────────────────────────────────────────────────────────────────────

    // ───────────────────────────────────────
    // Misc
    // ───────────────────────────────────────

    /// @dev Converts special/sentinel addresses to native. See constant definitions.
    /// @param safeAddr An address received as contract input possibly encoded
    /// @param custAddr Custodial address (vault)
    /// @return native The native address
    function resolveAddr(address safeAddr, address custAddr) internal pure returns(address native) {
        if (safeAddr == ContractHeld) return custAddr;
        return safeAddr == ExplicitBurn ? NativeBurn : safeAddr;
    }

    /// @dev Simplifies array length enforcement
    function requireSameArrayLength(uint a, uint b) internal pure returns(uint) {
        if (a != b) revert ArrayLengths(a, b);
        return a;
    }

    /// @dev Get a range/slice length for the given inputs
    /// @param arrayLen Length of the array being analyzed
    /// @param iBegin Range begin index
    /// @param count Requested range length, 0 = [iBegin:]
    /// @return rangeLen Range length for an array slice: [iBegin : iBegin + rangeLen]
    function getRangeLen(uint arrayLen, uint iBegin, uint count) internal pure returns(uint rangeLen) {
        uint end = count == 0 ? arrayLen : iBegin + count;
        if (end > arrayLen) end = arrayLen;
        return iBegin < end ? end - iBegin : 0;
    }

    /// @dev Simplifies creation of gap fields
    function gap5() internal pure returns(uint[5] memory) { return [uint(0), 0, 0, 0, 0]; }
}
