// SPDX-License-Identifier: UNLICENSED
// Copyright 2025, GigaStar Technologies LLC, All Rights Reserved, https://gigastar.io
pragma solidity ^0.8.29;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC1155/IERC1155.sol';
import '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol';

import './ICrt.sol';
import './LibraryUtil.sol';
import './LibraryARI.sol';

/// @dev Access Control library
/// @custom:api public
// prettier-ignore
library AC {
    // ────────────────────────────────────────────────────────────────────────────
    // Constants
    // ────────────────────────────────────────────────────────────────────────────
    // Role limits provide upper bounds on loops for complexity/gas analysis. These seem generous as the most practical
    // scenario is 1-2 admins, 3-5 voters (quorum: 2), 1 agent for a max of 8 accounts. Max 5 for each role is flexible
    uint internal constant RoleLenMax = 5; // Sufficient for quorum <= 5 such as 2/3, 3/5, etc
    uint internal constant RoleReqLenMax = uint(Role.Count) * uint(RoleLenMax); // Remove All + Add All in same request

    uint internal constant NonceAtInit = 1; // Sentinel to mark a nonce as during init, distinct from zero-value

    // ────────────────────────────────────────────────────────────────────────────
    // Types
    // ────────────────────────────────────────────────────────────────────────────

    // ───────────────────────────────────────
    // Enums
    // ───────────────────────────────────────
    enum Role { None, Admin, Voter, Agent,
        Count // Metadata: Used for input validation; Must remain last item
    }

    // ───────────────────────────────────────
    // Events
    // ───────────────────────────────────────
    event AdminAddPending(address indexed account);
    event AdminAddCanceled(address indexed account);
    event QuorumChanged(uint indexed oldQuorum, uint indexed newQuorum);

    // ───────────────────────────────────────
    // Errors
    // ───────────────────────────────────────
    error AccessDenied(address caller);
    error ChangeAlreadyPending(address account, Role role);
    error OutOfRange(uint actual, uint min, uint max);
    error RoleLenOutOfRange(uint actual, uint min, uint max, Role role);

    // ───────────────────────────────────────
    // Structs (See MEM_LAYOUT)
    // ───────────────────────────────────────

    /// @dev Tracks state related to Role Proposal (`PropType.Role`) - For adding/removing roles
    /// - Upgradability provides backwards compatibility in storage
    struct RoleRequest { //     Slot, Bytes: Description
        address account;        /// 0,  0-20: Subject of Action.Add/Delete and new account with Action.Swap
        bool add;               /// 0,    21: Add=true, Remove=false, See ROLE_SWAP
        Role role;              /// 0,    22: Membership to be adjusted

        uint[5] __gap; // Always last field, for upgradeability, reduce size by slots used for new fields
    }

    /// @dev Manages access control per account
    /// - Upgradability provides backwards compatibility in storage
    struct AccountMgr {
        ARI.AccountRoleInfo aris;                       /// account -> AccountInfo, values also enumerable by role
        uint quorum;                                    /// `Yay` votes required to pass a proposal
        uint peakNonce;                                 /// Highest nonce used, see NONCE_SEED
        mapping(address => ARI.AccountInfo) pending;    /// Key: pending account, info for pending admin add

        uint[5] __gap; // Always last field, for upgradeability, reduce size by slots used for new fields
    }

    // ────────────────────────────────────────────────────────────────────────────
    // Functions
    // ────────────────────────────────────────────────────────────────────────────

    // ───────────────────────────────────────
    // Setup
    // ───────────────────────────────────────

    /// @dev Init an Account Manager struct: `AccountMgr`
    /// @param mgr Primary struct in this library
    /// @param quorum Yays required for a consensus to pass a proposal, also minimum voters
    /// @param roleRequests Must contain adds for >=1 Admin, >=1 Agent, >=`quorum` Voters
    function _AccountMgr_init(AccountMgr storage mgr, uint quorum, RoleRequest[] calldata roleRequests) internal {
        if (quorum < 1 || RoleLenMax < quorum) revert OutOfRange(quorum, 1, RoleLenMax);
        mgr.quorum = quorum;
        emit QuorumChanged(0, quorum);

        // Add accounts to each role
        mgr.peakNonce = NonceAtInit; // Use 1-step Admin Add (only for init)
        roleApplyRequestsFromCd(mgr, roleRequests);

        // Use 2-step Admin Add post-init
        mgr.peakNonce = NonceAtInit + 1;
    }

    // ───────────────────────────────────────
    // Role management
    // ───────────────────────────────────────

    /// @dev Set count of approvals required to pass a proposal. Sufficient voters must exist
    /// @param newQuorum Value to set, must be in range: [1, len(voters)]
    function setQuorum(AccountMgr storage mgr, uint newQuorum) internal {
        uint votersLen = mgr.aris.voters.length;
        if (votersLen < newQuorum || RoleLenMax < newQuorum) {
            revert RoleLenOutOfRange(newQuorum, 1, RoleLenMax, AC.Role.Voter);
        }
        uint oldQuorum = mgr.quorum;
        mgr.quorum = newQuorum;
        emit QuorumChanged(oldQuorum, newQuorum);
    }

    /// @dev Add an account to a role - an account may have 1 role, limits verified downstream
    /// - Only `adminGrantStep2` should be used to to finalize a pending admin
    function addAccount(AccountMgr storage mgr, address account, Role role) internal {
        AC.Role currRole = ARI.getRole(mgr.aris, account);
        if (currRole != AC.Role.None) revert ARI.AccountHasRole(account, currRole); // Already has role

        uint peakNonce = mgr.peakNonce;

        // Admins do a 2-step grant (pending + accept), except during `_AccountMgr_init` when peakNonce == NonceAtInit
        if (role == Role.Admin && peakNonce > NonceAtInit) { // then check for a pending account
            // When used in the `mgr.pending`, AccountInfo fields meanings are overidden (less size), described below
            ARI.AccountInfo storage ai = mgr.pending[account];
            if (ai.nonce != NonceAtInit) { // then, Add Admin (step 1 of 2)
                if (ai.role != Role.None) revert ChangeAlreadyPending(account, role);
                ai.role = Role.Admin;   // Pending role
                // `account`            // Not used in a 2-step grant
                // `nonce`              // Controls execution path during a 2-step grant
                emit AdminAddPending(account);
                return;
            }
            // Add Admin (step 2 of 2)
            delete mgr.pending[account];
        }

        ARI.add(mgr.aris, account, role, peakNonce);
    }

    /// @dev Remove an account from a role, limits verified downstream
    function removeAccount(AccountMgr storage mgr, address account) internal {
        if (mgr.pending[account].role == Role.Admin) { // then pending admin
            // Remove from pending
            delete mgr.pending[account];
            emit AdminAddCanceled(account);
            return; // Since account was pending the role was not granted
        }
        if (ARI.getRole(mgr.aris, account) == AC.Role.None) revert ARI.AccountHasRole(account, AC.Role.None);
        ARI.remove(mgr.aris, account);
    }

    /// @dev Accept/reject an admin account during a 2-step grant process
    /// @param account Pending admin account
    /// @param accept Whether the account is accepting or rejecting the access
    function adminGrantStep2(AccountMgr storage mgr, address account, bool accept) internal {
        // Access control: Ensure account is a pending admin
        ARI.AccountInfo storage ai = mgr.pending[account];
        Role role = ai.role;
        if (role != Role.Admin) revert ARI.AccountHasRole(account, role);
        if (accept) {
            // `nonce` field meaning is overridden here to trigger step 2 of 2-step grant (`ai` state is temporary)
            ai.nonce = NonceAtInit;
            addAccount(mgr, account, role);
        } else {
            removeAccount(mgr, account);
        }
    }

    /// @dev Apply role changes (add/remove) via requests in calldata
    /// @param roleRequests A series of requests with role parameters for each
    function roleApplyRequestsFromCd(AccountMgr storage mgr, RoleRequest[] calldata roleRequests) internal {
        uint roleRequestsLen = roleRequests.length;
        for (uint i = 0; i < roleRequestsLen; ++i) { // Upper bound: RoleReqLenMax
            RoleRequest calldata rr = roleRequests[i];
            if (rr.add) {
                addAccount(mgr, rr.account, rr.role);
            } else {
                removeAccount(mgr, rr.account);
            }
        }
        _roleRangeCheck(mgr);
    }

    /// @dev Apply role changes (add/remove) via requests in storage
    /// @param roleRequests A series of requests with role parameters for each
    function roleApplyRequestsFromStore(AccountMgr storage mgr, RoleRequest[] storage roleRequests) internal {
        uint roleRequestsLen = roleRequests.length;
        for (uint i = 0; i < roleRequestsLen; ++i) { // Upper bound: RoleReqLenMax
            RoleRequest memory rr = roleRequests[i]; // Copy storage to memory
            if (rr.add) {
                addAccount(mgr, rr.account, rr.role);
            } else {
                removeAccount(mgr, rr.account);
            }
        }
        _roleRangeCheck(mgr);
    }

    /// @dev Verify cumulative results to allow changes that may breach limits in isolation.
    /// - All roles are checked rather than tracking those affected, at worst 2 extra checks, at best many less
    /// - In debug events may have already happened and then a check fails, in prod the revert suppresses events
    function _roleRangeCheck(AccountMgr storage mgr) private view {
        _requireRoleLength(mgr.aris.admins.length, 1, RoleLenMax, Role.Admin);
        _requireRoleLength(mgr.aris.agents.length, 1, RoleLenMax, Role.Agent);
        _requireRoleLength(mgr.aris.voters.length, mgr.quorum, RoleLenMax, Role.Voter);
    }

    /// @dev Require a role length in range [min, max]
    function _requireRoleLength(uint value, uint min, uint max, Role role) private pure {
        if (value < min || max < value) revert RoleLenOutOfRange(value, min, max, role);
    }
}
