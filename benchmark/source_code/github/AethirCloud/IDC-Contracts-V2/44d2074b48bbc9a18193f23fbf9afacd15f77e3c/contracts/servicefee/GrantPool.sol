// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {
    IRegistry,
    IGrantPool,
    BaseHolder,
    GRANT_POOL_ID,
    SERVICE_FEE_HANDLER_ID,
    SERVICE_FEE_FUND_HOLDER_ID
} from "../Index.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title GrantPool
/// @notice Holds grant funds
contract GrantPool is IGrantPool, BaseHolder {
    using SafeERC20 for IERC20;

    /// @notice Modifier to restrict access to the current handler
    modifier onlyHandler() {
        require(_registry.getAddress(SERVICE_FEE_HANDLER_ID) == msg.sender, "ServiceFeeHandler only");
        _;
    }

    constructor(IRegistry registry) BaseHolder(registry, GRANT_POOL_ID) {}

    /// @inheritdoc IGrantPool
    function spendGrantFund(uint256 amount) external override onlyHandler {
        require(amount > 0, "Invalid amount");
        _registry.getATHToken().safeTransfer(_registry.getAddress(SERVICE_FEE_FUND_HOLDER_ID), amount);
        emit GrantSpent(amount);
    }

    /// @inheritdoc IGrantPool
    function withdrawGrantFund(address recipient, uint256 amount) external override {
        _adminWithdrawToken(recipient, amount);
        emit GrantWithdrawn(recipient, amount);
    }
}
