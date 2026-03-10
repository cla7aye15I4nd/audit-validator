// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TEVA is ERC20 {
    constructor() ERC20("TestEvervalue", "TEVA") {
        _mint(msg.sender, 21_000_000 * 10 ** 18);
    }

    function decimals() public pure virtual override returns (uint8) {
        return 18; // Or any other number of decimal places you want
    }
}
