// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {
    IRegistry,
    IServiceFeeFundHolder,
    BaseHolder,
    SERVICE_FEE_FUND_HOLDER_ID,
    SERVICE_FEE_HANDLER_ID,
    SLASH_DEDUCTION_RECEIVER_ID,
    SERVICE_FEE_COMMISSION_RECEIVER_ID,
    VESTING_FUND_HOLDER_ID
} from "../Index.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract ServiceFeeFundHolder is IServiceFeeFundHolder, BaseHolder {
    using SafeERC20 for IERC20;

    constructor(IRegistry registry) BaseHolder(registry, SERVICE_FEE_FUND_HOLDER_ID) {}

    /// @notice Modifier to restrict access to the current handler
    modifier onlyHandler() {
        require(_registry.getAddress(SERVICE_FEE_HANDLER_ID) == msg.sender, "ServiceFeeHandler only");
        _;
    }

    /// @inheritdoc IServiceFeeFundHolder
    function sendServiceFeeToken(address beneficiary, uint256 amount) external override onlyHandler {
        require(amount > 0, "Invalid amount");
        _requireKYC(beneficiary);
        _registry.getATHToken().safeTransfer(beneficiary, amount);
        emit ServiceFeeTokenSent(beneficiary, amount);
    }

    /// @inheritdoc IServiceFeeFundHolder
    function sendCommissionToken(uint256 amount) external onlyHandler {
        require(amount > 0, "Invalid amount");
        _registry.getATHToken().safeTransfer(_registry.getAddress(SERVICE_FEE_COMMISSION_RECEIVER_ID), amount);
        emit ServiceFeeCommissionTokenSent(amount);
    }

    /// @inheritdoc IServiceFeeFundHolder
    function sendVestingToken(uint256 amount) external onlyHandler {
        require(amount > 0, "Invalid amount");
        _registry.getATHToken().safeTransfer(_registry.getAddress(VESTING_FUND_HOLDER_ID), amount);
        emit ServiceFeeVestingTokenSent(amount);
    }

    /// @inheritdoc IServiceFeeFundHolder
    function sendSlashedToken(uint256 amount) external onlyHandler {
        require(amount > 0, "Invalid amount");
        _registry.getATHToken().safeTransfer(_registry.getAddress(SLASH_DEDUCTION_RECEIVER_ID), amount);
        emit ServiceFeeSlashedTokenSent(amount);
    }
}
