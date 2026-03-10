// SPDX-License-Identifier: UNLICENSED
// Copyright 2025, GigaStar Technologies LLC, All Rights Reserved, https://gigastar.io
pragma solidity ^0.8.29;

// slither-disable-start dead-code (Entities are optimized away where unused though all used somewhere)

// ────────────────────────────────────────────────────────────────────────────
// Constants
// ────────────────────────────────────────────────────────────────────────────
uint constant MAX_ALLOWANCE = type(uint).max;

UUID constant UuidZero = UUID.wrap(0);
address constant AddrZero = address(0);

// WARNING: Be careful adding type safety. Minor changes can easily add ~1.5 KiB of bytecode to a contract.
//    Multiple type aliases were here (e.g. Epoch, Nonce, etc) but they were taking multiple KiB since
//    byte code is added for wrap/unwrap during comparisons, increments, interface usage, it bloats quickly.
//    Similarly, using uint8 instead of uint, while less storage, causes a mask/unmask in usage and more bloat.
//    Changing struct field 'tokenId' from uint to uint64 added 0.104 KiB with only 2 arg passes, 1 assignment

// ───────────────────────────────────────
// Errors
// ───────────────────────────────────────
error EmptyReqId();
error InvalidZeroAddr();
error EmptyString();
error EmptyDate();

function checkZeroAddr(address addr) pure {
    if (addr == AddrZero) revert InvalidZeroAddr();
}

// ───────────────────────────────────────
// UUID
// ───────────────────────────────────────
type UUID is bytes16; // RFC 4122, 16 bytes, 128 bits

function isEmpty(UUID a) pure returns(bool) {
    return UUID.unwrap(a) == 0;
}

// slither-disable-end dead-code
