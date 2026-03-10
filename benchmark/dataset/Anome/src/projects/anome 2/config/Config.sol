// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ConfigStorage} from "./ConfigStorage.sol";

import {SolidStateDiamond} from "../../lib/solidstate/proxy/diamond/SolidStateDiamond.sol";

contract Config is SolidStateDiamond {
    constructor() {}
}
