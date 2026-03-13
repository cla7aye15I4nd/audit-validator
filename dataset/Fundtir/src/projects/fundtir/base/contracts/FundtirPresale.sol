// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title FundtirPreSale
 * @dev A presale contract for Fundtir tokens that allows users to purchase FNDR tokens using USDT
 * 
 * Key Features:
 * - Purchase FNDR tokens using USDT
 * - Configurable token price and minimum purchase threshold
 * - Pausable functionality for emergency stops
 * - Reentrancy protection for secure token transfers
 * - Treasury wallet management for USDT collection
 * - Admin functions for price and threshold updates
 * 
 * @author Fundtir Team
 */
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

contract FundtirPreSale is Ownable2Step, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @dev Mapping to track total tokens bought by each address
    mapping(address => uint256) public tokensBought;

    /// @dev Address of the treasury wallet that receives USDT payments
    address public treasuryWallet;
    
    /// @dev The Fundtir token contract (FNDR)
    IERC20 immutable fundtir;
    
    /// @dev The USDT token contract for payments
    IERC20 immutable usdtToken;
    
    /// @dev Token price in USDT (with 18 decimals format)
    /// @notice Example: If 1 USDT = 2 FNDR, then tokenPrice = 2 * 10^18
    uint256 public tokenPrice;
    
    /// @dev Minimum purchase amount in USDT (with 6 decimals for USDT)
    uint256 public minThresholdLimit;

    /// @dev Emitted when a user purchases tokens
    event TokensPurchased(address indexed buyer, uint256 amount);
    
    /// @dev Emitted when the minimum threshold is updated
    event minThresholdUpdated(uint256 indexed newMinThresholdLimit);
    
    /// @dev Emitted when the token price is updated
    event TokenPriceUpdated(uint256 oldPrice, uint256 newPrice);
    
    /// @dev Emitted when admin withdraws tokens from the contract
    event TokensWithdrawn(address indexed admin, uint256 amount);
    
    /// @dev Emitted when the treasury wallet is updated
    event TreasuryWalletUpdated(address indexed newWallet);

    /**
     * @dev Constructor initializes the presale contract with token addresses and pricing
     * @param _tokenPrice Token price in USDT (must be in 18 decimals format)
     * @param _treasuryWallet Address that will receive USDT payments and become the owner
     * @param _minThresholdLimit Minimum purchase amount in USDT (with 6 decimals for USDT)
     * @param _Fundtiren Address of the Fundtir token contract
     * @param _usdttoken Address of the USDT token contract
     * 
     * Requirements:
     * - All addresses must be valid (non-zero)
     * - Token price must be greater than 0
     * - Minimum threshold must be greater than 0
     */
    constructor(
        uint256 _tokenPrice,
        address _treasuryWallet,
        uint256 _minThresholdLimit,
        address _Fundtiren,
        address _usdttoken
    ) Ownable(_treasuryWallet) {
        fundtir = IERC20(_Fundtiren);
        usdtToken = IERC20(_usdttoken);
        tokenPrice = _tokenPrice;
        treasuryWallet = _treasuryWallet;
        minThresholdLimit = _minThresholdLimit;
    }

    // ============ ADMIN FUNCTIONS ============
    
    /**
     * @dev Updates the treasury wallet address that receives USDT payments
     * @param _treasuryWallet New treasury wallet address
     * 
     * Requirements:
     * - Caller must be the contract owner
     * - New treasury wallet must be a valid address (non-zero)
     * - New treasury wallet must be different from current one
     */
    function updateTreasuryWallet(address _treasuryWallet) external onlyOwner {
        require(_treasuryWallet != address(0), "Invalid Treasury Wallet");
        require(treasuryWallet != _treasuryWallet, "Use Diff. Wallet");
        treasuryWallet = _treasuryWallet;
        emit TreasuryWalletUpdated(_treasuryWallet);
    }

    // ============ VIEW FUNCTIONS ============
    
    /**
     * @dev Preview how many FNDR tokens a user would receive for a given USDT amount
     * @param usdtAmount Amount of USDT to spend (with 6 decimals)
     * @return Amount of FNDR tokens that would be received (with 18 decimals)
     * 
     * Calculation: (usdtAmount * 1e18 * 1e12) / tokenPrice
     * - usdtAmount * 1e18: Convert USDT to 18 decimals
     * - * 1e12: Additional scaling for price calculation
     * - / tokenPrice: Divide by token price to get FNDR amount
     */
    function previewFundtirForUSDT(
        uint256 usdtAmount
    ) external view returns (uint256) {
        return (usdtAmount * 1e18 * 1e12) / tokenPrice;
    }

    // ============ PURCHASE FUNCTIONS ============
    
    /**
     * @dev Allows users to purchase FNDR tokens using USDT
     * @param usdtAmount Amount of USDT to spend (with 6 decimals)
     * 
     * Requirements:
     * - Contract must not be paused
     * - usdtAmount must be greater than 0
     * - usdtAmount must meet minimum threshold requirement
     * - Contract must have sufficient FNDR tokens
     * - User must have sufficient USDT balance and allowance
     * 
     * Process:
     * 1. Calculate FNDR tokens to receive based on current price
     * 2. Transfer USDT from user to treasury wallet
     * 3. Transfer FNDR tokens from contract to user
     * 4. Update user's total tokens bought
     */
    function buyTokens(uint256 usdtAmount) external whenNotPaused nonReentrant {
        require(usdtAmount > 0, "Must send some USDT");
        require(usdtAmount >= minThresholdLimit, "Less Than Threshold");

        // Calculate the number of FNDR tokens to be bought
        uint256 FundtirAmount = (usdtAmount * 1e18 * 1e12) / tokenPrice; // Adjust for 18 decimals
        require(FundtirAmount > 0, "FNDR too Small");

        // Check if there are enough tokens in the contract
        require(
            fundtir.balanceOf(address(this)) >= FundtirAmount,
            "Insufficient Fundtir bal"
        );

        // Transfer USDT to the treasury wallet
        usdtToken.safeTransferFrom(
            msg.sender,
            treasuryWallet,
            usdtAmount
        );

        // Transfer FNDR tokens to the buyer
        fundtir.safeTransfer(msg.sender, FundtirAmount);

        // Update user's total tokens bought
        tokensBought[msg.sender] = tokensBought[msg.sender] + FundtirAmount;

        emit TokensPurchased(msg.sender, FundtirAmount);
    }

    /**
     * @dev Updates the token price for FNDR tokens
     * @param _newTokenPrice New token price in USDT (must be in 18 decimals format)
     * 
     * Requirements:
     * - Caller must be the contract owner
     * - New price must be greater than 0
     * 
     * @notice Token price must be in 18 decimals format
     * @notice Example: If 1 USDT = 2 FNDR, then _newTokenPrice = 2 * 10^18
     */
    function setTokenPrice(uint256 _newTokenPrice) external onlyOwner {
        require(_newTokenPrice > 0, "Price must be greater than 0");
        uint256 oldPrice = tokenPrice;
        tokenPrice = _newTokenPrice;
        emit TokenPriceUpdated(oldPrice, _newTokenPrice);
    }

    /**
     * @dev Updates the minimum purchase threshold in USDT
     * @param _minThresholdLimit New minimum threshold in USDT (with 6 decimals)
     * 
     * Requirements:
     * - Caller must be the contract owner
     * - New threshold must be greater than 0
     */
    function setMinThreshold(uint256 _minThresholdLimit) external onlyOwner {
        require(_minThresholdLimit > 0, "Threshold must be greater than 0");
        minThresholdLimit = _minThresholdLimit;
        emit minThresholdUpdated(_minThresholdLimit);
    }

    /**
     * @dev Pauses the contract, preventing new token purchases
     * 
     * Requirements:
     * - Caller must be the contract owner
     * 
     * @notice When paused, buyTokens() function will revert
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpauses the contract, allowing token purchases to resume
     * 
     * Requirements:
     * - Caller must be the contract owner
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    // ============ WITHDRAWAL FUNCTIONS ============
    
    /**
     * @dev Allows the contract owner to withdraw tokens from the contract
     * @param tokenAddress Address of the token contract to withdraw
     * @param amount Amount of tokens to withdraw (will be adjusted to available balance if needed)
     * 
     * Requirements:
     * - Caller must be the contract owner
     * - Amount must be greater than 0
     * - Contract must have tokens to withdraw
     * 
     * Note: Tokens are transferred to the treasury wallet
     */
    function withdrawTokens(
        address tokenAddress,
        uint256 amount
    ) external onlyOwner {
        require(amount > 0, "Amount must be greater than 0");
        IERC20 token = IERC20(tokenAddress);
        require(token.balanceOf(address(this)) > 0, "Insufficient token");
        if (token.balanceOf(address(this)) < amount) {
            amount = token.balanceOf(address(this));
        }
        token.safeTransfer(treasuryWallet, amount);
        emit TokensWithdrawn(msg.sender, amount);
    }

}
