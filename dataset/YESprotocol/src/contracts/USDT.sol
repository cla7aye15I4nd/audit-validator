//SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract USDT is ERC20 {
    constructor() ERC20("USDT Test", "USDT") {
        _mint(msg.sender, 1000000000e18);
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }
}
