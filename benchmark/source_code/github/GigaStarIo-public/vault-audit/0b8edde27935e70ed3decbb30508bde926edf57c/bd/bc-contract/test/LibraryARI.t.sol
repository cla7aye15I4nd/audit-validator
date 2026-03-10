// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

// See LIB_PATHS
import '../lib/forge-std/src/console.sol';
import '../lib/forge-std/src/Test.sol';
import '../lib/forge-std/src/StdError.sol';

import '../contract/v1_0/LibraryARI.sol';
import '../contract/v1_0/LibraryUtil.sol';
import '../contract/v1_0/Types.sol';

// Helper to ensure reverts are at a lower level in the callstack to allow them to be handled
contract ARI_AccountRoleInfo_TestHelper {
    ARI.AccountRoleInfo private _ari;

    function add(ARI.AccountInfo memory a) external {
        ARI.add(_ari, a.account, a.role, a.nonce);
    }

    function get(address account) external view returns(ARI.AccountInfo memory accountInfo) {
        return ARI.get(_ari, account);
    }
}

contract ARI_AccountRoleInfo_Test is Test {
    ARI.AccountRoleInfo private _ari;

    // Init vars for test
    address constant aE = AddrZero;
    address constant a0 = address(10); // Addresses
    address constant a1 = address(11);
    address constant a2 = address(12);
    address constant a3 = address(13);
    address constant a4 = address(14);
    address constant a5 = address(15);
    address constant a6 = address(16);

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

    ARI.AccountInfo aiE = _makeAccountInfo(aE, nE, rE);
    ARI.AccountInfo ai1 = _makeAccountInfo(a1, n1, r1);
    ARI.AccountInfo ai2 = _makeAccountInfo(a2, n2, r2);
    ARI.AccountInfo ai3 = _makeAccountInfo(a3, n3, r3);
    ARI.AccountInfo ai4 = _makeAccountInfo(a4, n4, r4);
    ARI.AccountInfo ai5 = _makeAccountInfo(a5, n5, r5);
    ARI.AccountInfo ai6 = _makeAccountInfo(a6, n6, r6);

    function setUp() public {
    }

    function _makeAccountInfo(address account, uint nonce, AC.Role role) public pure
        returns(ARI.AccountInfo memory)
    {
        return ARI.AccountInfo({account: account, nonce: nonce, role: role, __gap: Util.gap5()});
    }

    function _verifyAccount(uint index, ARI.AccountInfo memory expect) internal view {
        ARI.RoleToIndex storage rti = _ari.map[expect.account]; // Map lookup
        assertEq(uint(rti.role), uint(expect.role), 'role in map');
        assertEq(rti.index, index, 'index in map');

        ARI.AccountInfo[] storage infos;
             if (rti.role == AC.Role.Admin) infos = _ari.admins;
        else if (rti.role == AC.Role.Agent) infos = _ari.agents;
        else if (rti.role == AC.Role.Voter) infos = _ari.voters;
        else revert('Unexpected role');

        assertGt(infos.length, index, 'array length');
        ARI.AccountInfo storage ai = infos[index]; // Array lookup
        assertEq(ai.account, expect.account, 'account in array');
        assertEq(ai.nonce, expect.nonce, 'nonce in array');
        assertEq(uint(ai.role), uint(expect.role), 'role in array');
    }

    function _add(ARI.AccountInfo memory a) public {
        ARI.add(_ari, a.account, a.role, a.nonce);
    }

    // Another contract is used to ensure the error is at a lower level in the callstack so it may be handled
    function test_ARI_ari_reverts() public {
        ARI_AccountRoleInfo_TestHelper helper = new ARI_AccountRoleInfo_TestHelper();
        helper.add(ai1);

        // Revert due to duplicate
        vm.expectRevert(abi.encodeWithSelector(ARI.AccountHasRole.selector, ai1.account, ai1.role));
        helper.add(ai1);

        // Revert due to no account for request
        vm.expectRevert(abi.encodeWithSelector(ARI.RoleOutOfRange.selector, rE, AC.Role.None, AC.Role.Count));
        helper.get(aE);
    }

    function test_ARI_ari_add_remove() public {
        assertEq(_ari.admins.length, 0);
        assertEq(_ari.voters.length, 0);
        assertEq(_ari.agents.length, 0);

        // ------------------------
        // Add accounts
        // ------------------------

        console2.log('Add 1 admin');
        _add(ai1);
        assertEq(_ari.admins.length, 1, 'admins.length');
        assertEq(_ari.voters.length, 0, 'voters.length');
        assertEq(_ari.agents.length, 0, 'agents.length');
        _verifyAccount(0, ai1);

        console2.log('Add 1 agent');
        _add(ai2);
        assertEq(_ari.admins.length, 1, 'admins.length');
        assertEq(_ari.voters.length, 0, 'voters.length');
        assertEq(_ari.agents.length, 1, 'agents.length');
        _verifyAccount(0, ai2);

        console2.log('Add 1 agent');
        _add(ai3);
        assertEq(_ari.admins.length, 1, 'admins.length');
        assertEq(_ari.voters.length, 0, 'voters.length');
        assertEq(_ari.agents.length, 2, 'agents.length');
        _verifyAccount(1, ai3);

        console2.log('Add 1 voter A');
        _add(ai4);
        assertEq(_ari.admins.length, 1, 'admins.length');
        assertEq(_ari.voters.length, 1, 'voters.length');
        assertEq(_ari.agents.length, 2, 'agents.length');
        _verifyAccount(0, ai4);

        console2.log('Add 1 voter B');
        _add(ai5);
        assertEq(_ari.admins.length, 1, 'admins.length');
        assertEq(_ari.voters.length, 2, 'voters.length');
        assertEq(_ari.agents.length, 2, 'agents.length');
        _verifyAccount(1, ai5);

        console2.log('Add 1 voter C');
        _add(ai6);
        assertEq(_ari.admins.length, 1, 'admins.length');
        assertEq(_ari.voters.length, 3, 'voters.length');
        assertEq(_ari.agents.length, 2, 'agents.length');
        _verifyAccount(2, ai6);

        // ------------------------
        // Get all by account
        // ------------------------
        console2.log('Get all by account');
        assertEq(ARI.get(_ari, ai1.account).account, ai1.account);
        assertEq(ARI.get(_ari, ai2.account).account, ai2.account);
        assertEq(ARI.get(_ari, ai3.account).account, ai3.account);
        assertEq(ARI.get(_ari, ai4.account).account, ai4.account);
        assertEq(ARI.get(_ari, ai5.account).account, ai5.account);
        assertEq(ARI.get(_ari, ai6.account).account, ai6.account);

        // ------------------------
        // Remove accounts
        // ------------------------

        console2.log('Remove an agent A');
        ARI.remove(_ari, ai2.account);
        assertEq(_ari.admins.length, 1, 'admins.length');
        assertEq(_ari.voters.length, 3, 'voters.length');
        assertEq(_ari.agents.length, 1, 'agents.length');
        _verifyAccount(0, ai3);

        console2.log('Remove an agent B');
        ARI.remove(_ari, ai3.account);
        assertEq(_ari.admins.length, 1, 'admins.length');
        assertEq(_ari.voters.length, 3, 'voters.length');
        assertEq(_ari.agents.length, 0, 'agents.length');

        console2.log('Remove a voter A');
        ARI.remove(_ari, ai6.account);
        assertEq(_ari.admins.length, 1, 'admins.length');
        assertEq(_ari.voters.length, 2, 'voters.length');
        assertEq(_ari.agents.length, 0, 'agents.length');
        _verifyAccount(1, ai5);

        console2.log('Remove a voter B');
        ARI.remove(_ari, ai4.account);
        assertEq(_ari.admins.length, 1, 'admins.length');
        assertEq(_ari.voters.length, 1, 'voters.length');
        assertEq(_ari.agents.length, 0, 'agents.length');
        _verifyAccount(0, ai5);

        console2.log('Remove a voter C');
        ARI.remove(_ari, ai5.account);
        assertEq(_ari.admins.length, 1, 'admins.length');
        assertEq(_ari.voters.length, 0, 'voters.length');
        assertEq(_ari.agents.length, 0, 'agents.length');

        console2.log('Remove a voter D');
        ARI.remove(_ari, ai1.account);
        assertEq(_ari.admins.length, 0, 'admins.length');
        assertEq(_ari.voters.length, 0, 'voters.length');
        assertEq(_ari.agents.length, 0, 'agents.length');
    }
}
