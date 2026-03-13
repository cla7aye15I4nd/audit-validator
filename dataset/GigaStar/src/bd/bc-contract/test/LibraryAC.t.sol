// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

// See LIB_PATHS
import '../lib/forge-std/src/console.sol';
import '../lib/forge-std/src/Test.sol';
import '../lib/forge-std/src/StdError.sol';

import '../contract/v1_0/LibraryAC.sol';
import '../contract/v1_0/Types.sol';

// Helper to ensure reverts are at a lower level in the callstack to allow them to be handled
contract AC_AccountMgr_TestHelper {
    AC.AccountMgr private _mgr;

    AC.RoleRequest[] _rrs; // Provides param translation

    function init(uint quorum, AC.RoleRequest[] calldata rrs) external {
        AC._AccountMgr_init(_mgr, quorum, rrs);
    }

    function setQuorum(uint newQuorum) external {
        return AC.setQuorum(_mgr, newQuorum);
    }

    function addAccount(address account, AC.Role role) external {
        return AC.addAccount(_mgr, account, role);
    }

    function removeAccount(address account) external {
        AC.removeAccount(_mgr, account);
    }

    function roleApplyRequestsFrom(AC.RoleRequest[] calldata rrs, bool useCalldata) external {
        if (useCalldata) {
            return AC.roleApplyRequestsFromCd(_mgr, rrs);               // Call with calldata param
        }
        for (uint i = 0; i < _rrs.length; ++i) _rrs.pop();          // Clear
        for (uint i = 0; i < rrs.length; ++i) _rrs.push(rrs[i]);    // Copy calldata to storage
        return AC.roleApplyRequestsFromStore(_mgr, _rrs);           // Call with storage param
    }

    function adminGrantStep2(address account, bool accept) external {
        return AC.adminGrantStep2(_mgr, account, accept);
    }

    function getRole(address account) external view returns(AC.Role) {
        return ARI.getRole(_mgr.aris, account);
    }

    function getAccountInfo(address account) external view returns(ARI.AccountInfo memory accountInfo) {
        return ARI.get(_mgr.aris, account);
    }

    function getQuorum() external view returns (uint) { return _mgr.quorum; }
}

contract AC_AccountMgr_Test is Test {
    AC.AccountMgr private _mgr;

    // Init vars for test
    uint constant quorum = 3;

    address constant aE = AddrZero;
    address constant a1 = address(11); // Addresses
    address constant a2 = address(12);
    address constant a3 = address(13);
    address constant a4 = address(14);
    address constant a5 = address(15);
    address constant a6 = address(16);
    address constant a7 = address(17);
    address constant a8 = address(18);

    uint constant nE = 0;   // Nonce empty
    uint constant n1 = 1;   // Nonces
    uint constant n2 = 2;
    uint constant n3 = 3;
    uint constant n4 = 4;
    uint constant n5 = 5;
    uint constant n6 = 6;

    AC.Role constant rE = AC.Role.None;
    AC.Role constant r1 = AC.Role.Admin;
    AC.Role constant r2 = AC.Role.Agent;
    AC.Role constant r3 = AC.Role.Agent;
    AC.Role constant r4 = AC.Role.Voter;
    AC.Role constant r5 = AC.Role.Voter;
    AC.Role constant r6 = AC.Role.Voter;
    AC.Role constant r7 = AC.Role.Voter;
    AC.Role constant r8 = AC.Role.Admin;

    AC.RoleRequest rrE = _makeRoleRequest(aE, true, rE);
    AC.RoleRequest rr1 = _makeRoleRequest(a1, true, r1);
    AC.RoleRequest rr2 = _makeRoleRequest(a2, true, r2);
    AC.RoleRequest rr3 = _makeRoleRequest(a3, true, r3);
    AC.RoleRequest rr4 = _makeRoleRequest(a4, true, r4);
    AC.RoleRequest rr5 = _makeRoleRequest(a5, true, r5);
    AC.RoleRequest rr6 = _makeRoleRequest(a6, true, r6);
    AC.RoleRequest rr7 = _makeRoleRequest(a7, true, r7);
    AC.RoleRequest rr8 = _makeRoleRequest(a8, true, r8);

    function setUp() public {
    }

    function _makeRoleRequest(address account, bool add, AC.Role role) public pure
        returns(AC.RoleRequest memory)
    {
        return AC.RoleRequest({ account: account, add: add, role: role, __gap: Util.gap5() });
    }

    function _add(AC.RoleRequest memory a) public {
        AC.addAccount(_mgr, a.account, a.role);
    }

    function _initAllRoles(AC_AccountMgr_TestHelper helper) private {
        // Init all roles
        AC.RoleRequest[] memory roleRequests = new AC.RoleRequest[](5);
        roleRequests[0] = rr1; // admin
        roleRequests[1] = rr2; // agent
        roleRequests[2] = rr4; // voter
        roleRequests[3] = rr5; // voter
        roleRequests[4] = rr6; // voter
        helper.init(quorum, roleRequests);
    }

    function test_AC_mgr_init() public {
        AC_AccountMgr_TestHelper helper = new AC_AccountMgr_TestHelper();
        AC.RoleRequest[] memory roleRequests = new AC.RoleRequest[](0);

        // Revert due to quorum out-of-range: Too low
        vm.expectRevert(abi.encodeWithSelector(AC.OutOfRange.selector, 0, 1, AC.RoleLenMax));
        helper.init(0, roleRequests);

        // Revert due to quorum out-of-range: Too high
        vm.expectRevert(abi.encodeWithSelector(AC.OutOfRange.selector, AC.RoleLenMax+1, 1, AC.RoleLenMax));
        helper.init(AC.RoleLenMax + 1, roleRequests);

        roleRequests = new AC.RoleRequest[](1);
        roleRequests[0] = rr4; // voter

        // Revert due to too few admin roles
        vm.expectRevert(abi.encodeWithSelector(AC.RoleLenOutOfRange.selector, 0, 1, AC.RoleLenMax, AC.Role.Admin));
        helper.init(quorum, roleRequests);

        roleRequests = new AC.RoleRequest[](1);
        roleRequests[0] = rr1; // admin

        // Revert due to too few agent roles
        vm.expectRevert(abi.encodeWithSelector(AC.RoleLenOutOfRange.selector, 0, 1, AC.RoleLenMax, AC.Role.Agent));
        helper.init(quorum, roleRequests);

        roleRequests = new AC.RoleRequest[](2);
        roleRequests[0] = rr1; // admin
        roleRequests[1] = rr2; // agent

        // Revert due to too few voter roles (< quorum)
        vm.expectRevert(abi.encodeWithSelector(AC.RoleLenOutOfRange.selector, 0, quorum, AC.RoleLenMax, AC.Role.Voter));
        helper.init(quorum, roleRequests);

        // Sufficient number of accounts for each role
        _initAllRoles(helper); // No revert
    }

    function test_AC_mgr_setQuorum() public {
        // Init all roles
        AC_AccountMgr_TestHelper helper = new AC_AccountMgr_TestHelper();
        _initAllRoles(helper);

        // Reduce quorum to 1
        vm.expectEmit();
        emit AC.QuorumChanged(quorum, 1);
        helper.setQuorum(1);
        assertEq(1, helper.getQuorum(), 'quorum');

        // Increase quorum to 3
        vm.expectEmit();
        emit AC.QuorumChanged(1, 3);
        helper.setQuorum(3);
        assertEq(3, helper.getQuorum(), 'quorum');

        // Increase quorum to 4; Revert due to too few voter roles (< quorum)
        vm.expectRevert(abi.encodeWithSelector(AC.RoleLenOutOfRange.selector, 4, 1, AC.RoleLenMax, AC.Role.Voter));
        helper.setQuorum(4);
        assertEq(3, helper.getQuorum(), 'quorum');
    }

    function _verifyRole(AC_AccountMgr_TestHelper helper, address account, AC.Role role) private view {
        AC.Role actualRole = helper.getRole(account);
        assertEq(uint(role), uint(actualRole), 'verify role');
        if (actualRole == AC.Role.None) return;

        ARI.AccountInfo memory ai = helper.getAccountInfo(account);
        assertEq(account, ai.account, 'verify ai.account');
        assertEq(uint(role), uint(ai.role), 'verify ai.role');
        assertEq(2, ai.nonce, 'verify ai.nonce');
    }

    function test_AC_mgr_add_remove_account_calldata() public {
        add_remove_account(true);
    }

    function test_AC_mgr_add_remove_account_storage() public {
        add_remove_account(false);
    }

    function add_remove_account(bool useCalldata) private {
        // Init all roles
        AC_AccountMgr_TestHelper helper = new AC_AccountMgr_TestHelper();
        _initAllRoles(helper);

        // Expect event during add
        vm.expectEmit();
        emit ARI.RoleChanged(true, AC.Role.Voter, rr7.account);

        // Add account rr7 as voter
        AC.RoleRequest[] memory roleRequests = new AC.RoleRequest[](1);
        roleRequests[0] = rr7;
        helper.roleApplyRequestsFrom(roleRequests, useCalldata);

        // Verify voter role granted
        _verifyRole(helper, rr7.account, AC.Role.Voter);

        // Expect event during remove
        vm.expectEmit();
        emit ARI.RoleChanged(false, AC.Role.Voter, rr7.account);

        // Remove rr7 account
        roleRequests[0].add = false;
        helper.roleApplyRequestsFrom(roleRequests, useCalldata);
    }

    function test_AC_mgr_duplicate_admin_add() public {
        // Init all roles
        AC_AccountMgr_TestHelper helper = new AC_AccountMgr_TestHelper();
        _initAllRoles(helper);

        // Add account rr8 as admin (step 1 of 2-step grant)
        helper.addAccount(rr8.account, rr8.role);

        // Add account rr8 as admin AGAIN; revert due to a change already pending
        vm.expectRevert(abi.encodeWithSelector(AC.ChangeAlreadyPending.selector, rr8, rr8.role));
        helper.addAccount(rr8.account, rr8.role);

        // Account rr8 accepts admin grant (step 2 of 2-step grant)
        helper.adminGrantStep2(rr8.account, true);

        // Verify admin role granted
        _verifyRole(helper, rr8.account, AC.Role.Admin);

        // Remove account
        helper.removeAccount(rr8.account);

        // // Verify admin role removed; revert due to unknown account
        // vm.expectRevert(abi.encodeWithSelector(ARI.RoleOutOfRange.selector, AC.Role.None, AC.Role.None, AC.Role.Count));

        // Verify account now unknown
        _verifyRole(helper, rr8.account, AC.Role.None);
    }

    // Do an admin 2-step grant: add + either accept/reject
    function _adminGrantStep2(bool accept) public {
        // Init all roles
        AC_AccountMgr_TestHelper helper = new AC_AccountMgr_TestHelper();

        // Init all roles
        _initAllRoles(helper);

        // Expect event during add
        vm.expectEmit();
        emit AC.AdminAddPending(rr8.account);

        // Add account rr8 as admin (step 1 of 2-step grant)
        helper.addAccount(rr8.account, rr8.role);

        // Expect event during accept/reject
        vm.expectEmit();
        if (accept) {
            emit ARI.RoleChanged(true, AC.Role.Admin, rr8.account);
        } else {
            emit AC.AdminAddCanceled(rr8.account);
        }

        // Account rr8 accepts admin grant (step 2 of 2-step grant)
        helper.adminGrantStep2(rr8.account, accept);

        if (accept) {
            // Verify admin role granted
            _verifyRole(helper, rr8.account, AC.Role.Admin);
        } else {
            // Verify account now unknown
            _verifyRole(helper, rr8.account, AC.Role.None);
        }
    }

    function test_AC_adminGrantStep2_accept() public {
        _adminGrantStep2(true);
    }

    function test_AC_adminGrantStep2_reject() public {
        _adminGrantStep2(false);
    }
}
