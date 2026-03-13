// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../libraries/LibDiamond.sol";
import "../libraries/RoleConstants.sol";
import "../libraries/DexHandler.sol";
import "./FacetBase.sol";
import "./ReentrancyGuardBase.sol";
import "../interfaces/IPriceOracleFacet.sol";
import "../interfaces/IFeeManagement.sol";

/**
 * @title MarginTradingFacet
 * @dev Manages margin trading operations with proper leverage and position tracking
 * @notice Implements margin trading functionality with proper collateral checks and leverage limits
 * @custom:security-contact security@koyodex.com
 */
contract MarginTradingFacet is FacetBase, ReentrancyGuardBase {
    using SafeERC20 for IERC20;

    uint256 private constant SCALE = 1e18;
    uint256 private constant MAX_LEVERAGE = 175; // 1.75x
    uint256 private constant MIN_LEVERAGE = 100; // 1x
    uint256 private constant BORROWING_LIMIT_PERCENTAGE = 7500; // 75%
    uint256 private constant MAX_SLIPPAGE = 100; // 1%
    uint256 private constant MIN_POSITION_SIZE = 100; // $100 equivalent
    uint256 private constant LIQUIDATION_THRESHOLD = 9500; // 95%

    /**
     * @dev Emitted when a position is opened
     */
    event PositionOpened(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 leverage,
        bool isLong,
        uint256 entryPrice,
        uint256 borrowedAmount,
        uint256 timestamp
    );

    /**
     * @dev Emitted when a position is closed
     */
    event PositionClosed(
        address indexed user,
        address indexed token,
        uint256 positionId,
        uint256 exitPrice,
        uint256 pnl,
        uint256 timestamp
    );

    /**
     * @dev Emitted when leverage parameters are updated
     */
    event LeverageParamsUpdated(
        uint256 maxLeverage,
        uint256 borrowingLimit,
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
     * @notice Initializes the margin trading system
     * @param _marginAccounts The margin accounts contract address
     * @param _priceOracle The price oracle contract address
     * @param _feeManagement The fee management contract address
     */
    function initializeMarginTrading(
        address _marginAccounts,
        address _priceOracle,
        address _feeManagement
    ) external onlyRole(RoleConstants.ADMIN_ROLE) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        require(!ds.initialized, "Already initialized");
        
        require(_marginAccounts != address(0), "Invalid margin accounts");
        require(_priceOracle != address(0), "Invalid price oracle");
        require(_feeManagement != address(0), "Invalid fee management");

        ds.marginAccountsFacet = _marginAccounts;
        ds.priceOracleFacet = _priceOracle;
        ds.feeManagementFacet = _feeManagement;
        ds.initialized = true;
    }

    /**
     * @notice Opens a leveraged position
     * @param token The token to trade
     * @param amount The amount to trade
     * @param leverage The leverage multiplier
     * @param isLong Whether the position is long
     * @param maxSlippage Maximum acceptable slippage
     */
    function openPosition(
        address token,
        uint256 amount,
        uint256 leverage,
        bool isLong,
        uint256 maxSlippage
    ) external nonReentrant validToken(token) {
        require(amount > 0, "Amount must be greater than 0");
        require(leverage >= MIN_LEVERAGE && leverage <= MAX_LEVERAGE, "Invalid leverage");
        require(maxSlippage <= MAX_SLIPPAGE, "Slippage too high");

        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        
        // Calculate position size with leverage
        uint256 positionSize = (amount * leverage) / 100;
        uint256 borrowedAmount = positionSize - amount;

        // Get current price and calculate value
        uint256 price = IPriceOracleFacet(ds.priceOracleFacet).getPrice(token);
        uint256 positionValue = (positionSize * price) / SCALE;
        require(positionValue >= MIN_POSITION_SIZE, "Position size too small");

        // Calculate and check buying power
        uint256 buyingPower = calculateBuyingPower(msg.sender);
        uint256 requiredBuyingPower = (borrowedAmount * price) / SCALE;
        require(buyingPower >= requiredBuyingPower, "Insufficient buying power");
        require(
            requiredBuyingPower <= (buyingPower * BORROWING_LIMIT_PERCENTAGE) / 10000,
            "Exceeds borrowing limit"
        );

        // Calculate trading fee
        uint256 tradingFee = IFeeManagement(ds.feeManagementFacet).calculateTradingFee(positionSize);
        require(buyingPower >= tradingFee, "Insufficient funds for fee");

        // Update borrowed amount
        ds.marginAccounts[msg.sender].borrowed += borrowedAmount;

        // Create position
        uint256 positionId = ds.nextPositionId[msg.sender]++;
        ds.leveragedPositions[msg.sender].push(LibDiamond.LeveragedPosition({
            positionId: positionId,
            entryPrice: price,
            size: positionSize,
            leverage: leverage,
            liquidationPrice: calculateLiquidationPrice(price, leverage, isLong),
            isLong: isLong,
            isOpen: true,
            token: IERC20(token),
            amount: amount,
            collateralAmount: amount
        }));

        // Execute swap with slippage protection
        if (isLong) {
            _executeSwapForLong(token, positionSize, maxSlippage);
        } else {
            _executeSwapForShort(token, positionSize, maxSlippage);
        }

        // Collect trading fee
        IFeeManagement(ds.feeManagementFacet).collectFee(token, tradingFee);

        emit PositionOpened(
            msg.sender,
            token,
            amount,
            leverage,
            isLong,
            price,
            borrowedAmount,
            block.timestamp
        );
    }

    /**
     * @notice Closes a leveraged position
     * @param positionId The ID of the position to close
     * @param maxSlippage Maximum acceptable slippage
     */
    function closePosition(
        uint256 positionId,
        uint256 maxSlippage
    ) external nonReentrant {
        require(maxSlippage <= MAX_SLIPPAGE, "Slippage too high");

        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        LibDiamond.LeveragedPosition storage position = _getPosition(msg.sender, positionId);
        require(position.isOpen, "Position already closed");

        uint256 currentPrice = IPriceOracleFacet(ds.priceOracleFacet).getPrice(address(position.token));
        
        // Calculate PnL
        uint256 pnl;
        if (position.isLong) {
            pnl = position.size * (currentPrice > position.entryPrice ? 
                (currentPrice - position.entryPrice) : 0) / SCALE;
        } else {
            pnl = position.size * (position.entryPrice > currentPrice ? 
                (position.entryPrice - currentPrice) : 0) / SCALE;
        }

        // Calculate trading fee
        uint256 tradingFee = IFeeManagement(ds.feeManagementFacet).calculateTradingFee(position.size);

        // Update borrowed amount
        uint256 borrowedAmount = (position.size * (position.leverage - 100)) / 100;
        ds.marginAccounts[msg.sender].borrowed -= borrowedAmount;

        // Execute closing swap with slippage protection
        if (position.isLong) {
            _executeSwapForCloseLong(address(position.token), position.size, maxSlippage);
        } else {
            _executeSwapForCloseShort(address(position.token), position.size, maxSlippage);
        }

        // Collect trading fee
        IFeeManagement(ds.feeManagementFacet).collectFee(address(position.token), tradingFee);

        // Close position
        position.isOpen = false;

        emit PositionClosed(
            msg.sender,
            address(position.token),
            positionId,
            currentPrice,
            pnl,
            block.timestamp
        );
    }

    /**
     * @notice Calculates the buying power for a user
     * @param user The user address
     * @return The calculated buying power
     */
    function calculateBuyingPower(address user) public view returns (uint256) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        uint256 totalValue = 0;

        for (uint256 i = 0; i < ds.supportedTokens.length; i++) {
            address token = ds.supportedTokens[i];
            uint256 balance = ds.marginAccounts[user].balance[token];
            if (balance > 0) {
                uint256 price = IPriceOracleFacet(ds.priceOracleFacet).getPrice(token);
                totalValue += (balance * price) / SCALE;
            }
        }

        return totalValue > ds.marginAccounts[user].borrowed ? 
            totalValue - ds.marginAccounts[user].borrowed : 0;
    }

    /**
     * @notice Returns the function selectors for this facet
     * @return selectors Array of function selectors
     */
    function getMarginTradingFacetSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](3);
        selectors[0] = this.openPosition.selector;
        selectors[1] = this.closePosition.selector;
        selectors[2] = this.calculateBuyingPower.selector;
        return selectors;
    }

    /**
     * @dev Gets a position by ID
     * @param user The user address
     * @param positionId The position ID
     * @return The position
     */
    function _getPosition(
        address user,
        uint256 positionId
    ) internal view returns (LibDiamond.LeveragedPosition storage) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        
        for (uint256 i = 0; i < ds.leveragedPositions[user].length; i++) {
            if (ds.leveragedPositions[user][i].positionId == positionId) {
                return ds.leveragedPositions[user][i];
            }
        }
        
        revert("Position not found");
    }

    /**
     * @dev Calculates liquidation price for a position
     * @param entryPrice The entry price
     * @param leverage The leverage used
     * @param isLong Whether the position is long
     * @return The liquidation price
     */
    function calculateLiquidationPrice(
        uint256 entryPrice,
        uint256 leverage,
        bool isLong
    ) internal pure returns (uint256) {
        uint256 liquidationThreshold = (leverage * LIQUIDATION_THRESHOLD) / 10000;
        if (isLong) {
            return (entryPrice * (10000 - liquidationThreshold)) / 10000;
        } else {
            return (entryPrice * (10000 + liquidationThreshold)) / 10000;
        }
    }

    /**
     * @dev Executes swap for long position
     * @param token The token address
     * @param amount The amount to swap
     * @param maxSlippage Maximum acceptable slippage
     */
    function _executeSwapForLong(
        address token,
        uint256 amount,
        uint256 maxSlippage
    ) internal {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        
        uint256 price = IPriceOracleFacet(ds.priceOracleFacet).getPrice(token);
        uint256 minOutput = (amount * price * (10000 - maxSlippage)) / (SCALE * 10000);
        
        DexHandler.SwapParams memory params = DexHandler.SwapParams({
            router: ds.feeManagement.ShibaSwapRouterAddress,
            tokenIn: ds.WBONE,
            tokenOut: token,
            amountIn: amount,
            minAmountOut: minOutput,
            maxSlippage: maxSlippage,
            deadline: block.timestamp + 15 minutes,
            priceOracle: ds.priceOracleFacet
        });

        DexHandler.executeEthForTokenSwap(params);
    }

    /**
     * @dev Executes swap for short position
     * @param token The token address
     * @param amount The amount to swap
     * @param maxSlippage Maximum acceptable slippage
     */
    function _executeSwapForShort(
        address token,
        uint256 amount,
        uint256 maxSlippage
    ) internal {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        
        uint256 price = IPriceOracleFacet(ds.priceOracleFacet).getPrice(token);
        uint256 minOutput = (amount * price * (10000 - maxSlippage)) / (SCALE * 10000);
        
        DexHandler.SwapParams memory params = DexHandler.SwapParams({
            router: ds.feeManagement.ShibaSwapRouterAddress,
            tokenIn: token,
            tokenOut: ds.WBONE,
            amountIn: amount,
            minAmountOut: minOutput,
            maxSlippage: maxSlippage,
            deadline: block.timestamp + 15 minutes,
            priceOracle: ds.priceOracleFacet
        });

        DexHandler.executeTokenForEthSwap(params);
    }

    /**
     * @dev Executes swap for closing long position
     * @param token The token address
     * @param amount The amount to swap
     * @param maxSlippage Maximum acceptable slippage
     */
    function _executeSwapForCloseLong(
        address token,
        uint256 amount,
        uint256 maxSlippage
    ) internal {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        
        uint256 price = IPriceOracleFacet(ds.priceOracleFacet).getPrice(token);
        uint256 minOutput = (amount * price * (10000 - maxSlippage)) / (SCALE * 10000);
        
        DexHandler.SwapParams memory params = DexHandler.SwapParams({
            router: ds.feeManagement.ShibaSwapRouterAddress,
            tokenIn: token,
            tokenOut: ds.WBONE,
            amountIn: amount,
            minAmountOut: minOutput,
            maxSlippage: maxSlippage,
            deadline: block.timestamp + 15 minutes,
            priceOracle: ds.priceOracleFacet
        });

        DexHandler.executeTokenForEthSwap(params);
    }

    /**
     * @dev Executes swap for closing short position
     * @param token The token address
     * @param amount The amount to swap
     * @param maxSlippage Maximum acceptable slippage
     */
    function _executeSwapForCloseShort(
        address token,
        uint256 amount,
        uint256 maxSlippage
    ) internal {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        
        uint256 price = IPriceOracleFacet(ds.priceOracleFacet).getPrice(token);
        uint256 minOutput = (amount * price * (10000 - maxSlippage)) / (SCALE * 10000);
        
        DexHandler.SwapParams memory params = DexHandler.SwapParams({
            router: ds.feeManagement.ShibaSwapRouterAddress,
            tokenIn: ds.WBONE,
            tokenOut: token,
            amountIn: amount,
            minAmountOut: minOutput,
            maxSlippage: maxSlippage,
            deadline: block.timestamp + 15 minutes,
            priceOracle: ds.priceOracleFacet
        });

        DexHandler.executeEthForTokenSwap(params);
    }
}