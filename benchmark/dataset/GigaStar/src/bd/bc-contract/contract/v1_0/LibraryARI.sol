// SPDX-License-Identifier: UNLICENSED
// Copyright 2025, GigaStar Technologies LLC, All Rights Reserved, https://gigastar.io
pragma solidity ^0.8.29;

import './LibraryAC.sol';
import './LibraryUtil.sol';

/// @dev Account Role Info Library
/// @custom:api public
// prettier-ignore
library ARI {
    // ────────────────────────────────────────────────────────────────────────────
    // Types
    // ────────────────────────────────────────────────────────────────────────────

    // ───────────────────────────────────────
    // Structs (See MEM_LAYOUT)
    // ───────────────────────────────────────

    /// @dev Tracks info for accounts with a role
    /// - Upgradability provides backwards compatibility in storage
    struct AccountInfo { //     Slot, Bytes: Description
        uint nonce;             /// 0,   all: Prevent replay attacks
        address account;        /// 1,  0-20: Account address
        AC.Role role;           /// 1,    21: One role per account

        // slither-disable-next-line unused-state (Space reserved for future use - upgradability)
        uint[5] __gap; // Always last field, for upgradeability, reduce size by slots used for new fields
    }

    /// @dev Facilitates an O(1) lookup from account to `AccountInfo`
    /// - A struct field may not be a storage ptr so this simulates it via: `_getAccountsByRole(mgr, role)[index]`
    /// - Upgradability is not a concern for this fundamental type
    struct RoleToIndex { //     Slot, Bytes: Description
        uint index;             /// 0,   all: Location in related `AccountInfo[]`
        AC.Role role;           /// 1,     1: Indicates the `AccountInfo[]` that `index` refers to
    }

    /// @dev An enumerable map:
    /// - O(1) CRUD via map[account] -> _getAccountsByRole -> AccountInfo
    /// - Allows each account to have [0,1] role, cannot have >1 role
    /// - Enumerable disjoint accounts per role
    /// - Upgradability provides backwards compatibility in storage
    struct AccountRoleInfo {
        mapping(address => RoleToIndex) map;    /// Facilitates a role lookup per account, see `RoleToIndex`
        AccountInfo[] admins;                   /// `AccountInfo` for accounts with `AC.Role.Admin`
        AccountInfo[] voters;                   /// `AccountInfo` for accounts with `AC.Role.Voter`
        AccountInfo[] agents;                   /// `AccountInfo` for accounts with `AC.Role.Agent`

        // slither-disable-next-line unused-state (Space reserved for future use - upgradability)
        uint[5] __gap; // Always last field, for upgradeability, reduce size by slots used for new fields
    }

    // ───────────────────────────────────────
    // Events
    // ───────────────────────────────────────
    event RoleChanged(bool indexed add, AC.Role indexed role, address indexed account);

    // ───────────────────────────────────────
    // Errors
    // ───────────────────────────────────────
    error AccountHasRole(address account, AC.Role role);
    error RoleOutOfRange(AC.Role actual, AC.Role min, AC.Role max);

    // ────────────────────────────────────────────────────────────────────────────
    // Functions
    // ────────────────────────────────────────────────────────────────────────────

    // ───────────────────────────────────────
    // AccountRoleInfo
    // ───────────────────────────────────────

    /// @dev An `AccountRoleInfo` accessor to add an item
    function add(AccountRoleInfo storage ari, address account, AC.Role role, uint nonce) internal {
        // Check account has no role
        RoleToIndex storage rti = ari.map[account]; // Get storage for new item
        if (rti.role != AC.Role.None) revert AccountHasRole(account, rti.role);

        // Get accounts
        AccountInfo[] storage accounts = _getAccountsByRole(ari, role);

        // Init new `RoleToIndex`; struct constructor-style init would require another lookup
        rti.index = accounts.length;    // Index of new account below
        rti.role = role;

        // Add account info to storage
        accounts.push(AccountInfo({
            nonce: nonce,       // See NONCE_SEED
            account: account,   //
            role: role,         //
            __gap: Util.gap5()  //
        }));

        emit RoleChanged(true, role, account);
    }

    /// @dev An `AccountRoleInfo` modifier; remove an item from `ari` by `key`, O(1) via swap & pop (unordered values)
    function remove(AccountRoleInfo storage ari, address account) internal {
        // Check account has a role
        RoleToIndex storage rti = ari.map[account];
        AC.Role role = rti.role;
        if (role == AC.Role.None) revert AccountHasRole(account, AC.Role.None);

        // Remove from array and map via swap-n-pop for stable array indexes (except the moved item)
        AccountInfo[] storage accounts = _getAccountsByRole(ari, role);
        uint i = rti.index;
        uint last = accounts.length - 1;
        if (last > 0) { // then moved item
            AccountInfo memory item = accounts[last];   // Copy last item
            accounts[i] = item;                         // Copy last item
            ari.map[item.account].index = i;            // Update index for moved item
        }
        accounts.pop();                                 // Pop: last=0; --length; (remove item)
        delete ari.map[account];                        // Delete index for removed item
        emit RoleChanged(false, role, account);
    }

    /// @dev An `AccountRoleInfo` accessor to get an item from `ari` by `key`, O(1) via indirection, fail if not found
    function get(AccountRoleInfo storage ari, address account) internal view returns(AccountInfo storage) {
        RoleToIndex storage rti = ari.map[account];
        return _getAccountsByRole(ari, rti.role)[rti.index];
    }

    /// @dev An `AccountRoleInfo` accessor to get an item's role
    function getRole(AccountRoleInfo storage ari, address account) internal view returns(AC.Role) {
        RoleToIndex storage rti = ari.map[account];
        return rti.role;
    }

    /// @dev Provides a mapping from role to related array, see `RoleToIndex`
    function _getAccountsByRole(AccountRoleInfo storage ari, AC.Role role) private view returns(AccountInfo[] storage) {
        // Ordered by desc freq
        if (role == AC.Role.Agent) return ari.agents;
        if (role == AC.Role.Voter) return ari.voters;
        if (role == AC.Role.Admin) return ari.admins;
        revert RoleOutOfRange(role, AC.Role.None, AC.Role.Count); // Otherwise could return a sentinel default
    }

    /// @dev Copy all `AccountInfo` items into a memory array
    function getAccountInfos(AccountRoleInfo storage ari) internal view returns (AccountInfo[] memory infos)
    { unchecked {
        // Get a ref to each storage array
        ARI.AccountInfo[] storage agents = ari.agents;
        ARI.AccountInfo[] storage voters = ari.voters;
        ARI.AccountInfo[] storage admins = ari.admins;
        uint agentsLen = agents.length;
        uint votersLen = voters.length;
        uint adminsLen = admins.length;

        // Transform storage to results
        infos = new ARI.AccountInfo[](agentsLen + votersLen + adminsLen);
        uint k = 0;
        for (uint i = 0; i < agentsLen; ++i) { // Upper bound: RoleLenMax
            infos[k] = agents[i];
            ++k;
        }
        for (uint i = 0; i < votersLen; ++i) { // Upper bound: RoleLenMax
            infos[k] = voters[i];
            ++k;
        }
        for (uint i = 0; i < adminsLen; ++i) { // Upper bound: RoleLenMax
            infos[k] = admins[i];
            ++k;
        }
    } }
}
