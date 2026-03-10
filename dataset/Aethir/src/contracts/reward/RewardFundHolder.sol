// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {
    IRegistry,
    IRewardFundHolder,
    BaseHolder,
    REWARD_HANDLER_ID,
    REWARD_FUND_HOLDER_ID,
    REWARD_COMMISSION_RECEIVER_ID,
    VESTING_FUND_HOLDER_ID,
    SLASH_DEDUCTION_RECEIVER_ID
} from "../Index.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title RewardFundHolder
/// @notice Holds reward token
contract RewardFundHolder is IRewardFundHolder, BaseHolder {
    using SafeERC20 for IERC20;

    /// @notice Modifier to restrict access to the current handler
    modifier onlyHandler() {
        require(_registry.getAddress(REWARD_HANDLER_ID) == msg.sender, "RewardHandler only");
        _;
    }

    constructor(IRegistry registry) BaseHolder(registry, REWARD_FUND_HOLDER_ID) {}

    /// @inheritdoc IRewardFundHolder
    function sendRewardToken(address beneficiary, uint256 amount) external override onlyHandler {
        require(amount > 0, "Invalid amount");
        _requireKYC(beneficiary);
        _registry.getATHToken().safeTransfer(beneficiary, amount);
        emit RewardTokenSent(beneficiary, amount);
    }

    /// @inheritdoc IRewardFundHolder
    function sendCommissionToken(uint256 amount) external override onlyHandler {
        require(amount > 0, "Invalid amount");
        _registry.getATHToken().safeTransfer(_registry.getAddress(REWARD_COMMISSION_RECEIVER_ID), amount);
        emit RewardCommissionTokenSent(amount);
    }

    /// @inheritdoc IRewardFundHolder
    function sendVestingToken(uint256 amount) external override onlyHandler {
        require(amount > 0, "Invalid amount");
        _registry.getATHToken().safeTransfer(_registry.getAddress(VESTING_FUND_HOLDER_ID), amount);
        emit RewardVestingTokenSent(amount);
    }

    /// @inheritdoc IRewardFundHolder
    function sendSlashedToken(uint256 amount) external override onlyHandler {
        require(amount > 0, "Invalid amount");
        _registry.getATHToken().safeTransfer(_registry.getAddress(SLASH_DEDUCTION_RECEIVER_ID), amount);
        emit RewardSlashedTokenSent(amount);
    }

    /// @inheritdoc IRewardFundHolder
    function withdrawRewardToken(address recipient, uint256 amount) external override {
        _adminWithdrawToken(recipient, amount);
        emit RewardTokenWithdrawn(recipient, amount);
    }
}
