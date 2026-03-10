// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

// See LIB_PATHS
import '../lib/forge-std/src/Test.sol';

import '../lib/openzeppelin-contracts/contracts/proxy/Clones.sol';
import '../lib/openzeppelin-contracts/contracts/interfaces/IERC1155Receiver.sol';
import '../lib/openzeppelin-contracts/contracts/interfaces/IERC1967.sol';

import '../contract/v1_0/Erc20Test.sol';
import '../contract/v1_0/ICallTracker.sol';
import '../contract/v1_0/IContractUser.sol';
import '../contract/v1_0/InstRevMgr.sol';
import '../contract/v1_0/IInstRevMgr.sol';
import '../contract/v1_0/IVersion.sol';
import '../contract/v1_0/LibraryAC.sol';
import '../contract/v1_0/LibraryCU.sol';
import '../contract/v1_0/LibraryIR.sol';
import '../contract/v1_0/LibraryString.sol';
import '../contract/v1_0/LibraryTI.sol';
import '../contract/v1_0/LogicDeployers.sol';
import '../contract/v1_0/ProxyDeployers.sol';
import '../contract/v1_0/Types.sol';

import './Const.sol';
import './LibraryTest.sol';

contract InstRevMgrLatest is InstRevMgr {
    function getVersion() public pure override returns (uint) { return 999; }
}

// Exposes details for testing
contract InstRevMgrSpy is InstRevMgr {
    uint40 constant NoSeqNum = 0;
    UUID constant NoReqId = UuidZero;

    // Add an InstRev to a proposal
    function addInstRevToProp(uint pid, IR.InstRev calldata ir) public returns(bool) {
        return _pageSetInstRev(_proposals[pid].instRevs, ir);
    }

    // Add an InstRev to executed state
    function addInstRevToExecuted(IR.InstRev calldata ir) public returns(bool) {
        return _pageSetInstRev(_instRevs, ir);
    }

    // Simplistic/instrusive to add an InstRev
    function _pageSetInstRev(IR.Emap storage instRevs, IR.InstRev calldata ir) private returns(bool) {
        if (!IR.initialized(instRevs)) IR.Emap_init(instRevs);

        bytes32 instNameKey = String.toBytes32(ir.instName);
        IR.addFromCd(instRevs, ir, instNameKey, false);
        return IR.exists(instRevs, instNameKey, ir.earnDate);
    }
}

contract InstRevMgrSpyLogicDeployer is LogicDeployer {
    constructor() { _logic = address(new InstRevMgrSpy()); emit LogicDeployed(_logic); }
}

contract InstRevMgrSpyProxyDeployer {
    uint40 constant NoSeqNum = 0;
    UUID constant NoReqId = UuidZero;

    function createProxy(address logicAddr, address creator, UUID reqId) public returns(InstRevMgrSpy) {
        address proxyAddr = (new ProxyDeployer()).deployProxy(logicAddr, 'InstRevMgrSpy',
            abi.encodeWithSelector(IInstRevMgr.initialize.selector, creator, reqId));
        return InstRevMgrSpy(proxyAddr);
    }
}

contract InstRevMgrTest is Test {
    address admin = address(20);
    address agent = address(21);
    address voter1 = address(22);
    address voter2 = address(23);
    address voter3 = address(24);
    address creator = address(this);
    address other = address(6);
    address zeroAddr = AddrZero;

    IRevMgr revMgr = (new RevMgrProxyDeployer()).createProxy(
        (new RevMgrLogicDeployer()).deployLogic(), creator, NoReqId);

    IInstRevMgr instRevMgr = (new InstRevMgrProxyDeployer()).createProxy(
        (new InstRevMgrLogicDeployer()).deployLogic(), creator, NoReqId);

    IBoxMgr boxMgr = (new BoxMgrProxyDeployer()).createProxy(
        (new BoxMgrLogicDeployer()).deployLogic(), creator, NoReqId);

    IVault vault = (new VaultProxyDeployer()).createProxy((
            new VaultLogicDeployer()).deployLogic(), creator, NoReqId, 3, _createRoles());

    address revMgrAddr = address(revMgr);
    address instRevMgrAddr = address(instRevMgr);
    address boxMgrAddr = address(boxMgr);
    address vaultAddr = address(vault);

    string nameE = '';
    string name1 = 'ABCD.1';
    string name2 = 'ABCD.2';
    string name3 = 'ABCD.3';
    string name4 = 'ABCD.4';

    uint earnDateE = 0;
    uint earnDate1 = 20260101;
    uint earnDate2 = 20260201;
    uint earnDate3 = 20260301;

    UUID constant eidE = UUID.wrap(0x00000000000000000000000000000000); // External ID empty: 0x prefix + 32 hex digits
    UUID constant eid1 = UUID.wrap(0x00000000000000000000000000000001); // External IDs
    UUID constant eid2 = UUID.wrap(0x00000000000000000000000000000002);
    UUID constant eid3 = UUID.wrap(0x00000000000000000000000000000003);
    UUID constant eid4 = UUID.wrap(0x00000000000000000000000000000004);

    Erc20Test tokenUsdc = new Erc20Test('USDC');
    Erc20Test tokenEurc = new Erc20Test('EURC');
    address usdcAddr = address(tokenUsdc);
    address eurcAddr = address(tokenEurc);

    address dropAddrE = AddrZero;
    address dropAddr1;
    address dropAddr2;
    address dropAddr3;

    // uint constant ccyScaleFactor = 1_000_000; // $9.123`456 USDC represented as 9,123,456
    uint unitRev1 = 200_000; // $0.20
    uint unitRev2 = 300_000; // $0.30
    uint unitRev3 = 600_000; // $0.60
    uint unitRev4 = 250_000; // $0.25

    uint totalQty1 = 1_000;
    uint totalQty2 = 2_000;
    uint totalQty3 = 3_000;

    uint totalRev1 = unitRev1 * totalQty1;
    uint totalRev2 = unitRev2 * totalQty2;
    uint totalRev3 = unitRev3 * totalQty3;
    uint totalRev4 = unitRev4 * totalQty1;

    uint40 constant NoSeqNum = 0;
    UUID constant NoReqId = UuidZero;

    function setUp() public {
        _setContracts(boxMgr);
        _setContracts(instRevMgr);
        _setContracts(vault);

        _addBoxes();

        _labelAddresses();

        tokenUsdc.setApproval(dropAddr1, instRevMgrAddr, MAX_ALLOWANCE);
        tokenUsdc.setApproval(dropAddr2, instRevMgrAddr, MAX_ALLOWANCE);
        tokenUsdc.setApproval(dropAddr3, instRevMgrAddr, MAX_ALLOWANCE);
        vault.approveMgr(NoSeqNum, NoReqId, usdcAddr, CU.InstRevMgr); // Allow transfers from vault
    }

    uint _counter = 0;
    function _newUuid() private returns (UUID) {
        ++_counter;
        return UUID.wrap(bytes16(uint128(_counter)));
    }

    function _labelAddresses() private {
        vm.label(creator, 'creator');
        vm.label(admin, 'admin');
        vm.label(agent, 'agent');
        vm.label(voter1, 'voter1');
        vm.label(voter2, 'voter2');
        vm.label(voter3, 'voter3');
        vm.label(other, 'other');

        vm.label(boxMgrAddr, 'boxMgr');
        vm.label(instRevMgrAddr, 'instRevMgr');
        vm.label(revMgrAddr, 'revMgr');
        vm.label(vaultAddr, 'vault');

        vm.label(dropAddr1, 'dropAddr1');
        vm.label(dropAddr2, 'dropAddr2');
        vm.label(dropAddr3, 'dropAddr3');

        vm.label(Util.ExplicitMint, 'ExplicitMintBurn');
        vm.label(Util.ContractHeld, 'ContractHeld');

        vm.label(usdcAddr, 'usdcAddr');
        vm.label(eurcAddr, 'eurcAddr');
    }

    function _setContracts(IContractUser user) private {
        user.setContract(NoSeqNum, NoReqId, CU.BoxMgr, boxMgrAddr);
        user.setContract(NoSeqNum, NoReqId, CU.InstRevMgr, instRevMgrAddr);
        user.setContract(NoSeqNum, NoReqId, CU.RevMgr, revMgrAddr);
        user.setContract(NoSeqNum, NoReqId, CU.Vault, vaultAddr);
    }

    function _createRoles() public view returns(AC.RoleRequest[] memory rr) {
        // Create roles
        rr = new AC.RoleRequest[](5);
        rr[0] = AC.RoleRequest({ account: admin,  add: true, role: AC.Role.Admin, __gap: Util.gap5()});
        rr[1] = AC.RoleRequest({ account: agent,  add: true, role: AC.Role.Agent, __gap: Util.gap5()});
        rr[2] = AC.RoleRequest({ account: voter1, add: true, role: AC.Role.Voter, __gap: Util.gap5() });
        rr[3] = AC.RoleRequest({ account: voter2, add: true, role: AC.Role.Voter, __gap: Util.gap5() });
        rr[4] = AC.RoleRequest({ account: voter3, add: true, role: AC.Role.Voter, __gap: Util.gap5() });
    }

    function _makeTokenInfo(string memory tokSym, address tokAddr, TI.TokenType tokType) private pure
        returns(TI.TokenInfo memory)
    {
        return TI.TokenInfo({ tokSym: tokSym, tokAddr: tokAddr, tokenId: 0, tokType: tokType });
    }

    function _addBoxes() private {
        // Add Boxes
        boxMgr.addBoxLogic(NoSeqNum, NoReqId, 10, (new BoxLogicDeployer()).deployLogic());
        address[] memory spenders = new address[](1);
        spenders[0] = address(instRevMgr);
        TI.TokenInfo[] memory tokens = new TI.TokenInfo[](2);
        tokens[0] = _makeTokenInfo('USDC', usdcAddr, TI.TokenType.Erc20);
        tokens[1] = _makeTokenInfo('EURC', eurcAddr, TI.TokenType.Erc20);
        dropAddr1 = _addBox(name1, spenders, tokens);
        dropAddr2 = _addBox(name2, spenders, tokens);
        dropAddr3 = _addBox(name3, spenders, tokens);
    }

    function _addBox(string memory name, address[] memory spenders, TI.TokenInfo[] memory tokens) private
        returns(address boxProxy)
    {
        console2.log('Creating box', name);
        boxMgr.addBox(NoSeqNum, NoReqId, IBoxMgr.AddBoxReq({
            name: name,
            version: 0,
            active: true,
            nonce: 0,
            deployedProxy: AddrZero,
            deployedLogic: AddrZero,
            spenders: spenders,
            tokens: tokens
        }));
        bool found; BI.BoxInfo memory box;
        (found, box) = boxMgr.getBoxByName(name, true);
        return box.boxProxy;
    }

    function test_InstRevMgr_initialize() public {
        // Attempt to initialize again; revert as not allowed
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        instRevMgr.initialize(creator, NoReqId);
    }

    function test_InstRevMgr_upgrade() public {
        // Deploy a mock upgraded logic
        address newLogic = address(new InstRevMgrLatest());
        assertNotEq(newLogic, zeroAddr);

        // Upgrade access denied
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(AC.AccessDenied.selector, other));
        UUPSUpgradeable(instRevMgrAddr).upgradeToAndCall(address(newLogic), '');

        // Upgrade via UUPS with an empty initData
        uint40 seqNum = instRevMgr.getSeqNum(creator);
        UUID reqId = _newUuid();
        UUID reqIdStage = _newUuid();
        vm.prank(creator);
        instRevMgr.preUpgrade(seqNum, reqId, reqIdStage);
        vm.expectEmit();
        emit IERC1967.Upgraded(newLogic);
        vm.prank(creator);
        UUPSUpgradeable(instRevMgrAddr).upgradeToAndCall(address(newLogic), '');

        // Verify
        assertEq(instRevMgr.getVersion(), 999);        // New behavior
        assertEq(instRevMgr.getPropHdr(0).pid, 0); // Old behavior
    }

    function _checkUuid(UUID actual, UUID expect, string memory description) private pure {
        assertEq(UUID.unwrap(actual), UUID.unwrap(expect), description);
    }

    function test_InstRevMgr_empty_state() public {
        vm.startPrank(other);
        assertEq(instRevMgr.getPropHdr(0).pid, 0, 'getPropHdr');
        assertEq(instRevMgr.getAllocFixesLen(0, name1, earnDate1), 0, 'getAllocFixesLen');
        (int revenue, UUID ownerEid) = instRevMgr.getAllocFix(0, name1, earnDate1, 0);
        assertEq(revenue, 0, 'revenue');
        _checkUuid(ownerEid, eidE, 'ownerEid');
        assertEq(instRevMgr.getInstRevsLen(0, name1, earnDate1), 0, 'getInstRevsLen');
        assertEq(instRevMgr.getInstRevs(0, name1, earnDate1, 0, 1).length, 0, 'getInstRevs');

        vm.expectRevert();
        assertEq(instRevMgr.getInstRev(0, 0).earnDate, 0, 'getInstRev 1');

        assertEq(instRevMgr.getInstRevForInstDate(0, name1, earnDate1).earnDate, 0, 'getInstRev 2');
    }

    function _createProp(uint pid, UUID reqId, bool correction) private {
        assertEq(instRevMgr.getPropHdr(pid).pid, 0, 'instRevMgr pid before');

        vm.prank(revMgrAddr);
        instRevMgr.propCreate(pid, reqId, usdcAddr, correction);
        IInstRevMgr.PropHdr memory hdr = instRevMgr.getPropHdr(pid);

        assertEq(hdr.pid, pid, 'pid');
        _checkUuid(hdr.eid, reqId, 'reqId');
        assertEq(hdr.fixInstRevCount, 0, 'fixInstRevCount');
        assertEq(hdr.fixCount, 0, 'fixCount');
        assertEq(hdr.uploadedAt, 0, 'uploadedAt');
        assertEq(hdr.executedAt, 0, 'executedAt');
        assertEq(hdr.correction, correction, 'correction');
        assertEq(hdr.ccyAddr, usdcAddr, 'ccyAddr');

        assertEq(instRevMgr.getPropHdr(pid).pid, pid, 'instRevMgr pid after');
    }

    function _propAddInstRev(uint pid, uint iAppend, uint total, IR.InstRev[] memory page,
        IInstRevMgr.AddInstRc rc, IInstRevMgr.AddInstLineRc lrc, uint count) private
    {
        uint40 seqNum = instRevMgr.getSeqNum(agent);
        UUID reqId = _newUuid();
        vm.prank(agent);
        instRevMgr.propAddInstRev(seqNum, reqId, IInstRevMgr.PropAddInstRevReq(
                {pid: pid, iAppend: iAppend, total: total, page: page}));
        vm.prank(agent);
        T.checkCall(vm, instRevMgr.getCallResBySeqNum(seqNum), uint(rc), uint(lrc), count, 'propAddInstRev');
    }

    function _pageSetInstRev(IR.InstRev[] memory page, uint iPage, string memory instName, uint earnDate, uint unitRev,
        uint totalQty, address dropAddr) private view
    {
        assertGt(page.length, iPage, 'page.length > iPage');
        page[iPage] = IR.InstRev({
            instName: instName,
            instNameKey: '', // Caller does not set this, set in contract
            earnDate: earnDate,
            unitRev: unitRev,
            totalRev: unitRev * totalQty,
            totalQty: totalQty,
            dropAddr: dropAddr,
            ccyAddr: usdcAddr,
            uploadedAt: 0,
            executedAt: 0,
            __gap: Util.gap5()
        });
    }

    function _expectEmitInstRevUploaded(uint pid, IR.InstRev memory ir) private {
        vm.expectEmit();
        emit IInstRevMgr.InstRevUploaded(pid, ir.instName, ir.earnDate, ir.totalQty, ir.totalRev, ir.unitRev, false);
    }

    function test_InstRevMgr_prop_create() public {
        uint pid1 = 1;
        bool correction = false;

        console2.logString('propCreate; Fail, Caller access');
        vm.expectRevert(abi.encodeWithSelector(AC.AccessDenied.selector, creator));
        vm.prank(creator);
        instRevMgr.propCreate(pid1, eid1, usdcAddr, correction);
        assertEq(instRevMgr.getPropHdr(pid1).pid, 0, 'getPropHdr');

        console2.logString('propCreate; Success');
        _createProp(pid1, eid1, correction);

        uint iAppend = 0;
        uint total = 0;
        IR.InstRev[] memory page = new IR.InstRev[](0);

        console2.logString('propAddInstRev; Fail, Caller access');
        vm.expectRevert(abi.encodeWithSelector(AC.AccessDenied.selector, creator));
        vm.prank(creator);
        instRevMgr.propAddInstRev(NoSeqNum, NoReqId,
            IInstRevMgr.PropAddInstRevReq({pid: pid1, iAppend: iAppend, total: total, page: page}));

        console2.logString('propAddInstRev; Fail, Bad pid');
        _propAddInstRev(pid1 + 1, iAppend, total, page,
            IInstRevMgr.AddInstRc.NoProp, IInstRevMgr.AddInstLineRc.Ok, 0);

        console2.logString('propAddInstRev; Fail, Bad page length');
        _propAddInstRev(pid1, iAppend, total, page,
            IInstRevMgr.AddInstRc.BadPage, IInstRevMgr.AddInstLineRc.Ok, 0);

        console2.logString('propAddInstRev; Fail, Bad index 2');
        page = new IR.InstRev[](1);
        _propAddInstRev(pid1, iAppend + 1, total, page,
            IInstRevMgr.AddInstRc.BadIndex, IInstRevMgr.AddInstLineRc.Ok, 0);



        uint partRev1 = totalRev1 / 2;
        uint partRev2 = totalRev2 / 2;

        console2.logString('Deposit revenue for each instrument');
        tokenUsdc.mint(dropAddr1, totalRev1); // A: Deposit
        tokenUsdc.mint(dropAddr2, partRev2);  // B: Deposit 1 of 2
        tokenUsdc.mint(dropAddr3, totalRev3); // C: Deposit
        tokenUsdc.mint(dropAddr1, totalRev4); // D: Deposit

        // console2.logString('Remove pre-approval on dropAddr2 to do boxMgr.approve path');
        // tokenUsdc.setApproval(dropAddr2, instRevMgrAddr, 0);

        console2.logString('Create InstRev page');
        page = new IR.InstRev[](3);
        _pageSetInstRev(page, 0, name1, earnDate1, unitRev1, totalQty1, dropAddr1); // A: Good inputs
        _pageSetInstRev(page, 1, nameE, earnDate1, unitRev2, totalQty2, dropAddr2); // B: Good inputs except empty name
        _pageSetInstRev(page, 2, name3, earnDate1, unitRev3, totalQty3, dropAddr3); // C: Good inputs
        total = 4; // Total items to be uploaded (A,B,C,D)

        console2.logString('propAddInstRev; Attempt Add (A,B,C), B fails validation (empty name)');
        assertEq(tokenUsdc.balanceOf(dropAddr1), totalRev1 + totalRev4, 'balance dropAddr1');
        IR.InstRev memory irA = page[0];
        _expectEmitInstRevUploaded(pid1, irA);
        _propAddInstRev(pid1, iAppend, total, page,
            IInstRevMgr.AddInstRc.BadLine, IInstRevMgr.AddInstLineRc.InstName, 1);

        console2.logString('propAddInstRev; Attempt Add (B,C), B fails validation (low src funds)');
        page = new IR.InstRev[](2);
        _pageSetInstRev(page, 0, name2, earnDate1, unitRev2, totalQty2, dropAddr2); // B: Good inputs
        _pageSetInstRev(page, 1, name3, earnDate1, unitRev3, totalQty3, dropAddr3); // C: Good inputs
        IR.InstRev memory irB = page[0];
        IR.InstRev memory irC = page[1];
        uint required = irB.totalRev;
        iAppend = 1;
        vm.expectEmit();
        emit IInstRevMgr.LowFundsErr(pid1, irB.instName, irB.earnDate, usdcAddr, irB.dropAddr, partRev2, required);
        _propAddInstRev(pid1, iAppend, total, page,
            IInstRevMgr.AddInstRc.BadLine, IInstRevMgr.AddInstLineRc.LowFunds, 0);

        console2.logString('propAddInstRev; Add (B,C), full page success');
        tokenUsdc.mint(dropAddr2, partRev2);  // B: Deposit 2 of 2 (fixes low src funds)
        _expectEmitInstRevUploaded(pid1, irB);
        _expectEmitInstRevUploaded(pid1, irC);
        _propAddInstRev(pid1, iAppend, total, page,
            IInstRevMgr.AddInstRc.FullPage, IInstRevMgr.AddInstLineRc.Ok, 2);

        // A duplicate call to verify no effect
        console2.logString('propAddInstRev; Fail, duplicate call - bad index (B,C not removed from page)');
        _propAddInstRev(pid1, iAppend, total, page,
            IInstRevMgr.AddInstRc.BadIndex, IInstRevMgr.AddInstLineRc.Ok, 0);

        console2.logString('propAddInstRev; Add (D), all pages success');
        assertEq(instRevMgr.getPropHdr(pid1).uploadedAt, 0, 'uploadedAt before');
        iAppend = 3;
        page = new IR.InstRev[](1);
        _pageSetInstRev(page, 0, name1, earnDate2, unitRev4, totalQty1, dropAddr1); // D: Good inputs
        IR.InstRev memory irD = page[0];
        _expectEmitInstRevUploaded(pid1, irD);
        vm.expectEmit();
        emit IInstRevMgr.AllInstRevUploaded(pid1, total);
        _propAddInstRev(pid1, iAppend, total, page,
            IInstRevMgr.AddInstRc.AllPages, IInstRevMgr.AddInstLineRc.Ok, 1);
        assertEq(instRevMgr.getPropHdr(pid1).uploadedAt, block.timestamp, 'uploadedAt after');

        console2.logString('propAddInstRev; Fail, duplicate call - prop sealed');
        _propAddInstRev(pid1, iAppend, total, page,
            IInstRevMgr.AddInstRc.ReadOnly, IInstRevMgr.AddInstLineRc.Ok, 0);

        // ----------
        // Validate InstRevs in proposal
        // ----------
        assertEq(0, instRevMgr.getInstRevsLen(0, nameE, earnDate1), 'exec: any name, earnDate1');
        assertEq(0, instRevMgr.getInstRevsLen(0, name1, earnDateE), 'exec: name1, any date');
        _checkInstRevs1(pid1);

        // ----------
        // Finalize proposal
        // ----------
        console2.logString('propFinalize; Fail, caller access');
        vm.expectRevert(abi.encodeWithSelector(AC.AccessDenied.selector, creator));
        vm.prank(creator);
        instRevMgr.propFinalize(pid1);

        console2.logString('propFinalize; Fail, unknown proposal');
        vm.prank(revMgrAddr);
        assertFalse(instRevMgr.propFinalize(pid1 + 1));

        console2.logString('propFinalize; Success');
        vm.prank(revMgrAddr);
        assertTrue(instRevMgr.propFinalize(pid1));

        // ----------
        // Execute proposal
        // ----------
        console2.logString('propExecInstRev; Fail, caller access');
        assertEq(instRevMgr.getInstRevsLen(pid1, nameE, earnDateE), 4, 'getInstRevsLen');
        vm.expectRevert(abi.encodeWithSelector(AC.AccessDenied.selector, creator));
        vm.prank(creator);
        instRevMgr.propExecInstRev(pid1, 0);

        console2.logString('propExecInstRev; Fail, unknown proposal');
        vm.prank(revMgrAddr);
        IRevMgr.ExecRevRc rc = instRevMgr.propExecInstRev(pid1 + 1, 0);
        assertEq(uint(rc), uint(IRevMgr.ExecRevRc.NoProp), 'ExecRevRc');

        // `dropAddr1` is the source for 2 InstRev; reducing these funds allows the first transfer but not the 2nd
        tokenUsdc.burn(dropAddr1, partRev1);  // B: Remove part of the deposit (protocol violation)

        console2.log('propExecInstRev; Progress, iInstRev=0');
        assertEq(tokenUsdc.balanceOf(dropAddr1), totalRev1 + totalRev4 - partRev1, 'dropAddr1 balance A');
        vm.expectEmit();
        emit IInstRevMgr.RevenueXfer(pid1, name1, earnDate1, true, false,
            usdcAddr, dropAddr1, vaultAddr, totalRev1);
        vm.prank(revMgrAddr);
        rc = instRevMgr.propExecInstRev(pid1, 0);
        assertEq(uint(rc), uint(IRevMgr.ExecRevRc.Progress), 'ExecRevRc');

        console2.log('propExecInstRev; Progress, iInstRev=1');
        assertEq(tokenUsdc.balanceOf(dropAddr2), totalRev2, 'dropAddr2 balance');
        vm.expectEmit();
        emit IInstRevMgr.RevenueXfer(pid1, name2, earnDate1, true, false,
            usdcAddr, dropAddr2, vaultAddr, totalRev2);
        vm.prank(revMgrAddr);
        rc = instRevMgr.propExecInstRev(pid1, 1);
        assertEq(uint(rc), uint(IRevMgr.ExecRevRc.Progress), 'ExecRevRc');

        console2.log('propExecInstRev; Progress, iInstRev=2');
        assertEq(tokenUsdc.balanceOf(dropAddr3), totalRev3, 'dropAddr3 balance');
        vm.expectEmit();
        emit IInstRevMgr.RevenueXfer(pid1, name3, earnDate1, true, false,
            usdcAddr, dropAddr3, vaultAddr, totalRev3);
        vm.prank(revMgrAddr);
        rc = instRevMgr.propExecInstRev(pid1, 2);
        assertEq(uint(rc), uint(IRevMgr.ExecRevRc.Progress), 'ExecRevRc');

        console2.log('propExecInstRev; Fail, funds removed after add and before exec (protocol violation)');
        assertEq(tokenUsdc.balanceOf(dropAddr1), totalRev4 - partRev1, 'dropAddr1 balance B');
        vm.expectEmit();
        emit IInstRevMgr.LowFundsErr(pid1, name1, earnDate2, usdcAddr, dropAddr1, totalRev4 - partRev1, totalRev4);
        vm.prank(revMgrAddr);
        rc = instRevMgr.propExecInstRev(pid1, 3);
        assertEq(uint(rc), uint(IRevMgr.ExecRevRc.LowFunds), 'ExecRevRc');

        console2.log('Resolve protocol violation');
        tokenUsdc.mint(dropAddr1, partRev1);  // B: Resolve the low funds protocol violation

        console2.log('propExecInstRev; Fail, iInstRev=3, xfer failure');
        assertEq(tokenUsdc.balanceOf(dropAddr1), totalRev4, 'dropAddr1 balance B');
        tokenUsdc.setFailXfer(true);
        vm.expectEmit();
        emit IInstRevMgr.RevenueXfer(pid1, name1, earnDate2, false, false,
            usdcAddr, dropAddr1, vaultAddr, totalRev4);
        vm.prank(revMgrAddr);
        rc = instRevMgr.propExecInstRev(pid1, 3);
        assertEq(uint(rc), uint(IRevMgr.ExecRevRc.LowFunds), 'ExecRevRc');
        tokenUsdc.setFailXfer(false);

        console2.log('propExecInstRev; Progress, iInstRev=3');
        assertEq(tokenUsdc.balanceOf(dropAddr1), totalRev4, 'dropAddr1 balance B');
        vm.expectEmit();
        emit IInstRevMgr.RevenueXfer(pid1, name1, earnDate2, true, false,
            usdcAddr, dropAddr1, vaultAddr, totalRev4);
        vm.prank(revMgrAddr);
        rc = instRevMgr.propExecInstRev(pid1, 3);
        assertEq(uint(rc), uint(IRevMgr.ExecRevRc.Progress), 'ExecRevRc');

        // ----------
        // Mark proposal as executed
        // ----------
        console2.logString('propExecuted; Fail, caller access');
        vm.expectRevert(abi.encodeWithSelector(AC.AccessDenied.selector, creator));
        vm.prank(creator);
        instRevMgr.propExecuted(pid1);

        console2.logString('propExecuted; Fail, unknown pid');
        vm.expectRevert(abi.encodeWithSelector(AC.AccessDenied.selector, creator));
        vm.prank(creator);
        instRevMgr.propExecuted(0);
        assertEq(instRevMgr.getPropHdr(pid1).executedAt, 0);

        console2.logString('propExecuted; Success');
        vm.prank(revMgrAddr);
        instRevMgr.propExecuted(pid1);
        assertEq(instRevMgr.getPropHdr(pid1).executedAt, block.timestamp);

        console2.logString('propExecInstRev; Fail, proposal already executed');
        vm.prank(revMgrAddr);
        rc = instRevMgr.propExecInstRev(pid1, 0);
        assertEq(uint(rc), uint(IRevMgr.ExecRevRc.Done), 'ExecRevRc');

        // ----------
        // Validate InstRevs (executed)
        // ----------
        _checkInstRevs1(0);
    }

    /// @dev Verify the InstRevs in either executed state or a proposal
    /// @param pid 0: Check executed state; >0 Check proposal
    function _checkInstRevs1(uint pid) public view {
        // getInstRevForInstDate(pid, name, date)
        console2.logString('getInstRevForInstDate; name1, earnDate1');
        IR.InstRev memory ir = instRevMgr.getInstRevForInstDate(pid, name1, earnDate1);
        assertEq(ir.instName, name1);
        assertEq(ir.earnDate, earnDate1);

        console2.logString('getInstRevForInstDate; name2, earnDate1');
        ir = instRevMgr.getInstRevForInstDate(pid, name2, earnDate1);
        assertEq(ir.instName, name2);
        assertEq(ir.earnDate, earnDate1);

        console2.logString('getInstRevForInstDate; name3, earnDate1');
        ir = instRevMgr.getInstRevForInstDate(pid, name3, earnDate1);
        assertEq(ir.instName, name3);
        assertEq(ir.earnDate, earnDate1);

        console2.logString('getInstRevForInstDate; name1, earnDate2');
        ir = instRevMgr.getInstRevForInstDate(pid, name1, earnDate2);
        assertEq(ir.instName, name1);
        assertEq(ir.earnDate, earnDate2);

        // getInstRev(pid, name, date)
        console2.logString('getInstRev; index 0');
        ir = instRevMgr.getInstRev(pid, 0);
        assertEq(ir.instName, name1);
        assertEq(ir.earnDate, earnDate1);

        console2.logString('getInstRev; index 1');
        ir = instRevMgr.getInstRev(pid, 1);
        assertEq(ir.instName, name2);
        assertEq(ir.earnDate, earnDate1);

        console2.logString('getInstRev; index 2');
        ir = instRevMgr.getInstRev(pid, 2);
        assertEq(ir.instName, name3);
        assertEq(ir.earnDate, earnDate1);

        console2.logString('getInstRev; index 3');
        ir = instRevMgr.getInstRev(pid, 3);
        assertEq(ir.instName, name1);
        assertEq(ir.earnDate, earnDate2);

        // getInstRevsLen
        console2.logString('getInstRevsLen; various scenarios');
        assertEq(0, instRevMgr.getInstRevsLen(pid, 'unknown', earnDateE), 'unknown name, any date');
        assertEq(0, instRevMgr.getInstRevsLen(pid, nameE, earnDate3), 'unknown date, any name');
        assertEq(1, instRevMgr.getInstRevsLen(pid, name1, earnDate1), 'name1, earnDate1');
        assertEq(1, instRevMgr.getInstRevsLen(pid, name2, earnDate1), 'name2, earnDate1');
        assertEq(1, instRevMgr.getInstRevsLen(pid, name3, earnDate1), 'name3, earnDate1');
        assertEq(1, instRevMgr.getInstRevsLen(pid, name1, earnDate2), 'name1, earnDate2');
        assertEq(3, instRevMgr.getInstRevsLen(pid, nameE, earnDate1), 'any name, earnDate1');
        assertEq(1, instRevMgr.getInstRevsLen(pid, nameE, earnDate2), 'any name, earnDate2');
        assertEq(2, instRevMgr.getInstRevsLen(pid, name1, earnDateE), 'name1, any date');

        // getInstRevs
        console2.logString('getInstRevs; name: unknown, date: any');
        IR.InstRev[] memory instRevs = instRevMgr.getInstRevs(pid, 'unknown', earnDateE, 0, 10);
        assertEq(instRevs.length, 0);

        console2.logString('getInstRevs; name: name1, date: earnDate1');
        instRevs = instRevMgr.getInstRevs(pid, name1, earnDate1, 0, 2);
        assertEq(instRevs.length, 1);
        assertEq(instRevs[0].instName, name1);
        assertEq(instRevs[0].earnDate, earnDate1);

        console2.logString('getInstRevs; name: name1, date: any');
        instRevs = instRevMgr.getInstRevs(pid, name1, earnDateE, 0, 0);
        assertEq(instRevs.length, 2);
        assertEq(instRevs[0].instName, name1);
        assertEq(instRevs[0].earnDate, earnDate1);
        assertEq(instRevs[1].instName, name1);
        assertEq(instRevs[1].earnDate, earnDate2);

        console2.logString('getInstRevs; name: any, date: earnDate1');
        instRevs = instRevMgr.getInstRevs(pid, nameE, earnDate1, 0, 0);
        assertEq(instRevs.length, 3);
        assertEq(instRevs[0].instName, name1);
        assertEq(instRevs[0].earnDate, earnDate1);
        assertEq(instRevs[1].instName, name2);
        assertEq(instRevs[1].earnDate, earnDate1);
        assertEq(instRevs[2].instName, name3);
        assertEq(instRevs[2].earnDate, earnDate1);

        console2.logString('getInstRevs; name: any, date: any');
        instRevs = instRevMgr.getInstRevs(pid, nameE, earnDateE, 0, 0);
        assertEq(instRevs.length, 4);
        assertEq(instRevs[0].instName, name1);
        assertEq(instRevs[0].earnDate, earnDate1);
        assertEq(instRevs[1].instName, name2);
        assertEq(instRevs[1].earnDate, earnDate1);
        assertEq(instRevs[2].instName, name3);
        assertEq(instRevs[2].earnDate, earnDate1);
        assertEq(instRevs[3].instName, name1);
        assertEq(instRevs[3].earnDate, earnDate2);

        console2.logString('getInstRevs; name: any, date: any, get middle 2 of 4 items');
        instRevs = instRevMgr.getInstRevs(pid, nameE, earnDateE, 1, 2);
        assertEq(instRevs.length, 2);
        assertEq(instRevs[0].instName, name2);
        assertEq(instRevs[0].earnDate, earnDate1);
        assertEq(instRevs[1].instName, name3);
        assertEq(instRevs[1].earnDate, earnDate1);
    }

    function test_InstRevMgr_prop_prune() public {
        uint pid1 = 1;
        bool correction = false;

        console2.logString('propCreate; Fail, Caller access');
        vm.expectRevert(abi.encodeWithSelector(AC.AccessDenied.selector, creator));
        vm.prank(creator);
        instRevMgr.propCreate(pid1, eid1, usdcAddr, correction);
        assertEq(instRevMgr.getPropHdr(pid1).pid, 0, 'getPropHdr');

        console2.logString('propCreate; Success');
        _createProp(pid1, eid1, correction);

        console2.logString('Deposit revenue for each instrument');
        tokenUsdc.mint(dropAddr1, totalRev1); // A: Deposit
        tokenUsdc.mint(dropAddr2, totalRev2); // B: Deposit
        tokenUsdc.mint(dropAddr3, totalRev3); // C: Deposit
        tokenUsdc.mint(dropAddr1, totalRev4); // D: Deposit

        console2.logString('Create InstRev page');
        IR.InstRev[] memory page = new IR.InstRev[](3);
        _pageSetInstRev(page, 0, name1, earnDate1, unitRev1, totalQty1, dropAddr1); // A: Good inputs
        _pageSetInstRev(page, 1, name2, earnDate1, unitRev2, totalQty2, dropAddr2); // B: Good inputs
        _pageSetInstRev(page, 2, name3, earnDate1, unitRev3, totalQty3, dropAddr3); // C: Good inputs
        uint total = 4; // Total items to be uploaded (A,B,C,D)
        uint iAppend = 0;

        console2.logString('propAddInstRev; Add (A,B,C), full page success');
        _propAddInstRev(pid1, iAppend, total, page,
            IInstRevMgr.AddInstRc.FullPage, IInstRevMgr.AddInstLineRc.Ok, 3);

        // ----------
        // Remove InstRev from proposal
        // ----------

        console2.logString('pruneProp; Fail, Caller access');
        vm.expectRevert(abi.encodeWithSelector(AC.AccessDenied.selector, creator));
        vm.prank(creator);
        instRevMgr.pruneProp(pid1, name1, earnDate2);

        console2.logString('pruneProp; Fail, Bad pid');
        vm.prank(revMgrAddr);
        (IRevMgr.PruneRevRc rc, uint totalRev) = instRevMgr.pruneProp(pid1 + 1, name1, earnDate2);
        assertEq(uint(rc), uint(IRevMgr.PruneRevRc.NoProp), 'rc');
        assertEq(totalRev, 0, 'totalRev');

        console2.logString('pruneProp; Fail, Upload not complete');
        vm.prank(revMgrAddr);
        (rc, totalRev) = instRevMgr.pruneProp(pid1, name1, earnDate2);
        assertEq(uint(rc), uint(IRevMgr.PruneRevRc.PropStat), 'rc');
        assertEq(totalRev, 0, 'totalRev');

        console2.logString('Create InstRev page');
        page = new IR.InstRev[](1);
        _pageSetInstRev(page, 0, name1, earnDate2, unitRev4, totalQty1, dropAddr1); // D: Good inputs
        iAppend = 3;
        console2.logString('propAddInstRev; Add (D), full page success (all items uploaded)');
        _propAddInstRev(pid1, iAppend, total, page,
            IInstRevMgr.AddInstRc.AllPages, IInstRevMgr.AddInstLineRc.Ok, 1);
        assertEq(instRevMgr.getPropHdr(pid1).uploadedAt, block.timestamp, 'uploadedAt');

        console2.logString('pruneProp; Success Remove D');
        vm.prank(revMgrAddr);
        (rc, totalRev) = instRevMgr.pruneProp(pid1, name1, earnDate2);
        assertEq(uint(rc), uint(IRevMgr.PruneRevRc.Done), 'rc');
        assertEq(totalRev, totalRev4, 'totalRev');

        console2.logString('pruneProp; Success Remove C');
        vm.prank(revMgrAddr);
        (rc, totalRev) = instRevMgr.pruneProp(pid1, name3, earnDate1);
        assertEq(uint(rc), uint(IRevMgr.PruneRevRc.Done), 'rc');
        assertEq(totalRev, totalRev3, 'totalRev');

        console2.logString('pruneProp; Fail, Unknown name');
        vm.prank(revMgrAddr);
        (rc, totalRev) = instRevMgr.pruneProp(pid1, name3, earnDate1);
        assertEq(uint(rc), uint(IRevMgr.PruneRevRc.NoInst), 'rc');
        assertEq(totalRev, 0, 'totalRev');

        console2.logString('pruneProp; Success Remove B');
        vm.prank(revMgrAddr);
        (rc, totalRev) = instRevMgr.pruneProp(pid1, name2, earnDate1);
        assertEq(uint(rc), uint(IRevMgr.PruneRevRc.Done), 'rc');
        assertEq(totalRev, totalRev2, 'totalRev');

        console2.logString('pruneProp; Fail, Remove A (last item)');
        vm.prank(revMgrAddr);
        (rc, totalRev) = instRevMgr.pruneProp(pid1, name1, earnDate1);
        assertEq(uint(rc), uint(IRevMgr.PruneRevRc.LastInst), 'rc');
        assertEq(totalRev, 0, 'totalRev');

        // console2.logString('pruneProp; Fail, Already executed');
        // vm.prank(revMgrAddr);
        // instRevMgr.propExecuted(pid1);
        // vm.prank(revMgrAddr);
        // (rc, totalRev) = instRevMgr.pruneProp(pid1, name1, earnDate2);
        // assertEq(uint(rc), uint(IRevMgr.PruneRevRc.PropStat), 'rc');
        // assertEq(totalRev, 0, 'totalRev');
    }

    function _cloneParam(IInstRevMgr.AddInstRevAdjReq memory arg) private pure
        returns(IInstRevMgr.AddInstRevAdjReq memory clone)
    {
        uint len = arg.page.length;
        clone = IInstRevMgr.AddInstRevAdjReq({
            pid: arg.pid,
            iAppend: arg.iAppend,
            total: arg.total,
            instName: arg.instName,
            earnDate: arg.earnDate,
            requiredFunds: arg.requiredFunds,
            page: new IInstRevMgr.AllocFix[](len)
        });
        clone.page = new IInstRevMgr.AllocFix[](len);
        for (uint i = 0; i < len; ++i) {
            IInstRevMgr.AllocFix memory a = clone.page[i];
            IInstRevMgr.AllocFix memory b = arg.page[i];
            a.revenue = b.revenue;
            a.ownerEid = b.ownerEid;
        }
    }

    function test_InstRevMgr_prop_fixes() public {
        uint pid1 = 1;
        uint unitRev1Extra = 100_000;
        uint unitRev2Short =  50_000;
        uint totalRev1Extra = totalQty1 * unitRev1Extra;
        uint totalRev2Short = totalQty2 * unitRev2Short;
        console2.log('totalRev1Extra=', totalRev1Extra);
        console2.log('totalRev2Short=', totalRev2Short);
        uint unitRev1Before = unitRev1 + unitRev1Extra;
        uint unitRev2Before = unitRev2 - unitRev2Short;
        console2.log('unitRev1Before=', unitRev1Before);
        console2.log('unitRev2Before=', unitRev2Before);
        assertEq(totalRev1Extra, totalRev2Short, 'extra vs short');

        console2.logString('propCreate; Success');
        _createProp(pid1, eid1, true);

        console2.logString('Deposit revenue for each instrument');
        // Simulate an excess being allocated to name1 but should have been name2
        uint rev1Before = totalRev1 + totalRev1Extra;
        uint rev2Before = totalRev2 - totalRev2Short;
        tokenUsdc.mint(dropAddr2, totalRev2Short); // B: Deposit

        // ----------
        // Add revenue fixes for (name1,earnDate1) and (name2,earnDate1)
        // ----------
        IInstRevMgr.AddInstRevAdjReq memory reqOrig = IInstRevMgr.AddInstRevAdjReq({
            pid: pid1,
            iAppend: 0,
            total: 2,
            instName: name1,
            earnDate: earnDate1,
            requiredFunds: -int(totalRev1Extra),
            page: new IInstRevMgr.AllocFix[](2)
        });
        reqOrig.page[0] = IInstRevMgr.AllocFix({ revenue: 1, ownerEid: eid1, __gap: Util.gap5() });
        reqOrig.page[1] = IInstRevMgr.AllocFix({ revenue: 2, ownerEid: eid2, __gap: Util.gap5() });

        console2.logString('propAddInstRevAdj; Fail, Caller access');
        IInstRevMgr.AddInstRevAdjReq memory req = reqOrig; // Shallow copy, restore fields
        vm.expectRevert(abi.encodeWithSelector(AC.AccessDenied.selector, creator));
        vm.prank(creator);
        instRevMgr.propAddInstRevAdj(NoSeqNum, NoReqId, req);

        console2.logString('propAddInstRevAdj; Fail, Bad pid');
        req = _cloneParam(reqOrig); // Restore fields, deep copy
        req.pid += 1;
        uint40 seqNum = instRevMgr.getSeqNum(agent);
        UUID reqId = _newUuid();
        vm.prank(agent);
        instRevMgr.propAddInstRevAdj(seqNum, reqId, req);
        vm.prank(agent);
        ICallTracker.CallRes memory cr = instRevMgr.getCallResBySeqNum(seqNum);
        T.checkCall(vm, cr, uint(IInstRevMgr.AddInstRc.NoProp), 0, 0, 'propAddInstRevAdj');

        console2.logString('propAddInstRevAdj; Fail, Bad page');
        req = _cloneParam(reqOrig); // Restore fields, deep copy
        req.page = new IInstRevMgr.AllocFix[](0);
        reqId = _newUuid();
        vm.prank(agent);
        instRevMgr.propAddInstRevAdj(++seqNum, reqId, req);
        vm.prank(agent);
        cr = instRevMgr.getCallResBySeqNum(seqNum);
        T.checkCall(vm, cr, uint(IInstRevMgr.AddInstRc.BadPage), 0, 0);

        console2.logString('propAddInstRevAdj; Fail, Bad index');
        req = _cloneParam(reqOrig); // Restore fields, deep copy
        req.iAppend = 1;
        reqId = _newUuid();
        vm.prank(agent);
        instRevMgr.propAddInstRevAdj(++seqNum, reqId, req);
        vm.prank(agent);
        cr = instRevMgr.getCallResBySeqNum(seqNum);
        T.checkCall(vm, cr, uint(IInstRevMgr.AddInstRc.BadIndex), 0, 0);

        console2.logString('propAddInstRevAdj; Fail, Bad total');
        req = _cloneParam(reqOrig); // Restore fields, deep copy
        req.total = 0;
        reqId = _newUuid();
        vm.prank(agent);
        instRevMgr.propAddInstRevAdj(++seqNum, reqId, req);
        vm.prank(agent);
        cr = instRevMgr.getCallResBySeqNum(seqNum);
        T.checkCall(vm, cr, uint(IInstRevMgr.AddInstRc.BadTotal), 0, 0);

        console2.logString('propAddInstRevAdj; Fail, Low funds');
        req = _cloneParam(reqOrig); // Restore fields, deep copy
        reqId = _newUuid();
        vm.prank(agent);
        instRevMgr.propAddInstRevAdj(++seqNum, reqId, req);
        vm.prank(agent);
        cr = instRevMgr.getCallResBySeqNum(seqNum);
        T.checkCall(vm, cr, uint(IInstRevMgr.AddInstRc.LowFunds), 0, 0);

        console2.logString('Simulate funds having been previously sent to the vault');
        tokenUsdc.mint(vaultAddr, rev1Before + rev2Before + totalRev3);

        console2.logString('propAddInstRevAdj; Fail, Bad line - empty eid');
        req = _cloneParam(reqOrig); // Restore fields, deep copy
        req.page[0].ownerEid = eidE;
        reqId = _newUuid();
        vm.prank(agent);
        instRevMgr.propAddInstRevAdj(++seqNum, reqId, req);
        vm.prank(agent);
        cr = instRevMgr.getCallResBySeqNum(seqNum);
        T.checkCall(vm, cr, uint(IInstRevMgr.AddInstRc.BadLine), 0, 0);

        console2.logString('propAddInstRevAdj; Fail, Bad line - empty revenue');
        req = _cloneParam(reqOrig); // Restore fields, deep copy
        req.page[0].revenue = 0;
        reqId = _newUuid();
        vm.prank(agent);
        instRevMgr.propAddInstRevAdj(++seqNum, reqId, req);
        vm.prank(agent);
        cr = instRevMgr.getCallResBySeqNum(seqNum);
        T.checkCall(vm, cr, uint(IInstRevMgr.AddInstRc.BadLine), 0, 0);

        console2.logString('propAddInstRevAdj; Success name1');
        req = _cloneParam(reqOrig); // Restore fields, deep copy
        reqId = _newUuid();
        vm.expectEmit();
        emit IInstRevMgr.InstAllocFixUploaded(pid1, name1, earnDate1, 2, 2);
        vm.prank(agent);
        instRevMgr.propAddInstRevAdj(++seqNum, reqId, req);
        vm.prank(agent);
        cr = instRevMgr.getCallResBySeqNum(seqNum);
        T.checkCall(vm, cr, uint(IInstRevMgr.AddInstRc.AllPages), 0, 2);

        assertEq(instRevMgr.getAllocFixesLen(pid1, name1, earnDate1), 2, 'getAllocFixesLen');
        (int revenue, UUID ownerEid) = instRevMgr.getAllocFix(pid1, name1, earnDate1, 0);
        assertEq(revenue, 1, 'revenue');
        assertEq(UUID.unwrap(ownerEid), UUID.unwrap(eid1), 'ownerEid');
        (revenue, ownerEid) = instRevMgr.getAllocFix(pid1, name1, earnDate1, 1);
        assertEq(revenue, 2, 'revenue');
        assertEq(UUID.unwrap(ownerEid), UUID.unwrap(eid2), 'ownerEid');

        console2.logString('propAddInstRevAdj; Fail, Upload complete');
        req = _cloneParam(reqOrig); // Restore fields, deep copy
        reqId = _newUuid();
        vm.prank(agent);
        instRevMgr.propAddInstRevAdj(++seqNum, reqId, req);
        vm.prank(agent);
        cr = instRevMgr.getCallResBySeqNum(seqNum);
        T.checkCall(vm, cr, uint(IInstRevMgr.AddInstRc.ReadOnly), 0, 0);

        console2.logString('propAddInstRevAdj; Success name2');
        req = _cloneParam(reqOrig); // Restore fields, deep copy
        req.instName = name2;
        req.requiredFunds = int(totalRev2Short); // Funds from dropAddr to vault
        req.page[0].ownerEid = eid3;
        req.page[1].ownerEid = eid4;
        req.page[0].revenue = 3;
        req.page[1].revenue = 4;
        reqId = _newUuid();
        vm.expectEmit();
        emit IInstRevMgr.InstAllocFixUploaded(pid1, name2, earnDate1, 2, 2);
        vm.prank(agent);
        instRevMgr.propAddInstRevAdj(++seqNum, reqId, req);
        vm.prank(agent);
        cr = instRevMgr.getCallResBySeqNum(seqNum);
        T.checkCall(vm, cr, uint(IInstRevMgr.AddInstRc.AllPages), 0, 2);
        assertEq(instRevMgr.getAllocFixesLen(pid1, name2, earnDate1), 2, 'getAllocFixesLen');
        (revenue, ownerEid) = instRevMgr.getAllocFix(pid1, name2, earnDate1, 0);
        assertEq(revenue, 3, 'revenue');
        assertEq(UUID.unwrap(ownerEid), UUID.unwrap(eid3), 'ownerEid');
        (revenue, ownerEid) = instRevMgr.getAllocFix(pid1, name2, earnDate1, 1);
        assertEq(revenue, 4, 'revenue');
        assertEq(UUID.unwrap(ownerEid), UUID.unwrap(eid4), 'ownerEid');

        // ----------
        // Add InstRev
        // ----------
        console2.logString('Create InstRev page');
        IR.InstRev[] memory page = new IR.InstRev[](2);
        // Accidentally add extra (`totalRev1Extra`) to `name1` instead of `name2` - will be fixed after
        _pageSetInstRev(page, 0, name1, earnDate1, unitRev1Before, totalQty1, dropAddr1);   // A: Good inputs, high rev
        _pageSetInstRev(page, 1, name2, earnDate1, unitRev2Before, totalQty2, dropAddr2);   // B: Good inputs, low rev
        uint total = 2; // Total items to be uploaded (A,B)
        uint iAppend = 0;

        console2.logString('propAddInstRev; Add (A,B), full page success');
        _propAddInstRev(pid1, iAppend, total, page,
            IInstRevMgr.AddInstRc.AllPages, IInstRevMgr.AddInstLineRc.Ok, 2);

        // ----------
        // Finalize
        // ----------
        console2.logString('propFinalize; Success');
        vm.prank(revMgrAddr);
        assertTrue(instRevMgr.propFinalize(pid1));

        // ----------
        // Execute
        // ----------
        console2.log('propExecInstRev; Progress, iInstRev=0');
        assertEq(tokenUsdc.balanceOf(dropAddr1), 0, 'dropAddr1 balance A');
        vm.expectEmit();
        emit IInstRevMgr.RevenueXfer(pid1, name1, earnDate1, true, true,
            usdcAddr, vaultAddr, dropAddr1, totalRev1Extra);
        vm.prank(revMgrAddr);
        IRevMgr.ExecRevRc rc = instRevMgr.propExecInstRev(pid1, 0);
        assertEq(uint(rc), uint(IRevMgr.ExecRevRc.Progress), 'ExecRevRc');
        assertEq(tokenUsdc.balanceOf(dropAddr1), totalRev1Extra, 'dropAddr1 balance B'); // extra sent from vault

        console2.log('propExecInstRev; Progress, iInstRev=1');
        assertEq(tokenUsdc.balanceOf(dropAddr2), totalRev2Short, 'dropAddr2 balance A');
        vm.expectEmit();
        emit IInstRevMgr.RevenueXfer(pid1, name2, earnDate1, true, true,
            usdcAddr, dropAddr2, vaultAddr, totalRev2Short);
        vm.prank(revMgrAddr);
        rc = instRevMgr.propExecInstRev(pid1, 1);
        assertEq(uint(rc), uint(IRevMgr.ExecRevRc.Progress), 'ExecRevRc');
        assertEq(tokenUsdc.balanceOf(dropAddr2), 0, 'dropAddr2 balance B'); // shortage sent to vault
    }

    function _cloneInstRev(IR.InstRev memory orig) internal pure returns (IR.InstRev memory copy) {
        copy.instName = orig.instName;
        copy.earnDate = orig.earnDate;
        copy.unitRev = orig.unitRev;
        copy.totalRev = orig.totalRev;
        copy.totalQty = orig.totalQty;
        copy.dropAddr = orig.dropAddr;
        copy.uploadedAt = orig.uploadedAt;
        copy.executedAt = orig.executedAt;
    }

    function test_InstRevMgr_validateInstRev() public {
        InstRevMgrSpy spy1 = (new InstRevMgrSpyProxyDeployer()).createProxy(
                (new InstRevMgrSpyLogicDeployer()).deployLogic(), creator, NoReqId);
        assertEq(spy1.getVersion(), 10, 'getVersion'); // Sanity check

        // Test inputs
        uint pid1 = 1;
        IR.InstRev memory instRevOrig = IR.InstRev({
            instName: name1,
            instNameKey: '', // Caller does not set this, set in contract
            earnDate: earnDate1,
            unitRev: unitRev1,
            totalRev: totalRev1,
            totalQty: totalQty1,
            dropAddr: dropAddr1,
            ccyAddr: usdcAddr,
            uploadedAt: 0,
            executedAt: 0,
            __gap: Util.gap5()
        });
        IR.InstRev memory instRev = instRevOrig;
        InstRevMgr.AddInstLineRc lrc;

        // No access control check as only exposed via spy, could be external but +SIZE

        console2.logString('Name empty');
        instRev = _cloneInstRev(instRevOrig);   // Restore fields
        instRev.instName = '';                  // Modify for test
        lrc = spy1.validateInstRev(pid1, instRev, false);
        assertEq(uint(lrc), uint(IInstRevMgr.AddInstLineRc.InstName), 'lrc');

        console2.logString('TotalQty zero');
        instRev = _cloneInstRev(instRevOrig);   // Restore fields
        instRev.totalQty = 0;                   // Modify for test
        lrc = spy1.validateInstRev(pid1, instRev, false);
        assertEq(uint(lrc), uint(IInstRevMgr.AddInstLineRc.TotalQty), 'lrc');

        console2.logString('EarnDate zero');
        instRev = _cloneInstRev(instRevOrig);   // Restore fields
        instRev.earnDate = 0;                   // Modify for test
        lrc = spy1.validateInstRev(pid1, instRev, false);
        assertEq(uint(lrc), uint(IInstRevMgr.AddInstLineRc.EarnDate), 'lrc');

        console2.logString('TotalRev exceeds the sum of the parts');
        instRev = _cloneInstRev(instRevOrig);   // Restore fields
        instRev.totalRev -= 1;                  // Modify for test
        lrc = spy1.validateInstRev(pid1, instRev, false);
        assertEq(uint(lrc), uint(IInstRevMgr.AddInstLineRc.SubtotalRev), 'lrc');

        console2.logString('Success');
        instRev = _cloneInstRev(instRevOrig);   // Restore fields
        lrc = spy1.validateInstRev(pid1, instRev, false);
        assertEq(uint(lrc), uint(IInstRevMgr.AddInstLineRc.Ok), 'lrc');

        console2.logString('Inst not in prop, correction');
        instRev = _cloneInstRev(instRevOrig);   // Restore fields
        lrc = spy1.validateInstRev(pid1, instRev, true);
        assertEq(uint(lrc), uint(IInstRevMgr.AddInstLineRc.Ok), 'lrc');

        console2.logString('Inst not in prop, !correction');
        instRev = _cloneInstRev(instRevOrig);               // Restore fields
        assertTrue(spy1.addInstRevToProp(pid1, instRev));   // Modify state for test
        lrc = spy1.validateInstRev(pid1, instRev, false);
        assertEq(uint(lrc), uint(IInstRevMgr.AddInstLineRc.PropHas2), 'lrc');

        console2.logString('InstRev already in executed state, !correction');
        instRev = _cloneInstRev(instRevOrig);               // Restore fields
        assertTrue(spy1.addInstRevToExecuted(instRev));     // Modify state for test
        lrc = spy1.validateInstRev(pid1, instRev, false);
        assertEq(uint(lrc), uint(IInstRevMgr.AddInstLineRc.PropHas2), 'lrc');

        InstRevMgrSpy spy2 = (new InstRevMgrSpyProxyDeployer()).createProxy(
            (new InstRevMgrSpyLogicDeployer()).deployLogic(), creator, NoReqId);
        assertEq(spy2.getVersion(), 10, 'getVersion');      // Sanity check

        console2.logString('InstRev already in executed state, correction');
        instRev = _cloneInstRev(instRevOrig);               // Restore fields
        assertTrue(spy2.addInstRevToExecuted(instRev));     // Modify state for test
        lrc = spy2.validateInstRev(pid1, instRev, true);
        assertEq(uint(lrc), uint(IInstRevMgr.AddInstLineRc.Ok), 'lrc');
    }
}
