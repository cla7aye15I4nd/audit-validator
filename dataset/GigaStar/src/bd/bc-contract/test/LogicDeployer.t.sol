// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

// See LIB_PATHS
import '../lib/forge-std/src/Test.sol';

import '../contract/v1_0/LogicDeployer.sol';

contract LogicDeployerSpyHelper {
    uint a;
}

contract LogicDeployerSpy is LogicDeployer {
    constructor() {
        _logic = address(new LogicDeployerSpyHelper());
        emit LogicDeployed(_logic);
    }

    function getLogic() public view returns(address) { return _logic; }
}

contract LogicDeployerTest is Test {
    function test_LogicDeployer() public {
        LogicDeployerSpy spy = new LogicDeployerSpy();
        assertEq(spy.deployLogic(), spy.getLogic());
    }
}
