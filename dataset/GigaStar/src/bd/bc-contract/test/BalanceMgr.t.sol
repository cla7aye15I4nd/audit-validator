// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

// See LIB_PATHS
import '../lib/forge-std/src/Test.sol';

import '../lib/openzeppelin-contracts/contracts/proxy/Clones.sol';
import '../lib/openzeppelin-contracts/contracts/interfaces/IERC1155Receiver.sol';
import '../lib/openzeppelin-contracts/contracts/interfaces/IERC1967.sol';

import '../contract/v1_0/BalanceMgr.sol';
import '../contract/v1_0/Erc20Test.sol';
import '../contract/v1_0/LogicDeployers.sol';
import '../contract/v1_0/ProxyDeployers.sol';
import '../contract/v1_0/IBalanceMgr.sol';
import '../contract/v1_0/ICallTracker.sol';
import '../contract/v1_0/IContractUser.sol';
import '../contract/v1_0/IVersion.sol';
import '../contract/v1_0/LibraryAC.sol';
import '../contract/v1_0/LibraryBI.sol';
import '../contract/v1_0/LibraryCU.sol';
import '../contract/v1_0/RevMgr.sol';
import '../contract/v1_0/Types.sol';

import './Const.sol';
import './LibraryTest.sol';
import './MockVault.sol';

contract BalanceMgrLatest is BalanceMgr {
    function getVersion() public pure override returns (uint) { return 999; }
}

contract MockXferMgr is IVersion {
    function getVersion() external pure override returns (uint) { return 1; }
}

contract MockRevMgr is IVersion {
    function getVersion() external pure override returns (uint) { return 1; }
}

contract BalanceMgrTest is Test {
    IBalanceMgr mgr;

    address creator = address(this);
    address vault = address(new MockVault());
    address agent = address(1);
    address spender1 = address(2);
    address spender2 = address(3);
    address xferMgr = address(new MockXferMgr());
    address revMgr = address(new RevMgr());
    address other = address(6);

    UUID constant eidE = UUID.wrap(0x00000000000000000000000000000000); // External ID empty: 0x prefix + 32 hex digits
    UUID constant eid1 = UUID.wrap(0x00000000000000000000000000000001); // External IDs
    UUID constant eid2 = UUID.wrap(0x00000000000000000000000000000002);
    UUID constant eid3 = UUID.wrap(0x00000000000000000000000000000003);

    Erc20Test tokenUsdc = new Erc20Test('USDC');
    Erc20Test tokenEurc = new Erc20Test('EURC');
    address usdcAddr = address(tokenUsdc);
    address eurcAddr = address(tokenEurc);

    uint40 constant NoSeqNum = 0;
    UUID constant NoReqId = UuidZero;

    function setUp() public {
        address mgrLogic = (new BalanceMgrLogicDeployer()).deployLogic();
        assertNotEq(mgrLogic, AddrZero, 'mgrLogic');

        address mgrProxyAddr = (new ProxyDeployer()).deployProxy(mgrLogic, 'BalanceMgr',
            abi.encodeWithSelector(IBalanceMgr.initialize.selector, creator, NoReqId));
        assertNotEq(mgrProxyAddr, AddrZero, 'mgrProxyAddr');
        mgr = IBalanceMgr(mgrProxyAddr);
        assertEq(10, mgr.getVersion(), 'getVersion');
        assertEq(mgr.getContract(CU.Creator), creator, 'getCreator');

        MockVault(vault).addMockRole(agent, AC.Role.Agent);
        mgr.setContract(NoSeqNum, NoReqId, CU.Vault, vault);
        assertEq(mgr.getContract(CU.Vault), vault, 'vault');

        mgr.setContract(NoSeqNum, NoReqId, CU.XferMgr, xferMgr);
        assertEq(mgr.getContract(CU.XferMgr), xferMgr, 'xferMgr');

        mgr.setContract(NoSeqNum, NoReqId, CU.RevMgr, revMgr);
        assertEq(mgr.getContract(CU.RevMgr), revMgr, 'revMgr');
    }

    uint _counter = 0;
    function _newUuid() private returns (UUID) {
        ++_counter;
        return UUID.wrap(bytes16(uint128(_counter)));
    }

    function test_BalanceMgr_initialize() public {
        // Attempt to initialize again; revert as not allowed
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        mgr.initialize(creator, NoReqId);
    }

    function test_BalanceMgr_upgrade() public {
        // Deploy a mock upgraded logic
        address newLogic = address(new BalanceMgrLatest());
        assertNotEq(newLogic, AddrZero);

        // Upgrade access denied
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(AC.AccessDenied.selector, other));
        UUPSUpgradeable(address(mgr)).upgradeToAndCall(address(newLogic), '');

        // Upgrade via UUPS with an empty initData
        vm.prank(creator);
        uint40 seqNum = ICallTracker(address(mgr)).getSeqNum(creator);
        UUID reqId = _newUuid();
        UUID reqIdStage = _newUuid();
        vm.prank(creator);
        IContractUser(address(mgr)).preUpgrade(seqNum, reqId, reqIdStage);
        vm.expectEmit();
        emit IERC1967.Upgraded(newLogic);
        vm.prank(creator);
        UUPSUpgradeable(address(mgr)).upgradeToAndCall(address(newLogic), '');

        // Verify
        assertEq(mgr.getVersion(), 999);           // New behavior
        assertEq(mgr.getOwnerBalance(usdcAddr, eidE), 0);    // Old behavior
    }

    function test_BalanceMgr_misc() public {
        // ----------
        // getOwnerBalance
        // ----------
        console2.log('getOwnerBalance, all empty');
        vm.prank(other);
        assertEq(mgr.getOwnerBalance(usdcAddr, eidE), 0, 'balance addrZero');
        assertEq(mgr.getOwnerBalance(usdcAddr, eid1), 0, 'balance 0');
        assertEq(mgr.getOwnerBalance(usdcAddr, eid2), 0, 'balance 1');
        assertEq(mgr.getOwnerBalance(usdcAddr, eid3), 0, 'balance 2');
        UUID[] memory eids = new UUID[](3);
        eids[0] = eid1;
        eids[1] = eid2;
        eids[2] = eid3;

        console2.log('getOwnerBalances, all empty');
        vm.prank(other);
        int[] memory balances = mgr.getOwnerBalances(usdcAddr, eids);
        assertEq(balances.length, 3);
        assertEq(balances[0], 0, 'balances 0');
        assertEq(balances[1], 0, 'balances 1');
        assertEq(balances[2], 0, 'balances 2');

        // ----------
        // setOwnerBalances
        // ----------
        console2.log('setOwnerBalances; Fail due to caller');
        vm.expectRevert(abi.encodeWithSelector(AC.AccessDenied.selector, other));
        vm.prank(other);
        mgr.setOwnerBalances(NoSeqNum, NoReqId, usdcAddr, eids, balances, false);

        uint40 seqNum = mgr.getSeqNum(creator);
        UUID reqId = _newUuid();
        for (uint i = 0; i < 2; ++i) {
            string memory suffix = i == 0 ? '(initial)' : '(duplicate, noop)';
            console2.log(T.concat('setOwnerBalances, 1', suffix));
            if (i == 0) {
                balances[0] = 1;
                balances[1] = 3;
                balances[2] = 7;
            }
            vm.prank(creator);
            mgr.setOwnerBalances(seqNum, reqId, usdcAddr, eids, balances, false);
            assertEq(mgr.getOwnerBalance(usdcAddr, eidE), 0, 'balance addrZero');
            assertEq(mgr.getOwnerBalance(usdcAddr, eid1), 1, 'balance 0');
            assertEq(mgr.getOwnerBalance(usdcAddr, eid2), 3, 'balance 1');
            assertEq(mgr.getOwnerBalance(usdcAddr, eid3), 7, 'balance 2');
            vm.prank(creator);
            assertEq(seqNum + 1, mgr.getSeqNum(creator), 'seqNum');
        }
        ++seqNum;

        console2.log('setOwnerBalances, 2 (relative values / add)');
        balances[0] = 0;
        balances[1] = 1;
        balances[2] = 2;
        vm.prank(creator);
        mgr.setOwnerBalances(NoSeqNum, NoReqId, usdcAddr, eids, balances, true);
        assertEq(mgr.getOwnerBalance(usdcAddr, eidE), 0, 'balance addrZero');
        assertEq(mgr.getOwnerBalance(usdcAddr, eid1), 1, 'balance 0');
        assertEq(mgr.getOwnerBalance(usdcAddr, eid2), 4, 'balance 1');
        assertEq(mgr.getOwnerBalance(usdcAddr, eid3), 9, 'balance 2');

        console2.log('setOwnerBalances, 3 (absolute values / overwrite)');
        eids = new UUID[](2);
        eids[0] = eid2;
        eids[1] = eid3;
        balances = new int[](2);
        balances[0] = -2;
        balances[1] = 7;
        vm.prank(creator);
        mgr.setOwnerBalances(NoSeqNum, NoReqId, usdcAddr, eids, balances, false);
        assertEq(mgr.getOwnerBalance(usdcAddr, eidE), 0, 'balance addrZero');
        assertEq(mgr.getOwnerBalance(usdcAddr, eid1), 1, 'balance 0');
        assertEq(mgr.getOwnerBalance(usdcAddr, eid2), -2, 'balance 1');
        assertEq(mgr.getOwnerBalance(usdcAddr, eid3), 7, 'balance 2');

        // ----------
        // updateBalance
        // ----------
        console2.log('updateBalance; Fail due to caller');
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(AC.AccessDenied.selector, other));
        mgr.updateBalance(usdcAddr, eid1, 0, true);

        console2.log('updateBalance relative; Success');
        assertEq(mgr.getOwnerBalance(usdcAddr, eid1), 1, 'balance before');
        vm.prank(revMgr);
        mgr.updateBalance(usdcAddr, eid1, 1, true);
        assertEq(mgr.getOwnerBalance(usdcAddr, eid1), 2, 'balance after');

        console2.log('updateBalance absolute; Success');
        assertEq(mgr.getOwnerBalance(usdcAddr, eid1), 2, 'balance before');
        vm.prank(revMgr);
        mgr.updateBalance(usdcAddr, eid1, 3, false);
        assertEq(mgr.getOwnerBalance(usdcAddr, eid1), 3, 'balance after');

        // ----------
        // claimQty
        // ----------
        console2.log('claimQty; Fail due to caller');
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(AC.AccessDenied.selector, other));
        assertEq(mgr.claimQty(usdcAddr, eid1, 0), false);

        console2.log('claimQty; Fail qty < balance');
        assertEq(mgr.getOwnerBalance(usdcAddr, eid1), 3, 'balance before');
        vm.prank(xferMgr);
        assertEq(mgr.claimQty(usdcAddr, eid1, 4), false);
        assertEq(mgr.getOwnerBalance(usdcAddr, eid1), 3, 'balance after');

        console2.log('claimQty relative; Success');
        vm.prank(xferMgr);
        assertEq(mgr.claimQty(usdcAddr, eid1, 1), true);
        assertEq(mgr.getOwnerBalance(usdcAddr, eid1), 2, 'balance after');

        // ----------
        // unclaimQty
        // ----------
        console2.log('unclaimQty; Fail due to caller');
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(AC.AccessDenied.selector, other));
        mgr.unclaimQty(usdcAddr, eid1, 0);

        console2.log('unclaimQty; Success');
        assertEq(mgr.getOwnerBalance(usdcAddr, eid1), 2, 'balance before');
        vm.prank(xferMgr);
        mgr.unclaimQty(usdcAddr, eid1, 4);
        assertEq(mgr.getOwnerBalance(usdcAddr, eid1), 6, 'balance after');
    }
}
