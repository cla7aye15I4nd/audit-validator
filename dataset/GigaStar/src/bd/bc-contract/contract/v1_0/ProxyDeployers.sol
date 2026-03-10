// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import './BalanceMgr.sol';
import './Box.sol';
import './BoxMgr.sol';
import './Crt.sol';
import './EarnDateMgr.sol';
import './IBalanceMgr.sol';
import './IBox.sol';
import './IBoxMgr.sol';
import './ICrt.sol';
import './IInstRevMgr.sol';
import './InstRevMgr.sol';
import './IRevMgr.sol';
import './IEarnDateMgr.sol';
import './IVault.sol';
import './IXferMgr.sol';
import './LibraryAC.sol';
import './ProxyDeployer.sol';
import './RevMgr.sol';
import './Types.sol';
import './XferMgr.sol';
import './Vault.sol';

// ───────────────────────────────────────
// ProxyDeployers - Each acts like a contract constructor
// ───────────────────────────────────────

/// @custom:api private
/// @custom:deploy none
contract BalanceMgrProxyDeployer {
    /// @custom:api public
    function createProxy(address logicAddr, address creator, UUID reqId) public returns(IBalanceMgr) {
        address proxyAddr = (new ProxyDeployer()).deployProxy(logicAddr, 'BalanceMgr',
            abi.encodeWithSelector(IBalanceMgr.initialize.selector, creator, reqId));
        return IBalanceMgr(proxyAddr);
    }
}

// No need for BoxLogicProxyDeployer as proxy creation is handled in BoxMgr via clones

/// @custom:api private
/// @custom:deploy none
contract CrtProxyDeployer {
    /// @custom:api public
    function createProxy(address logicAddr, address creator, UUID reqId, string memory url) public returns(ICrt) {
        address proxyAddr = (new ProxyDeployer()).deployProxy(logicAddr, 'Crt',
            abi.encodeWithSelector(ICrt.initialize.selector, creator, reqId, url));
        return ICrt(proxyAddr);
    }
}

/// @custom:api private
/// @custom:deploy none
contract BoxMgrProxyDeployer {
    /// @custom:api public
    function createProxy(address logicAddr, address creator, UUID reqId) public returns(IBoxMgr) {
        address proxyAddr = (new ProxyDeployer()).deployProxy(logicAddr, 'BoxMgr',
            abi.encodeWithSelector(IBoxMgr.initialize.selector, creator, reqId));
        return IBoxMgr(proxyAddr);
    }
}

/// @custom:api private
/// @custom:deploy none
contract EarnDateMgrProxyDeployer {
    /// @custom:api public
    function createProxy(address logicAddr, address creator, UUID reqId) public returns(IEarnDateMgr) {
        address proxyAddr = (new ProxyDeployer()).deployProxy(logicAddr, 'EarnDateMgr',
            abi.encodeWithSelector(IEarnDateMgr.initialize.selector, creator, reqId));
        return IEarnDateMgr(proxyAddr);
    }
}

/// @custom:api private
/// @custom:deploy none
contract InstRevMgrProxyDeployer {
    /// @custom:api public
    function createProxy(address logicAddr, address creator, UUID reqId) public returns(IInstRevMgr) {
        address proxyAddr = (new ProxyDeployer()).deployProxy(logicAddr, 'InstRevMgr',
            abi.encodeWithSelector(IInstRevMgr.initialize.selector, creator, reqId));
        return IInstRevMgr(proxyAddr);
    }
}

/// @custom:api private
/// @custom:deploy none
contract RevMgrProxyDeployer {
    /// @custom:api public
    function createProxy(address logicAddr, address creator, UUID reqId) public returns(IRevMgr) {
        address proxyAddr = (new ProxyDeployer()).deployProxy(logicAddr, 'RevMgr',
            abi.encodeWithSelector(IRevMgr.initialize.selector, creator, reqId));
        return IRevMgr(proxyAddr);
    }
}

/// @custom:api private
/// @custom:deploy none
contract XferMgrProxyDeployer {
    /// @custom:api public
    function createProxy(address logicAddr, address creator, UUID reqId) public returns(IXferMgr) {
        address proxyAddr = (new ProxyDeployer()).deployProxy(logicAddr, 'XferMgr',
            abi.encodeWithSelector(IXferMgr.initialize.selector, creator, reqId));
        return IXferMgr(proxyAddr);
    }
}

/// @custom:api private
/// @custom:deploy none
contract VaultProxyDeployer {
    /// @custom:api public
    function createProxy(address logicAddr, address creator, UUID reqId,
        uint quorum, AC.RoleRequest[] memory roleRequests) public
        returns(IVault)
    {
        address proxyAddr = (new ProxyDeployer()).deployProxy(logicAddr, 'Vault',
            abi.encodeWithSelector(IVault.initialize.selector, creator, reqId, quorum, roleRequests));
        return IVault(payable(proxyAddr));
    }
}
