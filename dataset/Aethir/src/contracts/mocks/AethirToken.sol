// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract AethirToken is ERC20 {
    constructor() ERC20("Aethir Test Token", "ATH") {
        _mint(msg.sender, 42_000_000_000 * 10 ** decimals());
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
