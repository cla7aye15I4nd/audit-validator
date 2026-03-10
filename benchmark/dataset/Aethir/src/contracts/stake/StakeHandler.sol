// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {
    IRegistry,
    IRequestVerifier,
    IStakeHandler,
    IStakeFundHolder,
    IAccountStorage,
    IVestingHandler,
    VestingType,
    VestingRecord,
    IStakeStorage,
    ISlashStorage,
    IStakeConfigurator,
    BaseService,
    STAKE_CONFIGURATOR_ID,
    STAKE_FUND_HOLDER_ID,
    STAKE_HANDLER_ID,
    SLASH_HANDLER_ID,
    STAKE_STORAGE_ID,
    VESTING_HANDLER_ID,
    ACCOUNT_STORAGE_ID,
    SLASH_STORAGE_ID
} from "../Index.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAccountHandler} from "../account/IAccountHandler.sol";

contract StakeHandler is IStakeHandler, BaseService {
    using SafeERC20 for IERC20;

    constructor(IRegistry registry) BaseService(registry, STAKE_HANDLER_ID) {}

    modifier onlySlashHandler() {
        require(_registry.getAddress(SLASH_HANDLER_ID) == msg.sender, "StakeHandler: only slash handler");
        _;
    }

    /// @inheritdoc IStakeHandler
    function stake(IRequestVerifier.VerifiableData calldata vdata) external override {
        bytes32 vhash = _verifier().verify(vdata, msg.sender, this.stake.selector);
        (uint256 tid, uint256 gid, uint256[] memory cids, uint256[] memory amounts, VestingRecord memory record) = abi
            .decode(vdata.params, (uint256, uint256, uint256[], uint256[], VestingRecord));

        require(cids.length > 0, "Empty input");
        require(cids.length == amounts.length, "Invalid input length");
        IAccountStorage _account = _accountStorage();
        require(_account.getWallet(tid) == msg.sender, "Host wallet only");
        require(_account.getGroup(tid, gid).delegator == address(0), "Delegator already set");
        uint256 totalAmount = _processStake(address(0), tid, gid, cids, amounts, record);

        emit StandardStake(msg.sender, tid, gid, cids, amounts, totalAmount, vdata.nonce, vhash);
    }

    function delegationStake(IRequestVerifier.VerifiableData calldata vdata) external override {
        bytes32 vhash = _verifier().verify(vdata, msg.sender, this.delegationStake.selector);
        (uint256 tid, uint256 gid, uint256[] memory cids, uint256[] memory amounts, VestingRecord memory record) = abi
            .decode(vdata.params, (uint256, uint256, uint256[], uint256[], VestingRecord));

        require(cids.length > 0, "Empty input");
        require(cids.length == amounts.length, "Invalid input length");
        IAccountStorage _account = _accountStorage();
        require(_account.getGroup(tid, gid).delegator == msg.sender, "Delegator wallet only");
        uint256 totalAmount = _processStake(msg.sender, tid, gid, cids, amounts, record);

        emit DelegationStake(msg.sender, tid, gid, cids, amounts, totalAmount, vdata.nonce, vhash);
    }

    /// @inheritdoc IStakeHandler
    function unstake(IRequestVerifier.VerifiableData calldata vdata) external override {
        bytes32 vhash = _verifier().verify(vdata, msg.sender, this.unstake.selector);
        (uint256 tid, uint256 gid, uint256[] memory cids) = abi.decode(vdata.params, (uint256, uint256, uint256[]));

        require(cids.length > 0, "Empty input");
        IAccountStorage _account = _accountStorage();
        require(_account.getWallet(tid) == msg.sender, "Host wallet only");
        require(_account.getGroup(tid, gid).delegator == address(0), "Delegator already set");

        (uint256 totalAmount, uint256[] memory amounts) = _processUnstake(tid, gid, cids);
        emit Unstake(msg.sender, tid, gid, cids, amounts, totalAmount, vdata.nonce, vhash);
    }

    function delegationUnstake(IRequestVerifier.VerifiableData calldata vdata) external override {
        bytes32 vhash = _verifier().verify(vdata, msg.sender, this.delegationUnstake.selector);
        (uint256 tid, uint256 gid, uint256[] memory cids) = abi.decode(vdata.params, (uint256, uint256, uint256[]));

        require(cids.length > 0, "Empty input");
        IAccountHandler.Group memory group = _accountStorage().getGroup(tid, gid);
        require(group.delegator != address(0), "Delegator not set");

        IAccountStorage _account = _accountStorage();
        require(
            _account.getGroup(tid, gid).delegator == msg.sender || _account.getWallet(tid) == msg.sender,
            "Delegator or host wallet only"
        );

        (uint256 totalAmount, uint256[] memory amounts) = _processUnstake(tid, gid, cids);
        emit DelegationUnstake(msg.sender, tid, gid, cids, amounts, totalAmount, vdata.nonce, vhash);
    }

    /// @inheritdoc IStakeHandler
    function forceUnstake(IRequestVerifier.VerifiableData calldata vdata) external override {
        bytes32 vhash = _verifier().verify(vdata, msg.sender, this.forceUnstake.selector);
        (uint256 tid, uint256 gid, uint256[] memory cids) = abi.decode(vdata.params, (uint256, uint256, uint256[]));

        require(cids.length > 0, "Empty input");
        (uint256 totalAmount, uint256[] memory amounts) = _processUnstake(tid, gid, cids);
        emit ForceUnstake(msg.sender, tid, gid, cids, amounts, totalAmount, vdata.nonce, vhash);
    }

    /// @inheritdoc IStakeHandler
    function deductStaked(
        uint256 tid,
        uint256 gid,
        uint256 cid,
        uint256 slashAmount
    ) external override onlySlashHandler {
        require(slashAmount > 0, "Invalid amount");

        uint256 totalAmount = _stakeStorage().unstakeSingleContainer(tid, gid, cid);
        require(totalAmount >= slashAmount, "Insufficient staked amount");

        _fundHolder().sendSlashedToken(slashAmount);

        uint256 remainingAmount = totalAmount - slashAmount;
        if (remainingAmount > 0) {
            _fundHolder().sendVestingToken(remainingAmount);
            _vestingHandler().createVesting(VestingType.Unstake, tid, gid, remainingAmount);
        }
    }

    /// @inheritdoc IStakeHandler
    function initialSettleStakingRecords(IRequestVerifier.VerifiableData calldata vdata) external override {
        bytes32 vhash = _verifier().verifyInitiator(vdata, this.initialSettleStakingRecords.selector);
        (uint256[] memory tids, uint256[] memory gids, uint256[][] memory cids, uint256[][] memory amounts) = abi
            .decode(vdata.params, (uint256[], uint256[], uint256[][], uint256[][]));

        require(tids.length > 0, "Empty input");
        require(
            tids.length == gids.length && tids.length == cids.length && tids.length == amounts.length,
            "Invalid input length"
        );
        IAccountStorage _account = _accountStorage();
        IStakeStorage _stake = _stakeStorage();
        for (uint256 i = 0; i < tids.length; i++) {
            address delegator = _account.getGroup(tids[i], gids[i]).delegator;
            uint256 totalAmount = _stake.stake(tids[i], gids[i], cids[i], amounts[i], delegator);
            emit InitialStake(delegator, tids[i], gids[i], cids[i], amounts[i], totalAmount, vdata.nonce, vhash);
        }
    }

    /// @inheritdoc IStakeHandler
    function initialSettleVestingRecords(IRequestVerifier.VerifiableData calldata vdata) external override {
        bytes32 vhash = _verifier().verifyInitiator(vdata, this.initialSettleVestingRecords.selector);
        (uint256[] memory tids, uint256[] memory gids, VestingRecord[] memory records) = abi.decode(
            vdata.params,
            (uint256[], uint256[], VestingRecord[])
        );

        require(tids.length > 0, "Empty input");
        require(tids.length == gids.length && gids.length == records.length, "lengths mismatch");

        for (uint256 i = 0; i < tids.length; i++) {
            _vestingHandler().initialVesting(VestingType.Unstake, tids[i], gids[i], records[i]);
        }

        emit UnstakeInitialSettled(tids, gids, records, vdata.nonce, vhash);
    }

    function _processStake(
        address delegator,
        uint256 tid,
        uint256 gid,
        uint256[] memory cids,
        uint256[] memory amounts,
        VestingRecord memory record
    ) private returns (uint256 totalAmount) {
        if (record.vestingDays.length > 0) {
            require(record.vestingDays.length == record.amounts.length, "Invalid vesting record");
            totalAmount = _stakeStorage().stake(tid, gid, cids, amounts, delegator);

            uint256 totalVested = 0;
            for (uint256 i = 0; i < record.vestingDays.length; i++) {
                totalVested += record.amounts[i];
            }

            uint256 restakeAmount = ((totalVested) * (100 - _config().getRestakingTransactionFeePercentage())) / 100;
            require(totalAmount >= restakeAmount, "Invalid restake amount");
            _vestingHandler().restakeVestedToken(tid, gid, record, totalVested - restakeAmount);
            if (totalAmount > restakeAmount) {
                // transfer the rest of the amount from the host or delegator to the fund holder
                _registry.getATHToken().safeTransferFrom(
                    msg.sender,
                    address(_fundHolder()),
                    totalAmount - restakeAmount
                );
            }
        } else {
            totalAmount = _stakeStorage().stake(tid, gid, cids, amounts, delegator);
            _registry.getATHToken().safeTransferFrom(msg.sender, address(_fundHolder()), totalAmount);
        }
    }

    /// @notice Processes the unstake operation.
    function _processUnstake(
        uint256 tid,
        uint256 gid,
        uint256[] memory cids
    ) private returns (uint256, uint256[] memory) {
        ISlashStorage slashStorage = _slashStorage();
        for (uint256 i = 0; i < cids.length; i++) {
            require(slashStorage.getTicket(tid, gid, cids[i]).amount == 0, "Outstanding penalties");
        }
        (uint256 totalAmount, uint256[] memory amounts) = _stakeStorage().unstake(tid, gid, cids);
        _fundHolder().sendVestingToken(totalAmount);
        _vestingHandler().createVesting(VestingType.Unstake, tid, gid, totalAmount);

        return (totalAmount, amounts);
    }

    /// @notice Returns the stake storage contract.
    function _stakeStorage() private view returns (IStakeStorage) {
        return IStakeStorage(_registry.getAddress(STAKE_STORAGE_ID));
    }

    /// @notice returns the address of the fund holder
    function _fundHolder() private view returns (IStakeFundHolder) {
        return IStakeFundHolder(_registry.getAddress(STAKE_FUND_HOLDER_ID));
    }

    /// @notice Returns the account handler contract.
    function _accountStorage() private view returns (IAccountStorage) {
        return IAccountStorage(_registry.getAddress(ACCOUNT_STORAGE_ID));
    }

    /// @notice Returns the vesting handler contract.
    function _vestingHandler() private view returns (IVestingHandler) {
        return IVestingHandler(_registry.getAddress(VESTING_HANDLER_ID));
    }

    /// @notice Returns the slash storage contract.
    function _slashStorage() private view returns (ISlashStorage) {
        return ISlashStorage(_registry.getAddress(SLASH_STORAGE_ID));
    }

    /// @notice Returns the stake configurator contract.
    function _config() private view returns (IStakeConfigurator) {
        return IStakeConfigurator(_registry.getAddress(STAKE_CONFIGURATOR_ID));
    }
}
