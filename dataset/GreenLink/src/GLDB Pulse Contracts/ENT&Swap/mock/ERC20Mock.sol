// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title ERC20Mock
 * @dev Implementation of the ERC20 standard token for testing purposes.
 * This contract allows creation of tokens with specified name, symbol, and initial supply.
 */
contract ERC20Mock is ERC20 {
    /**
     * @dev Constructor that gives the msg.sender all initial tokens.
     * @param name_ The name of the token
     * @param symbol_ The symbol of the token
     * @param initialSupply The initial supply of tokens
     */
    constructor(string memory name_, string memory symbol_, uint256 initialSupply) ERC20(name_, symbol_) {
        _mint(msg.sender, initialSupply);
    }

    /**
     * @dev Mint tokens to a specific address.
     * @param to The address to mint tokens to
     * @param amount The amount of tokens to mint
     */
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /**
     * @dev Burn tokens from a specific address.
     * @param from The address to burn tokens from
     * @param amount The amount of tokens to burn
     */
    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}
