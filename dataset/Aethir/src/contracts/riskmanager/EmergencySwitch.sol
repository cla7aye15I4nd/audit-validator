// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {
    IRegistry,
    IEmergencySwitch,
    ITierController,
    BaseService,
    EMERGENCY_SWITCH_ID,
    TIER_CONTROLLER_ID
} from "../Index.sol";

contract EmergencySwitch is IEmergencySwitch, BaseService {
    uint8 public pausedTier = 0;

    constructor(IRegistry registry) BaseService(registry, EMERGENCY_SWITCH_ID) {}

    /// @inheritdoc IEmergencySwitch
    function pause(uint8 _tier) external override {
        _registry.getACLManager().requireDefaultAdmin(msg.sender);
        pausedTier = _tier;
        emit TierChanged(pausedTier);
    }

    /// @inheritdoc IEmergencySwitch
    function isAllowed(bytes4 functionSelector) external view override returns (bool) {
        ITierController tierController = ITierController(_registry.getAddress(TIER_CONTROLLER_ID));
        uint8 functionTier = tierController.getTier(functionSelector);
        return functionTier > pausedTier;
    }
}
