// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20} from "../../../lib/openzeppelin/token/ERC20/ERC20.sol";

contract Bnome is ERC20 {
    constructor(address shop, address receiver) ERC20("BNome", "BNome") {
        _mint(shop, 200000000 * 10 ** decimals());
        _mint(receiver, 800000000 * 10 ** decimals() - 20000 * 10 ** decimals());
        _mint(msg.sender, 20000 * 10 ** decimals());
    }
}
