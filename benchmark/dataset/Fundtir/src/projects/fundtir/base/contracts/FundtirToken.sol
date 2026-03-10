// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title FundtirToken
 * @dev ERC20 token contract for Fundtir with burnable and permit functionality
 * 
 * Features:
 * - Standard ERC20 token functionality
 * - Burnable tokens (users can burn their own tokens)
 * - EIP-2612 permit functionality for gasless approvals
 * - Ownable with 2-step ownership transfer for security
 * - Fixed supply of 700 million tokens
 * 
 * @author Fundtir Team
 */
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";

contract FundtirToken is ERC20, ERC20Burnable, ERC20Permit, Ownable2Step {
    /**
     * @dev Constructor initializes the Fundtir token
     * @param _adminWallet Address that will receive the initial token supply and become the owner
     * 
     * Token Details:
     * - Name: "Fundtir"
     * - Symbol: "FNDR"
     * - Decimals: 18 (standard)
     * - Total Supply: 700,000,000 FNDR tokens
     * - All tokens are minted to the admin wallet upon deployment
     */
    constructor(address _adminWallet)
        ERC20("Fundtir", "FNDR")
        ERC20Permit("Fundtir")
        Ownable(_adminWallet)
    {
        uint256 totalSupply = 700_000_000 * 10**decimals(); // 700 Million supply
        _mint(_adminWallet, totalSupply);
    }
}