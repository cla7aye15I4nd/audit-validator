// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "../interfaces/IDex.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

library DexHandler {
    /// @notice The address of the DEX contract. This should be replaced with the actual DEX address.
    address constant DEX_ADDRESS = address(0);  // TODO: Replace with the actual DEX address

    /// @notice The address of the WBONE (Wrapped Bone) token.
    address constant WBONE = address(0xC76F4c819D820369Fb2d7C1531aB3Bb18e6fE8d8);

    /**
     * @notice Executes a token to ETH swap using the DEX.
     * @param inputToken The address of the token to be swapped.
     * @param inputAmount The amount of the input token.
     * @param minOutputAmount The minimum amount of ETH expected from the swap.
     * @return receivedAmount The amount of ETH received from the swap.
     */
    function executeTokenForEthSwap(
        address inputToken,
        uint256 inputAmount,
        uint256 minOutputAmount
    ) internal returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = inputToken;
        path[1] = WBONE;  // ETH

        uint256 initialBalance = address(this).balance;

        IDex(DEX_ADDRESS).swapExactTokensForEthSupportingFeeOnTransferTokens(inputAmount, minOutputAmount, path, address(this), block.timestamp + 15 minutes);

        uint256 receivedAmount = address(this).balance - initialBalance;
        return receivedAmount;
    }

    /**
     * @notice Executes an ETH to token swap using the DEX.
     * @param outputToken The address of the token to be received.
     * @param ethAmount The amount of ETH to be swapped.
     * @param minOutputAmount The minimum amount of the output token expected from the swap.
     * @return receivedAmount The amount of the output token received from the swap.
     */
    function executeEthForTokenSwap(
        address outputToken,
        uint256 ethAmount,
        uint256 minOutputAmount
    ) internal returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = WBONE;  // ETH
        path[1] = outputToken;

        IDex(DEX_ADDRESS).swapExactEthForTokensSupportingFeeOnTransferTokens{value: ethAmount}(minOutputAmount, path, address(this), block.timestamp + 15 minutes);

        uint256 receivedAmount = IERC20(outputToken).balanceOf(address(this));
        return receivedAmount;
    }
}