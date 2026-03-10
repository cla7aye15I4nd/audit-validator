// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

// See LIB_PATHS
import '../lib/forge-std/src/Test.sol';

import '../lib/openzeppelin-contracts/contracts/proxy/Clones.sol';
import '../lib/openzeppelin-contracts/contracts/interfaces/IERC1155Receiver.sol';
import '../lib/openzeppelin-contracts/contracts/interfaces/IERC1967.sol';

import '../contract/v1_0/EarnDateMgr.sol';
import '../contract/v1_0/Erc20Test.sol';
import '../contract/v1_0/ICallTracker.sol';
import '../contract/v1_0/IContractUser.sol';
import '../contract/v1_0/IEarnDateMgr.sol';
import '../contract/v1_0/IVersion.sol';
import '../contract/v1_0/LibraryAC.sol';
import '../contract/v1_0/LibraryBI.sol';
import '../contract/v1_0/LibraryCU.sol';
import '../contract/v1_0/LogicDeployers.sol';
import '../contract/v1_0/ProxyDeployers.sol';
import '../contract/v1_0/Types.sol';

import './Const.sol';
import './LibraryTest.sol';

contract EarnDateMgrLatest is EarnDateMgr {
    function getVersion() public pure override returns (uint) { return 999; }
}

contract EarnDateMgrTest is Test {
    IEarnDateMgr earnDateMgr;

    address creator = address(this);
    address other = address(6);

    string name1 = 'ABCD.1';
    string name2 = 'ABCD.2';
    string name3 = 'ABCD.3';

    uint earnDate1 = 20260101;
    uint earnDate2 = 20260201;
    uint earnDate3 = 20260301;

    Erc20Test tokenUsdc = new Erc20Test('USDC');

    uint40 constant NoSeqNum = 0;
    UUID constant NoReqId = UUID.wrap(0);

    function setUp() public {
        address mgrLogic = (new EarnDateMgrLogicDeployer()).deployLogic();
        assertNotEq(mgrLogic, AddrZero, 'mgrLogic');

        address mgrProxyAddr = (new ProxyDeployer()).deployProxy(mgrLogic, 'EarnDateMgr',
            abi.encodeWithSelector(IEarnDateMgr.initialize.selector, creator, NoReqId));
        assertNotEq(mgrProxyAddr, AddrZero, 'mgrProxyAddr');
        earnDateMgr = IEarnDateMgr(mgrProxyAddr);
        assertEq(10, earnDateMgr.getVersion(), 'getVersion');
        assertEq(earnDateMgr.getContract(CU.Creator), creator, 'getCreator');

        _labelAddresses();
    }

    uint _counter = 0;
    function _newUuid() private returns (UUID) {
        ++_counter;
        return UUID.wrap(bytes16(uint128(_counter)));
    }

    function _labelAddresses() private {
        vm.label(address(earnDateMgr), 'mgr');
        vm.label(creator, 'creator');
        vm.label(other, 'other');
        vm.label(address(tokenUsdc), 'tokenUsdc');
    }

    function test_EarnDateMgr_initialize() public {
        // Attempt to initialize again; revert as not allowed
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        earnDateMgr.initialize(creator, NoReqId);
    }

    function test_EarnDateMgr_upgrade() public {
        // Deploy a mock upgraded logic
        address newLogic = address(new EarnDateMgrLatest());
        assertNotEq(newLogic, AddrZero);

        // Upgrade access denied
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(AC.AccessDenied.selector, other));
        UUPSUpgradeable(address(earnDateMgr)).upgradeToAndCall(address(newLogic), '');

        // Upgrade via UUPS with an empty initData
        uint40 seqNum = earnDateMgr.getSeqNum(creator);
        UUID reqId = _newUuid();
        UUID reqIdStage = _newUuid();
        vm.prank(creator);
        earnDateMgr.preUpgrade(seqNum, reqId, reqIdStage);
        vm.expectEmit();
        emit IERC1967.Upgraded(newLogic);
        vm.prank(creator);
        UUPSUpgradeable(address(earnDateMgr)).upgradeToAndCall(address(newLogic), '');

        // Verify
        assertEq(earnDateMgr.getVersion(), 999);       // New behavior
        assertEq(earnDateMgr.getInstNamesLen(), 0);    // Old behavior
    }

    function test_EarnDateMgr_misc() public {
        console2.log('Verify empty instNames');
        assertEq(earnDateMgr.getInstNamesLen(), 0);
        string[] memory instNames = earnDateMgr.getInstNames(0, 1);
        assertEq(instNames.length, 0, 'getInstNames');

        console2.log('Verify empty instNames; unknown earnDate');
        assertEq(earnDateMgr.getInstNamesForDateLen(0), 0);
        instNames = earnDateMgr.getInstNamesForDate(0, 0, 1);
        assertEq(instNames.length, 0, 'getInstNamesForDate unknown');

        console2.log('Verify empty earnDates');
        assertEq(earnDateMgr.getEarnDatesLen(), 0);
        uint[] memory earnDates = earnDateMgr.getEarnDates(0, 1);
        assertEq(earnDates.length, 0, 'getEarnDates');

        console2.log('Verify empty earnDates; unknown instName');
        assertEq(earnDateMgr.getEarnDatesForInstLen('unknown'), 0);
        earnDates = earnDateMgr.getEarnDatesForInst('unknown', 0, 1);
        assertEq(earnDates.length, 0, 'getEarnDates uknown');

        // ----------
        // Add Instrument Earn Dates
        // ----------
        uint40 seqNum = 0;
        UUID reqId = _newUuid();
        console2.log('addInstEarnDate; Fail due to caller');
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(AC.AccessDenied.selector, other));
        earnDateMgr.addInstEarnDate(seqNum, reqId, name1, earnDate1);

        // Add: name1 earnDate1
        console2.log('addInstEarnDate 1; Success');
        reqId = _newUuid();
        vm.prank(creator);
        earnDateMgr.addInstEarnDate(++seqNum, reqId, name1, earnDate1);

        console2.log('Verify 1 getInstNames');
        assertEq(earnDateMgr.getInstNamesLen(), 1);
        instNames = earnDateMgr.getInstNames(0, 10);
        assertEq(instNames.length, 1, 'getInstNames');
        assertEq(instNames[0], name1);

        console2.log('Verify 1 getInstNamesForDate(date)');
        assertEq(earnDateMgr.getInstNamesForDateLen(earnDate1), 1);
        instNames = earnDateMgr.getInstNamesForDate(earnDate1, 0, 10);
        assertEq(instNames.length, 1, 'getInstNamesForDate length');
        assertEq(instNames[0], name1, 'getInstNamesForDate name');

        console2.log('Verify 1 getEarnDates');
        assertEq(earnDateMgr.getEarnDatesLen(), 1);
        earnDates = earnDateMgr.getEarnDates(0, 10);
        assertEq(earnDates.length, 1, 'getEarnDates length');
        assertEq(earnDates[0], earnDate1, 'getEarnDates date');

        console2.log('Verify 1 getEarnDatesForInst(instName)');
        assertEq(earnDateMgr.getEarnDatesForInstLen(name1), 1);
        earnDates = earnDateMgr.getEarnDatesForInst(name1, 0, 10);
        assertEq(earnDates.length, 1, 'getEarnDatesForInst length');
        assertEq(earnDates[0], earnDate1, 'getEarnDatesForInst date');

        // Add: name1 earnDate2
        console2.log('addInstEarnDate 2; Success');
        reqId = _newUuid();
        vm.prank(creator);
        earnDateMgr.addInstEarnDate(++seqNum, reqId, name1, earnDate2);

        console2.log('Verify 2 getInstNames');
        assertEq(earnDateMgr.getEarnDatesLen(), 2);
        assertEq(earnDateMgr.getInstNamesLen(), 1);
        instNames = earnDateMgr.getInstNames(0, 10);
        assertEq(instNames.length, 1, 'getInstNames');
        assertEq(instNames[0], name1);

        console2.log('Verify 2a getInstNamesForDate(date)');
        assertEq(earnDateMgr.getInstNamesForDateLen(earnDate1), 1);
        instNames = earnDateMgr.getInstNamesForDate(earnDate1, 0, 10);
        assertEq(instNames.length, 1, 'getInstNamesForDate length');
        assertEq(instNames[0], name1, 'getInstNamesForDate name');

        console2.log('Verify 2b getInstNamesForDate(date)');
        assertEq(earnDateMgr.getInstNamesForDateLen(earnDate2), 1);
        instNames = earnDateMgr.getInstNamesForDate(earnDate2, 0, 10);
        assertEq(instNames.length, 1, 'getInstNamesForDate length');
        assertEq(instNames[0], name1, 'getInstNamesForDate name');

        console2.log('Verify 2 getEarnDates');
        assertEq(earnDateMgr.getEarnDatesLen(), 2);
        earnDates = earnDateMgr.getEarnDates(0, 10);
        assertEq(earnDates.length, 2, 'getEarnDates length');
        assertEq(earnDates[0], earnDate1, 'getEarnDates date');
        assertEq(earnDates[1], earnDate2, 'getEarnDates date');

        console2.log('Verify 2 getEarnDatesForInst(instName)');
        assertEq(earnDateMgr.getEarnDatesForInstLen(name1), 2);
        earnDates = earnDateMgr.getEarnDatesForInst(name1, 0, 10);
        assertEq(earnDates.length, 2, 'getEarnDatesForInst length');
        assertEq(earnDates[0], earnDate1, 'getEarnDatesForInst date');
        assertEq(earnDates[1], earnDate2, 'getEarnDatesForInst date');

        // Add: name1 earnDate3
        console2.log('addInstEarnDate 3; Success');
        reqId = _newUuid();
        vm.prank(creator);
        earnDateMgr.addInstEarnDate(++seqNum, reqId, name1, earnDate3);
        assertEq(earnDateMgr.getEarnDatesLen(), 3);

        // Add: name2 earnDate3
        console2.log('addInstEarnDate 4; Success');
        reqId = _newUuid();
        vm.prank(creator);
        earnDateMgr.addInstEarnDate(++seqNum, reqId, name2, earnDate3);
        assertEq(earnDateMgr.getEarnDatesLen(), 3);

        console2.log('Verify 3 getInstNames');
        assertEq(earnDateMgr.getInstNamesLen(), 2);
        instNames = earnDateMgr.getInstNames(0, 10);
        assertEq(instNames.length, 2, 'getInstNames');
        assertEq(instNames[0], name1);
        assertEq(instNames[1], name2);

        console2.log('Verify 3b getInstNamesForDate(date)');
        assertEq(earnDateMgr.getInstNamesForDateLen(earnDate2), 1);
        instNames = earnDateMgr.getInstNamesForDate(earnDate2, 0, 10);
        assertEq(instNames.length, 1, 'getInstNamesForDate length');
        assertEq(instNames[0], name1, 'getInstNamesForDate name');

        console2.log('Verify 3a getInstNamesForDate(date)');
        assertEq(earnDateMgr.getInstNamesForDateLen(earnDate3), 2);
        instNames = earnDateMgr.getInstNamesForDate(earnDate3, 0, 10);
        assertEq(instNames.length, 2, 'getInstNamesForDate length');
        assertEq(instNames[0], name1, 'getInstNamesForDate name');
        assertEq(instNames[1], name2, 'getInstNamesForDate name');

        console2.log('Verify 3 getEarnDates');
        assertEq(earnDateMgr.getEarnDatesLen(), 3);
        earnDates = earnDateMgr.getEarnDates(0, 10);
        assertEq(earnDates.length, 3, 'getEarnDates length');
        assertEq(earnDates[0], earnDate1, 'getEarnDates date');
        assertEq(earnDates[1], earnDate2, 'getEarnDates date');
        assertEq(earnDates[2], earnDate3, 'getEarnDates date');

        console2.log('Verify 3a getEarnDatesForInst(instName)');
        assertEq(earnDateMgr.getEarnDatesForInstLen(name1), 3);
        earnDates = earnDateMgr.getEarnDatesForInst(name1, 0, 10);
        assertEq(earnDates.length, 3, 'getEarnDatesForInst length');
        assertEq(earnDates[0], earnDate1, 'getEarnDatesForInst date');
        assertEq(earnDates[1], earnDate2, 'getEarnDatesForInst date');
        assertEq(earnDates[2], earnDate3, 'getEarnDatesForInst date');

        console2.log('Verify 3b getEarnDatesForInst(instName)');
        assertEq(earnDateMgr.getEarnDatesForInstLen(name2), 1);
        earnDates = earnDateMgr.getEarnDatesForInst(name2, 0, 10);
        assertEq(earnDates.length, 1, 'getEarnDatesForInst length');
        assertEq(earnDates[0], earnDate3, 'getEarnDatesForInst date');

        // ----------
        // Remove Instrument Earn Dates
        // ----------
        console2.log('removeInstEarnDate; Fail due to caller');
        reqId = _newUuid();
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(AC.AccessDenied.selector, other));
        earnDateMgr.removeInstEarnDate(seqNum, reqId, name1, earnDate1);

        console2.log('removeInstEarnDate name1 earnDate1; Success');
        reqId = _newUuid();
        vm.prank(creator);
        assertEq(earnDateMgr.getEarnDatesForInstLen(name1), 3);
        assertEq(earnDateMgr.getEarnDatesForInstLen(name2), 1);
        assertEq(earnDateMgr.getInstNamesForDateLen(earnDate1), 1);
        earnDateMgr.removeInstEarnDate(++seqNum, reqId, name1, earnDate1);

        console2.log('Verify 4a');
        assertEq(earnDateMgr.getEarnDatesForInstLen(name1), 2);
        assertEq(earnDateMgr.getEarnDatesForInstLen(name2), 1);
        earnDates = earnDateMgr.getEarnDatesForInst(name1, 0, 10);
        assertEq(earnDates.length, 2, 'getEarnDatesForInst length');
        assertEq(earnDates[0], earnDate3, 'getEarnDatesForInst date'); // Removal swapped 1st and last
        assertEq(earnDates[1], earnDate2, 'getEarnDatesForInst date');

        console2.log('Verify 4b');
        assertEq(earnDateMgr.getInstNamesForDateLen(earnDate1), 0);
        instNames = earnDateMgr.getInstNamesForDate(earnDate1, 0, 10);
        assertEq(instNames.length, 0, 'getEarnDatesForInst length');

        console2.log('removeInstEarnDate name1 earnDate2; Success');
        reqId = _newUuid();
        earnDateMgr.removeInstEarnDate(++seqNum, reqId, name1, earnDate2);

        console2.log('Verify 5');
        assertEq(earnDateMgr.getEarnDatesForInstLen(name1), 1);
        assertEq(earnDateMgr.getEarnDatesForInstLen(name2), 1);

        console2.log('removeInstEarnDate name1 earnDate3; Success');
        reqId = _newUuid();
        earnDateMgr.removeInstEarnDate(++seqNum, reqId, name1, earnDate3);
        assertEq(earnDateMgr.getInstNamesLen(), 1);

        console2.log('Verify 6');
        assertEq(earnDateMgr.getEarnDatesForInstLen(name1), 0);
        assertEq(earnDateMgr.getEarnDatesForInstLen(name2), 1);

        console2.log('removeInstEarnDate name2 earnDate3; Success');
        reqId = _newUuid();
        earnDateMgr.removeInstEarnDate(++seqNum, reqId, name2, earnDate3);

        console2.log('Verify 7');
        assertEq(earnDateMgr.getInstNamesLen(), 0);
        instNames = earnDateMgr.getInstNames(0, 1);
        assertEq(instNames.length, 0, 'getInstNames');

        assertEq(earnDateMgr.getEarnDatesLen(), 0);
        instNames = earnDateMgr.getInstNames(0, 1);
        assertEq(instNames.length, 0, 'getInstNames');
    }

    // Optimization off: Total: 1,000; PageLen: 200; Gas min=1.94M, max=2.04M, avg: 2.02M
    // Optimization on:  Total: 1,000; PageLen: 200; Gas min=6.08K, max=6.32K, avg: 6.27K
    function test_EarnDateMgr_getInstNames_gas() public {
        string memory namePrefix = 'ABCD.';
        uint totalLen = 1_000;
        uint pageLen = 200;
        uint40 seqNum = 0;
        UUID reqId = _newUuid();
        console2.log('loading items, len:', totalLen);
        string[] memory names = new string[](totalLen);
        for (uint i = 0; i < totalLen; ++i) {
            string memory name = string(abi.encodePacked(namePrefix, vm.toString(i)));
            names[i] = name;
            reqId = _newUuid();
            vm.prank(creator);
            earnDateMgr.addInstEarnDate(++seqNum, reqId, name, earnDate1);
        }

        vm.prank(creator);
        vm.resetGasMetering();
        uint numPages = totalLen / pageLen;
        if (numPages * pageLen < totalLen) ++numPages;
        uint minGas = type(uint).max;
        uint maxGas;
        uint gasSum;
        for (uint i = 0; i < numPages; ++i) {
            console2.log('getInstNamesForDate, page=', i);
            string[] memory page = earnDateMgr.getInstNamesForDate(earnDate1, i * pageLen, pageLen);
            Vm.Gas memory gas = vm.lastCallGas();
            uint used = gas.gasTotalUsed;
            // console2.log('Gas limit  : ', gas.gasLimit);
            console2.log('Gas used   : ', used);
            // console2.log('Gas refund : ', gas.gasRefunded);
            // console2.log('Gas remain : ', gas.gasRemaining);
            assertEq(page.length, pageLen, 'pageLen');

            if (used < minGas) minGas = used;
            if (used > maxGas) maxGas = used;
            gasSum += used;
        }
        uint avgGas = gasSum / numPages;
        console2.log('Gas min:', minGas);
        console2.log('Gas max:', maxGas);
        console2.log('Gas avg:', avgGas);
    }
}
