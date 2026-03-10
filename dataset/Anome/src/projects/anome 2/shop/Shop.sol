// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "../../lib/openzeppelin/token/ERC20/IERC20.sol";
import {SolidStateDiamond} from "../../lib/solidstate/proxy/diamond/SolidStateDiamond.sol";

import {ShopTypes} from "./ShopTypes.sol";
import {ShopStorage} from "./ShopStorage.sol";
import {IVnome} from "../token/vnome/IVnome.sol";
import {IConfig} from "../config/IConfig.sol";

contract Shop is SolidStateDiamond {}
