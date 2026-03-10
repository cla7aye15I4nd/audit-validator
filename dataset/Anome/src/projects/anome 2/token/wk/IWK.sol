// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "../../../lib/openzeppelin/token/ERC20/IERC20.sol";

interface IWK is IERC20 {
    function mint(address account, uint256 amount) external;
    function burn(address account, uint256 amount) external;
}
