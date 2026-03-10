// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

// See LIB_PATHS
import '../lib/forge-std/src/Test.sol';

import '../lib/openzeppelin-contracts/contracts/proxy/Clones.sol';
import '../lib/openzeppelin-contracts/contracts/interfaces/IERC1155Receiver.sol';
import '../lib/openzeppelin-contracts/contracts/interfaces/IERC1967.sol';

import '../contract/v1_0/BoxMgr.sol';
import '../contract/v1_0/Erc20Test.sol';
import '../contract/v1_0/LogicDeployers.sol';
import '../contract/v1_0/ProxyDeployers.sol';
import '../contract/v1_0/IBoxMgr.sol';
import '../contract/v1_0/ICallTracker.sol';
import '../contract/v1_0/IContractUser.sol';
import '../contract/v1_0/IVersion.sol';
import '../contract/v1_0/LibraryAC.sol';
import '../contract/v1_0/LibraryBI.sol';
import '../contract/v1_0/LibraryCU.sol';
import '../contract/v1_0/LibraryTI.sol';
import '../contract/v1_0/Types.sol';

import './Const.sol';
import './LibraryTest.sol';
import './MockVault.sol';

contract BoxMgrLatest is BoxMgr {
    function getVersion() public pure override returns (uint) { return 999; }
}

contract BoxMgrTest is Test {
    IBoxMgr boxMgr;

    address creator = address(this);
    address vault = address(new MockVault());
    address agent = address(1);
    address spender1 = address(2);
    address spender2 = address(3);
    address other = address(4);

    string name1 = 'ABCD.1';
    string name2 = 'ABCD.2';
    string name3 = 'ABCD.3';
    string name4 = 'ABCD.4';

    bytes32 name1Hash = keccak256(bytes(name1));
    bytes32 name2Hash = keccak256(bytes(name2));
    bytes32 name3Hash = keccak256(bytes(name3));
    bytes32 name4Hash = keccak256(bytes(name4));

    Erc20Test tokenUsdc = new Erc20Test('USDC');
    Erc20Test tokenEurc = new Erc20Test('EURC');
    address usdcAddr = address(tokenUsdc);
    address eurcAddr = address(tokenEurc);

    TI.TokenInfo tokenInfoUsdc = _makeTokenInfo('USDC', usdcAddr, TI.TokenType.Erc20);
    TI.TokenInfo tokenInfoEurc = _makeTokenInfo('EURC', eurcAddr, TI.TokenType.Erc20);
    TI.TokenInfo tokenInfoEth = _makeTokenInfo('ETH', AddrZero, TI.TokenType.NativeCoin);

    uint versionA = 10;
    uint versionB = 99;
    uint verLatest = 0;

    uint40 constant NoSeqNum = 0;
    UUID constant NoReqId = UuidZero;

    function setUp() public {
        address mgrLogic = (new BoxMgrLogicDeployer()).deployLogic();
        assertNotEq(mgrLogic, AddrZero, 'mgrLogic');

        address mgrProxyAddr = (new ProxyDeployer()).deployProxy(mgrLogic, 'BoxMgr',
            abi.encodeWithSelector(IBoxMgr.initialize.selector, creator, NoReqId));
        assertNotEq(mgrProxyAddr, AddrZero, 'mgrProxyAddr');
        boxMgr = IBoxMgr(mgrProxyAddr);
        assertEq(10, boxMgr.getVersion(), 'getVersion');
        assertEq(boxMgr.getContract(CU.Creator), creator, 'getCreator');

        MockVault(vault).addMockRole(agent, AC.Role.Agent);
        boxMgr.setContract(NoSeqNum, NoReqId, CU.Vault, vault);
        assertEq(boxMgr.getContract(CU.Vault), vault);

        _labelAddresses();
    }

    uint _counter = 0;
    function _newUuid() private returns (UUID) {
        ++_counter;
        return UUID.wrap(bytes16(uint128(_counter)));
    }

    function _labelAddresses() private {
        vm.label(address(boxMgr), 'mgr');

        vm.label(creator, 'creator');
        vm.label(agent, 'agent');
        vm.label(spender1, 'spender1');
        vm.label(spender2, 'spender2');
        vm.label(other, 'other');

        vm.label(Util.ExplicitMint, 'ExplicitMintBurn');
        vm.label(Util.ContractHeld, 'ContractHeld');

        vm.label(usdcAddr, 'usdcAddr');
        vm.label(eurcAddr, 'eurcAddr');
    }

    function test_BoxMgr_initialize() public {
        // Verify initial state
        (uint version, address logic) = boxMgr.getLatestBoxLogic();
        assertEq(0, version);
        assertEq(AddrZero, logic);
        assertEq(0, boxMgr.getBoxLen(true));
        assertEq(0, boxMgr.getBoxLen(false));
        assertEq(0, boxMgr.getBoxes(0, 1, true).length);
        assertEq(0, boxMgr.getBoxes(0, 1, false).length);
        assertEq(6, tokenUsdc.decimals());

        // Attempt to initialize again; revert as not allowed
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        boxMgr.initialize(creator, _newUuid());
    }

    function test_BoxMgr_upgrade() public {
        // Deploy a mock upgraded logic
        address newLogic = address(new BoxMgrLatest());
        assertNotEq(newLogic, AddrZero);

        // Upgrade access denied
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(AC.AccessDenied.selector, other));
        UUPSUpgradeable(address(boxMgr)).upgradeToAndCall(address(newLogic), '');

        // Upgrade via UUPS with an empty initData
        vm.prank(creator);
        uint40 seqNum = boxMgr.getSeqNum(creator);
        UUID reqId = _newUuid();
        UUID reqIdStage = _newUuid();
        vm.prank(creator);
        boxMgr.preUpgrade(seqNum, reqId, reqIdStage);
        vm.expectEmit();
        emit IERC1967.Upgraded(newLogic);
        vm.prank(creator);
        UUPSUpgradeable(address(boxMgr)).upgradeToAndCall(address(newLogic), '');

        // Verify
        assertEq(boxMgr.getVersion(), 999);   // New behavior
        assertEq(boxMgr.getBoxLen(true), 0);  // Old behavior
    }

    function test_BoxMgr_addBoxLogic() public {
        address boxLogic1 = (new BoxLogicDeployer()).deployLogic();
        assertNotEq(boxLogic1, AddrZero);
        uint version1 = IBox(boxLogic1).getVersion();
        assertNotEq(version1, 0);

        console2.logString('Fail; Caller access');
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(AC.AccessDenied.selector, other));
        boxMgr.addBoxLogic(NoSeqNum, NoReqId, version1, boxLogic1);

        console2.logString('Fail; Logic address zero');
        vm.expectRevert(abi.encodeWithSelector(InvalidZeroAddr.selector));
        boxMgr.addBoxLogic(NoSeqNum, NoReqId, version1, AddrZero);

        console2.logString('Fail; Logic address not a box');
        vm.expectRevert(); // skip selector match since revert will have no data from an invalid box
        // vm.expectRevert(abi.encodeWithSelector(IBoxMgr.BoxLogicInvalid.selector));
        address invalidBox = address(1);
        boxMgr.addBoxLogic(NoSeqNum, NoReqId, version1, invalidBox);

        console2.logString('Fail; Logic version too low');
        vm.expectRevert(abi.encodeWithSelector(IBoxMgr.BoxLogicVersionInvalid.selector, 0, 0));
        boxMgr.addBoxLogic(NoSeqNum, NoReqId, 0, boxLogic1);

        uint version; address logic;
        uint40 seqNum = boxMgr.getSeqNum(creator);
        UUID reqId = _newUuid();
        for (uint i = 0; i < 2; ++i) {
            string memory suffix = i == 0 ? '(initial)' : '(duplicate, noop)';
            console2.logString(T.concat('Success; First version', suffix));
            if (i == 0) {
                vm.expectEmit();
                emit IBoxMgr.BoxLogicContractAdded(version1, boxLogic1);
            }
            boxMgr.addBoxLogic(seqNum, reqId, version1, boxLogic1);
            (version, logic) = boxMgr.getLatestBoxLogic();
            assertEq(version1, version, 'version');
            assertEq(boxLogic1, logic, 'logic');
            assertEq(seqNum + 1, boxMgr.getSeqNum(creator), 'seqNum');
        }
        ++seqNum;

        console2.logString('Fail; Logic version already exists');
        vm.expectRevert(abi.encodeWithSelector(IBoxMgr.BoxLogicVersionInvalid.selector, version1, version1));
        boxMgr.addBoxLogic(seqNum, _newUuid(), version1, boxLogic1);

        console2.logString('Success; Second version');
        address boxLogic2 = (new BoxLogicDeployer()).deployLogic();
        uint version2 = version1 + 1;
        reqId = _newUuid();
        vm.expectEmit();
        emit IBoxMgr.BoxLogicContractAdded(version2, boxLogic2);
        _emitReqAck(creator, seqNum, reqId, 1, 0, 0, false);
        boxMgr.addBoxLogic(seqNum, reqId, version2, boxLogic2);
        (version, logic) = boxMgr.getLatestBoxLogic();
        assertEq(version2, version, 'version');
        assertEq(boxLogic2, logic, 'logic');
        assertEq(seqNum + 1, boxMgr.getSeqNum(creator), 'seqNum');

        // Stored `CallRes` should match `addInstEarnDate` return value
        ICallTracker.CallRes memory cr = boxMgr.getCallResBySeqNum(seqNum);
        T.checkCall(vm, cr, 1, 0, 0, 'getCallRes');
        // assertEq(cr.seqNum, seqNum, 'seqNum');
    }

    function _emitReqAck(address creator_, uint40 seqNum, UUID reqId, uint16 rc, uint16 lrc, uint16 count,
        bool replay) private
    {
        ICallTracker.CallRes memory cr = ICallTracker.CallRes({
            reqId: reqId,
            rc: rc,
            lrc: lrc,
            count: count,
            blockNum: uint40(block.number),
            reserved: 0
        });
        vm.expectEmit();
        emit ICallTracker.ReqAck(reqId, creator_, seqNum, cr, replay);
    }

    function _initBoxLogic() private {
        console2.logString('Initialize BoxLogic');
        address boxLogic1 = (new BoxLogicDeployer()).deployLogic();
        assertNotEq(boxLogic1, AddrZero);
        uint version1 = IBox(boxLogic1).getVersion();
        assertNotEq(version1, 0);

        vm.expectEmit();
        emit IBoxMgr.BoxLogicContractAdded(version1, boxLogic1);
        boxMgr.addBoxLogic(NoSeqNum, NoReqId, version1, boxLogic1);
        (uint version, address logic) = boxMgr.getLatestBoxLogic();
        assertEq(version1, version);
        assertEq(boxLogic1, logic);
    }

    function _makeTokenInfo(string memory tokSym, address tokAddr, TI.TokenType tokType) private pure
        returns(TI.TokenInfo memory)
    {
        return TI.TokenInfo({ tokSym: tokSym, tokAddr: tokAddr, tokenId: 0, tokType: tokType });
    }

    function _checkApprovals(IBox.ApproveRc[] memory approvals, uint expectLen, IBox.ApproveRc expectRc) private pure {
        assertEq(approvals.length, expectLen, 'approvals.length');
        for (uint i = 0; i < expectLen; ++i) {
            assertEq(uint(approvals[i]), uint(expectRc), 'ApproveRc');
        }
    }

    function _initBoxProxy(string memory name, uint nonce) public returns(IBox boxProxy) {
        address owner = address(boxMgr);
        address logicAddr = address(new Box());
        uint version = 10;
        bytes32 salt = keccak256(abi.encodePacked(name, version, nonce));
        boxProxy = IBox(Clones.cloneDeterministic(logicAddr, salt)); // May revert with FailedDeployment
        IBox(boxProxy).initialize(owner, name);
    }

    function _cloneAddBoxReq(IBoxMgr.AddBoxReq memory req) private pure returns(IBoxMgr.AddBoxReq memory bp) {
        uint len = req.spenders.length;
        bp = IBoxMgr.AddBoxReq({
            name: req.name,
            version: req.version,
            active: req.active,
            nonce: req.nonce,
            deployedProxy: req.deployedProxy,
            deployedLogic: req.deployedLogic,
            spenders: new address[](len),
            tokens: req.tokens
        });
        for (uint i = 0; i < len; ++i) {
            bp.spenders[i] = req.spenders[i];
        }
    }

    function test_BoxMgr_addBox_misc() public {
        _initBoxLogic();
        uint nonce = block.number + 1; // fixed nonce for test but avoids conflict with other tests
        // uint nonceLatest = 0;
        uint nonceUsed;
        address[] memory spenders = new address[](2);
        spenders[0] = spender1;
        spenders[1] = spender2;
        TI.TokenInfo[] memory tokens = new TI.TokenInfo[](2);
        tokens[0] = tokenInfoUsdc;
        tokens[1] = tokenInfoEurc;
        (uint versionC, address boxLogic) = boxMgr.getLatestBoxLogic();
        assertEq(versionC, versionA, 'getLatestBoxLogic');
        assertNotEq(boxLogic, AddrZero, 'boxLogic');
        address boxProxy1;
        address boxProxy2;
        address boxProxy3;

        IBoxMgr.AddBoxReq memory boxParamOrig = IBoxMgr.AddBoxReq({
            name: name1,
            version: versionC,
            active: true,
            nonce: nonce,
            deployedProxy: AddrZero,
            deployedLogic: AddrZero,
            spenders: new address[](2),
            tokens: tokens
        });
        boxParamOrig.spenders[0] = spender1;
        boxParamOrig.spenders[1] = spender2;
        IBoxMgr.AddBoxReq memory boxParam;

        // ----------
        // Create boxes
        // ----------
        console2.logString('Create Fail; Caller access');
        boxParam = _cloneAddBoxReq(boxParamOrig);
        vm.expectRevert(abi.encodeWithSelector(AC.AccessDenied.selector, other));
        vm.prank(other);
        boxMgr.addBox(NoSeqNum, NoReqId, boxParam);

        console2.logString('Create Fail; Box name empty');
        boxParam = _cloneAddBoxReq(boxParamOrig);
        boxParam.name = '';
        vm.expectRevert(abi.encodeWithSelector(IBoxMgr.BoxNameEmpty.selector, other));
        boxMgr.addBox(NoSeqNum, NoReqId, boxParam);

        console2.logString('Create Fail; Box version unknown');
        boxParam = _cloneAddBoxReq(boxParamOrig);
        boxParam.version = versionB;
        vm.expectRevert(abi.encodeWithSelector(IBoxMgr.BoxLogicVersionNotFound.selector, versionB));
        boxMgr.addBox(NoSeqNum, NoReqId, boxParam);

        assertEq(address(this), boxMgr.getContract(CU.Creator));

        ICallTracker.CallRes memory cr;
        uint40 seqNum = boxMgr.getSeqNum(creator);
        UUID reqId = _newUuid();
        address boxAddr2;
        bytes32 salt;
        for (uint i = 0; i < 2; ++i) {
            string memory suffix = i == 0 ? '(initial)' : '(duplicate, noop)';
            console2.log(T.concat('Create Success; Add existing inactive box ', suffix));
            if (i == 0) {
                boxAddr2 = address(_initBoxProxy(name3, nonce));   // Existing box
                boxParam = _cloneAddBoxReq(boxParamOrig);
                boxParam.active = false;
                boxParam.version = versionA;
                boxParam.deployedProxy = boxAddr2;
                boxParam.deployedLogic = boxLogic;
                vm.expectEmit();
                emit IBoxMgr.BoxAdded(name1, boxAddr2, versionA, name1, false, false, boxLogic, salt);
                // vm.expectEmit();
                // emit IBox.ApprovalUpdated(name, tokSym, name, tokAddr, spender, oldAllowance, newAllowance);
                // _emitReqAck(creator, seqNum, reqId, 1, 0, 0, false);
            }
            boxMgr.addBox(seqNum, reqId, boxParam);
            cr = boxMgr.getCallResBySeqNum(seqNum);
            assertEq(1, cr.rc);
            assertEq(4, cr.lrc);
            assertEq(4, cr.count);
            boxProxy1 = boxAddr2;
            // assertEq(result.boxProxy, boxAddr2);
            // boxProxy1 = result.boxProxy;
            // _checkApprovals(result.approvals, 4, IBox.ApproveRc.Success);
            assertEq(boxMgr.getBoxLen(false), 1, 'inactive boxes');
            assertEq(boxMgr.getBoxLen(true), 0, 'active boxes');
            assertEq(seqNum + 1, boxMgr.getSeqNum(creator), 'seqNum');
        }
        ++seqNum;

        console2.logString('Ensure active box 1 does not yet exist');
        (boxProxy2, nonceUsed, salt) = boxMgr.getBoxProxyAddress(name2, versionA, nonce);
        assertEq(nonceUsed, nonce);
        bool exists; address boxProxy; uint nonceUsed2;
        (exists, boxProxy, nonceUsed2, salt) = boxMgr.getBoxProxyDeployInfo(name2, versionA, nonce);
        assertEq(exists, false, 'exists');
        assertEq(boxProxy, boxProxy2, 'boxProxy');
        assertEq(nonceUsed2, nonce, 'nonceUsed2');

        console2.logString('Create Fail; SeqNum gapped forward');
        boxParam = _cloneAddBoxReq(boxParamOrig);
        assertEq(seqNum, boxMgr.getSeqNum(creator), 'seqNum A');
        ++seqNum; // 1 more than expected
        reqId = _newUuid();
        boxParam.version = verLatest;
        boxParam.name = name3;
        vm.expectRevert(abi.encodeWithSelector(ICallTracker.SeqNumGap.selector, seqNum-1, seqNum, creator));
        boxMgr.addBox(seqNum, reqId, boxParam);

        console2.logString('Create Success; Add a new deploy of active box 1');
        --seqNum; // Revert to expected
        reqId = _newUuid();
        assertEq(boxMgr.getProbeAddrMax(), 10_000);
        assertTrue(boxProxy2.code.length == 0, 'expect addr unused');
        vm.expectEmit(true, true, true, true);
        emit IBoxMgr.BoxAdded(name2, boxProxy2, versionA, name2, true, true, boxLogic, salt);
        // vm.expectEmit();
        // emit IBox.ApprovalUpdated(name, tokSym, name, tokAddr, spender, oldAllowance, newAllowance);
        // _emitReqAck(creator, seqNum, reqId, 1, 0, 0, false);
        boxParam = _cloneAddBoxReq(boxParamOrig);
        boxParam.name = name2;
        boxMgr.addBox(seqNum, reqId, boxParam);
        cr = boxMgr.getCallResBySeqNum(seqNum);
        assertEq(1, cr.rc);
        assertEq(4, cr.lrc);
        assertEq(4, cr.count);
        boxProxy1 = boxAddr2;
        ++seqNum;
        reqId = _newUuid();
        // assertEq(result.boxProxy, boxProxy2, 'boxProxy');
        // _checkApprovals(result.approvals, 4, IBox.ApproveRc.Success);
        assertEq(boxMgr.getBoxLen(false), 1, 'inactive boxes');
        assertEq(boxMgr.getBoxLen(true), 1, 'active boxes');
        assertEq(seqNum, boxMgr.getSeqNum(creator), 'seqNum');

        console2.logString('Ensure active box 1 does exist');
        vm.prank(other);
        (exists, boxProxy, nonceUsed2, salt) = boxMgr.getBoxProxyDeployInfo(name2, versionA, nonce);
        assertEq(exists, true, 'exists');
        assertEq(boxProxy, boxProxy2, 'boxProxy');
        assertEq(nonceUsed2, nonce, 'nonceUsed2');

        console2.logString('Create Success; Add a new deploy of active box 2');
        vm.prank(other);
        nonce = 2;
        (boxProxy3, nonceUsed, salt) = boxMgr.getBoxProxyAddress(name3, versionA, nonce);
        assertEq(nonceUsed, nonce);
        vm.expectEmit();
        emit IBoxMgr.BoxAdded(name3, boxProxy3, versionA, name3, true, true, boxLogic, salt);
        // vm.expectEmit();
        // emit IBox.ApprovalUpdated(name, tokSym, name, tokAddr, spender, oldAllowance, newAllowance);
        // _emitReqAck(creator, seqNum, reqId, 1, 0, 0, false);
        boxParam = _cloneAddBoxReq(boxParamOrig);
        boxParam.name = name3;
        boxParam.nonce = nonce;
        boxParam.version = versionA;
        boxMgr.addBox(seqNum, reqId, boxParam);
        cr = boxMgr.getCallResBySeqNum(seqNum);
        assertEq(1, cr.rc);
        assertEq(4, cr.lrc);
        assertEq(4, cr.count);
        ++seqNum;
        // assertEq(result.boxProxy, boxProxy3, 'boxProxy');
        // _checkApprovals(result.approvals, 4, IBox.ApproveRc.Success);
        vm.prank(other);
        assertEq(boxMgr.getBoxLen(false), 1, 'inactive boxes');
        vm.prank(other);
        assertEq(boxMgr.getBoxLen(true), 2, 'active boxes');

        console2.logString('Get 1 inactive box');
        vm.prank(other);
        BI.BoxInfo[] memory boxes = boxMgr.getBoxes(0, 4, false);
        assertEq(boxes.length, 1);
        assertEq(boxes[0].name, name1, 'name');
        assertEq(boxes[0].version, versionA, 'version');
        assertEq(boxes[0].boxProxy, boxProxy1, 'boxProxy');

        console2.logString('Get inactive box by name1');
        vm.prank(other);
        (bool found, BI.BoxInfo memory box) = boxMgr.getBoxByName(name1, false);
        assertEq(found, true);
        assertEq(box.name, name1, 'name');
        assertEq(box.version, versionA, 'version');
        assertEq(box.boxProxy, boxProxy1, 'boxProxy');

        console2.logString('Get inactive box by address1');
        vm.prank(other);
        (found, box) = boxMgr.getBoxByAddr(boxProxy1, false);
        assertEq(found, true);
        assertEq(box.name, name1);

        console2.logString('Get 2 active boxes');
        vm.prank(other);
        boxes = boxMgr.getBoxes(0, 4, true);
        assertEq(boxes.length, 2);
        assertEq(boxes[0].name, name2, 'name');
        assertEq(boxes[0].version, versionA, 'version');
        assertEq(boxes[0].boxProxy, boxProxy2, 'boxProxy');
        assertEq(boxes[1].name, name3, 'name');
        assertEq(boxes[1].version, versionA, 'version');
        assertEq(boxes[1].boxProxy, boxProxy3, 'boxProxy');

        console2.logString('Get active box by name2');
        (found, box) = boxMgr.getBoxByName(name2, true);
        assertEq(found, true);
        assertEq(box.name, name2, 'name');
        assertEq(box.version, versionA, 'version');
        assertEq(box.boxProxy, boxProxy2, 'boxProxy');

        console2.logString('Get active box by address2');
        (found, box) = boxMgr.getBoxByAddr(boxProxy2, true);
        assertEq(found, true);
        assertEq(box.name, name2);

        console2.logString('Get active box by name3');
        (found, box) = boxMgr.getBoxByName(name3, true);
        assertEq(found, true);
        assertEq(box.name, name3, 'name');
        assertEq(box.version, versionA, 'version');
        assertEq(box.boxProxy, boxProxy3, 'boxProxy');

        console2.logString('Get active box by address3');
        (found, box) = boxMgr.getBoxByAddr(boxProxy3, true);
        assertEq(found, true);
        assertEq(box.name, name3);

        console2.logString('Get box by unknown name');
        (found, box) = boxMgr.getBoxByName('unknown', true);
        assertEq(found, false);
        assertEq(box.name, '');
        assertEq(box.version, 0);
        assertEq(box.boxProxy, AddrZero);

        console2.logString('Get box by unknown address');
        (found, box) = boxMgr.getBoxByAddr(address(1), true);
        assertEq(found, false);
        assertEq(box.name, '');

        console2.logString('Create Fail; Box name1 exists in inactive');
        reqId = _newUuid();
        boxParam = _cloneAddBoxReq(boxParamOrig);
        boxParam.active = false;
        boxParam.version = verLatest;
        boxParam.name = name1;
        vm.expectRevert(abi.encodeWithSelector(IBoxMgr.BoxNameInUse.selector, name1, boxProxy1, false));
        boxMgr.addBox(seqNum, reqId, boxParam);

        console2.logString('Create Fail; Box name2 exists in active');
        reqId = _newUuid();
        boxParam = _cloneAddBoxReq(boxParamOrig);
        boxParam.version = verLatest;
        boxParam.name = name2;
        vm.expectRevert(abi.encodeWithSelector(IBoxMgr.BoxNameInUse.selector, name2, boxProxy2, true));
        boxMgr.addBox(seqNum, reqId, boxParam);

        console2.logString('Create Fail; Box name3 exists in active');
        reqId = _newUuid();
        boxParam = _cloneAddBoxReq(boxParamOrig);
        boxParam.version = verLatest;
        boxParam.name = name3;
        vm.expectRevert(abi.encodeWithSelector(IBoxMgr.BoxNameInUse.selector, name3, boxProxy3, true));
        boxMgr.addBox(seqNum, reqId, boxParam);

        // ----------
        // Rotate box
        // ----------
        console2.logString('Rotate Fail; Caller access');
        vm.expectRevert(abi.encodeWithSelector(AC.AccessDenied.selector, creator));
        boxMgr.rotateBox(NoSeqNum, NoReqId, name3, false);

        console2.logString('Rotate Fail; Empty box name');
        vm.prank(agent);
        boxMgr.rotateBox(NoSeqNum, NoReqId, '', true);

        console2.logString('Rotate Fail; Unknown box name');
        vm.prank(agent);
        boxMgr.rotateBox(NoSeqNum, NoReqId, 'unknown', true);
        vm.prank(agent);
        boxMgr.rotateBox(NoSeqNum, NoReqId, 'unknown', false);

        vm.prank(agent);
        seqNum = boxMgr.getSeqNum(agent);
        reqId = _newUuid();

        for (uint i = 0; i < 2; ++i) {
            string memory suffix = i == 0 ? '(initial)' : '(duplicate, noop)';
            console2.log(T.concat('Rotate Success; Active becomes inactive ', suffix));
            if (i == 0) {
                assertEq(boxMgr.getBoxLen(false), 1, 'inactive boxes');
                assertEq(boxMgr.getBoxLen(true), 2, 'active boxes');
                vm.expectEmit();
                emit IBoxMgr.BoxActivation(name3, boxProxy3, name3, false);
            }
            vm.prank(agent);
            boxMgr.rotateBox(seqNum, reqId, name3, false);
            assertEq(boxMgr.getBoxLen(false), 2, 'inactive boxes');
            assertEq(boxMgr.getBoxLen(true), 1, 'active boxes');
            vm.prank(agent);
            assertEq(seqNum + 1, boxMgr.getSeqNum(agent), 'seqNum');
        }
        ++seqNum;
        reqId = _newUuid();

        // ----------
        // Rename box
        // ----------
        console2.logString('Rename Fail; Caller access');
        vm.expectRevert(abi.encodeWithSelector(AC.AccessDenied.selector, creator));
        boxMgr.renameBox(NoSeqNum, NoReqId, name3, name4);

        for (uint i = 0; i < 2; ++i) {
            string memory suffix = i == 0 ? '(initial)' : '(duplicate, noop)';
            console2.log(T.concat('Rename Success; ', suffix));
            if (i == 0) {
                assertEq(boxMgr.getBoxLen(false), 2, 'inactive boxes');
                assertEq(boxMgr.getBoxLen(true), 1, 'active boxes');
                vm.expectEmit();
                emit IBoxMgr.BoxRenamed(name3, name4, name3, name4, false);
            }
            vm.prank(agent);
            boxMgr.renameBox(seqNum, reqId, name3, name4);
            assertEq(boxMgr.getBoxLen(false), 2, 'inactive boxes');
            assertEq(boxMgr.getBoxLen(true), 1, 'active boxes');
            vm.prank(agent);
            assertEq(seqNum + 1, boxMgr.getSeqNum(agent), 'seqNum');
        }
        ++seqNum;

        console2.logString('Get renamed box by name4');
        (found, box) = boxMgr.getBoxByName(name4, false);
        assertEq(found, true);
        assertEq(box.name, name4);
        assertEq(box.version, versionA);
        assertEq(box.boxProxy, boxProxy3);

        console2.logString('Get renamed box by address3');
        (found, box) = boxMgr.getBoxByAddr(boxProxy3, false);
        assertEq(found, true);
        assertEq(box.name, name4);

        // ----------
        // Approve box
        // ----------
        uint qty1 = 3;
        reqId = _newUuid();
        console2.logString('Approve Fail; Caller access');
        vm.expectRevert(abi.encodeWithSelector(AC.AccessDenied.selector, other));
        vm.prank(other);
        TI.TokenInfo memory tokenInfo = tokenInfoUsdc;
        boxMgr.approve(seqNum, reqId, tokenInfo, name2, spender1, qty1);

        console2.logString('Approve Fail; Spender access');
        reqId = _newUuid();
        boxMgr.approve(++seqNum, reqId, tokenInfo, 'unknown', spender1, qty1);
        cr = boxMgr.getCallResBySeqNum(seqNum);
        assertEq(uint(IBox.ApproveRc.NotAuth), uint(cr.rc));

        console2.logString('Approve Fail; Empty box name');
        reqId = _newUuid();
        boxMgr.approve(++seqNum, reqId, tokenInfo, '', vault, qty1);
        cr = boxMgr.getCallResBySeqNum(seqNum);
        assertEq(uint(IBox.ApproveRc.NoBox), uint(cr.rc));

        console2.logString('Approve Fail; Unknown box name');
        reqId = _newUuid();
        boxMgr.approve(++seqNum, reqId, tokenInfo, 'unknown', vault, qty1);
        cr = boxMgr.getCallResBySeqNum(seqNum);
        assertEq(uint(IBox.ApproveRc.NoBox), uint(cr.rc));

        console2.logString('Approve Success');
        reqId = _newUuid();
        boxMgr.approve(++seqNum, reqId, tokenInfo, name2, vault, qty1);
        cr = boxMgr.getCallResBySeqNum(seqNum);
        assertEq(uint(IBox.ApproveRc.Success), uint(cr.rc));
    }
}
