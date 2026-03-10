// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {IRegistry, IVestingSchemeManager, VestingType, BaseService, VESTING_SCHEME_MANAGER_ID} from "../Index.sol";

contract VestingSchemeManager is IVestingSchemeManager, BaseService {
    mapping(VestingType => uint32[]) private _percentages;
    mapping(VestingType => uint32[]) private _dates;

    constructor(IRegistry registry) BaseService(registry, VESTING_SCHEME_MANAGER_ID) {
        // service_fee_vesting_time - default = 45 days
        _percentages[VestingType.ServiceFee] = [100];
        _dates[VestingType.ServiceFee] = [45];
        // unstake_vesting_time - default 180 days
        _percentages[VestingType.Unstake] = [100];
        _dates[VestingType.Unstake] = [180];
        // reward_first_portion_percentage - default 30
        // reward_second_portion_percentage - default 30
        // reward_first_portion_vesting_time - default 0 days
        // reward_second_portion_vesting_time - default 90 days
        // reward_third_portion_vesting_time - default 180 days
        _percentages[VestingType.Reward] = [30, 30, 40];
        _dates[VestingType.Reward] = [0, 90, 180];
    }

    /// @inheritdoc IVestingSchemeManager
    function setVestingScheme(
        VestingType vestingType,
        uint32[] memory percentages,
        uint32[] memory dates
    ) external override {
        _registry.getACLManager().requireConfigurationAdmin(msg.sender);
        require(percentages.length == dates.length, "InputLengthMismatch");
        uint256 totalPercentage;
        for (uint256 i = 0; i < percentages.length; i++) {
            totalPercentage += percentages[i];
        }
        require(totalPercentage == 100, "TotalPercentage!=100");
        _percentages[vestingType] = percentages;
        _dates[vestingType] = dates;
        emit VestingSchemeSet(vestingType, percentages, dates);
    }

    /// @inheritdoc IVestingSchemeManager
    function getVestingScheme(
        VestingType vestingType
    ) external view override returns (uint32[] memory, uint32[] memory) {
        return (_percentages[vestingType], _dates[vestingType]);
    }

    /// @inheritdoc IVestingSchemeManager
    function getVestingAmount(
        VestingType vestingType,
        uint256 amount
    ) external view override returns (uint256[] memory, uint32[] memory) {
        require(amount > 0, "Invalid amount");
        uint32 _today = today();
        uint32[] memory percentages = _percentages[vestingType];
        uint32[] memory vestingDays = new uint32[](percentages.length);
        uint256[] memory amounts = new uint256[](percentages.length);
        for (uint256 i = 0; i < percentages.length; i++) {
            vestingDays[i] = _today + _dates[vestingType][i];
            amounts[i] = (amount * percentages[i]) / 100;
        }
        return (amounts, vestingDays);
    }

    function today() public view returns (uint32) {
        return uint32(block.timestamp / 1 days);
    }
}
