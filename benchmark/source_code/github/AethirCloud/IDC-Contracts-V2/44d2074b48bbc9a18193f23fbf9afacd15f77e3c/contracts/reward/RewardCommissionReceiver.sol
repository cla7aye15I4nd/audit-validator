// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {IRegistry, IRewardCommissionReceiver, BaseHolder, REWARD_COMMISSION_RECEIVER_ID} from "../Index.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract RewardCommissionReceiver is IRewardCommissionReceiver, BaseHolder {
    using SafeERC20 for IERC20;

    constructor(IRegistry registry) BaseHolder(registry, REWARD_COMMISSION_RECEIVER_ID) {}

    function withdrawRewardCommission(address recipient, uint256 amount) external override {
        _adminWithdrawToken(recipient, amount);
        emit RewardCommissionWithdrawn(recipient, amount);
    }
}
