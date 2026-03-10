// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {IRegistry, IVestingPenaltyManager, VestingType, BaseService, VESTING_PENALTY_MANAGER_ID} from "../Index.sol";

contract VestingPenaltyManager is IVestingPenaltyManager, BaseService {
    mapping(VestingType => uint32[]) private _percentages;
    mapping(VestingType => uint32[]) private _dates;

    constructor(IRegistry registry) BaseService(registry, VESTING_PENALTY_MANAGER_ID) {
        // Early claim of service fee penalty
        // 7-day - 40%
        // 45-days - 0%
        _percentages[VestingType.ServiceFee] = [40, 0];
        _dates[VestingType.ServiceFee] = [7, 45];
        // Early claim of unstaking penalty
        // 7-day - 80%
        // 60-days - 50%
        // 180-days - 0%
        _percentages[VestingType.Unstake] = [80, 50, 0];
        _dates[VestingType.Unstake] = [7, 60, 180];
        // Early claim of rewards penalty
        // 7-day - 80%
        // 60-days - 50%
        // 180-days - 0%
        _percentages[VestingType.Reward] = [80, 50, 0];
        _dates[VestingType.Reward] = [7, 60, 180];
    }

    /// @inheritdoc IVestingPenaltyManager
    function setVestingPenalties(
        VestingType vestingType,
        uint32[] memory percentages,
        uint32[] memory dates
    ) external override {
        _registry.getACLManager().requireConfigurationAdmin(msg.sender);
        require(percentages.length > 0, "Empty input");
        require(percentages.length == dates.length, "InputLengthMismatch");
        for (uint256 i = 0; i < percentages.length; i++) {
            require(percentages[i] <= 100, "Percentage>100");
        }
        _percentages[vestingType] = percentages;
        _dates[vestingType] = dates;
        emit VestingPenaltySet(vestingType, percentages, dates);
    }

    /// @inheritdoc IVestingPenaltyManager
    function getVestingPenalties(
        VestingType vestingType
    ) external view override returns (uint32[] memory, uint32[] memory) {
        return (_percentages[vestingType], _dates[vestingType]);
    }

    /// @inheritdoc IVestingPenaltyManager
    function getVestingPenalty(
        VestingType vestingType,
        uint32 daysToClaim
    ) external view override returns (uint256 percentage) {
        uint256 length = _dates[vestingType].length;
        for (uint256 i = 0; i < length; i++) {
            if (daysToClaim == _dates[vestingType][i]) {
                return _percentages[vestingType][i];
            }
        }
        revert("InvalidDaysToClaim");
    }
}
