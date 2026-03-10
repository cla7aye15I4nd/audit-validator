// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import "../Index.sol" as Index;

contract ServiceIdList {
    bytes4 public constant ACCOUNT_HANDLER_ID = Index.ACCOUNT_HANDLER_ID;
    bytes4 public constant ACCOUNT_STORAGE_ID = Index.ACCOUNT_STORAGE_ID;
    bytes4 public constant KYC_WHITELIST_ID = Index.KYC_WHITELIST_ID;
    bytes4 public constant REQUEST_VERIFIER_ID = Index.REQUEST_VERIFIER_ID;
    bytes4 public constant USER_STORAGE_ID = Index.USER_STORAGE_ID;
    bytes4 public constant REWARD_COMMISSION_RECEIVER_ID = Index.REWARD_COMMISSION_RECEIVER_ID;
    bytes4 public constant REWARD_CONFIGURATOR_ID = Index.REWARD_CONFIGURATOR_ID;
    bytes4 public constant REWARD_HANDLER_ID = Index.REWARD_HANDLER_ID;
    bytes4 public constant REWARD_FUND_HOLDER_ID = Index.REWARD_FUND_HOLDER_ID;
    bytes4 public constant REWARD_STORAGE_ID = Index.REWARD_STORAGE_ID;
    bytes4 public constant BLACKLIST_MANAGER_ID = Index.BLACKLIST_MANAGER_ID;
    bytes4 public constant EMERGENCY_SWITCH_ID = Index.EMERGENCY_SWITCH_ID;
    bytes4 public constant TIER_CONTROLLER_ID = Index.TIER_CONTROLLER_ID;
    bytes4 public constant GRANT_POOL_ID = Index.GRANT_POOL_ID;
    bytes4 public constant SERVICE_FEE_COMMISSION_RECEIVER_ID = Index.SERVICE_FEE_COMMISSION_RECEIVER_ID;
    bytes4 public constant SERVICE_FEE_HANDLER_ID = Index.SERVICE_FEE_HANDLER_ID;
    bytes4 public constant SERVICE_FEE_STORAGE_ID = Index.SERVICE_FEE_STORAGE_ID;
    bytes4 public constant SERVICE_FEE_FUND_HOLDER_ID = Index.SERVICE_FEE_FUND_HOLDER_ID;
    bytes4 public constant SERVICE_FEE_CONFIGURATOR_ID = Index.SERVICE_FEE_CONFIGURATOR_ID;
    bytes4 public constant SLASH_CONFIGURATOR_ID = Index.SLASH_CONFIGURATOR_ID;
    bytes4 public constant SLASH_DEDUCTION_RECEIVER_ID = Index.SLASH_DEDUCTION_RECEIVER_ID;
    bytes4 public constant SLASH_HANDLER_ID = Index.SLASH_HANDLER_ID;
    bytes4 public constant SLASH_STORAGE_ID = Index.SLASH_STORAGE_ID;
    bytes4 public constant TICKET_MANAGER_ID = Index.TICKET_MANAGER_ID;
    bytes4 public constant RESTAKE_FEE_RECEIVER_ID = Index.RESTAKE_FEE_RECEIVER_ID;
    bytes4 public constant STAKE_CONFIGURATOR_ID = Index.STAKE_CONFIGURATOR_ID;
    bytes4 public constant STAKE_FUND_HOLDER_ID = Index.STAKE_FUND_HOLDER_ID;
    bytes4 public constant STAKE_HANDLER_ID = Index.STAKE_HANDLER_ID;
    bytes4 public constant STAKE_STORAGE_ID = Index.STAKE_STORAGE_ID;
    bytes4 public constant VESTING_CONFIGURATOR_ID = Index.VESTING_CONFIGURATOR_ID;
    bytes4 public constant VESTING_PENALTY_RECEIVER_ID = Index.VESTING_PENALTY_RECEIVER_ID;
    bytes4 public constant VESTING_PENALTY_MANAGER_ID = Index.VESTING_PENALTY_MANAGER_ID;
    bytes4 public constant VESTING_SCHEME_MANAGER_ID = Index.VESTING_SCHEME_MANAGER_ID;
    bytes4 public constant VESTING_STORAGE_ID = Index.VESTING_STORAGE_ID;
    bytes4 public constant VESTING_FUND_HOLDER_ID = Index.VESTING_FUND_HOLDER_ID;
    bytes4 public constant VESTING_HANDLER_ID = Index.VESTING_HANDLER_ID;
}
