// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {
    IRegistry,
    ISlashDeductionReceiver,
    BaseHolder,
    SLASH_DEDUCTION_RECEIVER_ID,
    SLASH_HANDLER_ID
} from "../Index.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title SlashDeductionReceiver
/// @notice Receives penalty payments.
contract SlashDeductionReceiver is ISlashDeductionReceiver, BaseHolder {
    using SafeERC20 for IERC20;

    constructor(IRegistry registry) BaseHolder(registry, SLASH_DEDUCTION_RECEIVER_ID) {}

    /// @notice Modifier to restrict access to the current handler
    modifier onlyHandler() {
        require(_registry.getAddress(SLASH_HANDLER_ID) == msg.sender, "SlashHandler only");
        _;
    }

    /// @inheritdoc ISlashDeductionReceiver
    function withdrawSlashPenalty(address recipient, uint256 amount) external override {
        _adminWithdrawToken(recipient, amount);
        emit PenaltySlashWithdrawn(recipient, amount);
    }

    /// @inheritdoc ISlashDeductionReceiver
    function sendSlashToken(address beneficiary, uint256 amount) external override onlyHandler {
        require(amount > 0, "Invalid amount");
        _registry.getATHToken().safeTransfer(beneficiary, amount);
        emit DeductedSlashingTokenSent(beneficiary, amount);
    }
}
