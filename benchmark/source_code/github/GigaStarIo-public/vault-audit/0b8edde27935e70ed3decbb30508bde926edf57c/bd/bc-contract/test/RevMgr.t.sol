// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

// See LIB_PATHS
import '../lib/forge-std/src/Test.sol';

import '../lib/openzeppelin-contracts/contracts/interfaces/IERC1155Receiver.sol';
import '../lib/openzeppelin-contracts/contracts/interfaces/IERC1967.sol';
import '../lib/openzeppelin-contracts/contracts/proxy/Clones.sol';
import '../lib/openzeppelin-contracts/contracts/utils/Strings.sol';

import '../contract/v1_0/Erc20Test.sol';
import '../contract/v1_0/IRevMgr.sol';
import '../contract/v1_0/ICallTracker.sol';
import '../contract/v1_0/IContractUser.sol';
import '../contract/v1_0/IVersion.sol';
import '../contract/v1_0/LibraryAC.sol';
import '../contract/v1_0/LibraryBI.sol';
import '../contract/v1_0/LibraryCU.sol';
import '../contract/v1_0/LibraryIR.sol';
import '../contract/v1_0/LibraryOI.sol';
import '../contract/v1_0/LibraryString.sol';
import '../contract/v1_0/LibraryTI.sol';
import '../contract/v1_0/LogicDeployers.sol';
import '../contract/v1_0/ProxyDeployers.sol';
import '../contract/v1_0/RevMgr.sol';
import '../contract/v1_0/Types.sol';

import './Const.sol';
import './LibraryTest.sol';

contract RevMgrLatest is RevMgr {
    function getVersion() public pure override returns (uint) { return 999; }
}

// Exposes details for testing
contract RevMgrSpy is RevMgr {
}

contract RevMgrSpyLogicDeployer is LogicDeployer {
    constructor() { _logic = address(new RevMgrSpy()); emit LogicDeployed(_logic); }
}

contract RevMgrSpyProxyDeployer {
    uint40 constant NoSeqNum = 0;
    UUID constant NoReqId = UuidZero;

    function createProxy(address logicAddr, address creator, UUID reqId) public returns(RevMgrSpy) {
        address proxyAddr = (new ProxyDeployer()).deployProxy(logicAddr, 'RevMgrSpy',
            abi.encodeWithSelector(IRevMgr.initialize.selector, creator, reqId));
        return RevMgrSpy(proxyAddr);
    }
}

contract RevMgrTest is Test {
    address creator = address(this);
    address admin = address(20);
    address agent = address(21);
    address voter1 = address(22);
    address voter2 = address(23);
    address voter3 = address(24);
    address other = address(6);
    address zeroAddr = AddrZero;

    IRevMgr revMgr = (new RevMgrProxyDeployer()).createProxy((
            new RevMgrLogicDeployer()).deployLogic(), creator, NoReqId);

    IInstRevMgr instRevMgr = (new InstRevMgrProxyDeployer()).createProxy((
        new InstRevMgrLogicDeployer()).deployLogic(), creator, NoReqId);

    IEarnDateMgr earnDateMgr = (new EarnDateMgrProxyDeployer()).createProxy((
        new EarnDateMgrLogicDeployer()).deployLogic(), creator, NoReqId);

    IBalanceMgr balanceMgr = (new BalanceMgrProxyDeployer()).createProxy((
        new BalanceMgrLogicDeployer()).deployLogic(), creator, NoReqId);

    IBoxMgr boxMgr = (new BoxMgrProxyDeployer()).createProxy((
        new BoxMgrLogicDeployer()).deployLogic(), creator, NoReqId);

    IVault vault = (new VaultProxyDeployer()).createProxy((
        new VaultLogicDeployer()).deployLogic(), creator, NoReqId, 3, _createRoles());

    address revMgrAddr = address(revMgr);
    address instRevMgrAddr = address(instRevMgr);
    address earnDateMgrAddr = address(earnDateMgr);
    address balanceMgrAddr = address(balanceMgr);
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

    TI.TokenInfo tokenInfoUsdc = _makeTokenInfo('USDC', usdcAddr, TI.TokenType.Erc20);
    TI.TokenInfo tokenInfoEurc = _makeTokenInfo('EURC', eurcAddr, TI.TokenType.Erc20);
    TI.TokenInfo tokenInfoEth = _makeTokenInfo('ETH', zeroAddr, TI.TokenType.NativeCoin);
    TI.TokenInfo[] _tokens; // storage var to reduce stack pressure

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
        _setContracts(balanceMgr);
        _setContracts(boxMgr);
        _setContracts(earnDateMgr);
        _setContracts(instRevMgr);
        _setContracts(revMgr);
        _setContracts(vault);

        _labelAddresses();

        _addBoxes();

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

    function _setContracts(IContractUser user) private {
        user.setContract(NoSeqNum, NoReqId, CU.BoxMgr, boxMgrAddr);
        user.setContract(NoSeqNum, NoReqId, CU.BalanceMgr, balanceMgrAddr);
        user.setContract(NoSeqNum, NoReqId, CU.EarnDateMgr, earnDateMgrAddr);
        user.setContract(NoSeqNum, NoReqId, CU.InstRevMgr, instRevMgrAddr);
        user.setContract(NoSeqNum, NoReqId, CU.RevMgr, revMgrAddr);
        user.setContract(NoSeqNum, NoReqId, CU.Vault, vaultAddr);
    }

    function _labelAddresses() private {
        vm.label(creator, 'creator');
        vm.label(admin, 'admin');
        vm.label(agent, 'agent');
        vm.label(voter1, 'voter1');
        vm.label(voter2, 'voter2');
        vm.label(voter3, 'voter3');
        vm.label(other, 'other');

        vm.label(balanceMgrAddr, 'balanceMgr');
        vm.label(boxMgrAddr, 'boxMgr');
        // vm.label(crtAddr, 'crt');
        vm.label(earnDateMgrAddr, 'earnDateMgr');
        vm.label(instRevMgrAddr, 'instRevMgr');
        vm.label(revMgrAddr, 'revMgr');
        // vm.label(xferMgrAddr, 'xferMgr');
        vm.label(vaultAddr, 'vault');

        vm.label(dropAddr1, 'dropAddr1');
        vm.label(dropAddr2, 'dropAddr2');
        vm.label(dropAddr3, 'dropAddr3');

        vm.label(Util.ExplicitMint, 'ExplicitMintBurn');
        vm.label(Util.ContractHeld, 'ContractHeld');

        vm.label(usdcAddr, 'usdcAddr');
        vm.label(eurcAddr, 'eurcAddr');
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
        spenders[0] = address(revMgr);
        if (_tokens.length == 0) {
            _tokens.push(tokenInfoUsdc);
            _tokens.push(tokenInfoEurc);
        }
        dropAddr1 = _addBox(name1, spenders);
        dropAddr2 = _addBox(name2, spenders);
        dropAddr3 = _addBox(name3, spenders);
    }

    function _addBox(string memory name, address[] memory spenders) private
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
            tokens: _tokens
        }));
        bool found; BI.BoxInfo memory box;
        (found, box) = boxMgr.getBoxByName(name, true);
        return box.boxProxy;
    }

    function test_RevMgr_initialize() public {
        // Attempt to initialize again; revert as not allowed
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        revMgr.initialize(creator, NoReqId);
    }

    function test_RevMgr_upgrade() public {
        // Deploy a mock upgraded logic
        address newLogic = address(new RevMgrLatest());
        assertNotEq(newLogic, zeroAddr);

        // Upgrade access denied
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(AC.AccessDenied.selector, other));
        UUPSUpgradeable(revMgrAddr).upgradeToAndCall(address(newLogic), '');

        // Upgrade via UUPS with an empty initData
        uint40 seqNum = revMgr.getSeqNum(creator);
        UUID reqId = _newUuid();
        UUID reqIdStage = _newUuid();
        vm.prank(creator);
        revMgr.preUpgrade(seqNum, reqId, reqIdStage);
        vm.expectEmit();
        emit IERC1967.Upgraded(newLogic);
        vm.prank(creator);
        UUPSUpgradeable(revMgrAddr).upgradeToAndCall(address(newLogic), '');

        // Verify
        assertEq(revMgr.getVersion(), 999);        // New behavior
        assertEq(revMgr.getPropHdr(0).pid, 0); // Old behavior
    }

    function test_RevMgr_empty_state() public {
        vm.startPrank(other);
        assertEq(revMgr.getPropHdr(0).pid, 0, 'getPropHdr');

        (uint revenue, uint qty) = revMgr.getOwnInfo(0, name1, earnDate1, eid1);
        assertEq(revenue, 0, 'revenue');
        assertEq(qty, 0, 'qty');

        (uint len, uint uploadedAt, uint executedAt) = revMgr.getOwnInfosLen(0, name1, earnDate1);
        assertEq(len, 0, 'len');
        assertEq(uploadedAt, 0, 'uploadedAt');
        assertEq(executedAt, 0, 'executedAt');

        OI.OwnInfo[] memory ownInfos = revMgr.getOwnInfos(0, name1, earnDate1, 0, 1);
        assertEq(ownInfos.length, 0, 'ownInfos.length');
    }

    function _checkUuid(UUID actual, UUID expect, string memory description) private pure {
        assertEq(UUID.unwrap(actual), UUID.unwrap(expect), description);
    }

    function _createProp(uint pid, UUID reqId, bool correction) private {
        assertEq(instRevMgr.getPropHdr(pid).pid, 0, 'instRevMgr pid before');

        vm.prank(vaultAddr);
        revMgr.propCreate(pid, reqId, usdcAddr, correction);
        IRevMgr.PropHdr memory hdr = revMgr.getPropHdr(pid);

        assertEq(hdr.pid, pid, 'pid');
        _checkUuid(hdr.eid, reqId, 'reqId');
        assertEq(hdr.totalRevenue, 0, 'totalRevenue');
        assertEq(hdr.iInst, 0, 'iInst');
        assertEq(hdr.iOwner, 0, 'iOwner');
        assertEq(hdr.iRevFix, 0, 'iRevFix');
        assertEq(hdr.uploadedAt, 0, 'uploadedAt');
        assertEq(hdr.executedAt, 0, 'executedAt');
        assertEq(hdr.correction, correction, 'correction');

        assertEq(instRevMgr.getPropHdr(pid).pid, pid, 'instRevMgr pid after');
    }

    function _makeAddOwnersReq(uint pid, uint iAppend, uint total, string memory instName,
        uint earnDate, OI.OwnInfo[] memory page) private pure returns(IRevMgr.AddOwnersReq memory)
    {
        return IRevMgr.AddOwnersReq({
            pid: pid,
            iAppend: iAppend,
            total: total,
            instName: instName,
            earnDate: earnDate,
            page: page
        });
    }

    function _propAddOwners(uint40 seqNum, uint pid, uint iAppend, uint total, string memory instName,
        uint earnDate, OI.OwnInfo[] memory page, IRevMgr.AddOwnRc rc, uint count, uint totalExpect
    ) private {
        if (count > 0) _expectEmitOwnersUploaded(pid, instName, earnDate, count);
        if (total > 0 && total == totalExpect) {
            vm.expectEmit();
            emit IRevMgr.AllOwnersUploaded(pid, instName, earnDate, total);
        }
        UUID reqId = _newUuid();
        IRevMgr.AddOwnersReq memory req = _makeAddOwnersReq(pid, iAppend, total, instName, earnDate, page);
        seqNum = revMgr.getSeqNum(agent); // Not ideal but overriding input since caller likely tracking instRevMgr seqNum
        vm.prank(agent);
        revMgr.propAddOwners(seqNum, reqId, req);
        vm.prank(agent);
        ICallTracker.CallRes memory cr = revMgr.getCallResBySeqNum(seqNum);
        assertNotEq(uint(0), uint(cr.blockNum), 'blockNum');
        T.checkCall(vm, cr, uint(rc), 0, count, 'propAddOwners');
    }

    function _propAddInstRev(uint pid, uint iAppend, uint total, IR.InstRev[] memory page,
        IInstRevMgr.AddInstRc rc, IInstRevMgr.AddInstLineRc lrc, uint count) private
    {
        UUID reqId = _newUuid();
        uint40 seqNum = instRevMgr.getSeqNum(agent);
        vm.prank(agent);
        instRevMgr.propAddInstRev(seqNum, reqId,
            IInstRevMgr.PropAddInstRevReq({pid: pid, iAppend: iAppend, total: total, page: page}));
        vm.prank(agent);
        ICallTracker.CallRes memory cr = instRevMgr.getCallResBySeqNum(seqNum);
        assertNotEq(uint(0), uint(cr.blockNum), 'blockNum');
        T.checkCall(vm, cr, uint(rc), uint(lrc), count, 'propAddInstRev');
    }

    function _pageAddInstRev(IR.InstRev[] memory page, uint iPage, string memory instName, uint earnDate, uint unitRev,
        uint totalQty, address dropAddr) private view
    {
        assertGt(page.length, iPage, 'page.length > iPage');
        page[iPage] = IR.InstRev({
            instName: instName,
            instNameKey: 0, // Set in contract
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

    function _pageAddInstRevs(uint pid) private {
        console2.logString('Create InstRev page');
        IR.InstRev[] memory page = new IR.InstRev[](2);
        _pageAddInstRev(page, 0, name1, earnDate1, unitRev1, totalQty1, dropAddr1); // A: Good inputs
        _pageAddInstRev(page, 1, name2, earnDate1, unitRev2, totalQty2, dropAddr2); // B: Good inputs

        console2.logString('propAddInstRev; Add (A,B), full page success');
        _propAddInstRev(pid, 0, page.length, page, IInstRevMgr.AddInstRc.AllPages, IInstRevMgr.AddInstLineRc.Ok, 2);
    }

    function _expectEmitOwnersUploaded(uint pid, string memory instName, uint earnDate, uint bookLen) private {
        vm.expectEmit();
        emit IRevMgr.OwnersUploaded(pid, instName, earnDate, bookLen);
    }

    function _makeOwners(uint ownersLen, uint unitRev, uint totalQty) private pure
        returns(OI.OwnInfo memory ownA, OI.OwnInfo memory ownB, OI.OwnInfo memory ownC, OI.OwnInfo memory ownD)
    {
        uint64 own1Qty = uint64(totalQty / 10);
        uint64 own2Qty; uint64 own3Qty; uint64 own4Qty;
        if (ownersLen == 2) {
            // Split the qty into 2 parts with ratio: 1:9
            own2Qty = uint64(own1Qty * 9);
        } else {
            // Split the qty into 4 parts with ratio: 1:2:3:4
            own2Qty = uint64(own1Qty * 2);
            own3Qty = uint64(own1Qty * 3);
            own4Qty = uint64(own1Qty * 4);
        }
        uint own1Rev = unitRev * own1Qty;
        ownA = OI.OwnInfo({revenue: own1Rev, qty: own1Qty, eid: eid1});
        if (ownersLen == 2) {
            // Split the revenue into 2 parts with ratio: 1:9
            uint own2Rev = own1Rev * 9;
            ownB = OI.OwnInfo({revenue: own2Rev, qty: own2Qty, eid: eid2});
        } else {
            // Split the revenue into 4 parts with ratio: 1:2:3:4
            uint own2Rev = own1Rev * 2;
            uint own3Rev = own1Rev * 3;
            uint own4Rev = own1Rev * 4;
            ownB = OI.OwnInfo({revenue: own2Rev, qty: own2Qty, eid: eid2});
            ownC = OI.OwnInfo({revenue: own3Rev, qty: own3Qty, eid: eid3});
            ownD = OI.OwnInfo({revenue: own4Rev, qty: own4Qty, eid: eid4});
        }
    }

    function test_RevMgr_prop_create() public {
        uint pid1 = 1;
        bool correction = false;

        // ───────────────────────────────────────
        // Create Proposal
        // ───────────────────────────────────────
        console2.logString('propCreate; Fail, Caller access');
        vm.expectRevert(abi.encodeWithSelector(AC.AccessDenied.selector, creator));
        vm.prank(creator);
        revMgr.propCreate(pid1, eid1, usdcAddr, correction);
        assertEq(revMgr.getPropHdr(pid1).pid, 0, 'getPropHdr');

        console2.logString('propCreate; Success');
        _createProp(pid1, eid1, correction);

        uint iAppend = 0;
        uint total = 0;
        uint40 seqNum = 1;
        OI.OwnInfo[] memory oiPage = new OI.OwnInfo[](0);
        UUID reqId = _newUuid();

        console2.logString('propAddOwners; Fail, Caller access');
        vm.expectRevert(abi.encodeWithSelector(AC.AccessDenied.selector, creator));
        vm.prank(creator);
        revMgr.propAddOwners(NoSeqNum, NoReqId, _makeAddOwnersReq(pid1, iAppend, total, name1, earnDate1, oiPage));

        console2.logString('propAddOwners; Fail, Bad pid');
        _propAddOwners(seqNum, pid1 + 1, iAppend, total, name1, earnDate1, oiPage, IRevMgr.AddOwnRc.NoProp, 0, 0);

        console2.logString('propAddOwners; Fail, No InstRev');
        reqId = _newUuid();
        _propAddOwners(++seqNum, pid1, iAppend, total, name1, earnDate1, oiPage, IRevMgr.AddOwnRc.NoInstRev, 0, 0);

        // Can't do this here since the proposal was created as not a correction, handled in another test
        // console2.logString('propAddOwners; Fail, Correction and not found');

        console2.logString('Deposit revenue for each instrument');
        tokenUsdc.mint(dropAddr1, totalRev1); // A: Deposit
        tokenUsdc.mint(dropAddr2, totalRev2); // B: Deposit
        assertEq(tokenUsdc.balanceOf(dropAddr1), totalRev1, 'dropAddr1 balance A');
        assertEq(tokenUsdc.balanceOf(dropAddr2), totalRev2, 'dropAddr2 balance B');

        // ───────────────────────────────────────
        // Add 2 InstRevs to Proposal
        // ───────────────────────────────────────
        console2.logString('Create InstRevs - required before owners');
        _pageAddInstRevs(pid1);

        console2.logString('propAddOwners; Fail, Bad page length');
        reqId = _newUuid();
        _propAddOwners(++seqNum, pid1, iAppend, total, name1, earnDate1, oiPage, IRevMgr.AddOwnRc.BadPage, 0, 0);

        console2.logString('propAddOwners; Fail, Bad index');
        oiPage = new OI.OwnInfo[](1);
        reqId = _newUuid();
        _propAddOwners(++seqNum, pid1, iAppend + 1, total, name1, earnDate1, oiPage, IRevMgr.AddOwnRc.BadIndex, 0, 0);

        console2.logString('propAddOwners; Fail, Bad total');
        reqId = _newUuid();
        _propAddOwners(++seqNum, pid1, iAppend, total, name1, earnDate1, oiPage, IRevMgr.AddOwnRc.BadTotal, 0, 0);

        // console2.logString('Remove pre-approval on dropAddr2 to do boxMgr.approve path');
        // tokenUsdc.setApproval(dropAddr2, revMgrAddr, 0);

        // ----------
        // Add Owners for InstRev1 (name1, earnDate1)
        // ----------
        console2.logString('propAddOwners; InstRev1 Attempt add (A,B,C), B fails validation (empty eid)');
        OI.OwnInfo memory ownE; // Empty
        OI.OwnInfo memory own1a; OI.OwnInfo memory own1b; OI.OwnInfo memory own1c; OI.OwnInfo memory own1d;
        (own1a, own1b, own1c, own1d) = _makeOwners(4, unitRev1, totalQty1);
        oiPage = new OI.OwnInfo[](3);
        oiPage[0] = own1a;
        oiPage[1] = own1b;
        oiPage[2] = own1c;
        total = 4; // Total owners to be uploaded (A,B,C,D)

        console2.logString('propAddOwners; InstRev1 Attempt add (A,B,C), B fails validation (empty eid)');
        OI.OwnInfo memory own1bBad = OI.OwnInfo({revenue: own1b.revenue, qty: own1b.qty, eid: eidE}); // Empty eid
        oiPage[1] = own1bBad;
        reqId = _newUuid();
        _propAddOwners(++seqNum, pid1, iAppend, total, name1, earnDate1, oiPage, IRevMgr.AddOwnRc.BadLine, 1, 1);

        console2.logString('propAddOwners; InstRev1 Attempt add (B,C), B fails validation (empty revenue)');
        oiPage = new OI.OwnInfo[](2);
        own1bBad = OI.OwnInfo({revenue: 0, qty: own1b.qty, eid: own1b.eid}); // Empty revenue
        oiPage[0] = own1bBad;
        oiPage[1] = own1c;
        iAppend = 1;
        reqId = _newUuid();
        _propAddOwners(++seqNum, pid1, iAppend, total, name1, earnDate1, oiPage, IRevMgr.AddOwnRc.BadLine, 0, 1);

        console2.logString('propAddOwners; InstRev1 Attempt add (B,C), B fails validation (revenue mismatch)');
        own1bBad = OI.OwnInfo({revenue: own1b.revenue, qty: 1, eid: own1b.eid}); // Revenue != (qty x unitRev)
        oiPage[0] = own1bBad;
        reqId = _newUuid();
        _propAddOwners(++seqNum, pid1, iAppend, total, name1, earnDate1, oiPage, IRevMgr.AddOwnRc.BadLine, 0, 1);

        console2.logString('propAddOwners; InstRev1 Add (B,C), full page success');
        oiPage[0] = own1b;
        reqId = _newUuid();
        _propAddOwners(++seqNum, pid1, iAppend, total, name1, earnDate1, oiPage, IRevMgr.AddOwnRc.FullPage, 2, 3);

        // A duplicate call to verify no effect
        console2.logString('propAddOwners; InstRev1 Fail, - bad index (B,C not removed from page)');
        reqId = _newUuid();
        _propAddOwners(++seqNum, pid1, iAppend, total, name1, earnDate1, oiPage, IRevMgr.AddOwnRc.BadIndex, 0, 3);

        console2.logString('propAddOwners; InstRev1 Add (D), all pages success');
        assertEq(revMgr.getPropHdr(pid1).uploadedAt, 0, 'uploadedAt before');
        iAppend = 3;
        oiPage = new OI.OwnInfo[](1);
        oiPage[0] = own1d;
        reqId = _newUuid();
        _propAddOwners(++seqNum, pid1, iAppend, total, name1, earnDate1, oiPage, IRevMgr.AddOwnRc.AllPages, 1, 4);
        assertEq(revMgr.getPropHdr(pid1).uploadedAt, 0, 'uploadedAt after');

        console2.logString('propAddOwners; InstRev1 Fail (already uploaded)');
        reqId = _newUuid();
        _propAddOwners(++seqNum, pid1, iAppend, total, name1, earnDate1, oiPage, IRevMgr.AddOwnRc.ReadOnly, 0, 0);

        // ----------
        // Validate InstRev and OwnInfo counts
        // ----------

        // Filter for owners added above
        total = 4;
        (uint len, uint uploadedAt, uint executedAt) = revMgr.getOwnInfosLen(pid1, name1, earnDate1);
        assertEq(len, total, 'len prop, OwnInfo: name1, earnDate1');

        // Filter for non-existant name2
        total = 0;
        (len, uploadedAt, executedAt) = revMgr.getOwnInfosLen(pid1, name2, earnDate1);
        assertEq(len, total, 'len prop, OwnInfo: name2, earnDate1');

        // ----------
        // Validate InstRevs and OwnInfos in state and proposal
        // ----------
        console2.log('Validate state in proposal before execution');
        _checkOwnInfos(pid1, name1, earnDate1, true, false, 1, 4, own1a, own1b, own1c, own1d);
        _checkOwnInfos(pid1, name2, earnDate1, false, false, 1, 0, ownE, ownE, ownE, ownE);

        console2.log('Validate executed state before execution');
        _checkOwnInfos(0, name1, earnDate1, false, false, 0, 0, ownE, ownE, ownE, ownE);
        _checkOwnInfos(0, name2, earnDate1, false, false, 0, 0, ownE, ownE, ownE, ownE);

        // ----------
        // Fail to finalize incomplete proposal (missing owners for InstRev2)
        // ----------
        console2.logString('propFinalize; Fail, caller access');
        vm.expectRevert(abi.encodeWithSelector(AC.AccessDenied.selector, agent));
        vm.prank(agent);
        revMgr.propFinalize(pid1);

        console2.logString('propFinalize; Fail, unknown proposal');
        vm.prank(vaultAddr);
        IRevMgr.PropRevFinalRc frc = revMgr.propFinalize(pid1 + 1);
        assertEq(uint(frc), uint(IRevMgr.PropRevFinalRc.NoProp));

        console2.logString('propFinalize; Fail, InstRevs and OwnSnaps length mismatch');
        vm.prank(vaultAddr);
        frc = revMgr.propFinalize(pid1);
        assertEq(uint(frc), uint(IRevMgr.PropRevFinalRc.DiffLens));

        // ----------
        // Add Owners for InstRev2 (name2, earnDate1)
        // ----------

        OI.OwnInfo memory own2a; OI.OwnInfo memory own2b; OI.OwnInfo memory own2c; OI.OwnInfo memory own2d;
        (own2a, own2b, own2c, own2d) = _makeOwners(2, unitRev2, totalQty2);
        console2.logString('propAddOwners; InstRev2 Add Owner A success');
        oiPage = new OI.OwnInfo[](1);
        oiPage[0] = own2a;
        total = 2;
        iAppend = 0;
        _propAddOwners(++seqNum, pid1, iAppend, total, name2, earnDate1, oiPage, IRevMgr.AddOwnRc.FullPage, 1, 1);

        console2.logString('propFinalize; Fail, OwnSnaps not fully uploaded');
        vm.prank(vaultAddr);
        frc = revMgr.propFinalize(pid1);
        assertEq(uint(frc), uint(IRevMgr.PropRevFinalRc.PartOwners));

        console2.logString('propAddOwners; InstRev2 Add Owner B success');
        oiPage[0] = own2b;
        iAppend = 1;
        _propAddOwners(++seqNum, pid1, iAppend, total, name2, earnDate1, oiPage, IRevMgr.AddOwnRc.AllPages, 1, 2);

        (len, uploadedAt, executedAt) = revMgr.getOwnInfosLen(pid1, name2, earnDate1);
        assertEq(len, total, 'len prop, OwnInfo: name2, earnDate1');
        assertEq(uploadedAt, block.timestamp, 'uploadedAt prop, OwnInfo: name2, earnDate1');
        assertEq(executedAt, 0, 'executedAt prop, OwnInfo: name2, earnDate1');

        console2.logString('propExecute; Fail, proposal not fully uploaded');
        vm.prank(vaultAddr);
        T.checkCall(vm, revMgr.propExecute(pid1), uint(IRevMgr.ExecRevRc.PartProp), 0, 0, 'propExecute');

        // ----------
        // Finalize proposal
        // ----------
        console2.logString('propFinalize; Success');
        assertEq(revMgr.getPropHdr(pid1).uploadedAt, 0, 'uploadedAt before');
        vm.prank(vaultAddr);
        frc = revMgr.propFinalize(pid1);
        assertEq(uint(frc), uint(IRevMgr.PropRevFinalRc.Ok));
        assertEq(revMgr.getPropHdr(pid1).uploadedAt, block.timestamp, 'uploadedAt after');

        console2.logString('propFinalize; Duplicate Success');
        vm.prank(vaultAddr);
        frc = revMgr.propFinalize(pid1);
        assertEq(uint(frc), uint(IRevMgr.PropRevFinalRc.Ok));

        // ----------
        // Execute proposal
        // ----------
        console2.logString('propExecute; Fail, caller access');
        vm.expectRevert(abi.encodeWithSelector(AC.AccessDenied.selector, agent));
        vm.prank(agent);
        revMgr.propExecute(pid1);

        console2.logString('propExecute; Fail, unknown proposal');
        vm.prank(vaultAddr);
        T.checkCall(vm, revMgr.propExecute(pid1 + 1), uint(IRevMgr.ExecRevRc.NoProp), 0, 0, 'propExecute');

        // `dropAddr1` is the source for 2 InstRev; reducing these funds allows the first transfer but not the 2nd
        console2.log('Trigger a protocol violation');
        assertEq(tokenUsdc.balanceOf(dropAddr1), totalRev1, 'dropAddr1 balance A before burn');
        uint partRev1 = totalRev1 / 4;
        uint partRev1Remain = partRev1 * 3;
        tokenUsdc.burn(dropAddr1, partRev1);  // A: Remove part of the deposit
        assertEq(tokenUsdc.balanceOf(dropAddr1), partRev1Remain, 'dropAddr1 balance A after burn');

        console2.log('propExecute; name1: Fail, low funds');
        vm.prank(vaultAddr);
        T.checkCall(vm, revMgr.propExecute(pid1), uint(IRevMgr.ExecRevRc.LowFunds), 0, 0, 'propExecute');

        console2.log('Resolve protocol violation');
        tokenUsdc.mint(dropAddr1, partRev1);  // A: Return the removed deposit
        assertEq(tokenUsdc.balanceOf(dropAddr1), totalRev1, 'dropAddr1 balance A after mint');

        console2.log('propExecute; name1: Success');
        vm.expectEmit();
        emit IInstRevMgr.RevenueXfer(pid1, name1, earnDate1, true, false, usdcAddr,
            dropAddr1, vaultAddr, totalRev1);
        vm.expectEmit();
        emit IRevMgr.RevenueAllocated(pid1, name1, earnDate1, 4, totalQty1, totalRev1, unitRev1);
        vm.expectEmit();
        emit IInstRevMgr.RevenueXfer(pid1, name2, earnDate1, true, false, usdcAddr,
            dropAddr2, vaultAddr, totalRev2);
        vm.expectEmit();
        emit IRevMgr.RevenueAllocated(pid1, name2, earnDate1, 2, totalQty2, totalRev2, unitRev2);
        vm.prank(vaultAddr);
        T.checkCall(vm, revMgr.propExecute(pid1), uint(IRevMgr.ExecRevRc.Done), 2, 6, 'propExecute');

        console2.log('Validate state in proposal after execution');
        _checkOwnInfos(pid1, name1, earnDate1, true, true, 1, 4, own1a, own1b, own1c, own1d);
        _checkOwnInfos(pid1, name2, earnDate1, true, true, 1, 2, own2a, own2b, ownE, ownE);

        console2.log('Validate executed state after execution');
        _checkOwnInfos(0, name1, earnDate1, true, true, 1, 4, own1a, own1b, own1c, own1d);
        _checkOwnInfos(0, name2, earnDate1, true, true, 1, 2, own2a, own2b, ownE, ownE);
    }

    function makeKeyString(string memory instName, uint earnDate) public pure returns (string memory) {
        return T.concat("name=", instName, ", earnDate=", Strings.toString(earnDate));
    }

    /// @dev Verify the InstRevs in either executed state or a proposal
    /// @param pid 0: Check executed state; >0 Check proposal
    function _checkOwnInfos(uint pid, string memory name, uint earnDate, bool ownUploaded, bool executed,
        uint instRevsLen, uint ownersLen,
        OI.OwnInfo memory ownA, OI.OwnInfo memory ownB, OI.OwnInfo memory ownC, OI.OwnInfo memory ownD
    ) public view {
        string memory key = makeKeyString(name, earnDate);
        console2.log('Validate InstRev and OwnInfos in state and proposal ', key, ', executed=', executed);

        string memory msg1 = T.concat('prop instRevsLen: ', key, ', executed=', (executed ? 'T' : 'F'));
        assertEq(instRevsLen, instRevMgr.getInstRevsLen(pid, name, earnDate), msg1);

        uint uploadTime = ownUploaded ? block.timestamp : 0;
        uint execTime = executed ? block.timestamp : 0;
        (uint len, uint uploadedAt, uint executedAt) = revMgr.getOwnInfosLen(pid, name, earnDate);
        assertEq(len, ownersLen, 'len prop, OwnInfo: name, earnDate');
        assertEq(uploadedAt, uploadTime, 'uploadedAt prop, OwnInfo: name, earnDate');
        assertEq(executedAt, execTime, 'executedAt prop, OwnInfo: name, earnDate');

        (uint revenue, uint qty) = revMgr.getOwnInfo(pid, name, earnDate, eidE);
        assertEq(revenue, 0, 'eidE revenue');
        assertEq(qty, 0, 'eidE qty');

        if (ownersLen >= 1) {
            (revenue, qty) = revMgr.getOwnInfo(pid, name, earnDate, ownA.eid);
            assertEq(revenue, ownA.revenue, 'eid1 revenue');
            assertEq(qty, uint(ownA.qty), 'eid1 qty');
        }

        if (ownersLen >= 2) {
            (revenue, qty) = revMgr.getOwnInfo(pid, name, earnDate, ownB.eid);
            assertEq(revenue, ownB.revenue, 'eid2 revenue');
            assertEq(qty, uint(ownB.qty), 'eid2 qty');
        }

        if (ownersLen >= 3) {
            (revenue, qty) = revMgr.getOwnInfo(pid, name, earnDate, ownC.eid);
            assertEq(revenue, ownC.revenue, 'eid3 revenue');
            assertEq(qty, uint(ownC.qty), 'eid3 qty');
        }

        if (ownersLen >= 4) {
            (revenue, qty) = revMgr.getOwnInfo(pid, name, earnDate, ownD.eid);
            assertEq(revenue, ownD.revenue, 'eid4 revenue');
            assertEq(qty, uint(ownD.qty), 'eid4 qty');
        }

        OI.OwnInfo[] memory ownInfos = revMgr.getOwnInfos(pid, name, earnDate, 0, 10);
        assertEq(ownInfos.length, ownersLen, 'ownInfos.length');

        if (ownersLen >= 1) {
            assertEq(ownInfos[0].revenue, ownA.revenue, 'ownInfos 0 revenue');
            assertEq(ownInfos[0].qty,  uint(ownA.qty), 'ownInfos 0 qty');
            assertEq(UUID.unwrap(ownInfos[0].eid), UUID.unwrap(ownA.eid), 'ownInfos 0 eid');
        }
        if (ownersLen >= 2) {
            assertEq(ownInfos[1].revenue, ownB.revenue, 'ownInfos 1 revenue');
            assertEq(ownInfos[1].qty,  uint(ownB.qty), 'ownInfos 1 qty');
            assertEq(UUID.unwrap(ownInfos[1].eid), UUID.unwrap(ownB.eid), 'ownInfos 1 eid');
        }
        if (ownersLen >= 3) {
            assertEq(ownInfos[2].revenue, ownC.revenue, 'ownInfos 2 revenue');
            assertEq(ownInfos[2].qty,  uint(ownC.qty), 'ownInfos 2 qty');
            assertEq(UUID.unwrap(ownInfos[2].eid), UUID.unwrap(ownC.eid), 'ownInfos 2 eid');
        }
        if (ownersLen >= 4) {
            assertEq(ownInfos[3].revenue, ownD.revenue, 'ownInfos 3 revenue');
            assertEq(ownInfos[3].qty,  uint(ownD.qty), 'ownInfos 3 qty');
            assertEq(UUID.unwrap(ownInfos[3].eid), UUID.unwrap(ownD.eid), 'ownInfos 3 eid');
        }
    }

    function test_RevMgr_prop_prune() public {
        uint pid1 = 1;
        bool correction = false;

        console2.logString('propCreate; Fail, Caller access');
        vm.expectRevert(abi.encodeWithSelector(AC.AccessDenied.selector, creator));
        vm.prank(creator);
        revMgr.propCreate(pid1, eid1, usdcAddr, correction);
        assertEq(revMgr.getPropHdr(pid1).pid, 0, 'getPropHdr');

        console2.logString('propCreate; Success');
        _createProp(pid1, eid1, correction);

        console2.logString('Deposit revenue for each instrument');
        tokenUsdc.mint(dropAddr1, totalRev1); // A: Deposit
        tokenUsdc.mint(dropAddr2, totalRev2); // B: Deposit

        console2.logString('Create InstRevs - required before owners');
        console2.logString('Create InstRev page 1');
        IR.InstRev[] memory page = new IR.InstRev[](1);
        _pageAddInstRev(page, 0, name1, earnDate1, unitRev1, totalQty1, dropAddr1); // A: Good inputs
        uint total = 2; // Total items to be uploaded (A,B)
        uint iAppend = 0;

        console2.logString('propAddInstRev; Add (A), full page success');
        _propAddInstRev(pid1, 0, total, page, IInstRevMgr.AddInstRc.FullPage, IInstRevMgr.AddInstLineRc.Ok, 1);

        // ----------
        // Remove InstRev from proposal
        // ----------

        console2.logString('pruneProp; Fail, Caller access');
        vm.expectRevert(abi.encodeWithSelector(AC.AccessDenied.selector, agent));
        vm.prank(agent);
        revMgr.pruneProp(pid1, name1, earnDate1);

        console2.logString('pruneProp; Fail, Bad pid');
        vm.prank(vaultAddr);
        IRevMgr.PruneRevRc rc = revMgr.pruneProp(pid1 + 1, name1, earnDate1);
        assertEq(uint(rc), uint(IRevMgr.PruneRevRc.NoProp), 'rc');

        console2.logString('pruneProp; Fail, Upload not complete');
        vm.prank(vaultAddr);
        rc = revMgr.pruneProp(pid1, name1, earnDate1);
        assertEq(uint(rc), uint(IRevMgr.PruneRevRc.PropStat), 'rc');

        console2.logString('Create InstRev page 2');
        page = new IR.InstRev[](1);
        _pageAddInstRev(page, 0, name2, earnDate1, unitRev2, totalQty2, dropAddr2); // B: Good inputs
        iAppend = 1;
        console2.logString('propAddInstRev; Add (B), full page success (all items uploaded)');
        _propAddInstRev(pid1, iAppend, total, page, IInstRevMgr.AddInstRc.AllPages, IInstRevMgr.AddInstLineRc.Ok, 1);
        assertEq(revMgr.getPropHdr(pid1).uploadedAt, 0, 'uploadedAt');

        console2.logString('pruneProp; Fail, uploads not complete (no owners)');
        vm.prank(vaultAddr);
        rc = revMgr.pruneProp(pid1, name1, earnDate1);
        assertEq(uint(rc), uint(IRevMgr.PruneRevRc.PropStat), 'rc');

        console2.logString('Add owners InstRev1');
        uint40 seqNum = 1;
        UUID reqId = _newUuid();
        OI.OwnInfo memory own1a; OI.OwnInfo memory own1b; OI.OwnInfo memory own1c; OI.OwnInfo memory own1d;
        (own1a, own1b, own1c, own1d) = _makeOwners(4, unitRev1, totalQty1);
        OI.OwnInfo[] memory oiPage = new OI.OwnInfo[](4);
        oiPage[0] = own1a;
        oiPage[1] = own1b;
        oiPage[2] = own1c;
        oiPage[3] = own1d;
        total = 4;
        iAppend = 0;
        _propAddOwners(seqNum, pid1, iAppend, total, name1, earnDate1, oiPage, IRevMgr.AddOwnRc.AllPages, 4, 4);
        ++seqNum;

        console2.logString('Add owners InstRev2');
        OI.OwnInfo memory own2a; OI.OwnInfo memory own2b; OI.OwnInfo memory own2c; OI.OwnInfo memory own2d;
        (own2a, own2b, own2c, own2d) = _makeOwners(2, unitRev2, totalQty2);
        oiPage = new OI.OwnInfo[](2);
        oiPage[0] = own2a;
        oiPage[1] = own2b;
        total = 2;
        _propAddOwners(seqNum, pid1, iAppend, total, name2, earnDate1, oiPage, IRevMgr.AddOwnRc.AllPages, 2, 2);
        ++seqNum;
        reqId = _newUuid();

        console2.logString('propFinalize; Success');
        vm.prank(vaultAddr);
        IRevMgr.PropRevFinalRc frc = revMgr.propFinalize(pid1);
        assertEq(uint(frc), uint(IRevMgr.PropRevFinalRc.Ok), 'frc');

        console2.logString('pruneProp; Fail, Unknown name');
        vm.prank(vaultAddr);
        rc = revMgr.pruneProp(pid1, name3, earnDate1);
        assertEq(uint(rc), uint(IRevMgr.PruneRevRc.NoInst), 'rc');

        console2.logString('pruneProp; Success Remove A');
        vm.expectEmit();
        emit IRevMgr.PropPruned(pid1, name1, earnDate1);
        vm.prank(vaultAddr);
        rc = revMgr.pruneProp(pid1, name1, earnDate1);
        assertEq(uint(rc), uint(IRevMgr.PruneRevRc.Done), 'rc');

        console2.logString('pruneProp; Fail, Remove A (already removed)');
        vm.prank(vaultAddr);
        rc = revMgr.pruneProp(pid1, name1, earnDate1);
        assertEq(uint(rc), uint(IRevMgr.PruneRevRc.LastInst), 'rc');

        console2.logString('pruneProp; Fail, Remove B (last item)');
        vm.prank(vaultAddr);
        rc = revMgr.pruneProp(pid1, name2, earnDate1);
        assertEq(uint(rc), uint(IRevMgr.PruneRevRc.LastInst), 'rc');

        console2.logString('Execute proposal, 1 inst w/ 2 owners');
        vm.prank(vaultAddr);
        T.checkCall(vm, revMgr.propExecute(pid1), uint(IRevMgr.ExecRevRc.Done), 1, 2, 'propExecute');

        console2.logString('pruneProp; Fail, Already executed');
        IRevMgr.PropHdr memory hdr = revMgr.getPropHdr(pid1);
        assertEq(hdr.pid, pid1, 'pid');
        assertNotEq(hdr.uploadedAt, 0, 'uploadedAt');
        assertNotEq(hdr.executedAt, 0, 'executedAt');
        vm.prank(vaultAddr);
        rc = revMgr.pruneProp(pid1, name2, earnDate1);
        assertEq(uint(rc), uint(IRevMgr.PruneRevRc.PropStat), 'rc');

        // ----------
        // Apply a correction to the previously executed proposal
        // ----------
        console2.logString('Preparing a correction proposal to reduce InstRev1 revenue by 1/2');
        uint pid2 = pid1 + 1;
        _createProp(pid2, eid1, true);

        console2.logString('Correction: Create InstRevs - required before owners');
        page = new IR.InstRev[](1);
        uint unitRev2b = unitRev2 / 2;
        uint totalRev2b = totalRev2 / 2;
        _pageAddInstRev(page, 0, name2, earnDate1, unitRev2b, totalQty2, dropAddr2); // A: Good inputs
        total = 1; // Total items to be uploaded (A)
        iAppend = 0;

        console2.logString('Correction: propAddInstRev; Add (A), all pages success');
        _propAddInstRev(pid2, 0, total, page, IInstRevMgr.AddInstRc.AllPages, IInstRevMgr.AddInstLineRc.Ok, 1);

        console2.logString('Correction: propAddInstRevAdj; Success');
        IInstRevMgr.AddInstRevAdjReq memory fixParam = IInstRevMgr.AddInstRevAdjReq({
            pid: pid2,
            iAppend: 0,
            total: 2,
            instName: name2,
            earnDate: earnDate1,
            requiredFunds: -int(unitRev2b),
            page: new IInstRevMgr.AllocFix[](2)
        });
        (own2a, own2b, own2c, own2d) = _makeOwners(2, unitRev2b, totalQty2);
        fixParam.page[0] = IInstRevMgr.AllocFix({ revenue: -int(own2a.revenue), ownerEid: own2a.eid,
            __gap: Util.gap5() });
        fixParam.page[1] = IInstRevMgr.AllocFix({ revenue: -int(own2b.revenue), ownerEid: own2b.eid,
            __gap: Util.gap5() });

        console2.logString('propAddInstRevAdj; Success');
        reqId = _newUuid();
        vm.prank(agent);
        instRevMgr.propAddInstRevAdj(++seqNum, reqId, fixParam);
        vm.prank(agent);
        ICallTracker.CallRes memory cr = instRevMgr.getCallResBySeqNum(seqNum);
        T.checkCall(vm, cr, uint(IInstRevMgr.AddInstRc.AllPages), 0, 2, 'propAddInstRevAdj');

        console2.logString('Correction: Add owners InstRev1');
        oiPage = new OI.OwnInfo[](2);
        oiPage[0] = own2a;
        oiPage[1] = own2b;
        total = 2;
        iAppend = 0;
        reqId = _newUuid();
        _propAddOwners(++seqNum, pid2, iAppend, total, name2, earnDate1, oiPage, IRevMgr.AddOwnRc.AllPages, 2, 2);

        console2.logString('Correction: propFinalize');
        vm.prank(vaultAddr);
        frc = revMgr.propFinalize(pid2);
        assertEq(uint(frc), uint(IRevMgr.PropRevFinalRc.Ok), 'frc');

        OI.OwnInfo memory ownE; // Empty
        console2.log('Correction: Validate state in proposal before execution');
        _checkOwnInfos(pid2, name2, earnDate1, true, false, 1, 2, own2a, own2b, ownE, ownE);

        console2.logString('Correction: Execute proposal');
        vm.prank(vaultAddr);
        T.checkCall(vm, revMgr.propExecute(pid2), uint(IRevMgr.ExecRevRc.Done), 1, 2, 'propExecute');

        console2.log('Correction: Validate executed state after execution');
        _checkOwnInfos(0, name2, earnDate1, true, true, 1, 2, own2a, own2b, ownE, ownE);
        assertEq(instRevMgr.getInstRevForInstDate(0, name2, earnDate1).totalRev, totalRev2b, 'B totalRev');
    }
}
