// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

/**
 * @dev Will be used as the governor of `ACLManager` smart contract,
 * it enforces a timelock on all `governor` operations.
 *
 * At the deploy time, proposer and executor should be set to a multisig address
 * In the long-term, they will be replaced by a DAO
 */
contract GovernorTimelockController is TimelockController {
    constructor(address[] memory governor) TimelockController(1 days, governor, governor, address(0)) {}
}
