// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {IRegistry, IVestingPenaltyReceiver, BaseHolder, VESTING_PENALTY_RECEIVER_ID} from "../Index.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract VestingPenaltyReceiver is IVestingPenaltyReceiver, BaseHolder {
    using SafeERC20 for IERC20;

    constructor(IRegistry registry) BaseHolder(registry, VESTING_PENALTY_RECEIVER_ID) {}

    /// @inheritdoc IVestingPenaltyReceiver
    function withdrawEarlyClaimPenalty(address to, uint256 amount) external {
        _adminWithdrawToken(to, amount);
        emit EarlyClaimPenaltyWithdrawn(to, amount);
    }
}
