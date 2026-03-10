// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {
    IRegistry,
    IStakeFundHolder,
    BaseHolder,
    STAKE_FUND_HOLDER_ID,
    STAKE_HANDLER_ID,
    SLASH_DEDUCTION_RECEIVER_ID,
    VESTING_FUND_HOLDER_ID
} from "../Index.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract StakeFundHolder is IStakeFundHolder, BaseHolder {
    using SafeERC20 for IERC20;

    /// @notice Modifier to restrict access to the current handler
    modifier onlyHandler() {
        require(_registry.getAddress(STAKE_HANDLER_ID) == msg.sender, "StakeFundHolder: handler only");
        _;
    }

    constructor(IRegistry registry) BaseHolder(registry, STAKE_FUND_HOLDER_ID) {}

    /// @inheritdoc IStakeFundHolder
    function sendStakedToken(address beneficiary, uint256 amount) external override onlyHandler {
        require(amount > 0, "Invalid amount");
        _requireKYC(beneficiary);
        _registry.getATHToken().safeTransfer(beneficiary, amount);
        emit StakedTokenSent(beneficiary, amount);
    }

    /// @inheritdoc IStakeFundHolder
    function sendSlashedToken(uint256 amount) external onlyHandler {
        require(amount > 0, "Invalid amount");
        _registry.getATHToken().safeTransfer(_registry.getAddress(SLASH_DEDUCTION_RECEIVER_ID), amount);
        emit StakeSlashedTokenSent(amount);
    }

    /// @inheritdoc IStakeFundHolder
    function sendVestingToken(uint256 amount) external onlyHandler {
        require(amount > 0, "Invalid amount");
        _registry.getATHToken().safeTransfer(_registry.getAddress(VESTING_FUND_HOLDER_ID), amount);
        emit StakeVestingTokenSent(amount);
    }
}
