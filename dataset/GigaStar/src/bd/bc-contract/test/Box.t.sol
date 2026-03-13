// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

// See LIB_PATHS
import '../lib/forge-std/src/Test.sol';

import '../lib/openzeppelin-contracts/contracts/proxy/Clones.sol';
import '../lib/openzeppelin-contracts/contracts/interfaces/IERC1155Receiver.sol';

import '../contract/v1_0/Box.sol';
import '../contract/v1_0/Erc20Test.sol';
import '../contract/v1_0/IBox.sol';
import '../contract/v1_0/IRoleMgr.sol';
import '../contract/v1_0/IVersion.sol';
import '../contract/v1_0/LibraryAC.sol';
import '../contract/v1_0/LibraryTI.sol';
import '../contract/v1_0/Types.sol';

import './Const.sol';

contract WalletRejectEth {
    // Reject any ETH transfers
    receive() external payable { revert('reject eth'); }
}

contract BoxTest is Test {
    address owner1 = address(this);
    address owner2 = address(1);
    address spender1 = address(2);
    address spender2 = address(3);
    address other = address(4);

    WalletRejectEth badWallet = new WalletRejectEth();

    string name1 = 'ABCD.1';
    string name2 = 'ABCD.2';

    Erc20Test tokenUsdc = new Erc20Test('USDC');
    Erc20Test tokenEurc = new Erc20Test('EURC');
    address usdcAddr = address(tokenUsdc);
    address eurcAddr = address(tokenEurc);

    TI.TokenInfo tokenInfoUsdc = _makeTokenInfo('USDC', usdcAddr, TI.TokenType.Erc20);
    TI.TokenInfo tokenInfoEurc = _makeTokenInfo('EURC', eurcAddr, TI.TokenType.Erc20);
    TI.TokenInfo tokenInfoEth = _makeTokenInfo('ETH', AddrZero, TI.TokenType.NativeCoin);

    uint40 constant NoSeqNum = 0;
    UUID constant NoReqId = UuidZero;

    function setUp() public {
        _labelAddresses();
    }

    function _labelAddresses() private {
        vm.label(owner1, 'owner1');
        vm.label(owner2, 'owner2');
        vm.label(spender1, 'spender1');
        vm.label(spender2, 'spender2');
        vm.label(other, 'other');

        vm.label(Util.ExplicitMint, 'ExplicitMintBurn');
        vm.label(Util.ContractHeld, 'ContractHeld');

        vm.label(usdcAddr, 'usdcAddr');
        vm.label(eurcAddr, 'eurcAddr');
    }

    function test_Box_initialize() public {
        Box b = new Box();
        // Attempt to initialize again; revert as not allowed
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        b.initialize(owner1, name1);
    }

    function _initProxy(address owner, string memory name) public returns(IBox boxProxy) {
        address logicAddr = address(new Box());
        uint version = 10;
        uint nonce = 1;
        bytes32 salt = keccak256(abi.encodePacked(name, version, nonce));
        boxProxy = IBox(Clones.cloneDeterministic(logicAddr, salt)); // May revert with FailedDeployment
        vm.label(address(boxProxy), string(abi.encodePacked('box=', name)));
        IBox(boxProxy).initialize(owner, name);
    }

    function test_Box_create() public {
        // Intialize
        IBox box = _initProxy(owner1, name1);

        // Validate post-init
        assertEq(box.getName(), name1);
        assertTrue(box.isOwner(owner1));
        assertFalse(box.isOwner(other));
        assertEq(box.getVersion(), 10, 'getVersion');
        assertEq(box.getOwnersLen(), 1, 'getOwnersLen');
        assertEq(box.getApprovalsLen(), 0, 'getApprovalsLen');

        // Attempt to initialize again; revert as not allowed
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        box.initialize(owner1, name2);
        assertEq(box.getName(), name1);

        // Change the name; revert as not owner1
        vm.expectRevert(abi.encodeWithSelector(IBox.OwnerRequired.selector, other));
        vm.prank(other);
        box.setName(name2);
        assertEq(box.getName(), name1);

        // Change the name
        box.setName(name2);
        assertEq(box.getName(), name2);
    }

    // Test ERC-1155 receive functions
    function test_Box_receive_1155() public {
        // Send 1 ether to the contract with no data (triggers receive)
        IBox box = _initProxy(owner1, name1);
        address a;
        uint i;
        uint[] memory u;
        bytes memory b;
        assertEq(box.onERC1155Received(a,a,i,i,b), box.onERC1155Received.selector, 'onERC1155Received');
        assertEq(box.onERC1155BatchReceived(a,a,u,u,b), box.onERC1155BatchReceived.selector, 'onERC1155BatchReceived');
    }

    // Test low-level receive function
    function test_Box_receive_native() public {
        // Send 1 ether to the contract with no data (triggers receive)
        IBox box = _initProxy(owner1, name1);
        (bool ok, ) = address(box).call{value: 1 ether}('');
        require(ok, 'receive() failed');
        assertEq(1 ether, address(box).balance);
    }

    // Test low-level fallback function
    function test_Box_fallback() public {
        // Send 1 ether with arbitrary data (triggers fallback)
        IBox box = _initProxy(owner1, name1);
        (bool ok, ) = address(box).call(hex'cafebabe');
        require(ok, 'fallback() failed (no ETH)');
        assertEq(0 ether, address(box).balance);

        // Send 1 ether with arbitrary data (triggers fallback)
        (ok, ) = address(box).call{value: 1 ether}(hex'deadbeef');
        require(ok, 'fallback() failed');
        assertEq(1 ether, address(box).balance);
    }

    function test_Box_addOwner() public {
        // Intialize
        IBox box = _initProxy(owner1, name1);

        // Validate post-init
        assertTrue(box.isOwner(owner1));
        assertFalse(box.isOwner(owner2));
        assertFalse(box.isOwner(other));
        assertEq(box.getOwnersLen(), 1);

        // Attempt to add an owner; revert due to caller
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(IBox.OwnerRequired.selector, other));
        box.addOwner(owner1);

        // Attempt to add an owner; revert due to invalid address
        vm.expectRevert(abi.encodeWithSelector(InvalidZeroAddr.selector));
        box.addOwner(AddrZero);

        // Attempt to add an owner; fail as already an owner
        assertFalse(box.addOwner(owner1));

        // Validate
        assertTrue(box.isOwner(owner1));
        assertFalse(box.isOwner(owner2));
        assertFalse(box.isOwner(other));

        // Attempt to add an owner; success
        vm.expectEmit();
        emit IBox.OwnerAdded(owner2);
        assertTrue(box.addOwner(owner2));

        // Validate
        assertEq(box.getOwnersLen(), 2);
        assertTrue(box.isOwner(owner1));
        assertTrue(box.isOwner(owner2));
        assertFalse(box.isOwner(other));
    }

    function test_Box_removeOwner() public {
        // Intialize
        IBox box = _initProxy(owner1, name1);
        assertTrue(box.addOwner(owner2));

        // Validate post-init
        assertTrue(box.isOwner(owner1));
        assertTrue(box.isOwner(owner2));
        assertFalse(box.isOwner(other));

        // Attempt to remove an owner; revert due to caller
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(IBox.OwnerRequired.selector, other));
        box.removeOwner(owner1);

        // Attempt to remove an owner; revert due to invalid address
        vm.expectRevert(abi.encodeWithSelector(InvalidZeroAddr.selector));
        box.removeOwner(AddrZero);

        // Attempt to remove an owner; fail as not an owner
        assertFalse(box.removeOwner(other));

        // Validate
        assertTrue(box.isOwner(owner1));
        assertTrue(box.isOwner(owner2));
        assertFalse(box.isOwner(other));
        assertEq(box.getOwnersLen(), 2);

        // Attempt to remove an owner; success
        vm.expectEmit();
        emit IBox.OwnerRemoved(owner1);
        assertTrue(box.removeOwner(owner1));

        // Validate
        assertFalse(box.isOwner(owner1));
        assertTrue(box.isOwner(owner2));
        assertFalse(box.isOwner(other));

        // Attempt to remove last owner; fail as >=1 required
        vm.prank(owner2);
        assertFalse(box.removeOwner(owner2));

        // Validate
        assertEq(box.getOwnersLen(), 1);
        assertFalse(box.isOwner(owner1));
        assertTrue(box.isOwner(owner2));
        assertFalse(box.isOwner(other));
    }

    function test_Box_IERC165() public {
        IBox box = _initProxy(owner1, name1);
        assertTrue(box.supportsInterface(type(IBox).interfaceId));
        assertTrue(box.supportsInterface(type(IERC165).interfaceId));
        assertTrue(box.supportsInterface(type(IERC1155Receiver).interfaceId));
        assertFalse(box.supportsInterface(type(IRoleMgr).interfaceId), 'random interface');
    }

    function test_Box_getOwners() public {
        // Intialize
        IBox box = _initProxy(owner1, name1);
        assertTrue(box.addOwner(owner2));

        // Validate post-init
        assertEq(box.getOwnersLen(), 2);
        assertTrue(box.isOwner(owner1));
        assertTrue(box.isOwner(owner2));
        assertFalse(box.isOwner(other));

        // Get owners
        address[] memory owners = box.getOwners(0, 10);
        assertEq(owners.length, 2);
        assertEq(owners[0], owner1);
        assertEq(owners[1], owner2);

        // Get only first owner
        owners = box.getOwners(0, 1);
        assertEq(owners.length, 1);
        assertEq(owners[0], owner1);

        // Get only last owner
        owners = box.getOwners(1, 1);
        assertEq(owners.length, 1);
        assertEq(owners[0], owner2);
    }

    function _makeTokenInfo(string memory tokSym, address tokAddr, TI.TokenType tokType) private pure
        returns(TI.TokenInfo memory)
    {
        return TI.TokenInfo({ tokSym: tokSym, tokAddr: tokAddr, tokenId: 0, tokType: tokType });
    }

    function test_Box_approve_fail_tokType() public {
        IBox box = _initProxy(owner1, name1);

        TI.TokenInfo memory tokenInfo = tokenInfoUsdc;
        uint allowance = MAX_ALLOWANCE;

        for (uint i = 0; i <= uint(TI.TokenType.Count); ++i) {
            TI.TokenType tokType = TI.TokenType(i);
            if (tokType == TI.TokenType.Erc20 || tokType == TI.TokenType.Erc1155) {
                continue; // Valid token type for approval
            }
            // Attempt approve; fail due to tokType
            tokenInfo.tokType = tokType;
            assertEq(uint(IBox.ApproveRc.BadToken), uint(box.approve(spender1, tokenInfo, allowance)));
        }
    }

    function test_Box_approve_erc20_fail() public {
        IBox box = _initProxy(owner1, name1);
        assertEq(tokenUsdc.allowance(address(box), spender1), 0, 'allowance');

        TI.TokenInfo memory usdc = tokenInfoUsdc;
        uint allowance = MAX_ALLOWANCE;

        console2.log('Attempt approve; revert due to zero spender');
        vm.expectRevert(abi.encodeWithSelector(InvalidZeroAddr.selector));
        box.approve(AddrZero, usdc, allowance);

        console2.log('Attempt approve; revert due to zero tokAddr');
        TI.TokenInfo memory badToken = _makeTokenInfo('BAD', AddrZero, TI.TokenType.Count);
        vm.expectRevert(abi.encodeWithSelector(InvalidZeroAddr.selector));
        box.approve(spender1, badToken, allowance);

        console2.log('Attempt approve; revert due to caller');
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(IBox.OwnerRequired.selector, other));
        box.approve(spender1, usdc, allowance);

        console2.log('Attempt approve; fail due to token.allowance revert => return code');
        assertEq(tokenUsdc.allowance(address(box), spender1), 0, 'allowance');
        tokenUsdc.setRevertAllowance(true);
        IBox.ApproveRc rc = box.approve(spender1, usdc, allowance);
        assertEq(uint(rc), uint(IBox.ApproveRc.AllowanceFail), 'rc');
        tokenUsdc.setRevertAllowance(false);

        console2.log('Attempt approve; fail due to token.approve revert => return code');
        assertEq(tokenUsdc.allowance(address(box), spender1), 0, 'allowance');
        tokenUsdc.setRevertApprove(true);
        rc = box.approve(spender1, usdc, allowance);
        assertEq(uint(rc), uint(IBox.ApproveRc.ApproveFail), 'rc');
        tokenUsdc.setRevertApprove(false);

        console2.log('Attempt approve; fail due to token.approve result => return code');
        tokenUsdc.setFailApprove(true);
        rc = box.approve(spender1, usdc, allowance);
        assertEq(uint(rc), uint(IBox.ApproveRc.ApproveFail), 'rc');
        tokenUsdc.setFailApprove(false);
    }

    function test_Box_approve_erc20_success() public {
        IBox box = _initProxy(owner1, name1);

        TI.TokenInfo memory usdc = tokenInfoUsdc;
        TI.TokenInfo memory eurc = tokenInfoEurc;
        TI.TokenInfo[] memory tokens = new TI.TokenInfo[](2);
        tokens[0] = usdc;
        tokens[1] = eurc;
        uint allowance = MAX_ALLOWANCE;

        console2.log('Approve a single token; success');
        IBox.ApproveRc rc = box.approve(spender1, usdc, allowance);
        assertEq(uint(rc), uint(IBox.ApproveRc.Success));
        assertEq(box.getApprovalsLen(), 1);
        assertEq(box.getAllowance(usdc.tokAddr, spender1), allowance, 'usdc spender1');

        console2.log('Approve a single token; success');
        rc = box.approve(spender1, eurc, allowance);
        assertEq(uint(rc), uint(IBox.ApproveRc.Success));
        assertEq(box.getApprovalsLen(), 2);
        assertEq(box.getAllowance(usdc.tokAddr, spender1), allowance, 'usdc spender1');
        assertEq(box.getAllowance(eurc.tokAddr, spender1), allowance, 'eurc spender1');

        console2.log('Approve multiple tokens; success');
        IBox.ApproveRc[] memory rcs = box.approveAll(spender2, tokens, allowance);
        assertEq(rcs.length, 2, 'rcs length');
        assertEq(uint(rcs[0]), uint(IBox.ApproveRc.Success));
        assertEq(uint(rcs[1]), uint(IBox.ApproveRc.Success));
        assertEq(box.getApprovalsLen(), 4);
        assertEq(box.getAllowance(usdc.tokAddr, spender1), allowance, 'usdc spender1');
        assertEq(box.getAllowance(eurc.tokAddr, spender1), allowance, 'eurc spender1');
        assertEq(box.getAllowance(usdc.tokAddr, spender2), allowance, 'usdc spender2');
        assertEq(box.getAllowance(eurc.tokAddr, spender2), allowance, 'eurc spender2');

        console2.log('Get approvals');
        IBox.Approval[] memory approvals = box.getApprovals(0, 10);
        assertEq(approvals.length, 4);
        _checkApproval(approvals[0], usdc.tokAddr, spender1, allowance);
        _checkApproval(approvals[1], eurc.tokAddr, spender1, allowance);
        _checkApproval(approvals[2], usdc.tokAddr, spender2, allowance);
        _checkApproval(approvals[3], eurc.tokAddr, spender2, allowance);

        console2.log('Get only first 2 approvals');
        approvals = box.getApprovals(0, 2);
        assertEq(approvals.length, 2);
        _checkApproval(approvals[0], usdc.tokAddr, spender1, allowance);
        _checkApproval(approvals[1], eurc.tokAddr, spender1, allowance);

        console2.log('Get only last 2 approvals');
        approvals = box.getApprovals(2, 2);
        assertEq(approvals.length, 2);
        _checkApproval(approvals[0], usdc.tokAddr, spender2, allowance);
        _checkApproval(approvals[1], eurc.tokAddr, spender2, allowance);

        console2.log('Update existing approval for spender1; success');
        assertEq(box.getApprovalsLen(), 4, 'before half approval');
        uint allowanceSmall = 9;
        rc = box.approve(spender1, usdc, allowanceSmall);
        assertEq(uint(rc), uint(IBox.ApproveRc.Success));
        assertEq(box.getApprovalsLen(), 4, 'after half approval');
        assertEq(box.getAllowance(usdc.tokAddr, spender1), allowanceSmall, 'usdc spender1');
        assertEq(box.getAllowance(eurc.tokAddr, spender1), allowance, 'eurc spender1');
        assertEq(box.getAllowance(usdc.tokAddr, spender2), allowance, 'usdc spender2');
        assertEq(box.getAllowance(eurc.tokAddr, spender2), allowance, 'eurc spender2');

        console2.log('Remove approvals for spender1; success');
        rcs = box.approveAll(spender1, tokens, 0);
        assertEq(rcs.length, 2, 'rcs length, remove1');
        assertEq(uint(rcs[0]), uint(IBox.ApproveRc.Success));
        assertEq(uint(rcs[1]), uint(IBox.ApproveRc.Success));
        assertEq(box.getApprovalsLen(), 2);
        assertEq(box.getAllowance(usdc.tokAddr, spender2), allowance, 'usdc spender2');
        assertEq(box.getAllowance(eurc.tokAddr, spender2), allowance, 'eurc spender2');

        console2.log('Remove approvals for spender2; success');
        rcs = box.approveAll(spender2, tokens, 0);
        assertEq(rcs.length, 2, 'rcs length, remove2');
        assertEq(uint(rcs[0]), uint(IBox.ApproveRc.Success));
        assertEq(uint(rcs[1]), uint(IBox.ApproveRc.Success));
        assertEq(box.getApprovalsLen(), 0);
        approvals = box.getApprovals(0, 10);
        assertEq(approvals.length, 0);
    }

    function _checkApproval(IBox.Approval memory actual, address tokAddr, address spender, uint allowance) private pure {
        assertEq(actual.tokAddr, tokAddr, 'checkApproval token');
        assertEq(actual.spender, spender, 'checkApproval spender');
        assertEq(actual.allowance, allowance, 'checkApproval allowance');
    }

    function test_Box_push_fail_caller_burn() public {
        IBox box = _initProxy(owner1, name1);

        TI.TokenInfo memory usdc = tokenInfoUsdc;
        TI.TokenInfo memory eurc = tokenInfoEurc;
        TI.TokenInfo[] memory tokens = new TI.TokenInfo[](2);
        tokens[0] = usdc;
        tokens[1] = eurc;
        uint qty = 3;

        console2.log('Attempt push single; revert due to caller');
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(IBox.OwnerRequired.selector, other));
        box.push(spender1, usdc, qty);

        console2.log('Attempt push many; revert due to caller');
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(IBox.OwnerRequired.selector, other));
        box.pushAll(spender1, tokens, qty);

        console2.log('Attempt push single; revert due to burn address');
        vm.expectRevert(abi.encodeWithSelector(InvalidZeroAddr.selector));
        box.push(AddrZero, usdc, qty);

        console2.log('Attempt push many; revert due to burn address');
        vm.expectRevert(abi.encodeWithSelector(InvalidZeroAddr.selector));
        box.pushAll(AddrZero, tokens, qty);
    }

    function _allowPush(TI.TokenType tokType) private pure returns(bool) {
        return tokType == TI.TokenType.Erc20
                || tokType == TI.TokenType.NativeCoin
                || tokType == TI.TokenType.Erc1155;
    }

    function test_Box_push_fail_tokType() public {
        IBox box = _initProxy(owner1, name1);
        TI.TokenInfo memory tokenInfo = tokenInfoUsdc;
        uint qty = 3;

        for (uint i = 0; i <= uint(TI.TokenType.Count); ++i) {
            TI.TokenType tokType = TI.TokenType(i);
            if (_allowPush(tokType)) continue;

            console2.log('Attempt push; fail due to tokType');
            tokenInfo.tokType = tokType;
            IBox.PushResult memory result = box.push(spender1, tokenInfo, qty);
            assertEq(uint(IBox.PushRc.BadToken), uint(result.rc));
            assertEq(0, result.qty);
        }
    }

    function test_Box_push_erc20() public {
        IBox box = _initProxy(owner1, name1);
        TI.TokenInfo memory tokenInfo = tokenInfoUsdc;
        uint qty = 3;

        console2.log('Attempt push ERC-20; fail due to low balance');
        IBox.PushResult memory result = box.push(spender1, tokenInfo, qty);
        assertEq(uint(IBox.PushRc.LowBalance), uint(result.rc));
        assertEq(0, result.qty);

        console2.log('Attempt push ERC-20; fail due to token.balanceOf(box)');
        tokenUsdc.setRevertBalanceOf(true);
        result = box.push(spender1, tokenInfo, qty);
        assertEq(uint(IBox.PushRc.BalanceFail), uint(result.rc));
        assertEq(0, result.qty);
        tokenUsdc.setRevertBalanceOf(false);

        console2.log('Init box token balance');
        tokenUsdc.mint(address(box), qty);

        console2.log('Attempt push ERC-20; fail due to token.transfer return code - simulates a race condition');
        tokenUsdc.setFailXfer(true);
        result = box.push(spender1, tokenInfo, qty);
        assertEq(uint(IBox.PushRc.XferFail), uint(result.rc), 'transfer return code');
        assertEq(0, result.qty);
        tokenUsdc.setFailXfer(false);

        console2.log('Attempt push ERC-20; fail due to token.transfer revert');
        tokenUsdc.setRevertXfer(true);
        result = box.push(spender1, tokenInfo, qty);
        assertEq(uint(IBox.PushRc.XferFail), uint(result.rc), 'transfer revert');
        assertEq(0, result.qty);
        tokenUsdc.setRevertXfer(false);

        console2.log('Attempt push ERC-20; success');
        result = box.push(spender1, tokenInfo, qty);
        assertEq(uint(IBox.PushRc.Success), uint(result.rc), 'transfer success 1');
        assertEq(qty, result.qty);

        console2.log('Init box token balance');
        uint qty2 = 2 * qty;
        tokenUsdc.mint(address(box), qty2);

        console2.log('Attempt push ERC-20; success');
        uint sendAll = 0;
        result = box.push(spender1, tokenInfo, sendAll);
        assertEq(uint(IBox.PushRc.Success), uint(result.rc), 'transfer success 2');
        assertEq(qty2, result.qty);
    }

    function _setEthBalance(address addr, uint qty) private {
        vm.deal(addr, qty);
    }

    function test_Box_push_nativeCoin() public {
        IBox box = _initProxy(owner1, name1);
        address boxAddr = address(box);
        TI.TokenInfo memory tokenInfo = tokenInfoUsdc;
        tokenInfo.tokType = TI.TokenType.NativeCoin;
        tokenInfo.tokAddr = AddrZero;
        uint qty = 3;

        console2.log('Attempt push NativeCoin; fail due to low balance');
        IBox.PushResult memory result = box.push(spender1, tokenInfo, qty);
        assertEq(uint(IBox.PushRc.LowBalance), uint(result.rc));
        assertEq(0, result.qty);

        _setEthBalance(boxAddr, 3);

        console2.log('Attempt push native coin; fail due to token.transfer return code - simulates a race condition');
        address recipient = address(badWallet);
        result = box.push(recipient, tokenInfo, qty);
        assertEq(uint(IBox.PushRc.XferFail), uint(result.rc), 'transfer return code');
        assertEq(0, result.qty);

        console2.log('Attempt push native coin; success');
        result = box.push(spender1, tokenInfo, qty);
        assertEq(uint(IBox.PushRc.Success), uint(result.rc), 'transfer success 1');
        assertEq(qty, result.qty);

        uint qty2 = 6;
        _setEthBalance(boxAddr, qty2);

        console2.log('Attempt push native coin; success');
        uint sendAll = 0;
        result = box.push(spender1, tokenInfo, sendAll);
        assertEq(uint(IBox.PushRc.Success), uint(result.rc), 'transfer success 2');
        assertEq(qty2, result.qty);
    }

    // Add tests for ERC-1155; requires a test token - Unlikely to be necessary; low priority (not used by CRTs)
}
