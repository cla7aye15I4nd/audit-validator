// SPDX-License-Identifier: UNLICENSED
// Copyright 2025, GigaStar Technologies LLC, All Rights Reserved, https://gigastar.io
pragma solidity ^0.8.29;

/// @dev String Library
/// @custom:api public
// prettier-ignore
library String {

// slither-disable-start assembly (Basic usage for performance)

/// @dev Converts a string in calldata to a left-aligned bytes32, chars > 32 are truncated
/// - Inline assembly substantially improves the performance of this conversion
function toBytes32(string calldata input) internal pure returns (bytes32 result) {
    if (bytes(input).length > 0) { assembly ("memory-safe") { result := calldataload(input.offset) } }
}

/// @dev Converts a string in memory to a left-aligned bytes32, chars > 32 are truncated
/// - Inline assembly substantially improves the performance of this conversion
function toBytes32Mem(string memory input) internal pure returns (bytes32 result) {
    if (bytes(input).length > 0) { assembly ("memory-safe") { result := mload(add(input, 32)) } }
}

// slither-disable-end assembly

/// @dev Converts a left-aligned bytes32 to string, right trimming at the first zero byte
/// - Assembly (~650-800 gas) is likely ~25-40% faster but this is only used by view functions
///   so this is sufficient for now. The assembly is also non-trivial so avoiding it until needed
function toString(bytes32 input) internal pure returns (string memory result)
{ unchecked {
    // Get string length by finding the first 0 byte
    uint len = 0;
    for (; len < 32; ++len) { // Ubound: 32
        if (input[len] == 0) {
            break;
        }
    }
    if (len == 0) return '';

    // Copy bytes into string
    result = new string(len);
    bytes memory bs = bytes(result);
    for (uint i = 0; i < len; ++i) { // Ubound: 32
        bs[i] = input[i];
    }
} }

}
