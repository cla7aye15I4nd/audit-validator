// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

enum ContractType {
    Avatar,
    HorseV1,
    HorseV2,
    Other
}

bytes32 constant MINTER_ADMIN_ROLE = keccak256("MINTER_ADMIN_ROLE");
