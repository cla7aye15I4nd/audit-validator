// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {
    IRegistry,
    IVestingFundHolder,
    BaseHolder,
    VESTING_FUND_HOLDER_ID,
    VESTING_HANDLER_ID,
    VESTING_PENALTY_RECEIVER_ID,
    SLASH_DEDUCTION_RECEIVER_ID,
    RESTAKE_FEE_RECEIVER_ID,
    STAKE_FUND_HOLDER_ID
} from "../Index.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract VestingFundHolder is IVestingFundHolder, BaseHolder {
    using SafeERC20 for IERC20;

    /// @notice Modifier to restrict access to the current Vesting Handler
    modifier onlyHandler() {
        require(_registry.getAddress(VESTING_HANDLER_ID) == msg.sender, "VestingFundHolder: handler only");
        _;
    }

    constructor(IRegistry registry) BaseHolder(registry, VESTING_FUND_HOLDER_ID) {}

    /// @inheritdoc IVestingFundHolder
    function sendVestedToken(address beneficiary, uint256 amount) external onlyHandler {
        require(amount > 0, "Invalid amount");
        _requireKYC(beneficiary);
        _registry.getATHToken().safeTransfer(beneficiary, amount);
        emit VestedTokenSent(beneficiary, amount);
    }

    /// @inheritdoc IVestingFundHolder
    function sendRestakeFeeToken(uint256 amount) external onlyHandler {
        require(amount > 0, "Invalid amount");
        _registry.getATHToken().safeTransfer(_registry.getAddress(RESTAKE_FEE_RECEIVER_ID), amount);
        emit RestakeFeeTokenSent(amount);
    }

    /// @inheritdoc IVestingFundHolder
    function sendRestakeToken(uint256 amount) external onlyHandler {
        require(amount > 0, "Invalid amount");
        _registry.getATHToken().safeTransfer(_registry.getAddress(STAKE_FUND_HOLDER_ID), amount);
        emit RestakeTokenSent(amount);
    }

    /// @inheritdoc IVestingFundHolder
    function sendPenaltyToken(uint256 amount) external onlyHandler {
        require(amount > 0, "Invalid amount");
        _registry.getATHToken().safeTransfer(_registry.getAddress(VESTING_PENALTY_RECEIVER_ID), amount);
        emit PenaltyTokenSent(amount);
    }

    /// @inheritdoc IVestingFundHolder
    function sendSettleSlashToken(uint256 amount) external onlyHandler {
        require(amount > 0, "Invalid amount");
        _registry.getATHToken().safeTransfer(_registry.getAddress(SLASH_DEDUCTION_RECEIVER_ID), amount);
        emit SettleSlashTokenSent(amount);
    }
}
