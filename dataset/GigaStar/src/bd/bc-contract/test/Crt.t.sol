// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

// See LIB_PATHS
import '../lib/forge-std/src/Test.sol';

import '../lib/openzeppelin-contracts/contracts/interfaces/IERC721.sol';
import '../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol';
import '../lib/openzeppelin-contracts/contracts/token/ERC1155/extensions/IERC1155MetadataURI.sol';
import '../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol';

import '../contract/v1_0/Crt.sol';
import '../contract/v1_0/ICrt.sol';
import '../contract/v1_0/IRoleMgr.sol';
import '../contract/v1_0/IVersion.sol';
import '../contract/v1_0/LibraryAC.sol';
import '../contract/v1_0/LibraryCU.sol';
import '../contract/v1_0/Types.sol';

import './Const.sol';
import './MockVault.sol';

// Sufficient to be used with `setContract`
contract MockMgr is IVersion {
    function getVersion() external pure override returns (uint) {
        return 1;
    }
}

// Helper to ensure reverts are at a lower level in the callstack to allow them to be handled
contract CrtSpy is Crt {
    constructor() {} // Required for proxy init w/o args

    // Base `constructor` disables `initialize` but this circumvents that for testing. The tested contract
    // would be created via proxy with `initialize`, but this path allows code coverage (not possible via proxy) and
    // the proxy oriented creation is tested separately from the general case via `test_Crt_proxy_initialize`
    function init(address creator, UUID reqId, string memory url) public {
        __Crt_init(creator, reqId, url);
    }

    function requireXferAuth(address caller) external view {
        _requireXferAuth(caller);
    }
}

contract CrtSpy2 is Crt {
    function getVersion() external pure override returns (uint) { return 10_02; }
}

// Foundry tests for Crt
contract CrtTest is Test {
    CrtSpy spy;
    MockVault vault;
    address vaultAddr;
    address immutable creator        = address(new MockMgr());
    address immutable xferMgr        = address(new MockMgr());
    address immutable admin          = address(new MockMgr());
    address immutable agent          = address(new MockMgr());
    address immutable other          = address(new MockMgr());
    string constant url = 'https://domain.io/dir1/{id}.json';

    uint40 constant NoSeqNum = 0;
    UUID constant NoReqId = UuidZero;

    function setUp() public {
        vault = new MockVault();
        vaultAddr = address(vault);
        vault.addMockRole(admin, AC.Role.Admin);
        vault.addMockRole(agent, AC.Role.Agent);

        spy = new CrtSpy();             // Direct construct for code coverage as proxy coverage is untracked
        spy.init(creator, NoReqId, url);  // Hack to init the instance without a proxy

        vm.prank(creator);
        spy.setContract(NoSeqNum, NoReqId, CU.XferMgr, xferMgr);
        vm.prank(creator);
        spy.setContract(NoSeqNum, NoReqId, CU.Vault, vaultAddr);
        assertEq(spy.getVersion(), 10);

        _labelAddresses();
    }

    uint _counter = 0;
    function _newUuid() private returns (UUID) {
        ++_counter;
        return UUID.wrap(bytes16(uint128(_counter)));
    }

    function _labelAddresses() private {
        vm.label(address(spy), 'spy');
        vm.label(vaultAddr, 'vault');
        vm.label(creator, 'creator');
        vm.label(xferMgr, 'xferMgr');
        vm.label(admin, 'admin');
        vm.label(agent, 'agent');
        vm.label(other, 'other');
    }

    // This does not use `spy` as code coverage ignores calls outside of this test function
    function test_Crt_initialize_again() public {
        CrtSpy cs = new CrtSpy();    // Direct construct for code coverage as proxy coverage is untracked
        cs.init(creator, NoReqId, url);       // Hack to mostly init the instance without a proxy for testing

        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        cs.initialize(creator, NoReqId, url); // Reverts due to an `initializer` modifier on `initialize`
    }

    // This does not use `spy` as it does proxy oriented creation. This test does not count towards code coverage
    // as calls are via proxy which Foundry ignores, but this test is important as it tests the proxy oriented init
    // as would happen in prod
    function test_Crt_proxy_initialize() public {
        console2.log('Initialize a proxy instance');
        CrtSpy logic = new CrtSpy();
        bytes memory initData = abi.encodeWithSelector(Crt.initialize.selector, creator, NoReqId, url);
        CrtSpy proxy = CrtSpy(address(new ERC1967Proxy(address(logic), initData)));

        console2.log('Verify init');
        assertEq(url, proxy.uri(0));
        assertEq(creator, proxy.getContract(CU.Creator));
        assertEq(proxy.getTokenCount(), 0);
        assertEq(spy.getVersion(), 10);

        console2.log('Can only `initialize` proxy once');
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        proxy.initialize(creator, NoReqId, url); // Reverts due to an `initializer` modifier on `initialize`

        console2.log('`initialize` disabled on logic contract to prevent hijacking');
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        logic.initialize(creator, NoReqId, url); // Reverts due to a `constructor` call to `_disableInitializers`
    }

    function test_Crt_upgrade() public {
        console2.log('Deploy version 1 logic and proxy');
        CrtSpy logicV1 = new CrtSpy();
        bytes memory initData = abi.encodeWithSelector(Crt.initialize.selector, creator, NoReqId, url);
        ERC1967Proxy proxy = new ERC1967Proxy(address(logicV1), initData);

        console2.log('Deploy version 2 logic');
        CrtSpy2 logicV2 = new CrtSpy2();

        console2.log('Upgrade access denied');
        vm.expectRevert(abi.encodeWithSelector(AC.AccessDenied.selector, other));
        vm.prank(other);
        UUPSUpgradeable(address(proxy)).upgradeToAndCall(address(logicV2), '');

        console2.log('Perform upgrade via UUPS, passing an empty byte array for the initData');
        uint40 seqNum = ICallTracker(address(proxy)).getSeqNum(creator);
        UUID reqId = _newUuid();
        UUID reqIdStage = _newUuid();
        vm.prank(creator);
        IContractUser(address(proxy)).preUpgrade(seqNum, reqId, reqIdStage);
        vm.prank(creator);
        UUPSUpgradeable(address(proxy)).upgradeToAndCall(address(logicV2), '');

        console2.log('Verify new version');
        CrtSpy2 upgraded = CrtSpy2(address(proxy));
        assertEq(upgraded.getVersion(), 10_02);
    }

    function test_Crt_requireXferAuth() public {
        console2.log('Not authorized');
        vm.expectRevert(abi.encodeWithSelector(AC.AccessDenied.selector, address(this)));
        spy.requireXferAuth(address(this));

        console2.log('Not authorized');
        vm.expectRevert(abi.encodeWithSelector(AC.AccessDenied.selector, other));
        spy.requireXferAuth(other);

        console2.log('Authorized');
        spy.requireXferAuth(creator);
        spy.requireXferAuth(vaultAddr);
        spy.requireXferAuth(admin);
        spy.requireXferAuth(xferMgr);
    }

    function test_Crt_setUri() public {
        string memory newUri = 'https://new-domain.io/dir1/{id}.json';
        uint40 seqNum;
        UUID reqId = _newUuid();

        console2.log('Not authorized');
        seqNum = 1;
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(AC.AccessDenied.selector, other));
        spy.setUri(seqNum, reqId, newUri);

        console2.log('Authorized');
        seqNum = spy.getSeqNum(creator);
        reqId = _newUuid();
        vm.prank(creator);
        spy.setUri(seqNum, reqId, newUri);
        assertEq(newUri, spy.uri(0));
    }

    function test_Crt_supportsInterface() public view {
        assertTrue(spy.supportsInterface(type(IERC1155).interfaceId));
        assertTrue(spy.supportsInterface(type(IERC1155MetadataURI).interfaceId));
        assertTrue(spy.supportsInterface(type(ICrt).interfaceId));
        assertFalse(spy.supportsInterface(type(IERC721).interfaceId));
    }

    function test_Crt_isApprovedForAll_setApprovalForAll() public {
        console2.log('Check fixed accounts with access');
        assertTrue(spy.isApprovedForAll(AddrZero, xferMgr), 'xferMgr');
        assertTrue(spy.isApprovedForAll(AddrZero, vaultAddr), 'vault');
        assertTrue(spy.isApprovedForAll(AddrZero, admin), 'admin');
        assertTrue(spy.isApprovedForAll(AddrZero, creator), 'creator');

        console2.log('Check dynamic accounts');
        assertFalse(spy.isApprovedForAll(AddrZero, agent), 'agent');
        assertFalse(spy.isApprovedForAll(AddrZero, other), 'other');

        console2.log('setApprovalForAll; Fail, access control');
        vm.expectRevert(abi.encodeWithSelector(AC.AccessDenied.selector, other));
        vm.prank(other);
        spy.setApprovalForAll(other, true);

        console2.log('setApprovalForAll; Success - grant access');
        vm.expectEmit();
        emit IERC1155.ApprovalForAll(creator, agent, true);
        vm.prank(creator);
        spy.setApprovalForAll(agent, true);
        assertTrue(spy.isApprovedForAll(AddrZero, agent), 'agent');

        console2.log('setApprovalForAll; Success - revoke access');
        vm.expectEmit();
        emit IERC1155.ApprovalForAll(admin, agent, false);
        vm.prank(admin);
        spy.setApprovalForAll(agent, false);
        assertFalse(spy.isApprovedForAll(AddrZero, agent), 'agent');
    }

    function test_Crt_supply_and_balance_no_tokens() public view {
        assertEq(spy.getTokenCount(), 0);
        assertEq(spy.getTokenSupply(1), 0);
        assertEq(spy.getTokenSupply(2), 0);

        console2.log('Check balance of tokenId = 1');
        assertEq(spy.balanceOf(address(spy), 1), 0);
        assertEq(spy.balanceOf(other, 1), 0);

        console2.log('Check balance of tokenId = 2');
        assertEq(spy.balanceOf(address(spy), 2), 0);
        assertEq(spy.balanceOf(other, 2), 0);

        console2.log('Check balance of tokenIds 1 and 2');
        address[] memory accounts = new address[](2);
        accounts[0] = address(spy);
        accounts[1] = address(other);
        uint[] memory ids = new uint[](2);
        ids[0] = 1;
        ids[1] = 2;
        uint[] memory balances = spy.balanceOfBatch(accounts, ids);
        assertEq(balances.length, 2);
        assertEq(balances[0], 0);
        assertEq(balances[1], 0);
    }

    function _xfer(address from, address to, uint id, uint qty) private {
        // Translate addresses from sentinel to native
        address from2 = Util.resolveAddr(from, vaultAddr);
        address to2 = Util.resolveAddr(to, vaultAddr);

        vm.expectEmit();
        emit IERC1155.TransferSingle(creator, from2, to2, id, qty);

        spy.safeTransferFrom(from, to, id, qty, '');
    }

    function test_Crt_safeTransferFrom() public {
        address mint = Util.ExplicitMint;       // Token source
        address burn = Util.ExplicitBurn;       // Token destination
        address custody = Util.ContractHeld;    // Sentinel value
        address owner1 = address(spy);
        address owner2 = other;
        address owner3 = address(3);
        uint t1 = 1;                        // TokenId
        uint t2 = 2;                        // TokenId
        uint t3 = 3;                        // TokenId
        vm.startPrank(creator);

        console2.log('Mint tokenId 1');
        _xfer(mint, owner1, t1, 1);
        _xfer(mint, owner1, t1, 4);
        _xfer(mint, owner2, t1, 16);
        assertEq(spy.getTokenCount(), 1);
        assertEq(spy.getTokenSupply(t1), 21);
        assertEq(spy.getTokenSupply(t2), 0);
        assertEq(spy.balanceOf(owner1, t1), 5);
        assertEq(spy.balanceOf(owner2, t1), 16);
        assertEq(spy.balanceOf(owner3, t1), 0);

        console2.log('Mint tokenId 2');
        _xfer(mint, owner1, t2, 12);
        _xfer(mint, owner2, t2, 32);
        assertEq(spy.getTokenCount(), 2);
        assertEq(spy.getTokenSupply(t1), 21);
        assertEq(spy.getTokenSupply(t2), 44);
        assertEq(spy.balanceOf(owner1, t2), 12);
        assertEq(spy.balanceOf(owner2, t2), 32);
        assertEq(spy.balanceOf(owner3, t2), 0);

        console2.log('Mint tokenId 3 to custody');
        _xfer(mint, custody, t3, 7);
        assertEq(spy.balanceOf(custody, t3), 7, 'balanceOf custody');       // Custody
        assertEq(spy.balanceOf(vaultAddr, t3), 7, 'balanceOf vaultAddr');   // Custody
        assertEq(spy.getTokenCount(), 3, 'getTokenCount');
        assertEq(spy.getTokenSupply(t3), 7, 'getTokenSupply');

        console2.log('Xfer tokenId 3 to owner');
        _xfer(custody, owner1, t3, 7);
        assertEq(spy.balanceOf(custody, t3), 0, 'balanceOf custody');        // Custody
        assertEq(spy.balanceOf(vaultAddr, t3), 0, 'balanceOf vaultAddr');    // Custody
        assertEq(spy.balanceOf(owner1, t3), 7, 'balanceOf vaultAddr');

        console2.log('Burn tokenId 3');
        _xfer(owner1, burn, t3, 7);
        assertEq(spy.balanceOf(custody, t3), 0, 'balanceOf custody');        // Custody
        assertEq(spy.balanceOf(vaultAddr, t3), 0, 'balanceOf vaultAddr');    // Custody
        assertEq(spy.balanceOf(owner1, t3), 0, 'balanceOf vaultAddr');

        console2.log('Verify getTokenIds');
        uint[] memory tokenIds = spy.getTokenIds(0, 2);
        assertEq(tokenIds.length, 2);
        assertEq(tokenIds[0], 1);
        assertEq(tokenIds[1], 2);

        console2.log('Xfer tokenId 2 from owner2 to owner3');
        _xfer(owner2, owner3, t2, 3);
        assertEq(spy.getTokenCount(), 2);
        assertEq(spy.getTokenSupply(t1), 21);
        assertEq(spy.getTokenSupply(t2), 44);
        assertEq(spy.balanceOf(owner1, t2), 12);
        assertEq(spy.balanceOf(owner2, t2), 29);
        assertEq(spy.balanceOf(owner3, t2), 3);

        console2.log('Burn tokenId 1');
        _xfer(owner1, burn, t1, 5);
        _xfer(owner2, burn, t1, 16);
        assertEq(spy.getTokenCount(), 1);
        assertEq(spy.getTokenSupply(t1), 0);
        assertEq(spy.getTokenSupply(t2), 44);
        assertEq(spy.balanceOf(owner1, t1), 0);
        assertEq(spy.balanceOf(owner2, t1), 0);
        assertEq(spy.balanceOf(owner3, t1), 0);

        console2.log('Burn tokenId 2');
        _xfer(owner1, burn, t2, 12);
        _xfer(owner2, burn, t2, 29);
        _xfer(owner3, burn, t2, 3);
        assertEq(spy.getTokenCount(), 0);
        assertEq(spy.getTokenSupply(t1), 0);
        assertEq(spy.getTokenSupply(t2), 0);
        assertEq(spy.balanceOf(owner1, t2), 0);
        assertEq(spy.balanceOf(owner2, t2), 0);
        assertEq(spy.balanceOf(owner3, t2), 0);

        console2.log('Trigger BalanceUnderflow');
        uint Crt_INDEX_SINGLE = 12648430;  // Constant; HEX: 0xC0FFEE
        vm.expectRevert(abi.encodeWithSelector(ICrt.BalanceUnderflow.selector, owner1, 0, 7, t1, Crt_INDEX_SINGLE));
        spy.safeTransferFrom(owner1, owner2, t1, 7, '');

        console2.log('SupplyUnderflow cannot be reached/tested; it is extra defensive');
    }

    function _xferBatch(address from, address to, uint[] memory ids, uint[] memory qtys) private {
        // Translate addresses from sentinel to native
        address from2 = Util.resolveAddr(from, vaultAddr);
        address to2 = Util.resolveAddr(to, vaultAddr);

        vm.expectEmit();
        emit IERC1155.TransferBatch(xferMgr, from2, to2, ids, qtys);
        spy.safeBatchTransferFrom(from, to, ids, qtys, '');
    }

    function test_Crt_safeBatchTransferFrom() public {
        address mint = Util.ExplicitMint;   // Token source
        address owner1 = address(spy);
        address owner2 = other;
        uint t1 = 1;                        // TokenId
        uint t2 = 2;                        // TokenId
        vm.startPrank(xferMgr);

        uint[] memory ids = new uint[](2);
        ids[0] = 1;
        ids[1] = 2;

        console2.log('Mint tokenId 1 and 2 for owner1');
        uint[] memory qtys = new uint[](2);
        qtys[0] = 5;
        qtys[1] = 12;
        _xferBatch(mint, owner1, ids, qtys);

        assertEq(spy.getTokenCount(), 2);
        assertEq(spy.getTokenSupply(t1), 5);
        assertEq(spy.getTokenSupply(t2), 12);
        assertEq(spy.balanceOf(owner1, t1), 5);
        assertEq(spy.balanceOf(owner2, t1), 0);
        assertEq(spy.balanceOf(owner1, t2), 12);
        assertEq(spy.balanceOf(owner2, t2), 0);

        console2.log('Mint tokenId 1 and 2 for owner2');
        qtys[0] = 16;
        qtys[1] = 32;
        _xferBatch(mint, owner2, ids, qtys);

        assertEq(spy.getTokenCount(), 2);
        assertEq(spy.getTokenSupply(t1), 21);
        assertEq(spy.getTokenSupply(t2), 44);
        assertEq(spy.balanceOf(owner1, t1), 5);
        assertEq(spy.balanceOf(owner2, t1), 16);
        assertEq(spy.balanceOf(owner1, t2), 12);
        assertEq(spy.balanceOf(owner2, t2), 32);
    }
}
