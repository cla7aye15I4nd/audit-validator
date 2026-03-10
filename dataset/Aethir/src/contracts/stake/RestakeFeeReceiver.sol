// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {IRegistry, IRestakeFeeReceiver, BaseHolder, RESTAKE_FEE_RECEIVER_ID} from "../Index.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title RestakeFeeReceiver
/// @notice Receives restake transactions fees
contract RestakeFeeReceiver is IRestakeFeeReceiver, BaseHolder {
    using SafeERC20 for IERC20;

    constructor(IRegistry registry) BaseHolder(registry, RESTAKE_FEE_RECEIVER_ID) {}

    /// @inheritdoc IRestakeFeeReceiver
    function withdrawRestakeFee(address recipient, uint256 amount) external override {
        _adminWithdrawToken(recipient, amount);
        emit RestakeFeeWithdrawn(recipient, amount);
    }
}
