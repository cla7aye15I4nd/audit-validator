// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {IRegistry, IServiceFeeCommissionReceiver, BaseHolder, SERVICE_FEE_COMMISSION_RECEIVER_ID} from "../Index.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title ServiceFeeCommissionReceiver
/// @notice Receives service fee commission
contract ServiceFeeCommissionReceiver is IServiceFeeCommissionReceiver, BaseHolder {
    using SafeERC20 for IERC20;

    constructor(IRegistry registry) BaseHolder(registry, SERVICE_FEE_COMMISSION_RECEIVER_ID) {}

    /// @inheritdoc IServiceFeeCommissionReceiver
    function withdrawServiceFeeCommission(address recipient, uint256 amount) external override {
        _adminWithdrawToken(recipient, amount);
        emit ServiceFeeCommissionWithdrawn(recipient, amount);
    }
}
