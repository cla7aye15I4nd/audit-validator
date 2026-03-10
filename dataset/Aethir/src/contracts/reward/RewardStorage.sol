// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {IRegistry, IRewardStorage, BaseService, REWARD_HANDLER_ID, REWARD_STORAGE_ID} from "../Index.sol";

/// @title RewardStorage
contract RewardStorage is IRewardStorage, BaseService {
    mapping(uint32 => uint256) private _emissionAmounts;
    mapping(uint32 => uint256) private _allocatedAmounts;

    /// @notice Modifier to restrict access to the current handler
    modifier onlyHandler() {
        require(_registry.getAddress(REWARD_HANDLER_ID) == msg.sender, "RewardHandler only");
        _;
    }

    constructor(IRegistry registry) BaseService(registry, REWARD_STORAGE_ID) {}

    /// @inheritdoc IRewardStorage
    function getEmissionScheduleAt(uint256 epoch) external view override returns (uint256) {
        return _emissionAmounts[epochToDay(epoch)];
    }

    /// @inheritdoc IRewardStorage
    function setEmissionSchedule(uint256[] calldata epochs, uint256[] calldata amounts) external override onlyHandler {
        uint32 today = epochToDay(block.timestamp);
        require(epochs.length > 0, "Empty input");
        require(epochs.length == amounts.length, "Invalid input length");
        for (uint256 i = 0; i < epochs.length; i++) {
            uint32 epoch = epochToDay(epochs[i]);
            require(epoch > today || (epoch == today && _emissionAmounts[epoch] == 0), "Cannot update past dates");
            _emissionAmounts[epoch] = amounts[i];
        }
    }

    /// @inheritdoc IRewardStorage
    function getAllocatedAmount(uint256 epoch) external view override returns (uint256) {
        return _allocatedAmounts[epochToDay(epoch)];
    }

    /// @inheritdoc IRewardStorage
    function allocateReward(uint256 amount) external override onlyHandler {
        uint32 today = epochToDay(block.timestamp);
        require(amount > 0, "Invalid amount");
        require(_emissionAmounts[today] >= _allocatedAmounts[today] + amount, "Exceeds available emission");
        _allocatedAmounts[today] += amount;
        emit RewardAllocated(today, amount);
    }

    function epochToDay(uint256 epoch) public pure returns (uint32) {
        return uint32(epoch / 1 days);
    }
}
