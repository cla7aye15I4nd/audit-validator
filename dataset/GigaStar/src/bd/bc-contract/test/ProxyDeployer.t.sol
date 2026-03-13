// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

// See LIB_PATHS
import '../lib/forge-std/src/Test.sol';

import '../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol';
import '../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol';

import '../contract/v1_0/ProxyDeployer.sol';
import '../contract/v1_0/Types.sol';

contract ProxyDeployerSpyHelper is Initializable, UUPSUpgradeable {
    uint _a;

    /// @dev Ensures the logic contract cannot be hijacked before the `initializer` runs
    /// - Sets version to `type(uint64).max` + `emit Initialized(version)` to prevent future initialization
    /// - `initializer` modifier ensures this function can only be called once during deploy
    /// - See UUPS_UPGRADE_SEQ for details on how to upgrade this contract
    constructor() { _disableInitializers(); } // Do not add code to cstr

    function initialize(uint a) external initializer {
        _a = a;
    }

    function _authorizeUpgrade(address newImpl) internal override(UUPSUpgradeable) {
    }

    function getA() external view returns(uint) { return _a; }
}

contract ProxyDeployerTest is Test {

    function test_ProxyDeployer() public {
        ProxyDeployer pd = new ProxyDeployer();
        ProxyDeployerSpyHelper logic = new ProxyDeployerSpyHelper();
        address logicAddr = address(logic);
        string memory name = 'helper';
        uint expectA = 3;
        bytes memory initData = abi.encodeWithSelector(ProxyDeployerSpyHelper.initialize.selector, expectA);
        address proxyrAdd = pd.deployProxy(logicAddr, name, initData);
        assertFalse(proxyrAdd == AddrZero);
        ProxyDeployerSpyHelper proxy = ProxyDeployerSpyHelper(proxyrAdd);
        assertEq(proxy.getA(), expectA);

        // Try to re-initialize the proxy
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        proxy.initialize(1);

        // Try to initialize the logic contract
        vm.expectRevert(abi.encodeWithSelector(Initializable.InvalidInitialization.selector));
        logic.initialize(2);
    }

}
