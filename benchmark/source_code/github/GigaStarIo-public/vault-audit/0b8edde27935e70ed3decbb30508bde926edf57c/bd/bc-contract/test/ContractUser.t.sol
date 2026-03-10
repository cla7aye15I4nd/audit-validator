// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

// See LIB_PATHS
import '../lib/forge-std/src/Test.sol';

import '../contract/v1_0/ICallTracker.sol';
import '../contract/v1_0/IContractUser.sol';
import '../contract/v1_0/IRoleMgr.sol';
import '../contract/v1_0/IVersion.sol';
import '../contract/v1_0/LibraryAC.sol';
import '../contract/v1_0/LibraryCU.sol';
import '../contract/v1_0/ContractUser.sol';
import '../contract/v1_0/Types.sol';

import './LibraryTest.sol';
import './MockVault.sol';

// Sufficient to be used with `setContract`
contract MockMgr is IVersion {
    function getVersion() external pure override returns (uint) {
        return 1;
    }
}

// Helper to ensure reverts are at a lower level in the callstack to allow them to be handled
contract ContractUserSpy is ContractUser {
    uint public constant VERSION = 12_34;

    constructor(address creator, UUID reqId) {
        __ContractUser_init(creator, reqId);
    }

    function requireVaultOrAdminOrCreator(address a) external {
        _requireVaultOrAdminOrCreator(a);
    }

    function getVersion() external pure override returns (uint) {
        return VERSION;
    }
}

contract ContractUserTest is Test {
    ContractUserSpy spy;
    MockVault mockVault;
    address vault;
    address creator        = address(new MockMgr());
    address xferMgr        = address(new MockMgr());
    address revMgr         = address(new MockMgr());
    address instRevMgr     = address(new MockMgr());
    address balMgr         = address(new MockMgr());
    address earnDateMgr    = address(new MockMgr());
    address boxMgr         = address(new MockMgr());
    address admin          = address(new MockMgr());
    address agent          = address(new MockMgr());
    address voter1         = address(new MockMgr());
    address voter2         = address(new MockMgr());
    address other          = address(new MockMgr());

    uint40 constant NoSeqNum = 0;
    UUID constant NoReqId = UuidZero;

    function setUp() public {
        mockVault = new MockVault();
        vault = address(mockVault);
        UUID reqId = _newUuid();
        spy = new ContractUserSpy(creator, reqId);
        vm.prank(creator);
        mockVault.addMockRole(admin, AC.Role.Admin);
        mockVault.addMockRole(agent, AC.Role.Agent);
        mockVault.addMockRole(voter1, AC.Role.Voter);
        mockVault.addMockRole(voter2, AC.Role.Voter);
        assertEq(spy.VERSION(), spy.getVersion());

        _labelAddresses();
    }

    uint _counter = 0;
    function _newUuid() private returns (UUID) {
        ++_counter;
        return UUID.wrap(bytes16(uint128(_counter)));
    }

    function _labelAddresses() private {
        vm.label(address(spy), 'spy');
        vm.label(address(mockVault), 'vault');
        vm.label(creator,       'creator');
        vm.label(xferMgr,   'xferMgr');
        vm.label(revMgr,        'revMgr');
        vm.label(instRevMgr,    'instRevMgr');
        vm.label(balMgr,        'balMgr');
        vm.label(earnDateMgr,   'earnDateMgr');
        vm.label(boxMgr,        'boxMgr');
        vm.label(admin,         'admin');
        vm.label(agent,         'agent');
        vm.label(voter1,        'voter1');
        vm.label(voter2,        'voter2');
        vm.label(other,         'other');
    }

    function test_ContractUser_requireVaultOrAdminOrCreator() public {
        // For each address

        console2.logString('Not authorized');
        vm.expectRevert(abi.encodeWithSelector(AC.AccessDenied.selector, other));
        vm.prank(other);
        spy.requireVaultOrAdminOrCreator(other);

        console2.logString('Not authorized; Vault not set');
        vm.expectRevert(abi.encodeWithSelector(AC.AccessDenied.selector, vault));
        vm.prank(vault);
        spy.requireVaultOrAdminOrCreator(vault);

        uint40 seqNum = spy.getSeqNum(creator);
        UUID reqId = _newUuid();
        for (uint i = 0; i < 2; ++i) {
            string memory suffix = i == 0 ? '(initial)' : '(duplicate, noop)';
            console2.log(T.concat('setContract ', suffix, ', seqNum: ', vm.toString(seqNum)));
            vm.prank(creator);
            spy.setContract(seqNum, reqId, CU.Vault, vault);
            assertEq(seqNum + 1, spy.getSeqNum(creator), 'seqNum');
            vm.prank(creator);
            ICallTracker.CallRes memory cr = spy.getCallResBySeqNum(seqNum);
            assertNotEq(uint(0), uint(cr.blockNum), 'blockNum');
            T.checkEqual(vm, reqId, cr.reqId, 'reqId');
            assertEq(1, uint(cr.rc), 'rc');
        }

        console2.logString('Authorized vault');
        vm.prank(vault);
        spy.requireVaultOrAdminOrCreator(vault);

        console2.logString('Authorized creator');
        vm.prank(creator);
        spy.requireVaultOrAdminOrCreator(creator);
    }

    // All successful checks
    function test_ContractUser_getContract() public {
        vm.startPrank(creator);

        spy.setContract(NoSeqNum, NoReqId, CU.Creator,     creator);
        spy.setContract(NoSeqNum, NoReqId, CU.Vault,       vault);
        spy.setContract(NoSeqNum, NoReqId, CU.XferMgr, xferMgr);
        spy.setContract(NoSeqNum, NoReqId, CU.RevMgr,      revMgr);
        spy.setContract(NoSeqNum, NoReqId, CU.InstRevMgr,  instRevMgr);
        spy.setContract(NoSeqNum, NoReqId, CU.BalanceMgr,  balMgr);
        spy.setContract(NoSeqNum, NoReqId, CU.EarnDateMgr, earnDateMgr);
        spy.setContract(NoSeqNum, NoReqId, CU.BoxMgr,      boxMgr);

        assertEq(spy.getContract(CU.Creator), creator);
        assertEq(spy.getContract(CU.Vault), vault);
        assertEq(spy.getContract(CU.XferMgr), xferMgr);
        assertEq(spy.getContract(CU.RevMgr), revMgr);
        assertEq(spy.getContract(CU.InstRevMgr), instRevMgr);
        assertEq(spy.getContract(CU.BalanceMgr), balMgr);
        assertEq(spy.getContract(CU.EarnDateMgr), earnDateMgr);
        assertEq(spy.getContract(CU.BoxMgr), boxMgr);
    }

    function test_ContractUser_false() public {
        vm.startPrank(creator);
        uint40 seqNum = spy.getSeqNum(creator);
        UUID reqId = _newUuid();

        console2.log('Changed, seqNum: ', seqNum);
        spy.setContract(seqNum, reqId, CU.BoxMgr, other);
        assertEq(spy.getCallResBySeqNum(seqNum).rc, uint16(1));

        console2.log('No change - Zero addr');
        reqId = _newUuid();
        spy.setContract(++seqNum, reqId, CU.BoxMgr, AddrZero);
        assertEq(spy.getCallResBySeqNum(seqNum).rc, uint16(0));

        console2.log('No change - Same as existing');
        reqId = _newUuid();
        spy.setContract(++seqNum, reqId, CU.BoxMgr, other);
        assertEq(spy.getCallResBySeqNum(seqNum).rc, uint16(0));

        console2.log('No change - Invalid enum');
        reqId = _newUuid();
        spy.setContract(++seqNum, reqId, CU.Count, other);
        assertEq(spy.getCallResBySeqNum(seqNum).rc, uint16(0));
    }
}
