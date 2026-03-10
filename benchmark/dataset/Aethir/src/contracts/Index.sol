// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

/* solhint-disable no-unused-import */
// account
import {IAccountHandler} from "./account/IAccountHandler.sol";
import {IAccountStorage} from "./account/IAccountStorage.sol";
import {IKYCWhitelist} from "./account/IKYCWhitelist.sol";

// base
import {IACLManager} from "./base/IACLManager.sol";
import {BaseHolder} from "./base/BaseHolder.sol";
import {BaseService} from "./base/BaseService.sol";
import {IRegistry} from "./base/IRegistry.sol";
import {IRequestVerifier} from "./base/IRequestVerifier.sol";
import {IUserStorage} from "./base/IUserStorage.sol";

// reward
import {IRewardCommissionReceiver} from "./reward/IRewardCommissionReceiver.sol";
import {IRewardConfigurator} from "./reward/IRewardConfigurator.sol";
import {IRewardHandler} from "./reward/IRewardHandler.sol";
import {IRewardFundHolder} from "./reward/IRewardFundHolder.sol";
import {IRewardStorage} from "./reward/IRewardStorage.sol";

// riskmanager
import {IBlackListManager} from "./riskmanager/IBlackListManager.sol";
import {IEmergencySwitch} from "./riskmanager/IEmergencySwitch.sol";
import {ITierController} from "./riskmanager/ITierController.sol";

// servicefee
import {IGrantPool} from "./servicefee/IGrantPool.sol";
import {IServiceFeeCommissionReceiver} from "./servicefee/IServiceFeeCommissionReceiver.sol";
import {IServiceFeeConfigurator} from "./servicefee/IServiceFeeConfigurator.sol";
import {IServiceFeeFundHolder} from "./servicefee/IServiceFeeFundHolder.sol";
import {IServiceFeeHandler} from "./servicefee/IServiceFeeHandler.sol";
import {IServiceFeeStorage} from "./servicefee/IServiceFeeStorage.sol";

// slash
import {ISlashConfigurator} from "./slash/ISlashConfigurator.sol";
import {ISlashDeductionReceiver} from "./slash/ISlashDeductionReceiver.sol";
import {ISlashHandler} from "./slash/ISlashHandler.sol";
import {ISlashStorage} from "./slash/ISlashStorage.sol";
import {ITicketManager} from "./slash/ITicketManager.sol";

// stake
import {IRestakeFeeReceiver} from "./stake/IRestakeFeeReceiver.sol";
import {IStakeConfigurator} from "./stake/IStakeConfigurator.sol";
import {IStakeFundHolder} from "./stake/IStakeFundHolder.sol";
import {IStakeHandler} from "./stake/IStakeHandler.sol";
import {IStakeStorage} from "./stake/IStakeStorage.sol";

// vesting
import {IVestingConfigurator} from "./vesting/IVestingConfigurator.sol";
import {IVestingFundHolder} from "./vesting/IVestingFundHolder.sol";
import {IVestingHandler, VestingType, VestingRecord} from "./vesting/IVestingHandler.sol";
import {IVestingPenaltyManager} from "./vesting/IVestingPenaltyManager.sol";
import {IVestingPenaltyReceiver} from "./vesting/IVestingPenaltyReceiver.sol";
import {IVestingSchemeManager} from "./vesting/IVestingSchemeManager.sol";
import {IVestingStorage} from "./vesting/IVestingStorage.sol";
/* solhint-enable */

bytes4 constant ACCOUNT_HANDLER_ID = type(IAccountHandler).interfaceId;
bytes4 constant ACCOUNT_STORAGE_ID = type(IAccountStorage).interfaceId;
bytes4 constant KYC_WHITELIST_ID = type(IKYCWhitelist).interfaceId;

bytes4 constant REQUEST_VERIFIER_ID = type(IRequestVerifier).interfaceId;
bytes4 constant USER_STORAGE_ID = type(IUserStorage).interfaceId;

bytes4 constant REWARD_COMMISSION_RECEIVER_ID = type(IRewardCommissionReceiver).interfaceId;
bytes4 constant REWARD_CONFIGURATOR_ID = type(IRewardConfigurator).interfaceId;
bytes4 constant REWARD_HANDLER_ID = type(IRewardHandler).interfaceId;
bytes4 constant REWARD_FUND_HOLDER_ID = type(IRewardFundHolder).interfaceId;
bytes4 constant REWARD_STORAGE_ID = type(IRewardStorage).interfaceId;

bytes4 constant BLACKLIST_MANAGER_ID = type(IBlackListManager).interfaceId;
bytes4 constant EMERGENCY_SWITCH_ID = type(IEmergencySwitch).interfaceId;
bytes4 constant TIER_CONTROLLER_ID = type(ITierController).interfaceId;

bytes4 constant GRANT_POOL_ID = type(IGrantPool).interfaceId;
bytes4 constant SERVICE_FEE_COMMISSION_RECEIVER_ID = type(IServiceFeeCommissionReceiver).interfaceId;
bytes4 constant SERVICE_FEE_HANDLER_ID = type(IServiceFeeHandler).interfaceId;
bytes4 constant SERVICE_FEE_STORAGE_ID = type(IServiceFeeStorage).interfaceId;
bytes4 constant SERVICE_FEE_FUND_HOLDER_ID = type(IServiceFeeFundHolder).interfaceId;
bytes4 constant SERVICE_FEE_CONFIGURATOR_ID = type(IServiceFeeConfigurator).interfaceId;

bytes4 constant SLASH_CONFIGURATOR_ID = type(ISlashConfigurator).interfaceId;
bytes4 constant SLASH_DEDUCTION_RECEIVER_ID = type(ISlashDeductionReceiver).interfaceId;
bytes4 constant SLASH_HANDLER_ID = type(ISlashHandler).interfaceId;
bytes4 constant SLASH_STORAGE_ID = type(ISlashStorage).interfaceId;
bytes4 constant TICKET_MANAGER_ID = type(ITicketManager).interfaceId;

bytes4 constant RESTAKE_FEE_RECEIVER_ID = type(IRestakeFeeReceiver).interfaceId;
bytes4 constant STAKE_CONFIGURATOR_ID = type(IStakeConfigurator).interfaceId;
bytes4 constant STAKE_FUND_HOLDER_ID = type(IStakeFundHolder).interfaceId;
bytes4 constant STAKE_HANDLER_ID = type(IStakeHandler).interfaceId;
bytes4 constant STAKE_STORAGE_ID = type(IStakeStorage).interfaceId;

bytes4 constant VESTING_CONFIGURATOR_ID = type(IVestingConfigurator).interfaceId;
bytes4 constant VESTING_PENALTY_RECEIVER_ID = type(IVestingPenaltyReceiver).interfaceId;
bytes4 constant VESTING_PENALTY_MANAGER_ID = type(IVestingPenaltyManager).interfaceId;
bytes4 constant VESTING_SCHEME_MANAGER_ID = type(IVestingSchemeManager).interfaceId;
bytes4 constant VESTING_STORAGE_ID = type(IVestingStorage).interfaceId;
bytes4 constant VESTING_FUND_HOLDER_ID = type(IVestingFundHolder).interfaceId;
bytes4 constant VESTING_HANDLER_ID = type(IVestingHandler).interfaceId;
