// SPDX-License-Identifier: UNLICENSED
// Copyright 2025, GigaStar Technologies LLC, All Rights Reserved, https://gigastar.io
pragma solidity ^0.8.29;

/// @dev Contract User Library
/// - Namespace for constants related to `ContractUser_contracts`
/// - Ensure constants and enum order are synced
/// @custom:api public
// prettier-ignore
library CU {
    uint8 constant Creator      = 0;    // Creator Contract:    Access control during initial setup/deploy
    uint8 constant Vault        = 1;    // Vault:               Access control, proposal mgmt, revenue custodian
    uint8 constant XferMgr      = 2;    // Transfer Manager:    Handles instrument revenue proposals
    uint8 constant RevMgr       = 3;    // Revenue Manager:     Tracks owner balances and related proposals
    uint8 constant InstRevMgr   = 4;    // Inst Revenue Mgr:    Tracks instrument revenue and related proposals
    uint8 constant BalanceMgr   = 5;    // Balance Manager:     Tracks owner allocations and claims
    uint8 constant EarnDateMgr  = 6;    // Earn Date Manager:   Stores instName, earnDate combos for enumeration
    uint8 constant BoxMgr       = 7;    // Box Manager:         Manages drop/deposit addresses
    uint8 constant Crt          = 8;    // Crt:                 Security token allowing investor wallet views
    uint8 constant Placeholder1 = 9;    //
    uint8 constant Placeholder2 = 10;   //
    uint8 constant Placeholder3 = 11;   //
    uint8 constant Placeholder4 = 12;   //
    uint8 constant Placeholder5 = 13;   //
    uint8 constant Count        = 14;   // Metadata: Used for input validation

    /// @dev Enum for client type gen though contracts use the constants above for less bytecode/casting
    enum Contract { Creator, Vault, XferMgr, RevMgr, InstRevMgr, BalanceMgr, EarnDateMgr, BoxMgr, Crt,
        Placeholder1, Placeholder2, Placeholder3, Placeholder4, Placeholder5,
        Count // Metadata: Used for input validation; Must remain last item
    }
}
