// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {
    IRegistry,
    IAccountHandler,
    IAccountStorage,
    ISlashStorage,
    IVestingConfigurator,
    IVestingStorage,
    IVestingHandler,
    VestingType,
    VestingRecord,
    IVestingFundHolder,
    IVestingPenaltyManager,
    IVestingSchemeManager,
    BaseService,
    ACCOUNT_STORAGE_ID,
    VESTING_FUND_HOLDER_ID,
    VESTING_CONFIGURATOR_ID,
    VESTING_SCHEME_MANAGER_ID,
    VESTING_PENALTY_MANAGER_ID,
    VESTING_HANDLER_ID,
    VESTING_STORAGE_ID,
    STAKE_HANDLER_ID,
    SLASH_HANDLER_ID,
    SLASH_STORAGE_ID,
    SERVICE_FEE_HANDLER_ID,
    REWARD_HANDLER_ID
} from "../Index.sol";

contract VestingHandler is IVestingHandler, BaseService {
    mapping(VestingType => bytes4) private _handlers;

    constructor(IRegistry registry) BaseService(registry, VESTING_HANDLER_ID) {
        _handlers[VestingType.ServiceFee] = SERVICE_FEE_HANDLER_ID;
        _handlers[VestingType.Reward] = REWARD_HANDLER_ID;
        _handlers[VestingType.Unstake] = STAKE_HANDLER_ID;
        _handlers[VestingType.Stake] = STAKE_HANDLER_ID;
    }

    /// @inheritdoc IVestingHandler
    function createVesting(VestingType vestingType, uint256 tid, uint256 gid, uint256 amount) external override {
        require(_registry.getAddress(_handlers[vestingType]) == msg.sender, "InvalidHandler");
        (uint256[] memory amounts, uint32[] memory vestingDays) = _scheme().getVestingAmount(vestingType, amount);
        address beneficiary = _beneficiary(vestingType, tid, gid);
        _storage().increaseVestingAmounts(vestingType, tid, gid, beneficiary, VestingRecord(amounts, vestingDays));
        emit VestingCreated(beneficiary, vestingType, tid, gid, VestingRecord(amounts, vestingDays));
    }

    /// @inheritdoc IVestingHandler
    function initialVesting(
        VestingType vestingType,
        uint256 tid,
        uint256 gid,
        VestingRecord calldata record
    ) external override {
        require(_registry.getAddress(_handlers[vestingType]) == msg.sender, "InvalidHandler");
        address beneficiary = _beneficiary(vestingType, tid, gid);
        _storage().increaseVestingAmounts(vestingType, tid, gid, beneficiary, record);
        emit VestingCreated(beneficiary, vestingType, tid, gid, record);
    }

    /// @inheritdoc IVestingHandler
    function releaseHostVestedToken(
        uint256[] calldata tids,
        uint256[] calldata gids,
        VestingRecord[] calldata fees,
        VestingRecord[] calldata rewards,
        VestingRecord[] calldata stakes
    ) external override {
        _verifier().checkRisk(this.releaseHostVestedToken.selector, msg.sender);
        uint256 len = tids.length;
        require(len > 0, "Empty input");
        require(
            len == gids.length && len == fees.length && len == rewards.length && len == stakes.length,
            "Invalid length"
        );
        for (uint256 i = 0; i < len; i++) {
            _releaseHostVestedToken(tids[i], gids[i], fees[i], rewards[i], stakes[i]);
        }
    }

    /// @inheritdoc IVestingHandler
    function releaseHostAllVestedToken(
        uint256[] calldata tids,
        uint256[] calldata gids,
        bool[] calldata releaseServiceFees,
        bool[] calldata releaseRewards,
        bool[] calldata releaseUnstakes
    ) external override {
        _verifier().checkRisk(this.releaseHostAllVestedToken.selector, msg.sender);
        uint256 len = tids.length;
        require(len > 0, "Empty input");
        require(
            len == gids.length &&
                len == releaseServiceFees.length &&
                len == releaseRewards.length &&
                len == releaseUnstakes.length,
            "Invalid length"
        );

        IVestingStorage db = _storage();
        uint32 _today = today();
        VestingRecord memory emptyRecord = VestingRecord(new uint256[](0), new uint32[](0));
        for (uint256 i = 0; i < len; i++) {
            _releaseHostVestedToken(
                tids[i],
                gids[i],
                releaseServiceFees[i]
                    ? db.getVestedRecord(VestingType.ServiceFee, tids[i], gids[i], address(0), _today)
                    : emptyRecord,
                releaseRewards[i]
                    ? db.getVestedRecord(VestingType.Reward, tids[i], gids[i], address(0), _today)
                    : emptyRecord,
                releaseUnstakes[i]
                    ? db.getVestedRecord(VestingType.Unstake, tids[i], gids[i], address(0), _today)
                    : emptyRecord
            );
        }
    }

    function _releaseHostVestedToken(
        uint256 tid,
        uint256 gid,
        VestingRecord memory fees,
        VestingRecord memory rewards,
        VestingRecord memory stakes
    ) internal {
        require(_slashStorage().totalPenalty(tid) == 0, "Outstanding penalties");
        _requireVested(fees);
        _requireVested(rewards);
        _requireVested(stakes);

        IVestingStorage db = _storage();
        uint256 amount;
        if (fees.amounts.length > 0) {
            amount += db.decreaseVestingAmounts(VestingType.ServiceFee, tid, gid, address(0), fees);
            emit VestingReleased(address(0), VestingType.ServiceFee, tid, gid, fees);
        }
        if (rewards.amounts.length > 0) {
            amount += db.decreaseVestingAmounts(VestingType.Reward, tid, gid, address(0), rewards);
            emit VestingReleased(address(0), VestingType.Reward, tid, gid, rewards);
        }
        if (stakes.amounts.length > 0) {
            amount += db.decreaseVestingAmounts(VestingType.Unstake, tid, gid, address(0), stakes);
            emit VestingReleased(address(0), VestingType.Unstake, tid, gid, stakes);
        }
        require(amount >= _config().getMinimumClaimAmount(), "Minimum claim amount not met");
        _fundHolder().sendVestedToken(_accountStorage().getWallet(tid), amount);
    }

    /// @inheritdoc IVestingHandler
    function releaseDelegatorVestedToken(
        uint256[] calldata tids,
        uint256[] calldata gids,
        VestingRecord[] calldata stakes
    ) external override {
        _verifier().checkRisk(this.releaseDelegatorVestedToken.selector, msg.sender);
        uint256 len = tids.length;
        require(len > 0, "Empty input");
        require(len == gids.length && len == stakes.length, "Invalid length");
        for (uint256 i = 0; i < len; i++) {
            _releaseDelegatorVestedToken(tids[i], gids[i], stakes[i]);
        }
    }

    /// @inheritdoc IVestingHandler
    function releaseDelegatorAllVestedToken(uint256[] calldata tids, uint256[] calldata gids) external override {
        _verifier().checkRisk(this.releaseDelegatorAllVestedToken.selector, msg.sender);
        uint256 len = tids.length;
        require(len > 0, "Empty input");
        require(len == gids.length, "Invalid length");

        IVestingStorage db = _storage();
        uint32 _today = today();
        for (uint256 i = 0; i < len; i++) {
            IAccountHandler.Group memory group = _accountStorage().getGroup(tids[i], gids[i]);
            _releaseDelegatorVestedToken(
                tids[i],
                gids[i],
                db.getVestedRecord(VestingType.Unstake, tids[i], gids[i], group.delegator, _today)
            );
        }
    }

    function _releaseDelegatorVestedToken(uint256 tid, uint256 gid, VestingRecord memory stakes) internal {
        if (stakes.amounts.length == 0) {
            return;
        }
        _requireVested(stakes);
        IAccountHandler.Group memory group = _accountStorage().getGroup(tid, gid);
        IVestingStorage db = _storage();
        address receiver = group.delegator;
        uint256 amount = db.decreaseVestingAmounts(VestingType.Unstake, tid, gid, receiver, stakes);
        require(amount >= _config().getMinimumClaimAmount(), "Minimum claim amount not met");
        _fundHolder().sendVestedToken(receiver, amount);
        emit VestingReleased(receiver, VestingType.Unstake, tid, gid, stakes);
    }

    /// @inheritdoc IVestingHandler
    function restakeVestedToken(
        uint256 tid,
        uint256 gid,
        VestingRecord calldata stakes,
        uint256 restakeFeeAmount
    ) external override {
        require(_registry.getAddress(STAKE_HANDLER_ID) == msg.sender, "InvalidHandler");
        require(stakes.amounts.length > 0, "Empty input");
        IAccountHandler.Group memory group = _accountStorage().getGroup(tid, gid);

        IVestingStorage db = _storage();
        uint256 amount = db.decreaseVestingAmounts(VestingType.Unstake, tid, gid, group.delegator, stakes);
        require(amount > restakeFeeAmount, "InsufficientAmount");
        if (restakeFeeAmount > 0) {
            _fundHolder().sendRestakeFeeToken(restakeFeeAmount);
        }
        _fundHolder().sendRestakeToken(amount - restakeFeeAmount);
        emit VestingRestaked(group.delegator, tid, gid, stakes, restakeFeeAmount);
    }

    /// @inheritdoc IVestingHandler
    function releaseReceiverVestedToken(
        uint256[] calldata tids,
        uint256[] calldata gids,
        VestingRecord[] calldata fees,
        VestingRecord[] calldata rewards
    ) external override {
        _verifier().checkRisk(this.releaseReceiverVestedToken.selector, msg.sender);
        uint256 len = tids.length;
        require(len > 0, "Empty input");
        require(len == gids.length && len == fees.length && len == rewards.length, "Invalid length");
        for (uint256 i = 0; i < len; i++) {
            _releaseReceiverVestedToken(tids[i], gids[i], fees[i], rewards[i]);
        }
    }

    /// @inheritdoc IVestingHandler
    function releaseReceiverAllVestedToken(
        uint256[] calldata tids,
        uint256[] calldata gids,
        bool[] calldata releaseServiceFees,
        bool[] calldata releaseRewards
    ) external override {
        _verifier().checkRisk(this.releaseReceiverAllVestedToken.selector, msg.sender);
        uint256 len = tids.length;
        require(len > 0, "Empty input");
        require(
            len == gids.length && len == releaseServiceFees.length && len == releaseRewards.length,
            "Invalid length"
        );

        IVestingStorage db = _storage();
        uint32 _today = today();
        VestingRecord memory emptyRecord = VestingRecord(new uint256[](0), new uint32[](0));
        for (uint256 i = 0; i < len; i++) {
            IAccountHandler.Group memory group = _accountStorage().getGroup(tids[i], gids[i]);
            _releaseReceiverVestedToken(
                tids[i],
                gids[i],
                releaseServiceFees[i]
                    ? db.getVestedRecord(VestingType.ServiceFee, tids[i], gids[i], group.feeReceiver, _today)
                    : emptyRecord,
                releaseRewards[i]
                    ? db.getVestedRecord(VestingType.Reward, tids[i], gids[i], group.rewardReceiver, _today)
                    : emptyRecord
            );
        }
    }

    function _releaseReceiverVestedToken(
        uint256 tid,
        uint256 gid,
        VestingRecord memory fees,
        VestingRecord memory rewards
    ) internal {
        _requireVested(fees);
        _requireVested(rewards);

        IAccountHandler.Group memory group = _accountStorage().getGroup(tid, gid);
        IVestingStorage db = _storage();
        IVestingFundHolder fundHolder = _fundHolder();
        if (fees.amounts.length > 0) {
            address receiver = group.feeReceiver;
            uint256 amount = db.decreaseVestingAmounts(VestingType.ServiceFee, tid, gid, receiver, fees);
            require(amount >= _config().getMinimumClaimAmount(), "Minimum claim amount not met");
            fundHolder.sendVestedToken(receiver, amount);
            emit VestingReleased(receiver, VestingType.ServiceFee, tid, gid, fees);
        }
        if (rewards.amounts.length > 0) {
            address receiver = group.rewardReceiver;
            uint256 amount = db.decreaseVestingAmounts(VestingType.Reward, tid, gid, receiver, rewards);
            require(amount >= _config().getMinimumClaimAmount(), "Minimum claim amount not met");
            fundHolder.sendVestedToken(receiver, amount);
            emit VestingReleased(receiver, VestingType.Reward, tid, gid, rewards);
        }
    }

    /// @inheritdoc IVestingHandler
    function hostEarlyClaim(
        uint256[] calldata tids,
        uint256[] calldata gids,
        VestingType[] calldata vestingTypes,
        VestingRecord[] calldata records,
        uint32 earlyClaimDays
    ) external override {
        _verifier().checkRisk(this.hostEarlyClaim.selector, msg.sender);
        uint256 len = tids.length;
        require(len > 0, "Empty input");
        require(len == gids.length && len == vestingTypes.length && len == records.length, "Invalid length");
        for (uint256 i = 0; i < len; i++) {
            require(_slashStorage().totalPenalty(tids[i]) == 0, "Outstanding penalties");
            require(_accountStorage().getWallet(tids[i]) == msg.sender, "Invalid tid");
            _earlyClaim(address(0), tids[i], gids[i], vestingTypes[i], records[i], earlyClaimDays);
        }
    }

    /// @inheritdoc IVestingHandler
    function delegateEarlyClaim(
        uint256[] calldata tids,
        uint256[] calldata gids,
        VestingRecord[] calldata records,
        uint32 earlyClaimDays
    ) external override {
        _verifier().checkRisk(this.delegateEarlyClaim.selector, msg.sender);
        uint256 len = tids.length;
        require(len > 0, "Empty input");
        require(len == gids.length && len == records.length, "Invalid length");
        for (uint256 i = 0; i < len; i++) {
            IAccountHandler.Group memory group = _accountStorage().getGroup(tids[i], gids[i]);
            require(group.delegator == msg.sender, "Delegator only");
            _earlyClaim(msg.sender, tids[i], gids[i], VestingType.Unstake, records[i], earlyClaimDays);
        }
    }

    /// @inheritdoc IVestingHandler
    function receiverEarlyClaim(
        uint256[] calldata tids,
        uint256[] calldata gids,
        VestingType[] calldata vestingTypes,
        VestingRecord[] calldata records,
        uint32 earlyClaimDays
    ) external override {
        _verifier().checkRisk(this.receiverEarlyClaim.selector, msg.sender);
        uint256 len = tids.length;
        require(len > 0, "Empty input");
        require(len == gids.length && len == vestingTypes.length && len == records.length, "Invalid length");
        for (uint256 i = 0; i < len; i++) {
            IAccountHandler.Group memory group = _accountStorage().getGroup(tids[i], gids[i]);
            require(
                (group.rewardReceiver == msg.sender && vestingTypes[i] == VestingType.Reward) ||
                    (group.feeReceiver == msg.sender && vestingTypes[i] == VestingType.ServiceFee),
                "Invalid receiver"
            );
            _earlyClaim(msg.sender, tids[i], gids[i], vestingTypes[i], records[i], earlyClaimDays);
        }
    }

    function _earlyClaim(
        address beneficiary,
        uint256 tid,
        uint256 gid,
        VestingType vestingType,
        VestingRecord memory record,
        uint32 earlyClaimDays
    ) internal {
        if (record.amounts.length == 0) {
            return;
        }
        uint256 penaltyPercentage = _penaltyManager().getVestingPenalty(vestingType, earlyClaimDays);
        uint32 _today = today();
        for (uint256 i = 0; i < record.vestingDays.length; i++) {
            require(record.vestingDays[i] > _today + earlyClaimDays, "Invalid vesting day");
        }

        IVestingStorage db = _storage();
        uint256 amount = db.decreaseVestingAmounts(vestingType, tid, gid, beneficiary, record);
        uint256 penaltyAmount = (amount * penaltyPercentage) / 100;

        VestingRecord memory newRecord = VestingRecord(new uint256[](1), new uint32[](1));
        newRecord.vestingDays[0] = _today + earlyClaimDays;
        newRecord.amounts[0] = amount - penaltyAmount;
        db.increaseVestingAmounts(vestingType, tid, gid, beneficiary, newRecord);

        _fundHolder().sendPenaltyToken(penaltyAmount);
        emit EarlyClaimed(beneficiary, vestingType, tid, gid, record, penaltyAmount, penaltyPercentage, earlyClaimDays);
    }

    /// @inheritdoc IVestingHandler
    function settleSlash(
        uint256 tid,
        uint256 gid,
        VestingRecord calldata fees,
        VestingRecord calldata rewards
    ) external override {
        require(_registry.getAddress(SLASH_HANDLER_ID) == msg.sender, "Slash only");
        address host = _accountStorage().getWallet(tid);
        require(host != address(0), "Invalid tid");
        IVestingStorage db = _storage();
        uint256 amount;
        if (fees.amounts.length > 0) {
            amount += db.decreaseVestingAmounts(VestingType.ServiceFee, tid, gid, host, fees);
            emit VestingSlashed(host, VestingType.ServiceFee, tid, gid, fees);
        }
        if (rewards.amounts.length > 0) {
            amount += db.decreaseVestingAmounts(VestingType.Reward, tid, gid, host, rewards);
            emit VestingSlashed(host, VestingType.Reward, tid, gid, rewards);
        }
        _fundHolder().sendSettleSlashToken(amount);
    }

    /// @notice returns the address of the fund holder
    function _fundHolder() private view returns (IVestingFundHolder) {
        return IVestingFundHolder(_registry.getAddress(VESTING_FUND_HOLDER_ID));
    }

    /// @notice returns the address of the configurator
    function _storage() private view returns (IVestingStorage) {
        return IVestingStorage(_registry.getAddress(VESTING_STORAGE_ID));
    }

    /// @notice returns the address of the configurator
    function _config() private view returns (IVestingConfigurator) {
        return IVestingConfigurator(_registry.getAddress(VESTING_CONFIGURATOR_ID));
    }

    /// @notice returns the address of the scheme manager
    function _scheme() private view returns (IVestingSchemeManager) {
        return IVestingSchemeManager(_registry.getAddress(VESTING_SCHEME_MANAGER_ID));
    }

    /// @notice returns the address of the penalty manager
    function _penaltyManager() private view returns (IVestingPenaltyManager) {
        return IVestingPenaltyManager(_registry.getAddress(VESTING_PENALTY_MANAGER_ID));
    }

    /// @notice Returns the account handler contract.
    function _accountStorage() private view returns (IAccountStorage) {
        return IAccountStorage(_registry.getAddress(ACCOUNT_STORAGE_ID));
    }

    /// @notice Returns the slash storage contract.
    function _slashStorage() private view returns (ISlashStorage) {
        return ISlashStorage(_registry.getAddress(SLASH_STORAGE_ID));
    }

    function today() public view returns (uint32) {
        return uint32(block.timestamp / 1 days);
    }

    function _requireVested(VestingRecord memory record) private view {
        uint32 _today = today();
        for (uint256 i = 0; i < record.vestingDays.length; i++) {
            require(record.vestingDays[i] <= _today, "Invalid day");
            require(record.amounts[i] > 0, "Invalid amount");
        }
    }

    /// @notice returns the beneficiary address for the group
    /// return address(0) if the vested tokens go to the host
    function _beneficiary(VestingType vestingType, uint256 tid, uint256 gid) internal view returns (address) {
        IAccountHandler.Group memory group = _accountStorage().getGroup(tid, gid);
        if (vestingType == VestingType.Unstake) {
            return group.delegator;
        } else if (vestingType == VestingType.ServiceFee) {
            return group.feeReceiver;
        } else if (vestingType == VestingType.Reward) {
            return group.rewardReceiver;
        }
        return address(0);
    }
}
