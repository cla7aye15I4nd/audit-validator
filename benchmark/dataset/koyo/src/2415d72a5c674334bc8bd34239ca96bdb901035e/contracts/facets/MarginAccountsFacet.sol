// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./FacetBase.sol";
import "./ReentrancyGuardBase.sol";
import "../libraries/LibDiamond.sol";
import "../libraries/RoleConstants.sol";
import "../libraries/DexHandler.sol";
import "../interfaces/IPriceOracleFacet.sol";
import "../interfaces/IFeeManagement.sol";

/**
 * @title MarginAccountsFacet
 * @dev Manages margin accounts and liquidations in the protocol
 * @notice Implements margin account functionality with proper liquidation mechanics
 * @custom:security-contact security@koyodex.com
 */
contract MarginAccountsFacet is FacetBase, ReentrancyGuardBase {
    using SafeERC20 for IERC20;

    uint256 private constant SCALE = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 9500; // 95%
    uint256 private constant MIN_LIQUIDATION_SIZE = 100; // $100 equivalent
    uint256 private constant LIQUIDATION_REWARD = 500; // 5%
    uint256 private constant MIN_GAS_RESERVE = 50000;

    /**
     * @dev Emitted when tokens are deposited
     */
    event Deposited(
        address indexed user,
        address indexed token,
        uint256 requested,
        uint256 actual,
        uint256 timestamp
    );

    /**
     * @dev Emitted when tokens are withdrawn
     */
    event Withdrawn(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 timestamp
    );

    /**
     * @dev Emitted when an account is liquidated
     */
    event Liquidated(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 reward,
        address indexed liquidator,
        uint256 timestamp
    );

    /**
     * @dev Emitted when a user's margin status changes
     */
    event MarginStatusChanged(
        address indexed user,
        bool isEnabled,
        uint256 timestamp
    );

    /**
     * @dev Modifier that checks if the caller has the specified role
     */
    modifier onlyRole(bytes32 role) {
        require(LibDiamond.diamondStorage().roles[role][msg.sender], "Must have required role");
        _;
    }

    /**
     * @dev Modifier to validate token
     */
    modifier validToken(address token) {
        require(token != address(0), "Invalid token address");
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        require(ds.isTokenSupported[token], "Token not supported");
        require(ds.tokenInfo[token].isActive, "Token not active");
        _;
    }

    /**
     * @notice Initializes the margin accounts system
     * @param _feeManagement The fee management contract address
     */
    function initializeMarginAccounts(
        address _feeManagement
    ) external onlyRole(RoleConstants.ADMIN_ROLE) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        require(!ds.initialized, "Already initialized");
        
        require(_feeManagement != address(0), "Invalid fee management");
        ds.feeManagementFacet = _feeManagement;
        ds.initialized = true;
    }

    /**
     * @notice Deposits tokens into margin account
     * @dev Handles deflationary tokens by checking actual received amount
     * @param token The token to deposit
     * @param amount The amount to deposit
     */
    function depositMargin(
        address token,
        uint256 amount
    ) external nonReentrant validToken(token) {
        require(amount > 0, "Amount must be greater than 0");
        
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();

        // Get initial balance for deflationary token support
        uint256 balanceBefore = IERC20(token).balanceOf(address(this));
        
        // Transfer tokens with SafeERC20
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        
        // Calculate actual received amount for deflationary tokens
        uint256 balanceAfter = IERC20(token).balanceOf(address(this));
        uint256 actualAmount = balanceAfter - balanceBefore;
        
        require(actualAmount > 0, "No tokens received");

        // Update state with actual received amount
        ds.marginAccounts[msg.sender].balance[token] += actualAmount;

        // Add user to tracking array if not already present
        if (!_isUserTracked(msg.sender)) {
            ds.marginAccountsUsers.push(msg.sender);
            emit MarginStatusChanged(msg.sender, true, block.timestamp);
        }

        emit Deposited(msg.sender, token, amount, actualAmount, block.timestamp);
    }

    /**
     * @notice Withdraws tokens from margin account
     * @dev Checks margin requirements before withdrawal
     * @param token The token to withdraw
     * @param amount The amount to withdraw
     */
    function withdrawMargin(
        address token,
        uint256 amount
    ) external nonReentrant validToken(token) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        require(amount > 0, "Amount must be greater than 0");
        require(ds.marginAccounts[msg.sender].balance[token] >= amount, "Insufficient balance");
        require(ds.marginAccounts[msg.sender].borrowed == 0, "Outstanding borrowed amount");

        // Update state
        ds.marginAccounts[msg.sender].balance[token] -= amount;

        // Check if user still has any balances
        bool hasBalances = false;
        for (uint256 i = 0; i < ds.supportedTokens.length; i++) {
            if (ds.marginAccounts[msg.sender].balance[ds.supportedTokens[i]] > 0) {
                hasBalances = true;
                break;
            }
        }

        // Remove user from tracking if no balances remain
        if (!hasBalances) {
            _removeUserFromTracking(msg.sender);
            emit MarginStatusChanged(msg.sender, false, block.timestamp);
        }

        // Transfer tokens
        IERC20(token).safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, token, amount, block.timestamp);
    }

    /**
     * @notice Checks accounts for liquidation
     * @dev Processes accounts in batches to save gas
     * @param batchSize The number of accounts to check
     */
    function checkAccountsForLiquidation(
        uint256 batchSize
    ) external nonReentrant {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        require(batchSize > 0, "Invalid batch size");

        uint256 processed = 0;
        uint256 totalUsers = ds.marginAccountsUsers.length;

        while (processed < batchSize && processed < totalUsers && gasleft() > MIN_GAS_RESERVE) {
            address user = ds.marginAccountsUsers[processed];
            
            if (_shouldLiquidate(user)) {
                _liquidateAccount(user);
            }
            
            processed++;
        }
    }

    /**
     * @notice Gets margin account balances
     * @param user The user address
     * @return tokens Array of token addresses
     * @return balances Array of token balances
     */
    function getMarginBalances(
        address user
    ) external view returns (
        address[] memory tokens,
        uint256[] memory balances
    ) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        tokens = ds.supportedTokens;
        balances = new uint256[](tokens.length);
        
        for (uint256 i = 0; i < tokens.length; i++) {
            balances[i] = ds.marginAccounts[user].balance[tokens[i]];
        }
    }

    /**
     * @notice Returns the function selectors for this facet
     * @return selectors Array of function selectors
     */
    function getMarginAccountsFacetSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](5);
        selectors[0] = this.initializeMarginAccounts.selector;
        selectors[1] = this.depositMargin.selector;
        selectors[2] = this.withdrawMargin.selector;
        selectors[3] = this.checkAccountsForLiquidation.selector;
        selectors[4] = this.getMarginBalances.selector;
        return selectors;
    }

    /**
     * @dev Checks if a user should be liquidated
     * @param user The user address
     * @return Whether the user should be liquidated
     */
    function _shouldLiquidate(address user) internal view returns (bool) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        
        if (ds.marginAccounts[user].borrowed == 0) {
            return false;
        }

        uint256 totalCollateralValue = 0;
        uint256 totalBorrowedValue = 0;

        for (uint256 i = 0; i < ds.supportedTokens.length; i++) {
            address token = ds.supportedTokens[i];
            uint256 price = IPriceOracleFacet(ds.priceOracleFacet).getPrice(token);
            
            totalCollateralValue += (ds.marginAccounts[user].balance[token] * price) / SCALE;
            totalBorrowedValue += (ds.marginAccounts[user].borrowed * price) / SCALE;
        }

        return totalCollateralValue * SCALE / totalBorrowedValue < LIQUIDATION_THRESHOLD;
    }

    /**
     * @dev Liquidates a user's account
     * @param user The user address
     */
    function _liquidateAccount(address user) internal {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        
        for (uint256 i = 0; i < ds.supportedTokens.length; i++) {
            address token = ds.supportedTokens[i];
            uint256 balance = ds.marginAccounts[user].balance[token];
            
            if (balance > 0) {
                uint256 price = IPriceOracleFacet(ds.priceOracleFacet).getPrice(token);
                uint256 value = (balance * price) / SCALE;
                
                if (value >= MIN_LIQUIDATION_SIZE) {
                    uint256 reward = (balance * LIQUIDATION_REWARD) / 10000;
                    uint256 remainingBalance = balance - reward;

                    // Clear user's balance
                    ds.marginAccounts[user].balance[token] = 0;

                    // Transfer reward to liquidator
                    IERC20(token).safeTransfer(msg.sender, reward);

                    // Convert remaining balance to protocol's fee token
                    _convertToFeeToken(token, remainingBalance);

                    emit Liquidated(user, token, balance, reward, msg.sender, block.timestamp);
                }
            }
        }

        // Clear borrowed amount
        ds.marginAccounts[user].borrowed = 0;

        // Remove user from tracking
        _removeUserFromTracking(user);
        emit MarginStatusChanged(user, false, block.timestamp);
    }

    /**
     * @dev Converts tokens to protocol's fee token
     * @param token The token to convert
     * @param amount The amount to convert
     */
    function _convertToFeeToken(address token, uint256 amount) internal {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        
        if (token != address(ds.feeManagement.feeToken)) {
            IERC20(token).forceApprove(ds.feeManagement.ShibaSwapRouterAddress, amount);
            
            address[] memory path = new address[](2);
            path[0] = token;
            path[1] = address(ds.feeManagement.feeToken);
            
            IFeeManagement(ds.feeManagementFacet).collectFee(token, amount);
        }
    }

    /**
     * @dev Checks if a user is being tracked
     * @param user The user address
     * @return Whether the user is being tracked
     */
    function _isUserTracked(address user) internal view returns (bool) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        
        for (uint256 i = 0; i < ds.marginAccountsUsers.length; i++) {
            if (ds.marginAccountsUsers[i] == user) {
                return true;
            }
        }
        return false;
    }

    /**
     * @dev Removes a user from tracking array
     * @param user The user address
     */
    function _removeUserFromTracking(address user) internal {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        
        for (uint256 i = 0; i < ds.marginAccountsUsers.length; i++) {
            if (ds.marginAccountsUsers[i] == user) {
                ds.marginAccountsUsers[i] = ds.marginAccountsUsers[ds.marginAccountsUsers.length - 1];
                ds.marginAccountsUsers.pop();
                break;
            }
        }
    }
}