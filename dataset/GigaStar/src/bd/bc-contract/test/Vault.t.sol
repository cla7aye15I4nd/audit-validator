// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

// See LIB_PATHS
import '../lib/forge-std/src/Test.sol';
import '../lib/forge-std/src/Vm.sol';

import '../lib/openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol';
import '../lib/openzeppelin-contracts/contracts/interfaces/IERC1155Receiver.sol';
import '../lib/openzeppelin-contracts/contracts/interfaces/IERC1967.sol';
import '../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol';
import '../lib/openzeppelin-contracts/contracts/proxy/Clones.sol';

import '../contract/v1_0/Erc20Test.sol';
import '../contract/v1_0/ICallTracker.sol';
import '../contract/v1_0/IContractUser.sol';
import '../contract/v1_0/IPausable.sol';
import '../contract/v1_0/IVault.sol';
import '../contract/v1_0/IVersion.sol';
import '../contract/v1_0/LibraryAC.sol';
import '../contract/v1_0/LibraryARI.sol';
import '../contract/v1_0/LibraryBI.sol';
import '../contract/v1_0/LibraryCU.sol';
import '../contract/v1_0/LibraryIR.sol';
import '../contract/v1_0/LibraryOI.sol';
import '../contract/v1_0/LibraryString.sol';
import '../contract/v1_0/LibraryTI.sol';
import '../contract/v1_0/LogicDeployers.sol';
import '../contract/v1_0/ProxyDeployers.sol';
import '../contract/v1_0/Types.sol';
import '../contract/v1_0/Vault.sol';

import './Const.sol';
import './LibraryTest.sol';

contract VaultLatest is Vault {
    function getVersion() public pure override returns (uint) { return 999; }
}

// Exposes details for testing
contract VaultSpy is Vault {
}

contract VaultSpyLogicDeployer is LogicDeployer {
    constructor() { _logic = address(new VaultSpy()); emit LogicDeployed(_logic); }
}

contract VaultSpyProxyDeployer {
    function createProxy(address logicAddr, address creator, UUID reqId, uint quorum,
        AC.RoleRequest[] calldata roleRequests) public returns(VaultSpy)
    {
        address proxyAddr = (new ProxyDeployer()).deployProxy(logicAddr, 'VaultSpy',
            abi.encodeWithSelector(IVault.initialize.selector, creator, reqId, quorum, roleRequests));
            return VaultSpy(payable(proxyAddr));
    }
}

contract VaultTest is Test {
    address creator = address(this);

    // A private and public key can be acquired via either:
    //     1) uint256 privKey = 0x123; address pubKey = vm.addr(privKey); vm.label(pubKey, 'name')
    //     2) VmSafe.Wallet admin1 = vm.createWallet('admin'); // Allows `admin1.addr` and `admin1.privateKey`
    // Following uses option 1 but 2 would be preferred for a larger dynamic set

    uint256 admin1Pk = 0xC0FFEE1;         // Aribtrary private keys
    uint256 admin2Pk = 0xC0FFEE2;
    uint256 agentPk  = 0xDEADBEEF;
    uint256 voter1Pk = 0xACEFACE1;
    uint256 voter2Pk = 0xACEFACE2;
    uint256 voter3Pk = 0xACEFACE3;
    uint256 voter4Pk = 0xACEFACE4;
    uint256 otherPk  = 0xFADED;

    address admin1 = vm.addr(admin1Pk);   // Derive public addresses from private keys
    address admin2 = vm.addr(admin2Pk);
    address agent = vm.addr(agentPk);
    address voter1 = vm.addr(voter1Pk);
    address voter2 = vm.addr(voter2Pk);
    address voter3 = vm.addr(voter3Pk);
    address voter4 = vm.addr(voter4Pk);
    address other = vm.addr(otherPk);
    address zeroAddr = AddrZero;

    string constant url = 'https://domain.io/dir1/{id}.json';

    VaultSpy vault;
    ICrt crt;
    ICrt multiToken;
    IRevMgr revMgr;
    IInstRevMgr instRevMgr;
    IEarnDateMgr earnDateMgr;
    IBalanceMgr balanceMgr;
    IBoxMgr boxMgr;
    IXferMgr xferMgr;

    address vaultAddr;
    address crtAddr;
    address multiTokenAddr;
    address revMgrAddr;
    address instRevMgrAddr;
    address earnDateMgrAddr;
    address balanceMgrAddr;
    address boxMgrAddr;
    address xferMgrAddr;

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

    Erc20Test tokenUsdc = new Erc20Test('USDC');
    Erc20Test tokenEurc = new Erc20Test('EURC');
    address usdcAddr = address(tokenUsdc);
    address eurcAddr = address(tokenEurc);

    TI.TokenInfo tokenInfoUsdc = _makeTokenInfo('USDC', usdcAddr, TI.TokenType.Erc20, 0);
    TI.TokenInfo tokenInfoEurc = _makeTokenInfo('EURC', eurcAddr, TI.TokenType.Erc20, 0);
    TI.TokenInfo tokenInfoMulti;
    TI.TokenInfo tokenInfoCrt;
    TI.TokenInfo tokenInfoEth = _makeTokenInfo('ETH', zeroAddr, TI.TokenType.NativeCoin, 0);

    address dropAddrE = AddrZero;
    address dropAddr1;
    address dropAddr2;
    address dropAddr3;

    uint unitRev1 = 200_000;
    uint unitRev2 = 300_000;
    uint unitRev3 = 600_000;
    uint unitRev4 = 250_000;

    // uint constant ccyScaleFactor = 1_000_000; // $9.123`456 USDC represented as 9,123,456
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
        // Set proxies
        vault = (new VaultSpyProxyDeployer()).
            createProxy((new VaultSpyLogicDeployer()).deployLogic(), creator, NoReqId, 2, _createRoles());

        xferMgr = (new XferMgrProxyDeployer()).
            createProxy((new XferMgrLogicDeployer()).deployLogic(), creator, NoReqId);

        crt = (new CrtProxyDeployer()).
            createProxy((new CrtLogicDeployer()).deployLogic(), creator, NoReqId, url);

        multiToken = (new CrtProxyDeployer()).
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

        // Set addresses
        vaultAddr = address(vault);
        xferMgrAddr = address(xferMgr);
        crtAddr = address(crt);
        multiTokenAddr = address(multiToken);
        revMgrAddr = address(revMgr);
        instRevMgrAddr = address(instRevMgr);
        earnDateMgrAddr = address(earnDateMgr);
        balanceMgrAddr = address(balanceMgr);
        boxMgrAddr = address(boxMgr);

        _setContracts(balanceMgr);
        _setContracts(boxMgr);
        _setContracts(crt);
        _setContracts(multiToken);
        _setContracts(earnDateMgr);
        _setContracts(instRevMgr);
        _setContracts(revMgr);
        _setContracts(xferMgr);
        _setContracts(vault);

        _labelAddresses();

        tokenInfoCrt = _makeTokenInfo('CRT', crtAddr, TI.TokenType.Erc1155Crt, 7);
        tokenInfoMulti = _makeTokenInfo('MULTI', multiTokenAddr, TI.TokenType.Erc1155, 9);

        _addBoxes();

        tokenUsdc.setApproval(dropAddr1, instRevMgrAddr, MAX_ALLOWANCE);
        tokenUsdc.setApproval(dropAddr2, instRevMgrAddr, MAX_ALLOWANCE);
        tokenUsdc.setApproval(dropAddr3, instRevMgrAddr, MAX_ALLOWANCE);

        tokenEurc.setApproval(dropAddr1, instRevMgrAddr, MAX_ALLOWANCE);
        tokenEurc.setApproval(dropAddr2, instRevMgrAddr, MAX_ALLOWANCE);
        tokenEurc.setApproval(dropAddr3, instRevMgrAddr, MAX_ALLOWANCE);

        uint40 seqNum = 0;
        UUID reqId = _newUuid();
        vault.approveMgr(++seqNum, reqId, usdcAddr, CU.InstRevMgr); // Allow transfers from vault

        reqId = _newUuid();
        vault.approveMgr(++seqNum, reqId, usdcAddr, CU.XferMgr);    // Allow transfers from vault

        reqId = _newUuid();
        vault.approveMgr(++seqNum, reqId, eurcAddr, CU.InstRevMgr); // Allow transfers from vault

        reqId = _newUuid();
        vault.approveMgr(++seqNum, reqId, eurcAddr, CU.XferMgr);    // Allow transfers from vault
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

    uint _counter = 0;
    function _newUuid() private returns (UUID) {
        ++_counter;
        return UUID.wrap(bytes16(uint128(_counter)));
    }

    function _labelAddresses() private {
        vm.label(creator, 'creator');
        vm.label(admin1, 'admin1');
        vm.label(admin2, 'admin2');
        vm.label(agent, 'agent');
        vm.label(voter1, 'voter1');
        vm.label(voter2, 'voter2');
        vm.label(voter3, 'voter3');
        vm.label(voter4, 'voter4');
        vm.label(other, 'other');

        vm.label(balanceMgrAddr, 'balanceMgr');
        vm.label(boxMgrAddr, 'boxMgr');
        vm.label(crtAddr, 'crt');
        vm.label(multiTokenAddr, 'multiToken');
        vm.label(earnDateMgrAddr, 'earnDateMgr');
        vm.label(instRevMgrAddr, 'instRevMgr');
        vm.label(revMgrAddr, 'revMgr');
        vm.label(xferMgrAddr, 'xferMgr');
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
        rr = new AC.RoleRequest[](5);
        rr[0] = AC.RoleRequest({ account: admin1, add: true, role: AC.Role.Admin, __gap: Util.gap5() });
        rr[1] = AC.RoleRequest({ account: agent,  add: true, role: AC.Role.Agent, __gap: Util.gap5() });
        rr[2] = AC.RoleRequest({ account: voter1, add: true, role: AC.Role.Voter, __gap: Util.gap5() });
        rr[3] = AC.RoleRequest({ account: voter2, add: true, role: AC.Role.Voter, __gap: Util.gap5() });
        rr[4] = AC.RoleRequest({ account: voter3, add: true, role: AC.Role.Voter, __gap: Util.gap5() });
    }

    function _makeTokenInfo(string memory tokSym, address tokAddr, TI.TokenType tokType, uint tokenId) private pure
        returns(TI.TokenInfo memory)
    {
        return TI.TokenInfo({ tokSym: tokSym, tokAddr: tokAddr, tokenId: tokenId, tokType: tokType });
    }

    function _addBoxes() private {
        // Add Boxes
        boxMgr.addBoxLogic(NoSeqNum, NoReqId, 10, (new BoxLogicDeployer()).deployLogic());
        address[] memory spenders = new address[](2);
        spenders[0] = address(instRevMgr);  // For box => vault
        spenders[1] = address(vault);       // For FixDeposit proposals
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

    function test_Vault_initialize() public {
        uint quorum;
        AC.RoleRequest[] memory roleRequests;
        // Attempt to initialize again; revert as not allowed
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        vault.initialize(creator, NoReqId, quorum, roleRequests);
    }

    function test_Vault_upgrade() public {
        // Deploy a mock upgraded logic
        address newLogic = address(new VaultLatest());
        assertNotEq(newLogic, zeroAddr);

        // Upgrade access denied
        uint40 seqNum = vault.getSeqNum(creator);
        UUID reqId = _newUuid();
        UUID reqIdStage = _newUuid();
        vm.prank(creator);
        vault.preUpgrade(seqNum, reqId, reqIdStage);
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(AC.AccessDenied.selector, other));
        UUPSUpgradeable(vault).upgradeToAndCall(address(newLogic), '');

        // Upgrade via UUPS with an empty initData
        vm.expectEmit();
        emit IERC1967.Upgraded(newLogic);
        vm.prank(creator);
        UUPSUpgradeable(vault).upgradeToAndCall(address(newLogic), '');

        // Verify
        assertEq(vault.getVersion(), 999);      // New behavior
        assertEq(vault.getProp(0).pid, 0);  // Old behavior
    }

    // Vault is initialized with roles before this test
    function test_Vault_initial_state() public {
        vm.startPrank(other);
        assertEq(vault.getQuorum(), 2, 'getQuorum');
        assertEq(vault.getNonce(other), 0, 'getNonce other');
        assertEq(vault.getNonce(voter1), 1, 'getNonce voter');
        assertEq(vault.getLastPropId(), 0, 'getLastPropId');
        assertEq(vault.getProp(0).pid, 0, 'getProp');
        assertEq(uint(vault.getPropStatus(0)), uint(IVault.PropStatus.NoProp), 'getStatus');
        assertEq(vault.getRoleRequests(0).length, 0, 'getRoleRequests');
        (address[] memory voters, IVault.Vote[] memory votes) = vault.getVotes(0);
        assertEq(voters.length, 3, 'voters length');
        assertEq(voters[0], voter1, 'voter1');
        assertEq(voters[1], voter2, 'voter2');
        assertEq(voters[2], voter3, 'voter3');
        assertEq(votes.length, 3, 'votes length');
        assertEq(uint(votes[0]), uint(IVault.Vote.None), 'vote 0');
        assertEq(uint(votes[1]), uint(IVault.Vote.None), 'vote 1');
        assertEq(uint(votes[2]), uint(IVault.Vote.None), 'vote 2');

        ARI.AccountInfo[] memory infos = vault.getAccountInfos();
        assertEq(infos.length, 5, 'getAccountRoles'); // admin, agent, voter x 3

        // Removed due to size limit
        // (string memory name, string memory version, uint256 chainId, address verifier) = vault.getEip712Domain();
        // assertEq(name, 'Vault', 'name');
        // assertEq(version, '10', 'version');
        // assertEq(chainId, block.chainid, 'chainId');
        // assertEq(verifier, vaultAddr, 'verifier');

        console2.log('Get manager contracts');
        assertEq(vault.getContract(CU.Vault), vaultAddr, 'Vault');
        assertEq(vault.getContract(CU.BalanceMgr), balanceMgrAddr, 'BalanceMgr');
        assertEq(vault.getContract(CU.BoxMgr), boxMgrAddr, 'BoxMgr');
        assertEq(vault.getContract(CU.EarnDateMgr), earnDateMgrAddr, 'EarnDateMgr');
        assertEq(vault.getContract(CU.RevMgr), revMgrAddr, 'RevMgr');
        assertEq(vault.getContract(CU.InstRevMgr), instRevMgrAddr, 'InstRevMgr');
        assertEq(vault.getContract(CU.XferMgr), xferMgrAddr, 'XferMgr');
    }

    function test_Vault_IRoleMgr() public {
        vm.startPrank(other);

        // Verify roles created during setup via `_createRoles`
        _verifyRoles(false, false);
    }

    function _verifyRoles(bool hasVoter4, bool hasAdmin2) private view {
        assertEq(uint(vault.getRole(other)), uint(AC.Role.None), 'other');
        assertEq(uint(vault.getRole(admin1)), uint(AC.Role.Admin), 'admin1');
        assertEq(uint(vault.getRole(admin2)), uint(hasAdmin2 ? AC.Role.Admin : AC.Role.None), 'admin2');
        assertEq(uint(vault.getRole(agent)),  uint(AC.Role.Agent), 'agent');
        assertEq(uint(vault.getRole(voter1)), uint(AC.Role.Voter), 'voter1');
        assertEq(uint(vault.getRole(voter2)), uint(AC.Role.Voter), 'voter2');
        assertEq(uint(vault.getRole(voter3)), uint(AC.Role.Voter), 'voter3');
        assertEq(uint(vault.getRole(voter4)), uint(hasVoter4 ? AC.Role.Voter : AC.Role.None), 'voter4');
    }

    function test_Vault_IPausable() public {
        uint40 seqNum = vault.getSeqNum(other);
        UUID reqId = _newUuid();

        console2.log('pause; Fail, access control');
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(AC.AccessDenied.selector, other));
        vault.pause(NoSeqNum, NoReqId, true);
        assertFalse(vault.paused());

        console2.log('pause; Success, enabled');
        vm.expectEmit();
        emit IPausable.Paused(true, admin1);
        vm.prank(admin1);
        vault.pause(seqNum, reqId, true);
        assertTrue(vault.paused());

        console2.log('Call a pausable function; fail - paused');
        vm.expectRevert(abi.encodeWithSelector(IPausable.ContractPaused.selector));
        vm.prank(agent);
        vault.createQuorumProp(NoSeqNum, NoReqId, 1, 3);

        console2.log('pause; Success, disabled');
        vm.expectEmit();
        emit IPausable.Paused(false, admin1);
        vm.prank(admin1);
        vault.pause(NoSeqNum, NoReqId, false);
        assertFalse(vault.paused());
    }

    function getPrivateKey(address account) public view returns(uint256) {
        if (account == admin1) return  admin1Pk;
        if (account == agent)  return  agentPk;
        if (account == voter1) return voter1Pk;
        if (account == voter2) return voter2Pk;
        if (account == voter3) return voter3Pk;
        if (account == other)  return  otherPk;
        revert('Unexpected account');
    }

    function test_Vault_offChainSig() public view {
        uint pid = 1;
        bool approve = true;
        uint8 v = 0; bytes32 r = 0; bytes32 s = 0;
        uint nonce;
        uint expiredAt = block.timestamp + 1 days;

        console2.log('Fail wrong private key');
        address signerActual = voter1;
        nonce = vault.getNonce(signerActual);
        bytes32 digest = vault.getVoteDigest(pid, expiredAt, nonce, approve, signerActual);
        (v, r, s) = vm.sign(voter2Pk, digest);
        address signerRecovered = ECDSA.recover(digest, v, r, s);
        assertEq(signerRecovered, voter2, 'signerRecovered');

        console2.log('Success voter1');
        signerActual = voter1;
        nonce = vault.getNonce(signerActual);
        digest = vault.getVoteDigest(pid, expiredAt, nonce, approve, signerActual);
        (v, r, s) = vm.sign(getPrivateKey(signerActual), digest);
        signerRecovered = ECDSA.recover(digest, v, r, s);
        assertEq(signerRecovered, voter1, 'signerRecovered');

        console2.log('Success agent');
        signerActual = agent;
        nonce = vault.getNonce(signerActual);
        digest = vault.getVoteDigest(pid, expiredAt, nonce, approve, signerActual);
        (v, r, s) = vm.sign(agentPk, digest);
        signerRecovered = ECDSA.recover(digest, v, r, s);
        assertEq(signerRecovered, agent, 'signerRecovered');
    }

    function _verifyProp(string memory when, uint pid, address creatorAddr, uint createdAt,
        uint expiredAt, uint yay, uint nay, uint quorum,
        IVault.PropType propType, IVault.PropStatus status, UUID eid) public view
    {
        console2.log(T.concat('Verify proposal ', when));
        IVault.Prop memory prop = vault.getProp(pid);
        assertEq(prop.pid, pid, 'pid');
        assertEq(prop.creator, creatorAddr, 'creator');
        assertEq(prop.createdAt, createdAt, 'createdAt');
        assertEq(prop.expiredAt, expiredAt, 'expiredAt');
        assertEq(prop.countYay, yay, 'countYay');
        assertEq(prop.countNay, nay, 'countNay');
        assertEq(prop.quorum, quorum, 'quorum');
        assertEq(uint(prop.propType), uint(propType), 'propType');
        assertEq(uint(prop.status), uint(status), 'status');
        _checkUuid(prop.eid, eid, 'eid');
    }

    function test_Vault_quorum_prop() public {
        uint pid = 0;
        uint futurePid = 0;
        uint expiredAt = block.timestamp;
        uint quorum1 = vault.getQuorum();
        uint quorum2 = quorum1 - 1;
        uint quorum = 1;

        // ----------
        // Create Proposal: Bad inputs
        // ----------
        console2.log('createQuorumProp; Fail, access control');
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(AC.AccessDenied.selector, other));
        vault.createQuorumProp(NoSeqNum, NoReqId, expiredAt, quorum);

        console2.log('createQuorumProp; Fail, paused');
        vm.prank(admin1);
        vault.pause(NoSeqNum, NoReqId, true); // Pause
        vm.expectRevert(abi.encodeWithSelector(IPausable.ContractPaused.selector));
        vm.prank(agent);
        vault.createQuorumProp(NoSeqNum, NoReqId, expiredAt, quorum);
        vm.prank(admin1);
        vault.pause(NoSeqNum, NoReqId, false); // Unpause

        uint40 seqNumA = 1; // Agent sequence number
        UUID reqId = _newUuid();
        console2.log('createQuorumProp; Fail, expired');
        expiredAt = block.timestamp - 1;
        vm.expectRevert(abi.encodeWithSelector(IVault.InvalidInput.selector, INVALID_PROP_EXPIRED));
        vm.prank(agent);
        vault.createQuorumProp(seqNumA, reqId, expiredAt, quorum);
        vm.prank(agent);
        assertEq(uint(vault.getCallResBySeqNum(seqNumA).rc), pid);
        expiredAt = block.timestamp + 10;

        console2.log('createQuorumProp; Fail, empty quorum');
        reqId = _newUuid();
        quorum = 0;
        vm.expectRevert(abi.encodeWithSelector(IVault.InvalidInput.selector, INVALID_QUORUM_PROP));
        vm.prank(agent);
        vault.createQuorumProp(seqNumA, reqId, expiredAt, quorum);
        vm.prank(agent);
        assertEq(uint(vault.getCallResBySeqNum(seqNumA).rc), pid);
        quorum = vault.getQuorum();

        console2.log('createQuorumProp; Fail, quorum unchanged');
        reqId = _newUuid();
        vm.expectRevert(abi.encodeWithSelector(IVault.InvalidInput.selector, INVALID_QUORUM_PROP));
        vm.prank(agent);
        vault.createQuorumProp(seqNumA, reqId, expiredAt, quorum);
        vm.prank(agent);
        assertEq(uint(vault.getCallResBySeqNum(seqNumA).rc), pid);

        console2.log('createQuorumProp; Fail, quorum > RoleLenMax');
        reqId = _newUuid();
        quorum = AC.RoleLenMax + 1;
        vm.expectRevert(abi.encodeWithSelector(IVault.InvalidInput.selector, INVALID_QUORUM_PROP));
        vm.prank(agent);
        vault.createQuorumProp(seqNumA, reqId, expiredAt, quorum);
        vm.prank(agent);
        assertEq(uint(vault.getCallResBySeqNum(seqNumA).rc), pid);

        console2.log('createQuorumProp; Fail, quorum > votersLen');
        reqId = _newUuid();
        quorum = 4;
        vm.expectRevert(abi.encodeWithSelector(IVault.InvalidInput.selector, INVALID_QUORUM_PROP));
        vm.prank(agent);
        vault.createQuorumProp(seqNumA, reqId, expiredAt, quorum);
        vm.prank(agent);
        assertEq(uint(vault.getCallResBySeqNum(seqNumA).rc), pid);

        // ----------
        // Create Proposal: Success
        // ----------
        // Proposal 1: Create + Withdraw
        // Proposal 2: Create
        UUID reqId1;
        for (uint i = 0; i < 2; ++i) {
            console2.log(T.concat('createQuorumProp; Success, i=', vm.toString(i)));
            pid = vault.getLastPropId() + 1;    // Next pid to be created
            futurePid = pid + 1;                // After the next pid
            reqId1 = reqId = _newUuid();
            vm.expectEmit();
            emit IVault.PropCreated(pid, reqId1, agent, true);
            vm.prank(agent);
            vault.createQuorumProp(seqNumA, reqId1, expiredAt, quorum2);
            vm.prank(agent);
            assertEq(uint(vault.getCallResBySeqNum(seqNumA).rc), pid);
            ++seqNumA;
            uint countYay;
            uint countNay;

            _verifyProp('before execution', pid, agent, block.timestamp, expiredAt, countYay, countNay,
                quorum2, IVault.PropType.Quorum, IVault.PropStatus.Sealed, reqId1);

            if (i == 1) break;

            // ----------
            // Verify withdrawProposal behavior
            // ----------
            console2.log(T.concat('withdrawProp; Fail, access control, i=', vm.toString(i)));
            vm.expectRevert(abi.encodeWithSelector(AC.AccessDenied.selector, other));
            vm.prank(other);
            vault.withdrawProp(NoSeqNum, NoReqId, pid);

            console2.log(T.concat('withdrawProp; Fail, uknown proposal, i=', vm.toString(i)));
            reqId = _newUuid();
            vm.prank(agent);
            vault.withdrawProp(seqNumA, reqId, futurePid);
            assertEq(uint(vault.getPropStatus(futurePid)), uint(IVault.PropStatus.NoProp), 'status');
            reqId = _newUuid();
            ++seqNumA;

            console2.log(T.concat('withdrawProp; Success, i=', vm.toString(i)));
            vm.expectEmit();
            emit IVault.PropWithdrawn(pid, reqId1, false);
            vm.prank(agent);
            vault.withdrawProp(seqNumA, reqId, pid);
            assertEq(uint(vault.getPropStatus(pid)), uint(IVault.PropStatus.Withdrawn), 'status');
            reqId = _newUuid();
            ++seqNumA;
            assertEq(seqNumA, vault.getSeqNum(agent), 'seqNum');

            console2.log(T.concat('withdrawProp; No effect, already withdrawn (duplicate call), i=', vm.toString(i)));
            vm.prank(agent);
            vault.withdrawProp(seqNumA, reqId, pid);
            assertEq(uint(vault.getPropStatus(pid)), uint(IVault.PropStatus.Withdrawn), 'status');
            assertEq(seqNumA + 1, vault.getSeqNum(agent), 'seqNum');
            reqId = _newUuid();
            ++seqNumA;
        }

        // ----------
        // Cast Vote Directly: Failure
        // ----------
        bool approve = true;
        address voter = other;
        pid = vault.getLastPropId();
        futurePid = pid + 1;

        console2.log('castVote; Fail, access control');
        vm.expectRevert(abi.encodeWithSelector(AC.AccessDenied.selector, other));
        vm.prank(other);
        vault.castVote(NoSeqNum, NoReqId, pid, approve);
        voter = voter1;

        console2.log('castVote; Fail, paused');
        uint40 seqNumV = vault.getSeqNum(voter); // Voter sequence number
        reqId = _newUuid();
        vm.prank(admin1);
        vault.pause(NoSeqNum, NoReqId, true); // Pause
        vm.expectRevert(abi.encodeWithSelector(IPausable.ContractPaused.selector));
        vm.prank(voter);
        vault.castVote(seqNumV, reqId, futurePid, approve);
        vm.prank(admin1);
        vault.pause(NoSeqNum, NoReqId, false); // Unpause

        console2.log('castVote; Fail, unknown prop');
        vm.prank(voter);
        vault.castVote(seqNumV, reqId, futurePid, approve);
        vm.prank(voter);
        ICallTracker.CallRes memory callRes = vault.getCallResBySeqNum(seqNumV);
        assertEq(uint(callRes.rc), uint(IVault.CastVoteRc.NoProp), 'rc');
        ++seqNumV;

        // ----------
        // Cast Vote Relay: Failure
        // ----------
        uint nonce; bytes32 digest; uint8 v; bytes32 r; bytes32 s;

        IVault.CastVoteRelayReq memory req = IVault.CastVoteRelayReq({ pid: pid,
            approve: approve, voter: voter, v: v, r: r, s: s, __gap: Util.gap5()
        });

        console2.log('castVoteRelay; Fail, access control');
        reqId = _newUuid();
        vm.expectRevert(abi.encodeWithSelector(AC.AccessDenied.selector, voter));
        vm.prank(voter);
        vault.castVoteRelay(seqNumV, reqId, req);

        console2.log('castVoteRelay; Fail, unknown prop');
        vm.prank(agent);
        req.pid = futurePid;
        vault.castVoteRelay(seqNumA, reqId, req);
        req.pid = pid;
        vm.prank(agent);
        callRes = vault.getCallResBySeqNum(seqNumA);
        assertEq(uint(callRes.rc), uint(IVault.CastVoteRc.NoProp), 'rc');
        reqId = _newUuid();
        ++seqNumA;

        // Vote prepared for voter1 but signed by voter2
        console2.log('castVoteRelay; Fail, signer != voter');
        nonce = vault.getNonce(voter2);
        digest = vault.getVoteDigest(pid, expiredAt, nonce, approve, voter1);
        (v, r, s) = vm.sign(getPrivateKey(voter2), digest);
        req.voter = voter1;
        req.v = v;
        req.r = r;
        req.s = s;
        vm.expectEmit();
        emit IVault.SignerErr(pid, approve, voter1, nonce, expiredAt, voter2);
        vm.prank(agent);
        vault.castVoteRelay(seqNumA, reqId, req);
        vm.prank(agent);
        callRes = vault.getCallResBySeqNum(seqNumA);
        assertEq(uint(callRes.rc), uint(IVault.CastVoteRc.SigSigner), 'rc');
        assertEq(uint(callRes.lrc), uint(IVault.Vote.None), 'lrc');
        assertEq(uint(vault.getPropStatus(pid)), uint(IVault.PropStatus.Sealed), 'status');
        reqId = _newUuid();
        ++seqNumA;

        console2.log('castVoteRelay; Fail, signer does not have voter role');
        nonce = vault.getNonce(admin1);
        digest = vault.getVoteDigest(pid, expiredAt, nonce, approve, admin1);
        (v, r, s) = vm.sign(getPrivateKey(admin1), digest);
        req.voter = admin1;
        req.v = v;
        req.r = r;
        req.s = s;
        vm.prank(agent);
        vault.castVoteRelay(seqNumA, reqId, req);
        vm.prank(agent);
        callRes = vault.getCallResBySeqNum(seqNumA);
        assertEq(uint(callRes.rc), uint(IVault.CastVoteRc.SigRole), 'rc');
        assertEq(uint(callRes.lrc), uint(IVault.Vote.None), 'lrc');
        assertEq(uint(vault.getPropStatus(pid)), uint(IVault.PropStatus.Sealed), 'status');
        reqId = _newUuid();
        ++seqNumA;

        // ----------
        // Reject proposal when vote uncast < quorum
        // ----------
        approve = false;
        voter = voter1;
        reqId = _newUuid();
        for (uint i = 0; i < 2; ++i) {
            string memory suffix;
            if (i == 0) suffix = '(initial)';
            else if (i == 1) suffix = '(duplicate seqNum, noop)';
            else if (i == 2) suffix = '(vote again, noop)';
            console2.log(T.concat('castVote; Success, Nay 1 of 2 to reject ', suffix));
            if (i == 0) {
                vm.expectEmit();
                emit IVault.PropVoted(pid, reqId1, voter, approve, IVault.Vote.None);
            }
            IVault.Prop memory propPre = vault.getProp(pid);
            IVault.CastVoteRc voteRc = i <= 1 ? IVault.CastVoteRc.Success : IVault.CastVoteRc.NoChange;
            uint voteChange = i == 0 ? 1 : 0;
            vm.prank(voter);
            vault.castVote(seqNumV, reqId, pid, approve);

            vm.prank(voter);
            callRes = vault.getCallResBySeqNum(seqNumV);
            assertEq(uint(callRes.rc), uint(voteRc), 'rc');

            IVault.Prop memory propPost = vault.getProp(pid);
            assertEq(uint(propPost.status), uint(IVault.PropStatus.Sealed), 'status 1');
            assertEq(propPost.countNay, propPre.countNay + voteChange, 'countNay');

            assertEq(uint(vault.getPropStatus(pid)), uint(IVault.PropStatus.Sealed), 'status 2');

            assertEq(seqNumV + 1, vault.getSeqNum(voter), 'seqNum');
        }
        ++seqNumV;
        reqId = _newUuid();

        console2.log('castVote; Fail, seqNum > expected');
        vm.expectRevert(abi.encodeWithSelector(ICallTracker.SeqNumGap.selector, seqNumV, seqNumV+1, voter));
        vm.prank(voter);
        vault.castVote(seqNumV+1, reqId, pid, approve);

        console2.log('castVote; Success, Nay 2 of 2 to reject (insufficient pending)');
        voter = voter2;
        vm.expectEmit();
        emit IVault.PropVoted(pid, reqId1, voter, approve, IVault.Vote.Nay);
        vm.prank(voter);
        vault.castVote(NoSeqNum, NoReqId, pid, approve);
        assertEq(uint(vault.getPropStatus(pid)), uint(IVault.PropStatus.Rejected), 'status');

        // ----------
        // Create a new proposal
        // ----------
        console2.log('createQuorumProp; Success to try again');
        expiredAt = block.timestamp + 10;
        pid = vault.getLastPropId() + 1;    // Next pid to be created
        futurePid = pid + 1;                // After the next pid
        seqNumA = vault.getSeqNum(agent);
        reqId = _newUuid();
        reqId1 = reqId;
        vm.expectEmit();
        emit IVault.PropCreated(pid, reqId1, agent, true);
        for (uint i = 0; i < 2; ++i) {
            if (i == 1) console2.log('createQuorumProp; Duplicate call, noop');
            vm.prank(agent);
            vault.createQuorumProp(seqNumA, reqId1, expiredAt, quorum2);
            vm.prank(agent);
            assertEq(uint(vault.getCallResBySeqNum(seqNumA).rc), pid);
            assertEq(seqNumA + 1, vault.getSeqNum(agent), 'seqNum');
        }
        ++seqNumA;
        reqId = _newUuid();

        for (uint i = 0; i < 2; ++i) {
            console2.log(T.concat('castVote; Success, voter signs, i=', vm.toString(i)));
            assertEq(vault.getQuorum(), quorum1, 'getQuorum no change');
            approve = i > 0;
            uint40 seqNum;
            address caller;
            if (i == 0) {
                voter = voter1;
                caller = voter;
            } else {
                voter = voter2;
                caller = agent;
            }
            seqNum = vault.getSeqNum(caller);
            IVault.Vote voteExpect = approve ? IVault.Vote.Yay : IVault.Vote.Nay;
            IVault.Vote propResult = i == 0 ? IVault.Vote.None : IVault.Vote.Yay;
            vm.expectEmit();
            emit IVault.PropVoted(pid, reqId1, voter, approve, propResult);
            bool isQuorum = i == 1;
            if (isQuorum) {
                vm.expectEmit();
                emit AC.QuorumChanged(quorum1, quorum2);
                vm.expectEmit();
                emit IVault.PropExecuted(pid, reqId1);
            }
            _emitReqAck(caller, seqNum, reqId, 0, uint16(voteExpect), 0, false);
            uint statusExpect = uint(isQuorum ? IVault.PropStatus.Executed : IVault.PropStatus.Sealed);
            if (i == 0) {
                vm.prank(caller);
                vault.castVote(seqNum, reqId, pid, approve);
            } else {
                nonce = vault.getNonce(voter);
                digest = vault.getVoteDigest(pid, expiredAt, nonce, approve, voter);
                (v, r, s) = vm.sign(getPrivateKey(voter), digest);
                req.pid = pid;
                req.approve = approve;
                req.voter = voter;
                req.v = v;
                req.r = r;
                req.s = s;
                vm.prank(caller);
                vault.castVoteRelay(seqNum, reqId, req);
            }
            vm.prank(caller);
            callRes = vault.getCallResBySeqNum(seqNum);
            assertEq(uint(callRes.rc), uint(IVault.CastVoteRc.Success), 'rc');
            assertEq(uint(callRes.lrc), uint(voteExpect), 'lrc');
            assertEq(uint(vault.getPropStatus(pid)), statusExpect, 'status');

            if (i > 0) continue;

            console2.log(T.concat('castVote; Fail, duplicate vote, i=', vm.toString(i)));
            reqId = _newUuid();
            seqNum = vault.getSeqNum(voter);
            vm.prank(voter);
            vault.castVote(seqNum, reqId, pid, approve);
            vm.prank(voter);
            callRes = vault.getCallResBySeqNum(seqNum);
            assertEq(uint(callRes.rc), uint(IVault.CastVoteRc.NoChange), 'rc');
            assertEq(uint(callRes.lrc), uint(voteExpect), 'lrc');
            ++seqNum;
            reqId = _newUuid();

            console2.log(T.concat('castVote; Success, change Nay to Yay vote, i=', vm.toString(i)));
            approve = true;
            vm.prank(voter);
            vault.castVote(seqNum, reqId, pid, approve);
            vm.prank(voter);
            callRes = vault.getCallResBySeqNum(seqNum);
            assertEq(uint(callRes.rc), uint(IVault.CastVoteRc.Success), 'rc');
            assertEq(uint(callRes.lrc), uint(IVault.Vote.Yay), 'lrc');
            assertEq(uint(vault.getPropStatus(pid)), statusExpect, 'status');
            ++seqNum;
            reqId = _newUuid();
        }
        console2.log('castVote; post-execution');
        assertEq(vault.getQuorum(), quorum2, 'getQuorum');

        _verifyProp('after execution', pid, agent, block.timestamp, expiredAt, quorum1, 0, quorum2,
            IVault.PropType.Quorum, IVault.PropStatus.Executed, reqId1);

        console2.log('createQuorumProp; Create a proposal, expire, then vote');
        expiredAt = block.timestamp + 1 days;
        pid = vault.getLastPropId() + 1;    // Next pid to be created
        reqId = _newUuid();
        reqId1 = reqId;
        seqNumA = vault.getSeqNum(agent);
        vm.prank(agent);
        vault.createQuorumProp(seqNumA, reqId, expiredAt, quorum1);
        vm.prank(agent);
        assertEq(uint(vault.getCallResBySeqNum(seqNumA).rc), pid);
        vm.warp(expiredAt); // Move time forward to the expiration
        vm.expectEmit();
        emit IVault.PropExpired(pid, reqId1, expiredAt);
        seqNumV = vault.getSeqNum(voter1);
        reqId = _newUuid();
        vm.prank(voter1);
        vault.castVote(seqNumV, reqId, pid, approve);
        vm.prank(voter1);
        callRes = vault.getCallResBySeqNum(seqNumV);
        assertEq(uint(callRes.rc), uint(IVault.CastVoteRc.Status), 'rc');
        assertEq(uint(callRes.lrc), uint(IVault.Vote.None), 'lrc');

        assertEq(uint(vault.getPropStatus(pid)), uint(IVault.PropStatus.Expired), 'status');
    }

    function _emitReqAck(address caller, uint40 seqNum, UUID reqId, uint16 rc, uint16 lrc, uint16 count,
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
        emit ICallTracker.ReqAck(reqId, caller, seqNum, cr, replay);
    }

    function test_Vault_role_prop() public {
        uint pid = 0;
        uint expiredAt = block.timestamp;
        uint quorum = vault.getQuorum();
        AC.RoleRequest[] memory requests = new AC.RoleRequest[](1);
        requests[0].account = admin2;
        requests[0].role = AC.Role.Admin;

        // ----------
        // Create Proposal: Bad inputs
        // ----------
        console2.log('createRoleProp; Fail, access control');
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(AC.AccessDenied.selector, other));
        vault.createRoleProp(NoSeqNum, NoReqId, expiredAt, requests);

        console2.log('createRoleProp; Fail, paused');
        vm.prank(admin1);
        vault.pause(NoSeqNum, NoReqId, true);
        vm.expectRevert(abi.encodeWithSelector(IPausable.ContractPaused.selector));
        vm.prank(agent);
        vault.createRoleProp(NoSeqNum, NoReqId, expiredAt, requests);
        vm.prank(admin1);
        vault.pause(NoSeqNum, NoReqId, false);

        console2.log('createRoleProp; Fail, expired');
        vm.expectRevert(abi.encodeWithSelector(IVault.InvalidInput.selector, INVALID_PROP_EXPIRED));
        expiredAt = block.timestamp - 1;
        vm.prank(agent);
        vault.createRoleProp(NoSeqNum, NoReqId, expiredAt, requests);
        vm.prank(agent);
        assertEq(uint(vault.getCallResBySeqNum(NoSeqNum).rc), pid);
        expiredAt = block.timestamp + 10;

        console2.log('createRoleProp; Fail, empty requests');
        AC.RoleRequest[] memory requestsE;
        vm.expectRevert(abi.encodeWithSelector(IVault.InvalidInput.selector, INVALID_ROLE_PROP_LEN));
        vm.prank(agent);
        vault.createRoleProp(NoSeqNum, NoReqId, expiredAt, requestsE);
        vm.prank(agent);
        assertEq(uint(vault.getCallResBySeqNum(NoSeqNum).rc), pid);
        quorum = vault.getQuorum();

        console2.log('createRoleProp; Fail, requests > RoleLenMax');
        vm.expectRevert(abi.encodeWithSelector(IVault.InvalidInput.selector, INVALID_ROLE_PROP_LEN));
        requests = new AC.RoleRequest[](AC.RoleReqLenMax + 1);
        vm.prank(agent);
        vault.createRoleProp(NoSeqNum, NoReqId, expiredAt, requests);
        vm.prank(agent);
        assertEq(uint(vault.getCallResBySeqNum(NoSeqNum).rc), pid);

        console2.log('createRoleProp; Fail, request invalid address');
        vm.expectRevert(abi.encodeWithSelector(IVault.InvalidInput.selector, INVALID_ROLE_PROP_ITEM));
        requests = new AC.RoleRequest[](1);
        requests[0].account = zeroAddr;
        requests[0].role = AC.Role.Admin;
        vm.prank(agent);
        vault.createRoleProp(NoSeqNum, NoReqId, expiredAt, requests);
        vm.prank(agent);
        assertEq(uint(vault.getCallResBySeqNum(NoSeqNum).rc), pid);

        console2.log('createRoleProp; Fail, request invalid role');
        vm.expectRevert(abi.encodeWithSelector(IVault.InvalidInput.selector, INVALID_ROLE_PROP_ITEM));
        requests[0].account = admin2;
        requests[0].role = AC.Role.None;
        vm.prank(agent);
        vault.createRoleProp(NoSeqNum, NoReqId, expiredAt, requests);
        vm.prank(agent);
        assertEq(uint(vault.getCallResBySeqNum(NoSeqNum).rc), pid);

        // ----------
        // Create Proposal: Success
        // ----------

        // Create roles
        requests = new AC.RoleRequest[](2);
        requests[0] = AC.RoleRequest({ account: voter4, add: true, role: AC.Role.Voter, __gap: Util.gap5() });
        requests[1] = AC.RoleRequest({ account: admin2, add: true, role: AC.Role.Admin, __gap: Util.gap5() });
        pid = vault.getLastPropId() + 1;    // Next pid to be created
        uint40 seqNum = vault.getSeqNum(agent);
        UUID reqId = _newUuid();
        for (uint i = 0; i < 2; ++i) {
            string memory suffix = i == 0 ? '(initial)' : '(duplicate, noop)';
            console2.log(T.concat('createRoleProp; Success', suffix));
            if (i == 0) {
                vm.expectEmit();
                emit IVault.PropCreated(pid, reqId, agent, true);
            }
            vm.prank(agent);
            vault.createRoleProp(seqNum, reqId, expiredAt, requests);
            vm.prank(agent);
            assertEq(uint(vault.getCallResBySeqNum(seqNum).rc), pid);
            assertEq(seqNum + 1, vault.getSeqNum(agent), 'seqNum');
        }
        ++seqNum;

        _verifyProp('before execution', pid, agent, block.timestamp, expiredAt, 0, 0, 0,
            IVault.PropType.Role, IVault.PropStatus.Sealed, reqId);

        console2.log('Verify roles before execution');
        _verifyRoles(false, false);

        // ----------
        // Cast Votes: Success
        // ----------
        bool approve = true;
        _castVote1(pid, reqId, approve);

        console2.log('castVote voter2 Yay - Trigger execution');
        address voter = voter2;
        vm.expectEmit();
        emit IVault.PropVoted(pid, reqId, voter, approve, IVault.Vote.Yay);
        vm.expectEmit();
        emit ARI.RoleChanged(true, AC.Role.Voter, voter4);
        vm.expectEmit();
        emit AC.AdminAddPending(admin2);
        vm.expectEmit();
        emit IVault.PropExecuted(pid, reqId);
        vm.prank(voter);
        vault.castVote(NoSeqNum, NoReqId, pid, approve);
        assertEq(uint(vault.getPropStatus(pid)), uint(IVault.PropStatus.Executed), 'status');

        _verifyProp('after execution', pid, agent, block.timestamp, expiredAt, 2, 0, 0,
            IVault.PropType.Role, IVault.PropStatus.Executed, reqId);

        console2.log('Verify roles after execution');
        _verifyRoles(true, false);

        // ----------
        // Accept admin role (2 step grant)
        // ----------
        console2.log('acceptAdmin; Fail, no admin pending for account');
        vm.expectRevert(abi.encodeWithSelector(ARI.AccountHasRole.selector, other, AC.Role.None));
        vm.prank(other);
        vault.acceptAdmin(NoSeqNum, NoReqId, true);

        console2.log('acceptAdmin; Success');
        vm.expectEmit();
        emit ARI.RoleChanged(true, AC.Role.Admin, admin2);
        vm.prank(admin2);
        vault.acceptAdmin(NoSeqNum, NoReqId, true);

        console2.log('Verify roles after accepting admin2');
        _verifyRoles(true, true);
    }

    function test_Vault_fixDeposit_prop() public {
        uint pid;
        uint expiredAt = block.timestamp + 10;
        IVault.FixDepositReq[] memory fdrs = new IVault.FixDepositReq[](1);
        IVault.FixDepositReq memory fdr = fdrs[0];
        fdr.qty = 3;
        fdr.to = dropAddr2;
        fdr.instName = name1; // Related to `dropAddr1`
        fdr.ti.tokAddr = usdcAddr;
        fdr.ti.tokType = TI.TokenType.Erc20;
        UUID reqId = _newUuid();

        // ----------
        // Create Proposal: Bad inputs
        // ----------
        console2.log('createFixDepositProp; Fail, access control');
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(AC.AccessDenied.selector, other));
        vault.createFixDepositProp(NoSeqNum, reqId, expiredAt, fdrs);

        console2.log('createFixDepositProp; Fail, paused');
        vm.prank(admin1);
        vault.pause(NoSeqNum, NoReqId, true);
        vm.expectRevert(abi.encodeWithSelector(IPausable.ContractPaused.selector));
        vm.prank(agent);
        vault.createFixDepositProp(NoSeqNum, reqId, expiredAt, fdrs);
        vm.prank(admin1);
        vault.pause(NoSeqNum, NoReqId, false);

        console2.log('createFixDepositProp; Fail, expired');
        expiredAt = block.timestamp - 1;
        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(IVault.InvalidInput.selector, INVALID_PROP_EXPIRED));
        vault.createFixDepositProp(NoSeqNum, reqId, expiredAt, fdrs);
        vm.prank(agent);
        assertEq(uint(vault.getCallResBySeqNum(NoSeqNum).rc), pid);
        expiredAt = block.timestamp + 10;

        console2.log('createFixDepositProp; Fail, empty qty');
        fdr.qty = 0;
        vm.expectRevert(abi.encodeWithSelector(IVault.InvalidInput.selector, INVALID_FIX_DEP_PROP_MISC));
        vm.prank(agent);
        vault.createFixDepositProp(NoSeqNum, reqId, expiredAt, fdrs);
        vm.prank(agent);
        assertEq(uint(vault.getCallResBySeqNum(NoSeqNum).rc), pid);
        fdr.qty = 3;

        console2.log('createFixDepositProp; Fail, empty to');
        fdr.to = zeroAddr;
        vm.expectRevert(abi.encodeWithSelector(IVault.InvalidInput.selector, INVALID_FIX_DEP_PROP_MISC));
        vm.prank(agent);
        vault.createFixDepositProp(NoSeqNum, reqId, expiredAt, fdrs);
        vm.prank(agent);
        assertEq(uint(vault.getCallResBySeqNum(NoSeqNum).rc), pid);
        fdr.to = dropAddr2;

        console2.log('createFixDepositProp; Fail, bad tokType');
        vm.expectRevert(abi.encodeWithSelector(IVault.InvalidInput.selector, INVALID_FIX_DEP_PROP_TOK_TYPE));
        fdr.ti.tokType = TI.TokenType.Count;
        vm.prank(agent);
        vault.createFixDepositProp(NoSeqNum, reqId, expiredAt, fdrs);
        vm.prank(agent);
        assertEq(uint(vault.getCallResBySeqNum(NoSeqNum).rc), pid);
        fdr.ti.tokType = TI.TokenType.Erc20;

        console2.log('createFixDepositProp; Fail, empty tokAddr');
        fdr.ti.tokAddr = zeroAddr;
        vm.expectRevert(abi.encodeWithSelector(IVault.InvalidInput.selector, INVALID_FIX_DEP_PROP_MISC));
        vm.prank(agent);
        vault.createFixDepositProp(NoSeqNum, reqId, expiredAt, fdrs);
        vm.prank(agent);
        assertEq(uint(vault.getCallResBySeqNum(NoSeqNum).rc), pid);
        fdr.ti.tokAddr = usdcAddr;

        console2.log('createFixDepositProp; Fail, empty name');
        fdr.instName = '';
        vm.expectRevert(abi.encodeWithSelector(IVault.InvalidInput.selector, INVALID_FIX_DEP_PROP_NO_BOX));
        vm.prank(agent);
        vault.createFixDepositProp(NoSeqNum, reqId, expiredAt, fdrs);
        vm.prank(agent);
        assertEq(uint(vault.getCallResBySeqNum(NoSeqNum).rc), pid);
        fdr.instName = name1;
        fdr.ti = tokenInfoUsdc;

        // ----------
        // Create Proposal
        // ----------
        uint dropAddr1InitBal = 4;
        uint dropAddr2InitBal = 1;
        tokenUsdc.mint(dropAddr1, dropAddr1InitBal + fdr.qty);
        tokenUsdc.mint(dropAddr2, dropAddr2InitBal);

        pid = vault.getLastPropId() + 1;    // Next pid to be created
        uint40 seqNum = vault.getSeqNum(agent);
        reqId = _newUuid();
        for (uint i = 0; i < 2; ++i) {
            string memory suffix = i == 0 ? '(initial)' : '(duplicate, noop)';
            console2.log(T.concat('createFixDepositProp; Success', suffix));
            if (i == 0) {
                vm.expectEmit();
                emit IVault.PropCreated(pid, reqId, agent, true);
            }
            vm.prank(agent);
            vault.createFixDepositProp(seqNum, reqId, expiredAt, fdrs);
            vm.prank(agent);
            assertEq(uint(vault.getCallResBySeqNum(seqNum).rc), pid);
            assertEq(seqNum + 1, vault.getSeqNum(agent), 'seqNum');
        }
        ++seqNum;

        _verifyProp('before execution', pid, agent, block.timestamp, expiredAt, 0, 0, 0,
            IVault.PropType.FixDeposit, IVault.PropStatus.Sealed, reqId);

        console2.log('Verify proposal details before execution');
        IVault.FixDepositReq[] memory storedReqs = vault.getFixDepositReqs(pid);
        IVault.FixDepositReq memory storedReq = storedReqs[0];
        assertEq(storedReq.to, fdr.to, 'to');
        assertEq(storedReq.qty, fdr.qty, 'qty');
        assertEq(storedReq.instName, fdr.instName, 'instName');
        assertEq(storedReq.instNameKey, String.toBytes32Mem(fdr.instName), 'instNameKey');
        assertEq(storedReq.ti.tokAddr, fdr.ti.tokAddr, 'ti');

        // ----------
        // Approve proposal (Cast Votes)
        // ----------
        bool approve = true;
        _castVote1(pid, reqId, approve);

        console2.log('castVote voter2 Yay - Trigger execution');
        address voter = voter2;
        vm.expectEmit();
        emit IVault.PropVoted(pid, reqId, voter, approve, IVault.Vote.Yay);
        vm.expectEmit();
        emit IERC20.Transfer(dropAddr1, dropAddr2, fdr.qty);
        vm.expectEmit();
        emit IVault.PropExecuted(pid, reqId);
        vm.prank(voter);
        vault.castVote(NoSeqNum, NoReqId, pid, approve);
        assertEq(uint(vault.getPropStatus(pid)), uint(IVault.PropStatus.Executed), 'status');

        _verifyProp('after execution', pid, agent, block.timestamp, expiredAt, 2, 0, 0,
            IVault.PropType.FixDeposit, IVault.PropStatus.Executed, reqId);

        console2.log('Verify state after execution');
        assertEq(tokenUsdc.balanceOf(dropAddr1), dropAddr1InitBal, 'balanceOf 1');
        assertEq(tokenUsdc.balanceOf(dropAddr2), dropAddr2InitBal + fdr.qty, 'balanceOf 2');
    }

    function test_Vault_instRev_prop() public {
        uint pid;
        uint expiredAt = block.timestamp;
        address ccyAddr = usdcAddr;
        bool correction = false;

        // ----------
        // Create Proposal: Bad inputs
        // ----------
        console2.log('createInstRevProp; Fail, access control');
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(AC.AccessDenied.selector, other));
        vault.createInstRevProp(NoSeqNum, NoReqId, expiredAt, ccyAddr, correction);

        console2.log('createInstRevProp; Fail, paused');
        vm.prank(admin1);
        vault.pause(NoSeqNum, NoReqId, true);
        vm.expectRevert(abi.encodeWithSelector(IPausable.ContractPaused.selector));
        vm.prank(agent);
        vault.createInstRevProp(NoSeqNum, NoReqId, expiredAt, ccyAddr, correction);
        vm.prank(admin1);
        vault.pause(NoSeqNum, NoReqId, false);

        console2.log('createInstRevProp; Fail, expired');
        expiredAt = block.timestamp - 1;
        vm.expectRevert(abi.encodeWithSelector(IVault.InvalidInput.selector, INVALID_PROP_EXPIRED));
        vm.prank(agent);
        vault.createInstRevProp(NoSeqNum, NoReqId, expiredAt, ccyAddr, correction);
        vm.prank(agent);
        assertEq(uint(vault.getCallResBySeqNum(NoSeqNum).rc), pid);
        expiredAt = block.timestamp + 10;

        console2.log('createInstRevProp; Fail, empty ccyAddr');
        ccyAddr = zeroAddr;
        vm.expectRevert(abi.encodeWithSelector(IVault.InvalidInput.selector, INVALID_INST_REV_PROP_CCY));
        vm.prank(agent);
        vault.createInstRevProp(NoSeqNum, NoReqId, expiredAt, ccyAddr, correction);
        vm.prank(agent);
        assertEq(uint(vault.getCallResBySeqNum(NoSeqNum).rc), pid);
        ccyAddr = usdcAddr;

        // ----------
        // Create Proposal
        // ----------

        pid = vault.getLastPropId() + 1;    // Next pid to be created
        uint40 seqNum = vault.getSeqNum(agent);
        UUID reqId1 = _newUuid();
        for (uint i = 0; i < 2; ++i) {
            string memory suffix = i == 0 ? '(initial)' : '(duplicate, noop)';
            console2.log(T.concat('createInstRevProp; Success', suffix));
            if (i == 0) {
                vm.expectEmit();
                emit IVault.PropCreated(pid, reqId1, agent, false);
            }
            vm.prank(agent);
            vault.createInstRevProp(seqNum, reqId1, expiredAt, ccyAddr, correction);
            vm.prank(agent);
            assertEq(uint(vault.getCallResBySeqNum(seqNum).rc), pid);
            assertEq(seqNum + 1, vault.getSeqNum(agent), 'seqNum');
        }
        ++seqNum;

        _verifyProp('before execution', pid, agent, block.timestamp, expiredAt, 0, 0, 0,
            IVault.PropType.InstRev, IVault.PropStatus.Pending, reqId1);

        assertEq(revMgr.getPropHdr(pid).pid, pid, 'revMgr pid'); // Ensure RevMgr called

        console2.log('castVote; Fail, proposal not sealed');
        bool approve = true;
        address voter = voter1;
        vm.prank(voter);
        vault.castVote(NoSeqNum, NoReqId, pid, approve);
        assertEq(uint(vault.getPropStatus(pid)), uint(IVault.PropStatus.Pending), 'status');

        // ----------
        // Seal proposal
        // ----------

        // Mock the call to `IRevMgr.propExecute` since it has a separate unit test
        ICallTracker.CallRes memory crMock;
        crMock.rc = uint16(IRevMgr.ExecRevRc.Done);
        crMock.lrc = 3;
        crMock.count = 100;
        bytes memory callRv = abi.encode(crMock);
        vm.mockCall(address(revMgr), abi.encodeWithSelector(IRevMgr.propFinalize.selector, pid), callRv);

        console2.log('sealInstRevProp; Fail, paused');
        vm.prank(admin1);
        vault.pause(NoSeqNum, NoReqId, true); // Pause
        vm.expectRevert(abi.encodeWithSelector(IPausable.ContractPaused.selector));
        vm.prank(agent);
        vault.sealInstRevProp(NoSeqNum, NoReqId, pid);
        vm.prank(admin1);
        vault.pause(NoSeqNum, NoReqId, false); // Unpause

        seqNum = vault.getSeqNum(agent);
        UUID reqId = _newUuid();
        for (uint i = 0; i < 2; ++i) {
            string memory suffix = i == 0 ? '(initial)' : '(duplicate, noop)';
            console2.log(T.concat('sealInstRevProp; Success', suffix));
            vm.prank(agent);
            vault.sealInstRevProp(seqNum, reqId, pid);
            vm.prank(agent);
            ICallTracker.CallRes memory cr = vault.getCallResBySeqNum(seqNum);
            console2.log(T.concat('getCallRes; cr.rc: ', vm.toString(cr.rc), ', cr.lrc: ', vm.toString(cr.lrc)));
            assertEq(cr.rc, uint16(IRevMgr.PropRevFinalRc.Ok), 'pfCode');
            assertEq(cr.lrc, uint16(IVault.PropStatus.Sealed), 'status');
            assertEq(seqNum + 1, vault.getSeqNum(agent), 'seqNum');
        }
        ++seqNum;

        // ----------
        // Approve proposal (Cast Votes)
        // ----------
        _approvePropNoExec(pid, reqId1, approve);

        // ----------
        // Execute Proposal
        // ----------
        console2.log('execInstRevProp; Fail, access control');
        vm.expectRevert(abi.encodeWithSelector(AC.AccessDenied.selector, voter));
        vm.prank(voter);
        vault.execInstRevProp(NoSeqNum, NoReqId, pid);

        console2.log('execInstRevProp; Fail, paused');
        vm.prank(admin1);
        vault.pause(NoSeqNum, NoReqId, true);
        vm.expectRevert(abi.encodeWithSelector(IPausable.ContractPaused.selector));
        vm.prank(agent);
        vault.execInstRevProp(NoSeqNum, NoReqId, pid);
        vm.prank(admin1);
        vault.pause(NoSeqNum, NoReqId, false);

        // Mock the call to `IRevMgr.propExecute` since it has a separate unit test
        crMock.rc = uint16(IRevMgr.ExecRevRc.Done);
        crMock.lrc = 3;
        crMock.count = 100;
        callRv = abi.encode(crMock);
        vm.mockCall(address(revMgr), abi.encodeWithSelector(IRevMgr.propExecute.selector, pid), callRv);

        seqNum = vault.getSeqNum(agent);
        reqId = _newUuid();
        for (uint i = 0; i < 2; ++i) {
            string memory suffix = i == 0 ? '(initial)' : '(duplicate, noop)';
            console2.log(T.concat('execInstRevProp; Success', suffix));
            if (i == 0) {
                vm.expectEmit();
                emit IVault.PropExecuted(pid, reqId1);
            }
            vm.prank(agent);
            vault.execInstRevProp(seqNum, reqId, pid);
            vm.prank(agent);
            ICallTracker.CallRes memory cr = vault.getCallResBySeqNum(seqNum);
            assertEq(cr.rc, crMock.rc, 'rc');
            assertEq(cr.lrc, crMock.lrc, 'status');
            assertEq(seqNum + 1, vault.getSeqNum(agent), 'seqNum');
        }
        ++seqNum;

        _verifyProp('after execution', pid, agent, block.timestamp, expiredAt, 2, 0, 0,
            IVault.PropType.InstRev, IVault.PropStatus.Executed, reqId1);

        // No state to verify beyond the proposal status since the core functionality is mocked here
    }

    function _castVote1(uint pid, UUID reqId, bool approve) public {
        console2.log('castVote voter1 Yay');
        vm.expectEmit();
        emit IVault.PropVoted(pid, reqId, voter1, approve, IVault.Vote.None);
        vm.prank(voter1);
        vault.castVote(NoSeqNum, NoReqId, pid, approve);
        assertEq(uint(vault.getPropStatus(pid)), uint(IVault.PropStatus.Sealed), 'status');
    }

    function _castVote2NoExec(uint pid, UUID reqId, bool approve) public {
        console2.log('castVote voter2 Yay, proposal passed');
        vm.expectEmit();
        IVault.Vote propResult = approve ? IVault.Vote.Yay : IVault.Vote.Nay;
        emit IVault.PropVoted(pid, reqId, voter2, approve, propResult);
        vm.prank(voter2);
        vault.castVote(NoSeqNum, NoReqId, pid, approve);
        assertEq(uint(vault.getPropStatus(pid)), uint(IVault.PropStatus.Passed), 'status');
    }

    function _approvePropNoExec(uint pid, UUID reqId, bool approve) public {
        _castVote1(pid, reqId, approve);
        _castVote2NoExec(pid, reqId, approve);
    }

    function test_Vault_xfer_usdc() public {
        _test_Vault_xfer(tokenInfoUsdc);
    }

    function test_Vault_xfer_eurc() public {
        _test_Vault_xfer(tokenInfoEurc);
    }

    function test_Vault_xfer_crt() public {
        _test_Vault_xfer(tokenInfoCrt);
    }

    function test_Vault_xfer_1155() public {
        _test_Vault_xfer(tokenInfoMulti);
    }

    function test_Vault_xfer_eth() public {
        _test_Vault_xfer(tokenInfoEth);
    }

    // A helper to verify different tokens may be transfered in separate proposals
    function _test_Vault_xfer(TI.TokenInfo memory tokenInfo) public {
        uint pid;
        uint expiredAt = block.timestamp;
        TI.TokenInfo memory ti;
        ti.tokAddr = address(123);
        ti.tokType = TI.TokenType.Erc1155;
        bool isRevDist;

        // ----------
        // Create Proposal: Bad inputs
        // ----------
        console2.log('createXferProp; Fail, access control');
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(AC.AccessDenied.selector, other));
        vault.createXferProp(NoSeqNum, NoReqId, expiredAt, ti, isRevDist);

        console2.log('createXferProp; Fail, paused');
        vm.prank(admin1);
        vault.pause(NoSeqNum, NoReqId, true);
        vm.expectRevert(abi.encodeWithSelector(IPausable.ContractPaused.selector));
        vm.prank(agent);
        vault.createXferProp(NoSeqNum, NoReqId, expiredAt, ti, isRevDist);
        vm.prank(admin1);
        vault.pause(NoSeqNum, NoReqId, false);

        console2.log('createXferProp; Fail, expired');
        expiredAt = block.timestamp - 1;
        vm.expectRevert(abi.encodeWithSelector(IVault.InvalidInput.selector, INVALID_PROP_EXPIRED));
        vm.prank(agent);
        vault.createXferProp(NoSeqNum, NoReqId, expiredAt, ti, isRevDist);
        vm.prank(agent);
        assertEq(uint(vault.getCallResBySeqNum(NoSeqNum).rc), pid);
        expiredAt = block.timestamp + 10;

        console2.log('createXferProp; Fail, empty tokAddr Erc1155');
        ti.tokAddr = zeroAddr;
        ti.tokType = TI.TokenType.Erc1155;
        vm.expectRevert(abi.encodeWithSelector(IVault.InvalidInput.selector, INVALID_XFER_PROP_TOK_TYPE));
        vm.prank(agent);
        vault.createXferProp(NoSeqNum, NoReqId, expiredAt, ti, isRevDist);
        vm.prank(agent);
        assertEq(uint(vault.getCallResBySeqNum(NoSeqNum).rc), pid);

        console2.log('createXferProp; Fail, tokAddr != 0 for native coin');
        ti.tokAddr = address(123);
        ti.tokType = TI.TokenType.NativeCoin;
        vm.expectRevert(abi.encodeWithSelector(IVault.InvalidInput.selector, INVALID_XFER_PROP_TOK_TYPE));
        vm.prank(agent);
        vault.createXferProp(NoSeqNum, NoReqId, expiredAt, ti, isRevDist);
        vm.prank(agent);
        assertEq(uint(vault.getCallResBySeqNum(NoSeqNum).rc), pid);

        console2.log('createXferProp; Fail, bad tokType');
        ti.tokType = TI.TokenType.Count;
        vm.expectRevert(abi.encodeWithSelector(IVault.InvalidInput.selector, INVALID_XFER_PROP_TOK_TYPE));
        vm.prank(agent);
        vault.createXferProp(NoSeqNum, NoReqId, expiredAt, ti, isRevDist);
        vm.prank(agent);
        assertEq(uint(vault.getCallResBySeqNum(NoSeqNum).rc), pid);

        console2.log('createXferProp; Fail, bad tokType for rev dist');
        isRevDist = true;
        ti.tokType = TI.TokenType.Erc1155;
        vm.expectRevert(abi.encodeWithSelector(IVault.InvalidInput.selector, INVALID_XFER_PROP_REV_DIST));
        vm.prank(agent);
        vault.createXferProp(NoSeqNum, NoReqId, expiredAt, ti, isRevDist);
        vm.prank(agent);
        assertEq(uint(vault.getCallResBySeqNum(NoSeqNum).rc), pid);

        // ----------
        // Create Proposal
        // ----------
        isRevDist = false;
        ti = tokenInfo;
        pid = vault.getLastPropId() + 1;    // Next pid to be created
        uint40 seqNum = vault.getSeqNum(agent);
        UUID reqId1 = _newUuid();
        for (uint i = 0; i < 2; ++i) {
            string memory suffix = i == 0 ? '(initial)' : '(duplicate, noop)';
            console2.log(T.concat('createXferProp; Success', suffix));
            if (i == 0) {
                vm.expectEmit();
                emit IVault.PropCreated(pid, reqId1, agent, false);
            }
            vm.prank(agent);
            vault.createXferProp(seqNum, reqId1, expiredAt, ti, isRevDist);
            vm.prank(agent);
            assertEq(uint(vault.getCallResBySeqNum(seqNum).rc), pid);
            assertEq(seqNum + 1, vault.getSeqNum(agent), 'seqNum');
        }
        ++seqNum;

        _verifyProp('before execution', pid, agent, block.timestamp, expiredAt, 0, 0, 0,
            IVault.PropType.Xfer, IVault.PropStatus.Pending, reqId1);

        assertEq(xferMgr.getPropHdr(pid).pid, pid, 'xferMgr pid'); // Ensure RevMgr called

        console2.log('castVote; Fail, proposal not sealed');
        bool approve = true;
        address voter = voter1;
        vm.prank(voter);
        vault.castVote(NoSeqNum, NoReqId, pid, approve);
        assertEq(uint(vault.getPropStatus(pid)), uint(IVault.PropStatus.Pending), 'status');

        // ----------
        // Seal proposal
        // ----------
        // Mock the call to `IXferMgr.propExecute` since it has a separate unit test
        bytes memory callRv = abi.encode(IXferMgr.PropXferFinalRc.Ok);
        vm.mockCall(address(xferMgr), abi.encodeWithSelector(IXferMgr.propFinalize.selector, pid), callRv);

        console2.log('sealXferProp; Fail, paused');
        vm.prank(admin1);
        vault.pause(NoSeqNum, NoReqId, true); // Pause
        vm.expectRevert(abi.encodeWithSelector(IPausable.ContractPaused.selector));
        vm.prank(agent);
        vault.sealXferProp(NoSeqNum, NoReqId, pid);
        vm.prank(admin1);
        vault.pause(NoSeqNum, NoReqId, false); // Unpause

        seqNum = vault.getSeqNum(agent);
        UUID reqId = _newUuid();
        for (uint i = 0; i < 2; ++i) {
            string memory suffix = i == 0 ? '(initial)' : '(duplicate, noop)';
            console2.log(T.concat('sealXferProp; Success', suffix));
            vm.prank(agent);
            vault.sealXferProp(seqNum, reqId, pid);
            vm.prank(agent);
            ICallTracker.CallRes memory callRes = vault.getCallResBySeqNum(seqNum);
            assertEq(callRes.rc, uint16(IXferMgr.PropXferFinalRc.Ok), 'pfCode');
            assertEq(callRes.lrc, uint16(IVault.PropStatus.Sealed), 'status');
            assertEq(seqNum + 1, vault.getSeqNum(agent), 'seqNum');
        }
        ++seqNum;
        if (ti.tokAddr == zeroAddr) {
            // No approval for ETH since it may only be sent by the owner
        } else if (ti.tokAddr == usdcAddr) {
            assertEq(tokenUsdc.allowance(vaultAddr, xferMgrAddr), MAX_ALLOWANCE, 'allowance');
        } else if (ti.tokAddr == eurcAddr) {
            assertEq(tokenEurc.allowance(vaultAddr, xferMgrAddr), MAX_ALLOWANCE, 'allowance');
        }

        // ----------
        // Attempt to execute before approved
        // ----------
        console2.log('execXferProp; Fail, not approved');
        vm.recordLogs(); // Begin recording to expect no events
        vm.prank(agent);
        vault.execXferProp(NoSeqNum, NoReqId, pid);

        _verifyProp('after attempted execution', pid, agent, block.timestamp, expiredAt, 0, 0, 0,
            IVault.PropType.Xfer, IVault.PropStatus.Sealed, reqId1);

        // ----------
        // Approve proposal (Cast Votes)
        // ----------
        _approvePropNoExec(pid, reqId1, approve);

        // ----------
        // Execute Proposal
        // ----------
        console2.log('execXferProp; Fail, access control');
        vm.expectRevert(abi.encodeWithSelector(AC.AccessDenied.selector, voter));
        vm.prank(voter);
        vault.execXferProp(NoSeqNum, NoReqId, pid);

        console2.log('execXferProp; Fail, paused');
        vm.prank(admin1);
        vault.pause(NoSeqNum, NoReqId, true); // Pause
        vm.expectRevert(abi.encodeWithSelector(IPausable.ContractPaused.selector));
        vm.prank(agent);
        vault.execXferProp(NoSeqNum, NoReqId, pid);
        vm.prank(admin1);
        vault.pause(NoSeqNum, NoReqId, false); // Unpause

        // Mock the call to `IXferMgr.propExecute` since it has a separate unit test
        uint64 mockXfers = 3;
        ICallTracker.CallRes memory cr;
        cr.rc = uint16(IXferMgr.ExecXferRc.Done);
        cr.lrc = 0;
        cr.count = uint16(mockXfers);
        callRv = abi.encode(cr);
        vm.mockCall(address(xferMgr), abi.encodeWithSelector(IXferMgr.propExecute.selector, pid), callRv);

        // Mock the call to `IXferMgr.getXfersLen` since it has a separate unit test and to simulate transfers
        callRv = abi.encode(mockXfers);
        vm.mockCall(address(xferMgr), abi.encodeWithSelector(IXferMgr.getXfersLen.selector, pid), callRv);

        seqNum = vault.getSeqNum(agent);
        console2.log('execXferProp; Success, fully executed');
        vm.expectEmit();
        emit IVault.PropExecuted(pid, reqId1);
        reqId = _newUuid();
        vm.prank(agent);
        vault.execXferProp(seqNum, reqId, pid);
        // T.checkCall(vm, vault.execXferProp(seqNum, pid),
        //     uint(IXferMgr.ExecXferRc.Done), 0, mockXfers, 'execXferProp');
        // vault.execXferProp(seqNum, pid);
        vm.prank(agent);
        cr = vault.getCallResBySeqNum(seqNum);
        assertEq(cr.rc, uint(IXferMgr.ExecXferRc.Done), 'rc');
        assertEq(cr.lrc, 0, 'lrc');
        assertEq(seqNum + 1, vault.getSeqNum(agent), 'seqNum');

        _verifyProp('after execution', pid, agent, block.timestamp, expiredAt, 2, 0, 0,
            IVault.PropType.Xfer, IVault.PropStatus.Executed, reqId1);

        console2.log('execXferProp; Success, previously executed - noop');
        vm.prank(agent);
        // T.checkCall(vm, vault.execXferProp(seqNum, pid),
        //     uint(IXferMgr.ExecXferRc.Done), 0, 3, 'execXferProp');
        vault.execXferProp(seqNum, reqId, pid);
        vm.prank(agent);
        cr = vault.getCallResBySeqNum(seqNum);
        assertEq(cr.rc, uint(IXferMgr.ExecXferRc.Done), 'rc');
        assertEq(cr.lrc, 0, 'lrc');
        assertEq(seqNum + 1, vault.getSeqNum(agent), 'seqNum');

        // No state to verify beyond the proposal status since the core functionality is mocked here
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

    function _checkUuid(UUID actual, UUID expect, string memory description) private pure {
        assertEq(UUID.unwrap(actual), UUID.unwrap(expect), description);
    }
}
