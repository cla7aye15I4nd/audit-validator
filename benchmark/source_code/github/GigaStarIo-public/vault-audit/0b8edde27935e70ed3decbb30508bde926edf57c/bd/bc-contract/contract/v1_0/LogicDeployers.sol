// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import './BalanceMgr.sol';
import './Crt.sol';
import './Box.sol';
import './BoxMgr.sol';
import './EarnDateMgr.sol';
import './InstRevMgr.sol';
import './LibraryAC.sol';
import './LogicDeployer.sol';
import './RevMgr.sol';
import './Vault.sol';
import './XferMgr.sol';

// ───────────────────────────────────────
// LogicDeployers - Each isolates contract size
// ───────────────────────────────────────

/// @custom:api public
/// @custom:deploy none
contract BalanceMgrLogicDeployer is LogicDeployer {
    constructor() { _logic = address(new BalanceMgr()); emit LogicDeployed(_logic); }
}

/// @custom:api public
/// @custom:deploy none
contract BoxLogicDeployer is LogicDeployer {
    constructor() { _logic = address(new Box()); emit LogicDeployed(_logic); }
}

/// @custom:api public
/// @custom:deploy none
contract BoxMgrLogicDeployer is LogicDeployer {
    constructor() { _logic = address(new BoxMgr()); emit LogicDeployed(_logic); }
}

/// @custom:api public
/// @custom:deploy none
contract CrtLogicDeployer is LogicDeployer {
    constructor() { _logic = address(new Crt()); emit LogicDeployed(_logic); }
}

/// @custom:api public
/// @custom:deploy none
contract EarnDateMgrLogicDeployer is LogicDeployer {
    constructor() { _logic = address(new EarnDateMgr()); emit LogicDeployed(_logic); }
}

/// @custom:api public
/// @custom:deploy none
contract InstRevMgrLogicDeployer is LogicDeployer {
    constructor() { _logic = address(new InstRevMgr()); emit LogicDeployed(_logic); }
}

/// @custom:api public
/// @custom:deploy none
contract RevMgrLogicDeployer is LogicDeployer {
    constructor() { _logic = address(new RevMgr()); emit LogicDeployed(_logic); }
}

/// @custom:api public
/// @custom:deploy none
contract XferMgrLogicDeployer is LogicDeployer {
    constructor() { _logic = address(new XferMgr()); emit LogicDeployed(_logic); }
}

/// @custom:api public
/// @custom:deploy none
contract VaultLogicDeployer is LogicDeployer {
    constructor() { _logic = address(new Vault()); emit LogicDeployed(_logic); }
}
