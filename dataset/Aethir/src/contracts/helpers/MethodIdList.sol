// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import "../Index.sol" as Index;

contract MethodIdList {
    bytes4 public constant CREATE_ACCOUNT = Index.IAccountHandler.createAccount.selector;
    bytes4 public constant REBIND_WALLET = Index.IAccountHandler.rebindWallet.selector;
    bytes4 public constant CREATE_GROUP = Index.IAccountHandler.createGroup.selector;
    bytes4 public constant ASSIGN_DELEGATOR = Index.IAccountHandler.assignDelegator.selector;
    bytes4 public constant REVOKE_DELEGATOR = Index.IAccountHandler.revokeDelegator.selector;
    bytes4 public constant SET_FEE_RECEIVER = Index.IAccountHandler.setFeeReceiver.selector;
    bytes4 public constant REVOKE_FEE_RECEIVER = Index.IAccountHandler.revokeFeeReceiver.selector;
    bytes4 public constant SET_REWARD_RECEIVER = Index.IAccountHandler.setRewardReceiver.selector;
    bytes4 public constant REVOKE_REWARD_RECEIVER = Index.IAccountHandler.revokeRewardReceiver.selector;
    bytes4 public constant INITIAL_ACCOUNT_MIGRATION = Index.IAccountHandler.initialAccountsMigration.selector;
    bytes4 public constant BATCH_UPDATE_GROUP_SETTINGS = Index.IAccountHandler.batchUpdateGroupSettings.selector;
    bytes4 public constant BATCH_SET_RECEIVERS = Index.IAccountHandler.batchSetReceivers.selector;
    bytes4 public constant UPDATE_KYC = Index.IKYCWhitelist.updateKYC.selector;
    bytes4 public constant SET_REWARD_EMISSION_SCHEDULE = Index.IRewardHandler.setEmissionSchedule.selector;
    bytes4 public constant SETTLE_REWARD = Index.IRewardHandler.settleReward.selector;
    bytes4 public constant INITIAL_SETTLE_REWARD = Index.IRewardHandler.initialSettleReward.selector;
    bytes4 public constant LOCK_SERVICE_FEE = Index.IServiceFeeHandler.lockServiceFee.selector;
    bytes4 public constant UNLOCK_SERVICE_FEE = Index.IServiceFeeHandler.unlockServiceFee.selector;
    bytes4 public constant SETTLE_SERVICE_FEE = Index.IServiceFeeHandler.settleServiceFee.selector;
    bytes4 public constant INITIAL_SETTLE_SERVICE_FEE = Index.IServiceFeeHandler.initialSettleServiceFee.selector;
    bytes4 public constant INITIAL_TENANTS_SERVICE_FEE = Index.IServiceFeeHandler.initialTenantsServiceFee.selector;
    bytes4 public constant ADD_PENALTY = Index.ITicketManager.addPenalty.selector;
    bytes4 public constant SETTLE_PENALTY = Index.ITicketManager.settlePenalty.selector;
    bytes4 public constant DEDUCT_PENALTY = Index.ITicketManager.deductPenalty.selector;
    bytes4 public constant CANCEL_PENALTY = Index.ITicketManager.cancelPenalty.selector;
    bytes4 public constant REFUND_TENANTS = Index.ITicketManager.refundTenants.selector;
    bytes4 public constant STAKE = Index.IStakeHandler.stake.selector;
    bytes4 public constant DELEGATION_STAKE = Index.IStakeHandler.delegationStake.selector;
    bytes4 public constant UNSTAKE = Index.IStakeHandler.unstake.selector;
    bytes4 public constant DELEGATION_UNSTAKE = Index.IStakeHandler.delegationUnstake.selector;
    bytes4 public constant FORCE_UNSTAKE = Index.IStakeHandler.forceUnstake.selector;
    bytes4 public constant INITIAL_SETTLE_STAKING = Index.IStakeHandler.initialSettleStakingRecords.selector;
    bytes4 public constant INITIAL_SETTLE_VESTING = Index.IStakeHandler.initialSettleVestingRecords.selector;
}
