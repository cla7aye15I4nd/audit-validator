// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "../interfaces/IDex.sol";
import "../interfaces/IPriceOracleFacet.sol";

/**
 * @title DexHandler
 * @dev Library for managing DEX interactions with proper slippage protection
 * @notice Handles all AMM interactions with comprehensive safety checks
 */
library DexHandler {
    using SafeERC20 for IERC20;

    // Constants for swap operations
    uint256 private constant SCALE = 1e18;
    uint256 private constant MAX_SLIPPAGE = 300; // 3%
    uint256 private constant MIN_SWAP_DELAY = 5 minutes;
    uint256 private constant MAX_SWAP_DELAY = 20 minutes;
    uint256 private constant MIN_LIQUIDITY_REQUIREMENT = 1000; // $1000 equivalent
    uint256 private constant MAX_IMPACT_PERCENTAGE = 200; // 2%

    /**
     * @dev Struct for swap parameters
     */
    struct SwapParams {
        address router;          // DEX router address
        address tokenIn;         // Input token address
        address tokenOut;        // Output token address
        uint256 amountIn;       // Input amount
        uint256 minAmountOut;   // Minimum output amount
        uint256 maxSlippage;    // Maximum allowed slippage
        uint256 deadline;       // Swap deadline
        address priceOracle;    // Price oracle address for validation
    }

    /**
     * @dev Emitted when a swap is executed
     */
    event SwapExecuted(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 price,
        uint256 slippage,
        uint256 timestamp
    );

    /**
     * @dev Emitted when slippage protection is triggered
     */
    event SlippageProtectionTriggered(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 expectedAmount,
        uint256 actualAmount,
        uint256 slippage,
        uint256 timestamp
    );

    /**
     * @notice Executes a token to ETH swap with comprehensive safety checks
     * @param params The swap parameters
     * @return receivedAmount The amount of ETH received
     */
    function executeTokenForEthSwap(
        SwapParams memory params
    ) internal returns (uint256 receivedAmount) {
        // Validate parameters
        validateSwapParams(params);

        // Check liquidity and price impact
        require(
            checkLiquidityAndImpact(params),
            "Insufficient liquidity or high price impact"
        );

        // Get initial balance
        uint256 initialBalance = address(this).balance;

        // Approve router
        IERC20(params.tokenIn).forceApprove(params.router, params.amountIn);

        // Create swap path
        address[] memory path = new address[](2);
        path[0] = params.tokenIn;
        path[1] = params.tokenOut;

        // Execute swap with try-catch
        try IUniswapV2Router02(params.router).swapExactTokensForETHSupportingFeeOnTransferTokens(
            params.amountIn,
            params.minAmountOut,
            path,
            address(this),
            params.deadline
        ) {
            // Calculate received amount
            receivedAmount = address(this).balance - initialBalance;
            
            // Verify received amount
            require(receivedAmount >= params.minAmountOut, "Insufficient output amount");
            
            uint256 expectedAmount = IUniswapV2Router02(params.router).getAmountsOut(
                params.amountIn,
                path
            )[1];
            
            validateReceivedAmount(
                params,
                receivedAmount,
                expectedAmount
            );

            // Reset approval
            IERC20(params.tokenIn).forceApprove(params.router, 0);

            // Emit success event
            emit SwapExecuted(
                params.tokenIn,
                params.tokenOut,
                params.amountIn,
                receivedAmount,
                IPriceOracleFacet(params.priceOracle).getPrice(params.tokenIn),
                calculateSlippage(expectedAmount, receivedAmount),
                block.timestamp
            );

            return receivedAmount;
        } catch {
            // Reset approval on failure
            IERC20(params.tokenIn).forceApprove(params.router, 0);
            revert("Swap execution failed");
        }
    }

    /**
     * @notice Executes an ETH to token swap with comprehensive safety checks
     * @param params The swap parameters
     * @return receivedAmount The amount of tokens received
     */
    function executeEthForTokenSwap(
        SwapParams memory params
    ) internal returns (uint256 receivedAmount) {
        // Validate parameters
        validateSwapParams(params);

        // Check liquidity and price impact
        require(
            checkLiquidityAndImpact(params),
            "Insufficient liquidity or high price impact"
        );

        // Get initial balance
        uint256 initialBalance = IERC20(params.tokenOut).balanceOf(address(this));

        // Create swap path
        address[] memory path = new address[](2);
        path[0] = params.tokenIn;
        path[1] = params.tokenOut;

        // Execute swap with try-catch
        try IUniswapV2Router02(params.router).swapExactETHForTokensSupportingFeeOnTransferTokens{
            value: params.amountIn
        }(
            params.minAmountOut,
            path,
            address(this),
            params.deadline
        ) {
            // Calculate received amount
            receivedAmount = IERC20(params.tokenOut).balanceOf(address(this)) - initialBalance;
            
            // Verify received amount
            require(receivedAmount >= params.minAmountOut, "Insufficient output amount");
            
            uint256 expectedAmount = IUniswapV2Router02(params.router).getAmountsOut(
                params.amountIn,
                path
            )[1];
            
            validateReceivedAmount(
                params,
                receivedAmount,
                expectedAmount
            );

            // Emit success event
            emit SwapExecuted(
                params.tokenIn,
                params.tokenOut,
                params.amountIn,
                receivedAmount,
                IPriceOracleFacet(params.priceOracle).getPrice(params.tokenOut),
                calculateSlippage(expectedAmount, receivedAmount),
                block.timestamp
            );

            return receivedAmount;
        } catch {
            revert("Swap execution failed");
        }
    }

    /**
     * @dev Validates swap parameters
     * @param params The swap parameters to validate
     */
    function validateSwapParams(SwapParams memory params) private view {
        require(params.router != address(0), "Invalid router");
        require(params.tokenIn != address(0), "Invalid input token");
        require(params.tokenOut != address(0), "Invalid output token");
        require(params.tokenIn != params.tokenOut, "Invalid token pair");
        require(params.amountIn > 0, "Invalid amount");
        require(params.minAmountOut > 0, "Invalid min amount");
        require(params.maxSlippage <= MAX_SLIPPAGE, "Slippage too high");
        require(
            params.deadline >= block.timestamp + MIN_SWAP_DELAY &&
            params.deadline <= block.timestamp + MAX_SWAP_DELAY,
            "Invalid deadline"
        );
    }

    /**
     * @dev Checks liquidity and price impact
     * @param params The swap parameters
     * @return Whether the swap meets liquidity and price impact requirements
     */
    function checkLiquidityAndImpact(
        SwapParams memory params
    ) private view returns (bool) {
        uint256 price = IPriceOracleFacet(params.priceOracle).getPrice(params.tokenIn);
        uint256 swapValue = (params.amountIn * price) / SCALE;
        
        // Check minimum liquidity requirement
        if (swapValue < MIN_LIQUIDITY_REQUIREMENT) {
            return false;
        }

        // Check price impact
        uint256 impact = calculatePriceImpact(params);
        return impact <= MAX_IMPACT_PERCENTAGE;
    }

    /**
     * @dev Validates received amount against expected amount
     * @param params The swap parameters
     * @param receivedAmount The actual received amount
     * @param expectedAmount The expected amount
     */
    function validateReceivedAmount(
        SwapParams memory params,
        uint256 receivedAmount,
        uint256 expectedAmount
    ) private {
        require(receivedAmount >= params.minAmountOut, "Insufficient output amount");
        
        uint256 slippage = calculateSlippage(expectedAmount, receivedAmount);
        if (slippage > params.maxSlippage) {
            emit SlippageProtectionTriggered(
                params.tokenIn,
                params.tokenOut,
                expectedAmount,
                receivedAmount,
                slippage,
                block.timestamp
            );
            revert("Slippage too high");
        }
    }

    /**
     * @dev Calculates slippage between expected and actual amounts
     * @param expected The expected amount
     * @param actual The actual amount
     * @return The slippage percentage
     */
    function calculateSlippage(
        uint256 expected,
        uint256 actual
    ) private pure returns (uint256) {
        if (expected <= actual) {
            return 0;
        }
        return ((expected - actual) * 10000) / expected;
    }

    /**
     * @dev Calculates price impact of a swap
     * @param params The swap parameters
     * @return The price impact percentage
     */
    function calculatePriceImpact(
        SwapParams memory params
    ) private view returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = params.tokenIn;
        path[1] = params.tokenOut;

        uint256[] memory amounts = IUniswapV2Router02(params.router).getAmountsOut(
            params.amountIn,
            path
        );

        uint256 marketPrice = IPriceOracleFacet(params.priceOracle).getPrice(params.tokenIn);
        uint256 executionPrice = (amounts[0] * SCALE) / amounts[amounts.length - 1];

        return ((marketPrice > executionPrice ? marketPrice - executionPrice : executionPrice - marketPrice) * 10000) / marketPrice;
    }
}