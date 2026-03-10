// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IConfigImpl} from "./impl/IConfigImpl.sol";
import {IConfigAdmin} from "./admin/IConfigAdmin.sol";

interface IConfig is IConfigImpl, IConfigAdmin {}
