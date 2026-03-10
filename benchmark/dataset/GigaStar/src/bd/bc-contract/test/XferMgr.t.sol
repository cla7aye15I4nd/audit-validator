// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

// See LIB_PATHS
import '../lib/forge-std/src/Test.sol';

import '../lib/openzeppelin-contracts/contracts/interfaces/IERC1155Receiver.sol';
import '../lib/openzeppelin-contracts/contracts/interfaces/IERC1967.sol';
import '../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol';
import '../lib/openzeppelin-contracts/contracts/proxy/Clones.sol';

import '../contract/v1_0/Erc20Test.sol';
import '../contract/v1_0/ICallTracker.sol';
import '../contract/v1_0/IContractUser.sol';
import '../contract/v1_0/IVersion.sol';
import '../contract/v1_0/IXferMgr.sol';
import '../contract/v1_0/LibraryAC.sol';
import '../contract/v1_0/LibraryBI.sol';
import '../contract/v1_0/LibraryCU.sol';
import '../contract/v1_0/LibraryIR.sol';
import '../contract/v1_0/LibraryOI.sol';
import '../contract/v1_0/LibraryString.sol';
import '../contract/v1_0/LibraryTI.sol';
import '../contract/v1_0/LogicDeployers.sol';
import '../contract/v1_0/ProxyDeployers.sol';
import '../contract/v1_0/Types.sol';
import '../contract/v1_0/XferMgr.sol';

import './Const.sol';
import './LibraryTest.sol';

contract XferMgrLatest is XferMgr {
    function getVersion() public pure override returns (uint) { return 999; }
}

// Exposes details for testing
contract XferMgrSpy is XferMgr {
    uint40 constant NoSeqNum = 0;
    UUID constant NoReqId = UuidZero;

    function resetPropStatus(uint pid) external {
        console2.log('Before reset 1');
        PropHdr storage ph = _proposals[pid].hdr;
        console2.log('Before reset 2:', ph.iXfer, ph.executedAt);
        ph.iXfer = 0;
        ph.executedAt = 0;
    }

    function xferFieldsCheck(Xfer calldata x, bool isNative, bool allowMintBurn) public pure returns(AddXferLrc lrc) {
        return _xferFieldsCheck(x, isNative, allowMintBurn);
    }
}

contract XferMgrSpyLogicDeployer is LogicDeployer {
    constructor() { _logic = address(new XferMgrSpy()); emit LogicDeployed(_logic); }
}

contract XferMgrSpyProxyDeployer {
    uint40 constant NoSeqNum = 0;
    UUID constant NoReqId = UuidZero;

    function createProxy(address logicAddr, address creator, UUID reqId) public returns(XferMgrSpy) {
        address proxyAddr = (new ProxyDeployer()).deployProxy(logicAddr, 'XferMgrSpy',
            abi.encodeWithSelector(IXferMgr.initialize.selector, creator, reqId));
        return XferMgrSpy(proxyAddr);
    }
}

contract XferMgrTest is Test {
    address creator = address(this);
    address admin = address(20);
    address agent = address(21);
    address voter1 = address(22);
    address voter2 = address(23);
    address voter3 = address(24);
    address other = address(6);
    address zeroAddr = AddrZero;

    string constant url = 'https://domain.io/dir1/{id}.json';

    XferMgrSpy xferMgr;
    ICrt crt;
    IRevMgr revMgr;
    IInstRevMgr instRevMgr;
    IEarnDateMgr earnDateMgr;
    IBalanceMgr balanceMgr;
    IBoxMgr boxMgr;
    IVault vault;

    address xferMgrAddr;
    address crtAddr;
    address revMgrAddr;
    address instRevMgrAddr;
    address earnDateMgrAddr;
    address balanceMgrAddr;
    address boxMgrAddr;
    address vaultAddr;

    address owner1Addr = address(0xA1);
    address owner2Addr = address(0xA2);
    address owner3Addr = address(0xA3);
    address owner4Addr = address(0xA4);
    address owner5Addr = address(0xA5);

    string nameE = '';
    string name1 = 'ABCD.1';
    string name2 = 'ABCD.2';
    string name3 = 'ABCD.3';
    string name4 = 'ABCD.4';
    string name5 = 'ABCD.5';

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

    address dropAddrE = zeroAddr;
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

    uint pid1 = 1;      // TOO_DEEP: Hoisted to resolve stack too deep
    uint40 seqNum = 0;  // See TOO_DEEP
    UUID reqId = UUID.wrap(0x00000000000000000000000000000001); // See TOO_DEEP

    function setUp() public {
        // Set proxies
        xferMgr = (new XferMgrSpyProxyDeployer()).
            createProxy((new XferMgrSpyLogicDeployer()).deployLogic(), creator, NoReqId);

        crt = (new CrtProxyDeployer()).
            createProxy((new CrtLogicDeployer()).deployLogic(), creator, NoReqId, url);

        revMgr = (new RevMgrProxyDeployer()).
            createProxy((new RevMgrLogicDeployer()).deployLogic(), creator, NoReqId);

        instRevMgr = (new InstRevMgrProxyDeployer()).
            createProxy((new InstRevMgrLogicDeployer()).deployLogic(), creator, NoReqId);

        earnDateMgr = (new EarnDateMgrProxyDeployer()).
            createProxy((new EarnDateMgrLogicDeployer()).deployLogic(), creator, NoReqId);

        balanceMgr = (new BalanceMgrProxyDeployer()).
            createProxy((new BalanceMgrLogicDeployer()).deployLogic(), creator, NoReqId);

        boxMgr = (new BoxMgrProxyDeployer()).
            createProxy((new BoxMgrLogicDeployer()).deployLogic(), creator, NoReqId);

        vault = (new VaultProxyDeployer()).
            createProxy((new VaultLogicDeployer()).deployLogic(), creator, NoReqId, 3, _createRoles());

        // Set addresses
        xferMgrAddr = address(xferMgr);
        crtAddr = address(crt);
        revMgrAddr = address(revMgr);
        instRevMgrAddr = address(instRevMgr);
        earnDateMgrAddr = address(earnDateMgr);
        balanceMgrAddr = address(balanceMgr);
        boxMgrAddr = address(boxMgr);
        vaultAddr = address(vault);

        _setContracts(balanceMgr);
        _setContracts(boxMgr);
        _setContracts(crt);
        _setContracts(earnDateMgr);
        _setContracts(instRevMgr);
        _setContracts(revMgr);
        _setContracts(xferMgr);
        _setContracts(vault);

        _addBoxes();

        tokenUsdc.setApproval(dropAddr1, instRevMgrAddr, MAX_ALLOWANCE);
        tokenUsdc.setApproval(dropAddr2, instRevMgrAddr, MAX_ALLOWANCE);
        tokenUsdc.setApproval(dropAddr3, instRevMgrAddr, MAX_ALLOWANCE);
        vault.approveMgr(NoSeqNum, NoReqId, usdcAddr, CU.XferMgr); // Allow transfers from vault

        _labelAddresses();
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
        user.setContract(NoSeqNum, NoReqId, CU.XferMgr, xferMgrAddr);
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
        vm.label(crtAddr, 'crt');
        vm.label(earnDateMgrAddr, 'earnDateMgr');
        vm.label(instRevMgrAddr, 'instRevMgr');
        vm.label(revMgrAddr, 'revMgr');
        vm.label(xferMgrAddr, 'xferMgr');
        vm.label(vaultAddr, 'vault');

        vm.label(dropAddr1, 'dropAddr1');
        vm.label(dropAddr2, 'dropAddr2');
        vm.label(dropAddr3, 'dropAddr3');

        vm.label(owner1Addr, 'owner1');
        vm.label(owner2Addr, 'owner2');
        vm.label(owner3Addr, 'owner3');
        vm.label(owner4Addr, 'owner4');
        vm.label(owner5Addr, 'owner5');

        vm.label(Util.ExplicitMint, 'ExplicitMintBurn');
        vm.label(Util.ContractHeld, 'ContractHeld');

        vm.label(usdcAddr, 'usdcAddr');
        vm.label(eurcAddr, 'eurcAddr');
    }

    function _createRoles() public view returns(AC.RoleRequest[] memory rr) {
        // Create roles
        rr = new AC.RoleRequest[](5);
        rr[0] = AC.RoleRequest({ account: admin,  add: true, role: AC.Role.Admin, __gap: Util.gap5() });
        rr[1] = AC.RoleRequest({ account: agent,  add: true, role: AC.Role.Agent, __gap: Util.gap5() });
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
        TI.TokenInfo[] memory tokens = new TI.TokenInfo[](2);
        tokens[0] = tokenInfoUsdc;
        tokens[1] = tokenInfoEurc;
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

    function test_XferMgr_initialize() public {
        // Attempt to initialize again; revert as not allowed
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        xferMgr.initialize(creator, NoReqId);
    }

    function test_XferMgr_upgrade() public {
        // Deploy a mock upgraded logic
        address newLogic = address(new XferMgrLatest());
        assertNotEq(newLogic, zeroAddr);

        // Upgrade access denied
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(AC.AccessDenied.selector, other));
        UUPSUpgradeable(xferMgr).upgradeToAndCall(address(newLogic), '');

        // Upgrade via UUPS with an empty initData
        seqNum = xferMgr.getSeqNum(creator);
        reqId = _newUuid();
        UUID reqIdStage = _newUuid();
        vm.prank(creator);
        xferMgr.preUpgrade(seqNum, reqId, reqIdStage);
        vm.expectEmit();
        emit IERC1967.Upgraded(newLogic);
        vm.prank(creator);
        UUPSUpgradeable(xferMgr).upgradeToAndCall(address(newLogic), '');

        // Verify
        assertEq(xferMgr.getVersion(), 999);        // New behavior
        assertEq(xferMgr.getPropHdr(0).pid, 0); // Old behavior
    }

    function test_XferMgr_empty_state() public {
        vm.startPrank(other);
        assertEq(xferMgr.getPropHdr(0).pid, 0, 'getPropHdr');
        assertFalse(xferMgr.inTokenAdminList(usdcAddr));
        assertEq(xferMgr.getXferExecIndex(1), 0);
        assertEq(xferMgr.getXfersLen(1), 0);
        assertEq(xferMgr.getXfers(1, 0, 10).length, 0);
    }

    function _setEthBalance(address addr, uint qty) private {
        vm.deal(addr, qty);
    }

    function _addEthBalance(address addr, uint qty) private {
        vm.deal(addr, addr.balance + qty);
    }

    function _subEthBalance(address addr, uint qty) private {
        vm.deal(addr, addr.balance - qty);
    }

    function test_XferMgr_getTokenBalances() public {
        vm.startPrank(other);
        address[] memory accounts = new address[](3);
        accounts[0] = dropAddr1;
        accounts[1] = dropAddr2;
        accounts[2] = dropAddr3;

        console2.logString('Deposit USDC for each instrument');
        tokenUsdc.mint(dropAddr1, totalRev1); // Deposit USDC
        tokenUsdc.mint(dropAddr2, totalRev2); // Deposit USDC
        assertEq(tokenUsdc.balanceOf(dropAddr1), totalRev1, 'dropAddr1 balance');
        assertEq(tokenUsdc.balanceOf(dropAddr2), totalRev2, 'dropAddr2 balance');

        console2.logString('getTokenBalances USDC');
        uint[] memory balance = xferMgr.getTokenBalances(usdcAddr, TI.TokenType.Erc20, accounts);
        assertEq(balance[0], totalRev1, 'dropAddr1 balance');
        assertEq(balance[1], totalRev2, 'dropAddr2 balance');
        assertEq(balance[2], 0, 'dropAddr3 balance');

        console2.logString('getTokenBalances EURC');
        balance = xferMgr.getTokenBalances(eurcAddr, TI.TokenType.Erc20, accounts);
        assertEq(balance[0], 0, 'dropAddr1 balance');
        assertEq(balance[1], 0, 'dropAddr2 balance');
        assertEq(balance[2], 0, 'dropAddr3 balance');

        console2.logString('Deposit ETH for each instrument');
        _setEthBalance(dropAddr1, 6);
        _setEthBalance(dropAddr2, 7);

        console2.logString('getTokenBalances ETH');
        balance = xferMgr.getTokenBalances(usdcAddr, TI.TokenType.NativeCoin, accounts);
        assertEq(balance[0], 6, 'dropAddr1 balance');
        assertEq(balance[1], 7, 'dropAddr2 balance');
        assertEq(balance[2], 0, 'dropAddr3 balance');

        console2.logString('getTokenBalances ERC-1155');
        balance = xferMgr.getTokenBalances(address(1), TI.TokenType.Erc1155, accounts);
        assertEq(balance[0], 0, 'dropAddr1 balance');
        assertEq(balance[1], 0, 'dropAddr2 balance');
        assertEq(balance[2], 0, 'dropAddr3 balance');
    }

    function _checkUuid(UUID actual, UUID expect, string memory description) private pure {
        assertEq(UUID.unwrap(actual), UUID.unwrap(expect), description);
    }

    function _createProp(uint pid, UUID reqId_, TI.TokenInfo memory ti, bool isRevDist) private {
        assertEq(xferMgr.getPropHdr(pid).pid, 0, 'xferMgr pid before create');
        vm.prank(vaultAddr);
        xferMgr.propCreate(pid, reqId_, ti, isRevDist);
        IXferMgr.PropHdr memory hdr = xferMgr.getPropHdr(pid);
        assertEq(hdr.pid, pid, 'pid');
        _checkUuid(hdr.eid, reqId_, 'reqId');
        assertEq(hdr.iXfer, 0, 'iXfer');
        assertEq(hdr.uploadedAt, 0, 'uploadedAt');
        assertEq(hdr.executedAt, 0, 'executedAt');
        assertEq(hdr.isRevDist, isRevDist, 'isRevDist');
        assertEq(hdr.ti.tokAddr, ti.tokAddr, 'tokAddr');
        assertEq(hdr.ti.tokSym, ti.tokSym, 'tokSym');
        assertEq(uint(hdr.ti.tokType), uint(ti.tokType), 'tokType');
        assertEq(hdr.ti.tokenId, ti.tokenId, 'tokenId');
    }

    function test_XferMgr_prop_create_basic() public {
        uint pid = 1;
        reqId = eid1;
        TI.TokenInfo memory tokenInfo = tokenInfoUsdc;
        bool isRevDist = true;

        console2.logString('propCreate; Fail, Caller access');
        vm.expectRevert(abi.encodeWithSelector(AC.AccessDenied.selector, creator));
        vm.prank(creator);
        xferMgr.propCreate(pid, reqId, tokenInfo, isRevDist);
        assertEq(xferMgr.getPropHdr(pid).pid, 0, 'getPropHdr');

        console2.logString('propCreate; Success');
        vm.prank(vaultAddr);
        _createProp(pid, reqId, tokenInfo, isRevDist);
    }

    /// @dev Create an array of transfers with various from/to permutations
    function _makeCrtXfersA(uint qtyPart) private returns(IXferMgr.Xfer[] memory xfers) {
        xfers = new IXferMgr.Xfer[](2);
        xfers[0] = IXferMgr.Xfer({ // Mint to owner1
            eid: _newUuid(),
            from: Util.ExplicitMint,
            to: owner1Addr,
            qty: qtyPart * 1,
            fromEid: eid1,
            toEid: eidE,
            tokenId: 1,
            status: IXferMgr.XferStatus.Pending
        });
        xfers[1] = IXferMgr.Xfer({ // Move from custody to owner
            eid: _newUuid(),
            from: Util.ContractHeld,
            to: owner2Addr,
            qty: qtyPart * 2,
            fromEid: eid2,
            toEid: eidE,
            tokenId: 2,
            status: IXferMgr.XferStatus.Pending
        });
    }

    function _makeCrtXfersB(uint qtyPart) private returns(IXferMgr.Xfer[] memory xfers) {
        xfers = new IXferMgr.Xfer[](3);
        xfers[0] = IXferMgr.Xfer({ // Move from owner1 to owner3
            eid: _newUuid(),
            from: owner1Addr,
            to: owner3Addr,
            qty: qtyPart * 3,
            fromEid: eid1,
            toEid: eidE,
            tokenId: 3,
            status: IXferMgr.XferStatus.Pending
        });
        xfers[1] = IXferMgr.Xfer({ // Burn from owner4
            eid: _newUuid(),
            from: owner4Addr,
            to: Util.ExplicitBurn,
            qty: qtyPart * 4,
            fromEid: eid4,
            toEid: eidE,
            tokenId: 4,
            status: IXferMgr.XferStatus.Pending
        });
        xfers[2] = IXferMgr.Xfer({ // Move from owner5 to custody
            eid: _newUuid(),
            from: owner5Addr,
            to: Util.ContractHeld,
            qty: qtyPart * 10,
            fromEid: eid4,
            toEid: eidE,
            tokenId: 5,
            status: IXferMgr.XferStatus.Pending
        });
    }

    function _getQtySum(IXferMgr.Xfer[] memory xfers) private pure returns(uint sum) {
        for (uint i = 0; i < xfers.length; ++i) {
            sum += xfers[i].qty;
        }
    }

    function _logAddMsg(uint qty, string memory dest, address to) private pure {
        // console2.log(string(abi.encodePacked('Adding ', vm.toString(qty), dest)), to);
        // Multiple steps to reduce IR pipeline pressure
        string memory p1 = T.concat('Adding ', vm.toString(qty), dest);
        bytes memory p2 = abi.encodePacked(p1, to);
        console2.log(string(p2));
    }

    function _increaseOwnerBalances(bool isCcy, TI.TokenInfo memory ti,
        IXferMgr.Xfer[] memory xfers) private
    {
        IXferMgr.Xfer memory t;
        for (uint i = 0; i < xfers.length; ++i) {
            t = xfers[i];
            if (t.from == Util.ExplicitMint) continue;

            // Deposit qty to fund a later transfer
            if (ti.tokAddr == crtAddr) {
                address to = t.from; // Crt will translate sentinel address to native
                _logAddMsg(t.qty, ' CRT to ', to);
                crt.safeTransferFrom(Util.ExplicitMint, to, t.tokenId, t.qty, '');
                assertGe(crt.balanceOf(to, t.tokenId), t.qty, 'crt balanceOf');
            } else {
                address to = Util.resolveAddr(t.from, vaultAddr); // Translate sentinel to native
                if (ti.tokAddr == usdcAddr) {
                    _logAddMsg(t.qty, ' USDC to ', to);
                    tokenUsdc.mint(to, t.qty);
                    assertGe(tokenUsdc.balanceOf(to), t.qty, 'usdc balanceOf');
                } else if (ti.tokAddr == eurcAddr) {
                    _logAddMsg(t.qty, ' EURC to ', to);
                    tokenEurc.mint(to, t.qty);
                    assertGe(tokenEurc.balanceOf(to), t.qty, 'eurc balanceOf');
                } else if (ti.tokAddr == zeroAddr) {
                    _logAddMsg(t.qty, ' ETH to ', to);
                    _addEthBalance(to, t.qty);
                } else assertFalse(true, 'Cannot mint unknown token');
            }

            if (isCcy) {
                // Increase the owner's unclaimed balance
                vm.prank(revMgrAddr);
                balanceMgr.updateBalance(ti.tokAddr, t.fromEid, int(t.qty), true);
            }
        }
    }

    function _checkXfer(bool resolve,
        IXferMgr.Xfer memory actual, IXferMgr.Xfer memory expect, uint i) private view
    {
        string memory suffix = string.concat(', i=', vm.toString(i));
        address from = resolve ? Util.resolveAddr(expect.from, vaultAddr) : expect.from;
        address to = resolve ? Util.resolveAddr(expect.to, vaultAddr) : expect.to;
        assertEq(actual.from, from, string.concat('xfer.from', suffix));
        assertEq(actual.to, to, string.concat('xfer.to', suffix));
        assertEq(actual.qty, expect.qty, string.concat('xfer.qty', suffix));
        _checkUuid(actual.fromEid, expect.fromEid, string.concat('xfer.fromEid', suffix));
        assertEq(actual.tokenId, expect.tokenId, string.concat('xfer.tokenId', suffix));
        assertEq(uint(actual.status), uint(expect.status), string.concat('xfer.status', suffix));
    }

    function _checkXfers(bool resolve,
        IXferMgr.Xfer[] memory actual, IXferMgr.Xfer[] memory expect, string memory what) private view
    {
        assertEq(actual.length, expect.length, string.concat('checkXfers len', what));
        for (uint i = 0; i < actual.length; ++i) {
            _checkXfer(resolve, actual[i], expect[i], i);
        }
    }

    function _expectXfersEmit(IXferMgr.Xfer[] memory xfers) private {
        for (uint i = 0; i < xfers.length; ++i) {
            IXferMgr.Xfer memory t = xfers[i];

            // Translate addresses from sentinel to native
            address from2 = Util.resolveAddr(t.from, vaultAddr);
            address to2 = Util.resolveAddr(t.to, vaultAddr);

            vm.expectEmit();
            emit IERC1155.TransferSingle(xferMgrAddr, from2, to2, t.tokenId, t.qty);
        }
    }

    function _cloneXfer(IXferMgr.Xfer memory x) private pure returns(IXferMgr.Xfer memory) {
        return IXferMgr.Xfer({
            eid: x.eid,
            from: x.from,
            to: x.to,
            qty: x.qty,
            fromEid: x.fromEid,
            toEid: eidE,
            tokenId: x.tokenId,
            status: x.status
        });
    }

    function test_XferMgr_xferFieldsCheck() public {
        IXferMgr.Xfer memory xferOrig = IXferMgr.Xfer({
            eid: _newUuid(),
            from: owner1Addr,
            to: owner2Addr,
            qty: 1,
            fromEid: eid1,
            toEid: eidE,
            tokenId: 1,
            status: IXferMgr.XferStatus.Pending
        });
        XferMgrSpy spy = new XferMgrSpy();
        bool isNative = false;
        bool allowMintBurn = true;

        console2.logString('xferFieldsCheck; Success');
        IXferMgr.Xfer memory xfer = _cloneXfer(xferOrig);
        IXferMgr.AddXferLrc lrc;
        lrc = spy.xferFieldsCheck(xfer, isNative, allowMintBurn);
        assertEq(uint(lrc), uint(IXferMgr.AddXferLrc.Ok), 'Success');

        console2.logString('xferFieldsCheck; Fail, BadQty');
        xfer = _cloneXfer(xferOrig);    // Restore original
        xfer.qty = 0;
        lrc = spy.xferFieldsCheck(xfer, isNative, allowMintBurn);
        assertEq(uint(lrc), uint(IXferMgr.AddXferLrc.BadQty), 'BadQty 1');

        console2.logString('xferFieldsCheck; Fail, SelfXfer');
        xfer = _cloneXfer(xferOrig);    // Restore original
        xfer.to = xfer.from;
        lrc = spy.xferFieldsCheck(xfer, isNative, allowMintBurn);
        assertEq(uint(lrc), uint(IXferMgr.AddXferLrc.SelfXfer), 'SelfXfer');

        console2.logString('xferFieldsCheck; Fail, NativeSrc');
        xfer = _cloneXfer(xferOrig);    // Restore original
        xfer.from = Util.ContractHeld;
        lrc = spy.xferFieldsCheck(xfer, isNative, allowMintBurn);
        assertEq(uint(lrc), uint(IXferMgr.AddXferLrc.Ok), 'NativeSrc Skip 1');

        lrc = spy.xferFieldsCheck(xfer, true, allowMintBurn);
        assertEq(uint(lrc), uint(IXferMgr.AddXferLrc.Ok), 'NativeSrc Skip 2');

        xfer = _cloneXfer(xferOrig);    // Restore original
        lrc = spy.xferFieldsCheck(xfer, true, allowMintBurn);
        assertEq(uint(lrc), uint(IXferMgr.AddXferLrc.NativeSrc), 'NativeSrc Hit');

        console2.logString('xferFieldsCheck; Fail, NativeAddr');
        xfer = _cloneXfer(xferOrig);    // Restore original
        xfer.from = Util.NativeMint;
        lrc = spy.xferFieldsCheck(xfer, isNative, allowMintBurn);
        assertEq(uint(lrc), uint(IXferMgr.AddXferLrc.NativeAddr), 'NativeMint');

        xfer = _cloneXfer(xferOrig);    // Restore original
        xfer.to = Util.NativeBurn;
        lrc = spy.xferFieldsCheck(xfer, isNative, allowMintBurn);
        assertEq(uint(lrc), uint(IXferMgr.AddXferLrc.NativeAddr), 'NativeBurn');

        console2.logString('xferFieldsCheck; Fail, MintBurn');
        xfer = _cloneXfer(xferOrig);    // Restore original
        xfer.from = Util.ExplicitMint;
        lrc = spy.xferFieldsCheck(xfer, isNative, allowMintBurn);

        assertEq(uint(lrc), uint(IXferMgr.AddXferLrc.Ok), 'MintBurn Skip ExplicitMint');
        xfer = _cloneXfer(xferOrig);    // Restore original
        xfer.to = Util.ExplicitBurn;
        lrc = spy.xferFieldsCheck(xfer, isNative, allowMintBurn);
        assertEq(uint(lrc), uint(IXferMgr.AddXferLrc.Ok), 'MintBurn Skip ExplicitBurn');

        xfer = _cloneXfer(xferOrig);    // Restore original
        xfer.from = Util.ExplicitMint;
        lrc = spy.xferFieldsCheck(xfer, isNative, false);
        assertEq(uint(lrc), uint(IXferMgr.AddXferLrc.MintBurn), 'MintBurn Hit ExplicitMint');

        xfer = _cloneXfer(xferOrig);    // Restore original
        xfer.to = Util.ExplicitBurn;
        lrc = spy.xferFieldsCheck(xfer, isNative, false);
        assertEq(uint(lrc), uint(IXferMgr.AddXferLrc.MintBurn), 'MintBurn Hit ExplicitBurn');
    }

    function _clonePropAddXfersReq(IXferMgr.PropAddXfersReq memory arg) private pure
        returns(IXferMgr.PropAddXfersReq memory clone)
    {
        uint len = arg.page.length;
        clone = IXferMgr.PropAddXfersReq({
            pid: arg.pid,
            iAppend: arg.iAppend,
            total: arg.total,
            page: new IXferMgr.Xfer[](len)
        });
        clone.page = new IXferMgr.Xfer[](len);
        for (uint i = 0; i < len; ++i) {
            clone.page[i] = _cloneXfer(arg.page[i]);
        }
    }

    // Creates a CRT transfer related proposal (not a revenue distribution)
    function test_XferMgr_prop_create_crt() public {
        TI.TokenInfo memory ti = _makeTokenInfo('CRT', crtAddr, TI.TokenType.Erc1155Crt);
        uint qtyPart;
        { // Reduce stack pressure
            uint totalQty =    123_456_789_000; //    123,456.789`000
            qtyPart = totalQty / 20;

            console2.logString('propCreate; Success');
            _createProp(pid1, eid1, ti, false);
        }

        IXferMgr.Xfer[] memory xfersA = _makeCrtXfersA(qtyPart);
        IXferMgr.Xfer[] memory xfersB = _makeCrtXfersB(qtyPart);
        // uint sumA = _getQtySum(xfersA);
        // uint sumB = _getQtySum(xfersB);
        IXferMgr.Xfer memory t0 = xfersA[0];
        IXferMgr.Xfer memory t1 = xfersA[1];
        IXferMgr.Xfer memory t2 = xfersB[0];
        IXferMgr.Xfer memory t3 = xfersB[1];
        IXferMgr.Xfer memory t4 = xfersB[2];
        seqNum = 1;
        assertEq(xferMgr.getSeqNum(creator), seqNum, 'seqNum');

        uint iAppend = 0;
        uint total = 0;
        reqId = _newUuid();

        IXferMgr.PropAddXfersReq memory reqOrig = IXferMgr.PropAddXfersReq({
            pid: pid1, iAppend: 0, total: 0, page: xfersA
        });
        IXferMgr.PropAddXfersReq memory req = _clonePropAddXfersReq(reqOrig);

        console2.logString('propAddXfers; Fail, Caller access');
        req = _clonePropAddXfersReq(reqOrig);
        vm.expectRevert(abi.encodeWithSelector(AC.AccessDenied.selector, creator));
        vm.prank(creator);
        xferMgr.propAddXfers(seqNum, reqId, req);

        console2.logString('propAddXfers; Fail, Bad pid');
        req = _clonePropAddXfersReq(reqOrig);
        req.pid += 1;
        seqNum = xferMgr.getSeqNum(agent);
        vm.prank(agent);
        xferMgr.propAddXfers(seqNum, reqId, req);
        vm.prank(agent);
        ICallTracker.CallRes memory cr = xferMgr.getCallResBySeqNum(seqNum);
        T.checkCall(vm, cr, uint(IXferMgr.AddXferRc.NoProp), 0, 0, 'propAddXfers');

        console2.logString('propAddXfers; Fail, Bad page length');
        reqId = _newUuid();
        IXferMgr.Xfer[] memory xfersE; // Empty
        req = _clonePropAddXfersReq(reqOrig);
        req.page = xfersE;
        vm.prank(agent);
        xferMgr.propAddXfers(++seqNum, reqId, req);
        vm.prank(agent);
        cr = xferMgr.getCallResBySeqNum(seqNum);
        T.checkCall(vm, cr, uint(IXferMgr.AddXferRc.BadPage), 0, 0, 'propAddXfers');

        console2.logString('propAddXfers; Fail, Bad index');
        reqId = _newUuid();
        req = _clonePropAddXfersReq(reqOrig);
        req.iAppend += 1;
        vm.prank(agent);
        xferMgr.propAddXfers(++seqNum, reqId, req);
        vm.prank(agent);
        cr = xferMgr.getCallResBySeqNum(seqNum);
        T.checkCall(vm, cr, uint(IXferMgr.AddXferRc.BadIndex), 0, 0, 'propAddXfers');

        console2.logString('propAddXfers; Fail, Bad total');
        reqId = _newUuid();
        req = _clonePropAddXfersReq(reqOrig);
        vm.prank(agent);
        xferMgr.propAddXfers(++seqNum, reqId, req);
        vm.prank(agent);
        cr = xferMgr.getCallResBySeqNum(seqNum);
        T.checkCall(vm, cr, uint(IXferMgr.AddXferRc.BadTotal), 0, 0, 'propAddXfers');

        console2.logString('propAddXfers; Fail, Bad line, invalid qty');
        reqId = _newUuid();
        req = _clonePropAddXfersReq(reqOrig);
        req.total = total = xfersA.length;
        req.page[0].qty = 0; // Invalid qty
        vm.prank(agent);
        xferMgr.propAddXfers(++seqNum, reqId, req);
        vm.prank(agent);
        cr = xferMgr.getCallResBySeqNum(seqNum);
        T.checkCall(vm, cr, uint(IXferMgr.AddXferRc.BadLine), uint(IXferMgr.AddXferLrc.BadQty), 0, 'propAddXfers');
        xfersA = _makeCrtXfersA(qtyPart); // Restore proper transfers
        t0 = xfersA[0];

        uint lenA = xfersA.length;
        uint lenB = xfersB.length;
        req = _clonePropAddXfersReq(reqOrig);
        req.total = total = lenA + lenB;
        reqId = _newUuid();
        for (uint i = 0; i < 2; ++i) {
            string memory suffix = i == 0 ? '(initial)' : '(duplicate, noop)';
            console2.log(T.concat('propAddXfers; Success, full page A', suffix));
            if (i == 0) ++seqNum;
            vm.prank(agent);
            xferMgr.propAddXfers(seqNum, reqId, req);
            vm.prank(agent);
            cr = xferMgr.getCallResBySeqNum(seqNum);
            T.checkCall(vm, cr, uint(IXferMgr.AddXferRc.FullPage), 0, lenA, 'propAddXfers');
            assertEq(seqNum + 1, xferMgr.getSeqNum(agent), 'seqNum');
        }
        reqId = _newUuid();

        IXferMgr.PropHdr memory ph = xferMgr.getPropHdr(pid1);
        assertEq(ph.uploadedAt, 0, 'uploadedAt');

        console2.logString('getXfers; Check xfers in proposal A');
        assertEq(xferMgr.getXfersLen(pid1), lenA);
        _checkXfers(false, xferMgr.getXfers(pid1, 0, lenA), xfersA, 'A');
        {
            IXferMgr.XferLite[] memory xfers = xferMgr.getXferLites(pid1, 0, lenA);
            assertEq(xfers.length, lenA);
        }

        console2.logString('propAddXfers; Fail, bad index');
        req = _clonePropAddXfersReq(reqOrig);
        req.iAppend = 0;
        vm.prank(agent);
        xferMgr.propAddXfers(++seqNum, reqId, req);
        vm.prank(agent);
        cr = xferMgr.getCallResBySeqNum(seqNum);
        T.checkCall(vm, cr, uint(IXferMgr.AddXferRc.BadIndex), 0, 0, 'propAddXfers');

        console2.logString('propFinalize; Fail, uploads not finished');
        vm.prank(vaultAddr);
        IXferMgr.PropXferFinalRc finalRc = xferMgr.propFinalize(pid1);
        assertEq(uint(finalRc), uint(IXferMgr.PropXferFinalRc.PropStat), 'propFinalize Rc');

        console2.logString('propExecute; Fail, upload not complete');
        vm.prank(vaultAddr);
        T.checkCall(vm, xferMgr.propExecute(pid1),
            uint(IXferMgr.ExecXferRc.PropStat), 0, 0, 'propExecute');

        console2.logString('propAddXfers; Success, full page B (all count)');
        reqId = _newUuid();
        req = _clonePropAddXfersReq(reqOrig);
        req.iAppend = iAppend = lenA;
        req.page = xfersB;
        req.total = total;
        vm.prank(agent);
        xferMgr.propAddXfers(++seqNum, reqId, req);
        vm.prank(agent);
        cr = xferMgr.getCallResBySeqNum(seqNum);
        T.checkCall(vm, cr, uint(IXferMgr.AddXferRc.AllPages), 0, lenB, 'propAddXfers');

        ph = xferMgr.getPropHdr(pid1);
        assertEq(ph.uploadedAt, block.timestamp, 'uploadedAt');

        console2.logString('getXfers; Check xfers in proposal A+B');
        assertEq(xferMgr.getXfersLen(pid1), total);
        _checkXfers(false, xferMgr.getXfers(pid1, 0, lenA), xfersA, 'A');
        _checkXfers(false, xferMgr.getXfers(pid1, lenA, lenB), xfersB, 'B');

        console2.logString('propAddXfers; Fail, Read only (upload completed)');
        reqId = _newUuid();
        vm.prank(agent);
        xferMgr.propAddXfers(++seqNum, reqId, req);
        vm.prank(agent);
        cr = xferMgr.getCallResBySeqNum(seqNum);
        T.checkCall(vm, cr, uint(IXferMgr.AddXferRc.ReadOnly), 0, 0, 'propAddXfers');

        // ----------
        // Finalize proposal
        // ----------
        console2.logString('propFinalize; Fail, caller access');
        vm.expectRevert(abi.encodeWithSelector(AC.AccessDenied.selector, agent));
        vm.prank(agent);
        xferMgr.propFinalize(pid1);

        console2.logString('propFinalize; Fail, unknown proposal');
        vm.prank(vaultAddr);
        finalRc = xferMgr.propFinalize(pid1 + 1);
        assertEq(uint(finalRc), uint(IXferMgr.PropXferFinalRc.NoProp), 'propFinalize Rc');

        console2.logString('propFinalize; Success');
        vm.prank(vaultAddr);
        finalRc = xferMgr.propFinalize(pid1);
        assertEq(uint(finalRc), uint(IXferMgr.PropXferFinalRc.Ok), 'propFinalize Rc');

        console2.logString('propFinalize; Success, Duplicate call');
        vm.prank(vaultAddr);
        finalRc = xferMgr.propFinalize(pid1);
        assertEq(uint(finalRc), uint(IXferMgr.PropXferFinalRc.Ok), 'propFinalize Rc');

        // ----------
        // Execute proposal
        // ----------
        console2.logString('propExecute; Fail, caller access');
        vm.expectRevert(abi.encodeWithSelector(AC.AccessDenied.selector, agent));
        vm.prank(agent);
        xferMgr.propExecute(pid1);

        console2.logString('propExecute; Fail, unknown proposal');
        vm.prank(vaultAddr);
        T.checkCall(vm, xferMgr.propExecute(pid1 + 1), uint(IXferMgr.ExecXferRc.NoProp), 0, 0, 'propExecute');

        console2.log('propExecute; 1 success (mint), 4 fails (insufficient source ownership)');
        vm.prank(vaultAddr);
        T.checkCall(vm, xferMgr.propExecute(pid1), uint(IXferMgr.ExecXferRc.Done), 4, total, 'propExecute');

        console2.logString('propExecute; Fail, already executed');
        vm.prank(vaultAddr);
        T.checkCall(vm, xferMgr.propExecute(pid1), uint(IXferMgr.ExecXferRc.Done), 0, 0, 'propExecute');

        console2.log('Rollback proposal status');
        xferMgr.resetPropStatus(pid1);

        console2.log('Reverse the xfer (burn)');
        vm.prank(xferMgrAddr);
        crt.safeTransferFrom(t0.to, Util.NativeBurn, t0.tokenId, t0.qty, '');

        // ----------
        // Resolve low funds: Increase the unclaimed balances and add tokens to fund them
        // ----------
        console2.logString('increaseOwnerBalances A');
        _increaseOwnerBalances(false, ti, xfersA);

        console2.logString('increaseOwnerBalances B');
        _increaseOwnerBalances(false, ti, xfersB);

        console2.log('propExecute; Success');
        _expectXfersEmit(xfersA);
        _expectXfersEmit(xfersB);
        vm.expectEmit();
        emit IXferMgr.XfersProcessed(pid1, eid1, 0, total, 0, ti.tokSym);
        vm.prank(vaultAddr);
        T.checkCall(vm, xferMgr.propExecute(pid1), uint(IXferMgr.ExecXferRc.Done), 0, total, 'propExecute');

        console2.log('Validate executed state after execution');
        assertNotEq(t0.qty, 0, 't0.qty');
        assertEq(crt.balanceOf(t0.to, t0.tokenId), t0.qty, 't0 to'); // Mint

        assertEq(crt.balanceOf(t1.from, t1.tokenId), 0, 't1 from');
        assertEq(crt.balanceOf(t1.to, t1.tokenId), t1.qty, 't1 to');

        assertEq(crt.balanceOf(t2.from, t2.tokenId), 0, 't2 from');
        assertEq(crt.balanceOf(t2.to, t2.tokenId), t2.qty, 't2 to');

        assertEq(crt.balanceOf(t3.from, t3.tokenId), 0, 't3 from');

        assertEq(crt.balanceOf(t4.from, t4.tokenId), 0, 't4 from');
        assertEq(crt.balanceOf(t4.to, t4.tokenId), t4.qty, 't4 to'); // Burn
    }

    /// @dev Create an array of transfers from the vault
    function _makeVaultXfersA(uint qtyPart) private returns(IXferMgr.Xfer[] memory xfers) {
        xfers = new IXferMgr.Xfer[](2);
        xfers[0] = IXferMgr.Xfer({ // Inst1 -> owner1
            eid: _newUuid(),
            from: vaultAddr,
            to: owner1Addr,
            qty: qtyPart * 1,
            fromEid: eid1,
            toEid: eidE,
            tokenId: 0,
            status: IXferMgr.XferStatus.Pending
        });
        xfers[1] = IXferMgr.Xfer({ // Inst1 -> owner2
            eid: _newUuid(),
            from: vaultAddr,
            to: owner2Addr,
            qty: qtyPart * 2,
            fromEid: eid2,
            toEid: eidE,
            tokenId: 0,
            status: IXferMgr.XferStatus.Pending
        });
    }

    /// @dev Create an array of transfers from the vault
    function _makeVaultXfersB(uint qtyPart) private returns(IXferMgr.Xfer[] memory xfers) {
        xfers = new IXferMgr.Xfer[](3);
        xfers[0] = IXferMgr.Xfer({ // Inst2 -> owner1
            eid: _newUuid(),
            from: vaultAddr,
            to: owner1Addr,
            qty: qtyPart * 3,
            fromEid: eid1,
            toEid: eidE,
            tokenId: 0,
            status: IXferMgr.XferStatus.Pending
        });
        xfers[1] = IXferMgr.Xfer({ // Inst2 -> owner2
            eid: _newUuid(),
            from: vaultAddr,
            to: owner2Addr,
            qty: qtyPart * 4,
            fromEid: eid2,
            toEid: eidE,
            tokenId: 0,
            status: IXferMgr.XferStatus.Pending
        });
        xfers[2] = IXferMgr.Xfer({ // Inst2 -> owner3
            eid: _newUuid(),
            from: vaultAddr,
            to: owner3Addr,
            qty: qtyPart * 10,
            fromEid: eid3,
            toEid: eidE,
            tokenId: 0,
            status: IXferMgr.XferStatus.Pending
        });
    }

    // Creates a USDC transfer related proposal (a revenue distribution)
    function test_XferMgr_prop_create_usdc() public {
        TI.TokenInfo memory ti = tokenInfoUsdc;
        Erc20Test erc20Token = tokenUsdc;

        IXferMgr.Xfer[] memory xfersA;
        IXferMgr.Xfer[] memory xfersB;
        { // Reduce stack pressure
            uint totalQty = 123_456_789_000; //    123,456.789`000
            uint qtyPart = totalQty / 20;

            console2.logString('propCreate; Success');
            _createProp(pid1, eid1, ti, true);

            xfersA = _makeVaultXfersA(qtyPart);
            xfersB = _makeVaultXfersB(qtyPart);
        }
        uint sumA = _getQtySum(xfersA);
        uint sumB = _getQtySum(xfersB);
        // IXferMgr.Xfer memory t0 = xfersA[0];
        IXferMgr.Xfer memory t1 = xfersA[1];
        IXferMgr.Xfer memory t2 = xfersB[0];
        IXferMgr.Xfer memory t3 = xfersB[1];
        // IXferMgr.Xfer memory t4 = xfersB[2];
        seqNum = 0;
        reqId = _newUuid();

        uint total = 0;

        IXferMgr.PropAddXfersReq memory reqOrig = IXferMgr.PropAddXfersReq({
            pid: pid1, iAppend: 0, total: 0, page: xfersA
        });
        IXferMgr.PropAddXfersReq memory req = _clonePropAddXfersReq(reqOrig);

        console2.logString('propAddXfers; Fail, bad line (crt not in token admin list)');
        req = _clonePropAddXfersReq(reqOrig);
        req.total = total = xfersA.length;
        vm.prank(agent);
        xferMgr.propAddXfers(++seqNum, reqId, req);
        vm.prank(agent);
        ICallTracker.CallRes memory cr = xferMgr.getCallResBySeqNum(seqNum);
        T.checkCall(vm, cr, uint(IXferMgr.AddXferRc.BadLine), uint(IXferMgr.AddXferLrc.LowFunds), 0, 'propAddXfers');

        reqId = _newUuid();
        vm.expectEmit();
        emit IXferMgr.TokenAdminListUpdated(crtAddr, true);
        xferMgr.updateTokenAdminList(seqNum, reqId, crtAddr, true);

        console2.logString('propAddXfers; Fail, low funds');
        reqId = _newUuid();
        req = _clonePropAddXfersReq(reqOrig);
        req.total = total = xfersA.length;
        vm.prank(agent);
        xferMgr.propAddXfers(++seqNum, reqId, req);
        vm.prank(agent);
        cr = xferMgr.getCallResBySeqNum(seqNum);
        T.checkCall(vm, cr, uint(IXferMgr.AddXferRc.BadLine), uint(IXferMgr.AddXferLrc.LowFunds), 0, 'propAddXfers');

        // ----------
        // Resolve low funds: Increase the unclaimed balances and add tokens to fund them
        // ----------
        console2.logString('increaseOwnerBalances A');
        _increaseOwnerBalances(true, ti, xfersA);

        console2.logString('increaseOwnerBalances B');
        _increaseOwnerBalances(true, ti, xfersB);

        console2.logString('propAddXfers; Success, full page A');
        reqId = _newUuid();
        req = _clonePropAddXfersReq(reqOrig);
        uint lenA = xfersA.length;
        uint lenB = xfersB.length;
        req.total = total = lenA + lenB;
        vm.prank(agent);
        xferMgr.propAddXfers(++seqNum, reqId, req);
        vm.prank(agent);
        cr = xferMgr.getCallResBySeqNum(seqNum);
        T.checkCall(vm, cr, uint(IXferMgr.AddXferRc.FullPage), uint(IXferMgr.AddXferLrc.Ok), lenA, 'propAddXfers');

        IXferMgr.PropHdr memory ph = xferMgr.getPropHdr(pid1);
        assertEq(ph.uploadedAt, 0, 'uploadedAt');

        console2.logString('getXfers; Check xfers in proposal A');
        assertEq(xferMgr.getXfersLen(pid1), lenA);
        _checkXfers(true, xferMgr.getXfers(pid1, 0, lenA), xfersA, 'A');

        console2.logString('propPruneXfers; Fail, not fully uploaded');
        uint[] memory skips; // Empty
        vm.prank(agent);
        xferMgr.propPruneXfers(NoSeqNum, NoReqId, pid1, skips);

        console2.logString('propAddXfers; Success, full page B (all uploaded)');
        reqId = _newUuid();
        req = _clonePropAddXfersReq(reqOrig);
        req.iAppend = lenA;
        req.page = xfersB;
        req.total = total = lenA + lenB;
        vm.prank(agent);
        xferMgr.propAddXfers(++seqNum, reqId, req);
        vm.prank(agent);
        cr = xferMgr.getCallResBySeqNum(seqNum);
        T.checkCall(vm, cr, uint(IXferMgr.AddXferRc.AllPages), uint(IXferMgr.AddXferLrc.Ok), lenB, 'propAddXfers');

        ph = xferMgr.getPropHdr(pid1);
        assertEq(ph.uploadedAt, block.timestamp, 'uploadedAt');

        console2.logString('getXfers; Check xfers in proposal A+B');
        assertEq(xferMgr.getXfersLen(pid1), total);
        _checkXfers(true, xferMgr.getXfers(pid1, 0, lenA), xfersA, 'A');
        _checkXfers(true, xferMgr.getXfers(pid1, lenA, lenB), xfersB, 'B');

        // ----------
        // Finalize proposal
        // ----------
        console2.logString('propFinalize; Success');
        vm.prank(vaultAddr);
        assertEq(uint(xferMgr.propFinalize(pid1)), uint(IXferMgr.PropXferFinalRc.Ok), 'propFinalize Rc');

        // ----------
        // Prune proposal
        // ----------
        console2.logString('propPruneXfers; Fail, bad caller');
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(AC.AccessDenied.selector, other));
        xferMgr.propPruneXfers(NoSeqNum, NoReqId, 0, skips);

        console2.logString('propPruneXfers; Fail, bad pid');
        vm.prank(agent);
        xferMgr.propPruneXfers(NoSeqNum, NoReqId, 0, skips);

        console2.logString('propPruneXfers; Fail, empty indexes');
        vm.prank(agent);
        xferMgr.propPruneXfers(NoSeqNum, NoReqId, pid1, skips);

        console2.logString('propPruneXfers; Fail, empty indexes');
        skips = new uint[](2);
        skips[0] = 10;  // bad index
        skips[1] = 4;   // t4
        vm.prank(agent);
        xferMgr.propPruneXfers(NoSeqNum, NoReqId, pid1, skips);

        ++seqNum;
        reqId = _newUuid();
        for (uint i = 0; i < 2; ++i) {
            string memory suffix = i == 0 ? '(initial)' : '(duplicate, noop)';
            console2.log(T.concat('propPruneXfers; Success', suffix));
            skips[0] = 0;   // t0
            skips[1] = 4;   // t4
            if (i == 0) {
                vm.expectEmit();
                emit IXferMgr.XfersPruned(pid1, eid1, 2);
                // vm.expectEmit();
                // emit ICallTracker.ReqAck(reqId, agent, seqNum, cr, false);
            }
            vm.prank(agent);
            xferMgr.propPruneXfers(seqNum, reqId, pid1, skips);
            vm.prank(agent);
            cr = xferMgr.getCallResBySeqNum(seqNum);
            assertEq(cr.count, skips.length, 'count');
            // assertFalse(badIndex, 'badIndex');
            assertEq(seqNum + 1, xferMgr.getSeqNum(agent), 'seqNum');
        }
        ++seqNum;
        reqId = _newUuid();

        // Validate pruning
        IXferMgr.Xfer[] memory xfers = xferMgr.getXfers(pid1, 0, 5);
        assertEq(xfers.length, 5, 'xfersLen');
        assertEq(uint(xfers[0].status), uint(IXferMgr.XferStatus.Skipped), 'XferStatus 0'); // Pruned
        assertEq(uint(xfers[1].status), uint(IXferMgr.XferStatus.Pending), 'XferStatus 1');
        assertEq(uint(xfers[2].status), uint(IXferMgr.XferStatus.Pending), 'XferStatus 2');
        assertEq(uint(xfers[3].status), uint(IXferMgr.XferStatus.Pending), 'XferStatus 3');
        assertEq(uint(xfers[4].status), uint(IXferMgr.XferStatus.Skipped), 'XferStatus 4'); // Pruned

        // ----------
        // Execute proposal
        // ----------
        console2.logString('protocol violation, set');
        uint vaultBalance = erc20Token.balanceOf(vaultAddr);
        erc20Token.burn(vaultAddr, vaultBalance); // Trigger protocol violation

        console2.log('propExecute; Fail, no funds in vault');
        vm.prank(vaultAddr);
        T.checkCall(vm, xferMgr.propExecute(pid1), uint(IXferMgr.ExecXferRc.Done), 3, total, 'propExecute');

        console2.logString('protocol violation, resolved');
        erc20Token.mint(vaultAddr, vaultBalance); // Resolve protocol violation

        console2.log('Rollback proposal status');
        xferMgr.resetPropStatus(pid1);

        console2.log('propExecute; Fail, insufficient unclaimed balance');
        vm.prank(revMgrAddr);
        balanceMgr.updateBalance(ti.tokAddr, t1.fromEid, -int(t1.qty), true); // Reduce unclaimed balance
        vm.prank(revMgrAddr);
        balanceMgr.updateBalance(ti.tokAddr, t2.fromEid, -int(t2.qty), true); // Reduce unclaimed balance
        vm.prank(revMgrAddr);
        balanceMgr.updateBalance(ti.tokAddr, t3.fromEid, -int(t3.qty), true); // Reduce unclaimed balance
        vm.prank(vaultAddr);
        T.checkCall(vm, xferMgr.propExecute(pid1), uint(IXferMgr.ExecXferRc.Done), 3, total, 'propExecute');
        vm.prank(revMgrAddr);
        balanceMgr.updateBalance(ti.tokAddr, t1.fromEid, int(t1.qty), true); // Increase unclaimed balance
        vm.prank(revMgrAddr);
        balanceMgr.updateBalance(ti.tokAddr, t2.fromEid, int(t2.qty), true); // Increase unclaimed balance
        vm.prank(revMgrAddr);
        balanceMgr.updateBalance(ti.tokAddr, t3.fromEid, int(t3.qty), true); // Increase unclaimed balance

        console2.log('Rollback proposal status');
        xferMgr.resetPropStatus(pid1);

        console2.log('propExecute; Fail, xfer revert');
        erc20Token.setRevertXfer(true);
        vm.prank(vaultAddr);
        T.checkCall(vm, xferMgr.propExecute(pid1), uint(IXferMgr.ExecXferRc.Done), 3, total, 'propExecute');
        erc20Token.setRevertXfer(false);

        console2.log('Rollback proposal status');
        xferMgr.resetPropStatus(pid1);

        console2.log('propExecute; Success');
        assertEq(erc20Token.balanceOf(vaultAddr), sumA + sumB, 'vault balance before');
        vm.expectEmit();
        emit IERC20.Transfer(t1.from, t1.to, t1.qty);
        vm.expectEmit();
        emit IERC20.Transfer(t2.from, t2.to, t2.qty);
        vm.expectEmit();
        emit IERC20.Transfer(t3.from, t3.to, t3.qty);
        vm.expectEmit();
        emit IXferMgr.XfersProcessed(pid1, eid1, 0, total, 0, ti.tokSym);
        vm.prank(vaultAddr);
        T.checkCall(vm, xferMgr.propExecute(pid1), uint(IXferMgr.ExecXferRc.Done), 0, total, 'propExecute');

        console2.log('Validate executed state after execution');
        assertEq(erc20Token.balanceOf(owner1Addr), t2.qty, 't0 pruned, t2 sent');
        assertEq(erc20Token.balanceOf(owner2Addr), t1.qty + t3.qty, 't1 + t3 sent');
        assertEq(erc20Token.balanceOf(owner3Addr), 0, 't4 pruned');
        // assertEq(erc20Token.balanceOf(vaultAddr), t0.qty + t4.qty, 'vault balance after');
    }

    /// @dev Create an array of transfers from the vault
    function _makeVaultEthXfers(uint qtyPart) private returns(IXferMgr.Xfer[] memory xfers) {
        xfers = new IXferMgr.Xfer[](2);
        xfers[0] = IXferMgr.Xfer({
            eid: _newUuid(),
            from: Util.ContractHeld,
            to: owner1Addr,
            qty: qtyPart * 1,
            fromEid: eid1,
            toEid: eidE,
            tokenId: 0,
            status: IXferMgr.XferStatus.Pending
        });
        xfers[1] = IXferMgr.Xfer({
            eid: _newUuid(),
            from: Util.ContractHeld,
            to: owner2Addr,
            qty: qtyPart * 3,
            fromEid: eid2,
            toEid: eidE,
            tokenId: 0,
            status: IXferMgr.XferStatus.Pending
        });
    }

    // Creates a native coin transfer proposal (not a revenue distribution)
    function test_XferMgr_prop_create_native() public {
        TI.TokenInfo memory ti = tokenInfoEth;
        uint totalQty =    123_456_789_000 wei;
        uint qtyPart = totalQty / 4;
        bool isRevDist = true;

        console2.logString('Reset ETH balances');
        _setEthBalance(vaultAddr, 0);
        _setEthBalance(owner1Addr, 0);
        _setEthBalance(owner2Addr, 0);

        // ----------
        // Create proposal
        // ----------
        console2.logString('propCreate; Success');
        _createProp(pid1, eid1, ti, isRevDist);

        IXferMgr.Xfer[] memory xfersA = _makeVaultEthXfers(qtyPart);
        uint sumA = _getQtySum(xfersA);
        IXferMgr.Xfer memory t0 = xfersA[0];
        IXferMgr.Xfer memory t1 = xfersA[1];

        uint total = xfersA.length;
        seqNum = 0;
        reqId = _newUuid();

        IXferMgr.PropAddXfersReq memory reqOrig = IXferMgr.PropAddXfersReq({
            pid: pid1, iAppend: 0, total: total, page: xfersA
        });
        IXferMgr.PropAddXfersReq memory req = _clonePropAddXfersReq(reqOrig);

        console2.logString('Set vaultInitBalance');
        uint vaultInitBalance = 3;
        _setEthBalance(vaultAddr, vaultInitBalance);

        console2.logString('propAddXfers; Fail, low funds');
        reqId = _newUuid();
        vm.prank(agent);
        xferMgr.propAddXfers(++seqNum, reqId, req);
        vm.prank(agent);
        ICallTracker.CallRes memory cr = xferMgr.getCallResBySeqNum(seqNum);
        T.checkCall(vm, cr,
            uint(IXferMgr.AddXferRc.BadLine), uint(IXferMgr.AddXferLrc.LowFunds), 0, 'propAddXfers');

        // ----------
        // Resolve low funds: Increase the unclaimed balances and add tokens to fund them
        // ----------
        console2.logString('increaseOwnerBalances ETH');
        _increaseOwnerBalances(true, ti, xfersA);
        assertEq(owner1Addr.balance, 0, 't0 set');
        assertEq(owner2Addr.balance, 0, 't1 set');
        assertEq(vaultAddr.balance, sumA + vaultInitBalance, 'vault set');

        console2.logString('propAddXfers; Success');
        reqId = _newUuid();
        req = _clonePropAddXfersReq(reqOrig);
        uint lenA = xfersA.length;
        req.total = total = lenA;
        vm.prank(agent);
        xferMgr.propAddXfers(++seqNum, reqId, req);
        vm.prank(agent);
        cr = xferMgr.getCallResBySeqNum(seqNum);
        T.checkCall(vm, cr, uint(IXferMgr.AddXferRc.AllPages), 0, lenA, 'propAddXfers');

        IXferMgr.PropHdr memory ph = xferMgr.getPropHdr(pid1);
        assertEq(ph.uploadedAt, block.timestamp, 'uploadedAt');

        console2.logString('getXfers; Check xfers in proposal A');
        assertEq(xferMgr.getXfersLen(pid1), lenA);
        _checkXfers(true, xferMgr.getXfers(pid1, 0, lenA), xfersA, 'A');

        // ----------
        // Finalize proposal
        // ----------
        console2.logString('propFinalize; Success');
        vm.prank(vaultAddr);
        IXferMgr.PropXferFinalRc finalRc;
        finalRc = xferMgr.propFinalize(pid1);
        assertEq(uint(finalRc), uint(IXferMgr.PropXferFinalRc.Ok), 'propFinalize Rc');

        // ----------
        // Execute proposal with a protocol violation (insufficient funds)
        // ----------
        console2.logString('protocol violation, created');
        assertEq(vaultAddr.balance, sumA + vaultInitBalance, 'vault balance before');
        _subEthBalance(vaultAddr, t1.qty); // Trigger protocol violation (remove t1.qty)
        assertEq(owner1Addr.balance, 0, 't0 before');
        assertEq(owner2Addr.balance, 0, 't1 before');
        assertEq(vaultAddr.balance, t0.qty + vaultInitBalance, 'vault balance before');

        console2.log('propExecute; Partial fail, no funds in vault for t1');
        vm.expectEmit();
        emit IXferMgr.XfersProcessed(pid1, eid1, 0, total, 1, ti.tokSym);
        vm.prank(vaultAddr);
        T.checkCall(vm, xferMgr.propExecute(pid1),
            uint(IXferMgr.ExecXferRc.Done), 1, total, 'propExecute');

        console2.log('Validate executed state after execution');
        assertEq(owner1Addr.balance, t0.qty, 't0 sent');
        assertEq(owner2Addr.balance, 0, 't1 not sent');
        assertEq(vaultAddr.balance, vaultInitBalance, 'vault balance after');

        // ----------
        // Resolve protocol violation
        // ----------
        console2.logString('protocol violation, resolved');
        _addEthBalance(vaultAddr, t1.qty); // Resolve protocol violation (add t1.qty)

        console2.logString('Reverse the t0 xfer');
        _addEthBalance(vaultAddr, t0.qty);
        _setEthBalance(t0.to, 0);

        console2.log('Rollback proposal status');
        xferMgr.resetPropStatus(pid1);
        vm.prank(revMgrAddr);
        balanceMgr.updateBalance(ti.tokAddr, t0.fromEid, int(t0.qty), true); // Increase unclaimed balance

        // ----------
        // Execute proposal
        // ----------
        console2.log('propExecute; Success');
        assertEq(owner1Addr.balance, 0, 't0 before');
        assertEq(owner2Addr.balance, 0, 't1 before');
        assertEq(vaultAddr.balance, sumA + vaultInitBalance, 'vault balance before');
        vm.expectEmit();
        emit IXferMgr.XfersProcessed(pid1, eid1, 0, total, 0, ti.tokSym);
        vm.prank(vaultAddr);
        T.checkCall(vm, xferMgr.propExecute(pid1), uint(IXferMgr.ExecXferRc.Done), 0, total, 'propExecute');

        console2.log('Validate executed state after execution');
        assertEq(owner1Addr.balance, t0.qty, 't0 sent');
        assertEq(owner2Addr.balance, t1.qty, 't1 sent');
        assertEq(vaultAddr.balance, vaultInitBalance, 'vault balance after');
    }
}
