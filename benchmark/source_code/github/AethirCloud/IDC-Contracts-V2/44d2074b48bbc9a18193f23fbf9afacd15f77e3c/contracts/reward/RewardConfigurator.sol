// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {IRegistry, IRewardConfigurator, BaseService, REWARD_CONFIGURATOR_ID} from "../Index.sol";

contract RewardConfigurator is IRewardConfigurator, BaseService {
    uint16 private _rewardCommissionPercentage = 5; // 5%

    constructor(IRegistry registry) BaseService(registry, REWARD_CONFIGURATOR_ID) {}

    /// @inheritdoc IRewardConfigurator
    function getRewardCommissionPercentage() external view override returns (uint16) {
        return _rewardCommissionPercentage;
    }

    /// @inheritdoc IRewardConfigurator
    function setRewardCommissionPercentage(uint16 percentage) external override {
        _registry.getACLManager().requireConfigurationAdmin(msg.sender);
        require(percentage <= 100, "Value exceeds maximum");
        _rewardCommissionPercentage = percentage;
        emit RewardCommissionChanged(percentage);
    }
}
