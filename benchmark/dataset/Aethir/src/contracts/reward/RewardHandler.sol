// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {
    IRegistry,
    IRewardConfigurator,
    IRewardHandler,
    IRewardFundHolder,
    IRewardStorage,
    IRequestVerifier,
    IVestingHandler,
    VestingType,
    VestingRecord,
    BaseService,
    REWARD_CONFIGURATOR_ID,
    REWARD_HANDLER_ID,
    REWARD_STORAGE_ID,
    REWARD_FUND_HOLDER_ID,
    VESTING_HANDLER_ID
} from "../Index.sol";

contract RewardHandler is IRewardHandler, BaseService {
    constructor(IRegistry registry) BaseService(registry, REWARD_HANDLER_ID) {}

    /// @inheritdoc IRewardHandler
    function setEmissionSchedule(IRequestVerifier.VerifiableData calldata vdata) external override {
        bytes32 vhash = _verifier().verify(vdata, msg.sender, this.setEmissionSchedule.selector);

        (uint256[] memory epochs, uint256[] memory amounts) = abi.decode(vdata.params, (uint256[], uint256[]));
        require(epochs.length > 0, "Empty input");
        require(epochs.length == amounts.length, "Invalid input");
        _storage().setEmissionSchedule(epochs, amounts);
        emit EmissionScheduleSet(epochs, amounts, vdata.nonce, vhash);
    }

    /// @inheritdoc IRewardHandler
    function settleReward(IRequestVerifier.VerifiableData calldata vdata) external override {
        bytes32 vhash = _verifier().verify(vdata, msg.sender, this.settleReward.selector);

        (uint256[] memory tids, uint256[] memory gids, uint256[] memory amounts, uint256[] memory slashAmounts) = abi
            .decode(vdata.params, (uint256[], uint256[], uint256[], uint256[]));
        require(tids.length > 0, "Empty input");
        require(
            tids.length == gids.length && gids.length == amounts.length && amounts.length == slashAmounts.length,
            "RewardHandler: lengths mismatch"
        );
        for (uint256 i = 0; i < tids.length; i++) {
            _processSettleReward(tids[i], gids[i], amounts[i], slashAmounts[i]);
        }
        emit RewardSettled(tids, gids, amounts, vdata.nonce, vhash);
    }

    /// @inheritdoc IRewardHandler
    function initialSettleReward(IRequestVerifier.VerifiableData calldata vdata) external override {
        bytes32 vhash = _verifier().verifyInitiator(vdata, this.initialSettleReward.selector);
        (uint256[] memory tids, uint256[] memory gids, VestingRecord[] memory records) = abi.decode(
            vdata.params,
            (uint256[], uint256[], VestingRecord[])
        );
        require(tids.length > 0, "Empty input");
        require(tids.length == gids.length && gids.length == records.length, "lengths mismatch");
        for (uint256 i = 0; i < tids.length; i++) {
            _vestingHandler().initialVesting(VestingType.Reward, tids[i], gids[i], records[i]);
        }

        emit RewardInitialSettled(tids, gids, records, vdata.nonce, vhash);
    }

    function _processSettleReward(uint256 tid, uint256 gid, uint256 amount, uint256 slashAmount) private {
        require(amount > 0, "RewardHandler: invalid amount");
        require(slashAmount <= amount, "RewardHandler: invalid slash");
        _storage().allocateReward(amount);

        uint16 commissionPercentage = _configurator().getRewardCommissionPercentage();
        uint256 commissionAmount = (amount * commissionPercentage) / 100;
        uint256 netSlashAmount = (slashAmount * (100 - commissionPercentage)) / 100;
        uint256 receiverAmount = amount - commissionAmount - netSlashAmount;

        if (netSlashAmount > 0) {
            _fundHolder().sendSlashedToken(netSlashAmount);
        }
        if (commissionAmount > 0) {
            _fundHolder().sendCommissionToken(commissionAmount);
        }
        if (receiverAmount > 0) {
            _fundHolder().sendVestingToken(receiverAmount);
            _vestingHandler().createVesting(VestingType.Reward, tid, gid, receiverAmount);
        }
    }

    function _configurator() private view returns (IRewardConfigurator) {
        return IRewardConfigurator(_registry.getAddress(REWARD_CONFIGURATOR_ID));
    }

    function _fundHolder() private view returns (IRewardFundHolder) {
        return IRewardFundHolder(_registry.getAddress(REWARD_FUND_HOLDER_ID));
    }

    function _storage() private view returns (IRewardStorage) {
        return IRewardStorage(_registry.getAddress(REWARD_STORAGE_ID));
    }

    /// @notice Returns the vesting handler contract.
    function _vestingHandler() private view returns (IVestingHandler) {
        return IVestingHandler(_registry.getAddress(VESTING_HANDLER_ID));
    }
}
