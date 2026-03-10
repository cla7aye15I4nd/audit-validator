// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "../../lib/openzeppelin/token/ERC20/IERC20.sol";
import {IConfig} from "../config/IConfig.sol";
import {LiquidityManagerStorage} from "./LiquidityManagerStorage.sol";

import {SolidStateDiamond} from "../../lib/solidstate/proxy/diamond/SolidStateDiamond.sol";

contract LiquidityManager is SolidStateDiamond {
    constructor(
        address config,
        address tokenStaking,
        address tokenReward,
        uint256 rewardPerDay,
        uint256 rewardEndsAt
    ) {
        LiquidityManagerStorage.Layout storage l = LiquidityManagerStorage.layout();

        l.config = IConfig(config);
        l.tokenStaking = IERC20(tokenStaking);
        l.tokenReward = IERC20(tokenReward);
        l.rewardPerDay = rewardPerDay;
        l.rewardEndsAt = rewardEndsAt;

        l.lastRewardTime = block.timestamp;
    }
}
