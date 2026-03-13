// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {
    IRegistry,
    ITierController,
    IServiceFeeHandler,
    IStakeHandler,
    IVestingHandler,
    BaseService,
    TIER_CONTROLLER_ID
} from "../Index.sol";

contract TierController is ITierController, BaseService {
    mapping(bytes4 => uint8) private _functionTiers;
    uint8 private _defaultTier;

    constructor(IRegistry registry) BaseService(registry, TIER_CONTROLLER_ID) {
        // tier 1: claim / withdraw / unstake operations
        _functionTiers[IStakeHandler.unstake.selector] = 1;
        _functionTiers[IStakeHandler.delegationUnstake.selector] = 1;
        _functionTiers[IServiceFeeHandler.withdrawServiceFee.selector] = 1;
        _functionTiers[IVestingHandler.releaseHostVestedToken.selector] = 1;
        _functionTiers[IVestingHandler.releaseHostAllVestedToken.selector] = 1;
        _functionTiers[IVestingHandler.releaseDelegatorVestedToken.selector] = 1;
        _functionTiers[IVestingHandler.releaseDelegatorAllVestedToken.selector] = 1;
        _functionTiers[IVestingHandler.releaseReceiverVestedToken.selector] = 1;
        _functionTiers[IVestingHandler.releaseReceiverAllVestedToken.selector] = 1;
        _functionTiers[IVestingHandler.hostEarlyClaim.selector] = 1;
        _functionTiers[IVestingHandler.delegateEarlyClaim.selector] = 1;
        _functionTiers[IVestingHandler.receiverEarlyClaim.selector] = 1;

        // tier 2: all contract state-changing operations, including settlements
        _defaultTier = 2;
    }

    /// @inheritdoc ITierController
    function setFunctionTier(bytes4 functionSelector, uint8 tier) external override {
        _registry.getACLManager().requireDefaultAdmin(msg.sender);
        _functionTiers[functionSelector] = tier;
        emit TierChanged(functionSelector, tier);
    }

    /// @inheritdoc ITierController
    function getTier(bytes4 functionSelector) external view override returns (uint8) {
        if (_functionTiers[functionSelector] == 0) {
            return _defaultTier;
        }
        return _functionTiers[functionSelector];
    }

    /// @inheritdoc ITierController
    function setDefaultTier(uint8 tier) external override {
        _registry.getACLManager().requireDefaultAdmin(msg.sender);
        _defaultTier = tier;
        emit DefaultTierChanged(tier);
    }

    /// @inheritdoc ITierController
    function getDefaultTier() external view override returns (uint8) {
        return _defaultTier;
    }
}
