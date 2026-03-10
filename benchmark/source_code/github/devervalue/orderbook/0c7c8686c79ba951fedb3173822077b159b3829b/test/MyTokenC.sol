// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MyTokenC is ERC20 {
    constructor(uint256 initialSupply) ERC20("MyTokenC", "MTC") {
        _mint(msg.sender, initialSupply);
    }

    function decimals() public pure virtual override returns (uint8) {
        return 6; // Or any other number of decimal places you want
    }
}
