# Aethir IDC Smart Contracts V2

Contracts to handle Aethir IDC service fee and incentive model

## Requirement

- Nodejs (version >=v20.18.2)
- Yarn (version >=1.22.10)
- Solidity (version =0.8.27)

## Deployment instructions

Clone code and install dependencies

```bash
$ git clone https://github.com/AethirCloud/IDC-Contracts-V2 contracts
$ pushd contracts
$ yarn
```

Open file `hardhat.config.ts` and update these value:

- Deployer private key at line 10 (or use enviroment `DEPLOYER_KEY`)
- Admin multisig wallet address at line 15
- Aethir token address at line 20

Test contract

```bash
$ yarn test
```

Compile contract

```bash
$ yarn compile
```

Deploy contract

```bash
$ yarn one:deploy # for arbitrum one mainnet or
$ yarn sepolia:deploy # for arbitrum sepolia testnet
```

Run initialize script

```bash
$ npx hardhat --network arbitrumOne init
```

(Optional) Verify contract

- Sign up for arbiscan account: https://arbiscan.io/register
- Generate api token: https://arbiscan.io/myapikey

```bash
$ export ETHERSCAN_API_KEY=<arbiscan_api_token>
$ yarn one:verify # for arbitrum one mainnet or
$ yarn sepolia:verify # for arbitrum sepolia testnet
```

## Roles

There are multiple roles in the system. At the beginning, these roles will be granted to multisig wallets. Later on, these roles will be transfered to the DAO.

- `DEFAULT_ADMIN_ROLE`: only accounts with this role will be able to grant or revoke other roles, set required signatures for validator and approver, and holds the highest authority and can pause the contract in emergency situations.
- `CONFIGURATION_ADMIN_ROLE`: Responsible for setting configurable parameters such as token receivers, signature thresholds, and vesting times, etc. Manages risk management parameters as the second-highest privileged role. By default, assigned to the same BOD's multisig wallet, but it can be set to another multisig wallet of the BOD with a lower signature threshold
- `FUND_WITHDRAW_ADMIN_ROLE`: Responsible for withdrawing funds from various fund holder contracts. This role can be granted to trusted operators who need to manage fund withdrawals.
- `MIGRATOR_ROLE`: this role has the permission to update the contract module. The new module contract and migration contract should be audited to make sure the migration contract only allow to update the corresponding module. After that, `DEFAULT_ADMIN_ROLE` will grant the `MIGRATOR_ROLE` for the migration contract.
- `VALIDATOR_ROLE`: this role is for the backend signers. [VerifiableData](#verifiabledata) need to be signed by at least [required validator](contracts/base/IACLManager.sol#L88) signer to be valid.
- `INIT_SETTLEMENT_OPERATOR`: Responsible for performing an initial settlement to record accumulated service fees and rewards from V1 off-chain into the current on-chain contract. The role is granted at the start of the contract and used exclusively to execute the initial settlement process. Once the initialization is complete, the `DEFAULT_ADMIN_ROLE` will revoke this role to prevent further usage

## Registry

The Registry contract is responsible for managing service implementations and their addresses by using ServiceID.

It allows for the initialization of services and their corresponding implementations, as well as providing access to the ACL manager and ATH token. The contract ensures that only the deployer can initialize the registry and that only the migrator can update service addresses and the version.

### Usage

Use `Registry` contract to retrieve the current contract address of a service

```solidity
address serviceAddress = Registry(registryAddress).getAddress(serviceID);
```

The backend may cache `serviceAddress` for improving performance and reducing cost. In that case, it should listen for `IRegistry.SetAddress` event to validate cache.

### Deployment

Registry deployment on each network:

- Sepolia: `0xEE96f22dD9E76c53B5596e2fbA8f69485Ffc7a46`
- Arbitrum: TBD

### Services

ServiceID can be found from below table:

| Service                         | Interface                                                                               | Service ID   |
| ------------------------------- | --------------------------------------------------------------------------------------- | ------------ |
| ACCOUNT_HANDLER                 | [IAccountHandler](contracts/account/IAccountHandler.sol)                                | `0xba708def` |
| ACCOUNT_STORAGE                 | [IAccountStorage](contracts/account/IAccountStorage.sol)                                | `0x9aca72b5` |
| REQUEST_VERIFIER                | [IRequestVerifier](contracts/base/IRequestVerifier.sol)                                 | `0x79818cb6` |
| USER_STORAGE                    | [IUserStorage](contracts/base/IUserStorage.sol)                                         | `0x6df2c862` |
| REWARD_COMMISSION_RECEIVER      | [IRewardCommissionReceiver](contracts/reward/IRewardCommissionReceiver.sol)             | `0xb7e7333c` |
| REWARD_CONFIGURATOR             | [IRewardConfigurator](contracts/reward/IRewardConfigurator.sol)                         | `0x5022abb6` |
| REWARD_HANDLER                  | [IRewardHandler](contracts/reward/IRewardHandler.sol)                                   | `0xa51ed0fb` |
| REWARD_FUND_HOLDER              | [IRewardFundHolder](contracts/reward/IRewardFundHolder.sol)                             | `0x1de246eb` |
| REWARD_STORAGE                  | [IRewardStorage](contracts/reward/IRewardStorage.sol)                                   | `0xe4ec62f6` |
| BLACKLIST_MANAGER               | [IBlacklistManager](contracts/riskmanager/IBlacklistManager.sol)                        | `0xbdd85f2e` |
| EMERGENCY_SWITCH                | [IEmergencySwitch](contracts/riskmanager/IEmergencySwitch.sol)                          | `0xc50241a2` |
| TIER_CONTROLLER                 | [ITierController](contracts/riskmanager/ITierController.sol)                            | `0x7027fe08` |
| GRANT_POOL                      | [IGrantPool](contracts/servicefee/IGrantPool.sol)                                       | `0x79ea9242` |
| SERVICE_FEE_COMMISSION_RECEIVER | [IServiceFeeCommissionReceiver](contracts/servicefee/IServiceFeeCommissionReceiver.sol) | `0x2b63a849` |
| SERVICE_FEE_HANDLER             | [IServiceFeeHandler](contracts/servicefee/IServiceFeeHandler.sol)                       | `0x207b11e3` |
| SERVICE_FEE_STORAGE             | [IServiceFeeStorage](contracts/servicefee/IServiceFeeStorage.sol)                       | `0x2d79b7df` |
| SERVICE_FEE_FUND_HOLDER         | [IServiceFeeFundHolder](contracts/servicefee/IServiceFeeFundHolder.sol)                 | `0x5c28bc63` |
| SERVICE_FEE_CONFIGURATOR        | [IServiceFeeConfigurator](contracts/servicefee/IServiceFeeConfigurator.sol)             | `0x149167e4` |
| SLASH_CONFIGURATOR              | [ISlashConfigurator](contracts/slash/ISlashConfigurator.sol)                            | `0x357996ff` |
| SLASH_DEDUCTION_RECEIVER        | [ISlashDeductionReceiver](contracts/slash/ISlashDeductionReceiver.sol)                  | `0x0d471920` |
| SLASH_HANDLER                   | [ISlashHandler](contracts/slash/ISlashHandler.sol)                                      | `0x30b322f5` |
| SLASH_STORAGE                   | [ISlashStorage](contracts/slash/ISlashStorage.sol)                                      | `0xa7b1206e` |
| TICKET_MANAGER                  | [ITicketManager](contracts/slash/ITicketManager.sol)                                    | `0x91199276` |
| RESTAKE_FEE_RECEIVER            | [IRestakeFeeReceiver](contracts/stake/IRestakeFeeReceiver.sol)                          | `0x1f1fcd7c` |
| STAKE_CONFIGURATOR              | [IStakeConfigurator](contracts/stake/IStakeConfigurator.sol)                            | `0x322102f2` |
| STAKE_FUND_HOLDER               | [IStakeFundHolder](contracts/stake/IStakeFundHolder.sol)                                | `0x8a589f5d` |
| STAKE_HANDLER                   | [IStakeHandler](contracts/stake/IStakeHandler.sol)                                      | `0x3d83c76c` |
| STAKE_STORAGE                   | [IStakeStorage](contracts/stake/IStakeStorage.sol)                                      | `0xd9d30449` |
| VESTING_CONFIGURATOR            | [IVestingConfigurator](contracts/vesting/IVestingConfigurator.sol)                      | `0xe2f6a5a8` |
| VESTING_PENALTY_RECEIVER        | [IVestingPenaltyReceiver](contracts/vesting/IVestingPenaltyReceiver.sol)                | `0xbcfc79d5` |
| VESTING_PENALTY_MANAGER         | [IVestingPenaltyManager](contracts/vesting/IVestingPenaltyManager.sol)                  | `0x2841a714` |
| VESTING_SCHEME_MANAGER          | [IVestingSchemeManager](contracts/vesting/IVestingSchemeManager.sol)                    | `0xd71c67c3` |
| VESTING_STORAGE                 | [IVestingStorage](contracts/vesting/IVestingStorage.sol)                                | `0x909acc7f` |
| VESTING_FUND_HOLDER             | [IVestingFundHolder](contracts/vesting/IVestingFundHolder.sol)                          | `0x22a9f96e` |
| VESTING_HANDLER                 | [IVestingHandler](contracts/vesting/IVestingHandler.sol)                                | `0x2f0decb1` |
| KYC_WHITELIST                   | [IKYCWhitelist](contracts/account/IKYCWhitelist.sol)                                    | `0xeb9f4d8d` |

### Methods

MethodID can be found from below table:

| Service             | Method                       | Method ID    |
| ------------------- | ---------------------------- | ------------ |
| ACCOUNT_HANDLER     | CREATE_ACCOUNT               | `0xa30b866f` |
| ACCOUNT_HANDLER     | REBIND_WALLET                | `0xd5427764` |
| ACCOUNT_HANDLER     | CREATE_GROUP                 | `0xd2cd009d` |
| ACCOUNT_HANDLER     | ASSIGN_DELEGATOR             | `0xf9a909cb` |
| ACCOUNT_HANDLER     | REVOKE_DELEGATOR             | `0xb9638389` |
| ACCOUNT_HANDLER     | SET_FEE_RECEIVER             | `0x443ff395` |
| ACCOUNT_HANDLER     | REVOKE_FEE_RECEIVER          | `0xa1ffb9d2` |
| ACCOUNT_HANDLER     | SET_REWARD_RECEIVER          | `0xc2c4e8a5` |
| ACCOUNT_HANDLER     | REVOKE_REWARD_RECEIVER       | `0x6ce176a3` |
| ACCOUNT_HANDLER     | INITIAL_ACCOUNT_MIGRATION    | `0xca63cd74` |
| ACCOUNT_HANDLER     | BATCH_UPDATE_GROUP_SETTINGS  | `0x65acffad` |
| ACCOUNT_HANDLER     | BATCH_SET_RECEIVERS          | `0x9b74dc2d` |
| KYC_WHITELIST       | UPDATE_KYC                   | `0x63d914c6` |
| REWARD_HANDLER      | SET_REWARD_EMISSION_SCHEDULE | `0x283bda79` |
| REWARD_HANDLER      | SETTLE_REWARD                | `0x205402f7` |
| REWARD_HANDLER      | INITIAL_SETTLE_REWARD        | `0xad710875` |
| SERVICE_FEE_HANDLER | LOCK_SERVICE_FEE             | `0x79a9587d` |
| SERVICE_FEE_HANDLER | UNLOCK_SERVICE_FEE           | `0xb82b250a` |
| SERVICE_FEE_HANDLER | SETTLE_SERVICE_FEE           | `0x24438f65` |
| SERVICE_FEE_HANDLER | INITIAL_SETTLE_SERVICE_FEE   | `0xee956559` |
| SERVICE_FEE_HANDLER | INITIAL_TENANTS_SERVICE_FEE  | `0xe4ebce25` |
| TICKET_MANAGER      | ADD_PENALTY                  | `0x35a3f96c` |
| TICKET_MANAGER      | SETTLE_PENALTY               | `0x793d095c` |
| TICKET_MANAGER      | DEDUCT_PENALTY               | `0xc7872d06` |
| TICKET_MANAGER      | CANCEL_PENALTY               | `0x2265d30e` |
| TICKET_MANAGER      | REFUND_TENANTS               | `0x38659c4e` |
| STAKE_HANDLER       | STAKE                        | `0x0bcf60f7` |
| STAKE_HANDLER       | DELEGATION_STAKE             | `0xd0c98c1f` |
| STAKE_HANDLER       | UNSTAKE                      | `0xe0385368` |
| STAKE_HANDLER       | DELEGATION_UNSTAKE           | `0xd43ddb30` |
| STAKE_HANDLER       | FORCE_UNSTAKE                | `0xc766c692` |
| STAKE_HANDLER       | INITIAL_SETTLE_STAKING       | `0x1722f388` |
| STAKE_HANDLER       | INITIAL_SETTLE_VESTING       | `0x101e6d00` |

## VerifiableData

[RequestVerifier](contracts/base/RequestVerifier.sol#L29) is structure to hold off-chain data needed by the smart contract to handle on-chain logic.

- `nonce`: VerifiableData includes nonce to prevent replay attach. Off-chain system can use unique request ID as nonce for mapping request and event from user. Later requests must have higher nonce than the last one. Otherwise, the transaction will be reverted with `NonceTooLow` error.
- `deadline`: the request should be confirmed before that time. Otherwise, the transaction will be reverted with `DataExpired` error. Caller should fetch new data and submit a new transaction.
- `lastUpdateBlock`: is the last processed event blocknumber. It will be use as an optimistic lock to make sure that there is no on-chain state change after VerifiableData is created. If there is, the transaction will be reverted with `DataTooOld` error. Caller should fetch new data and submit a new transaction.
- `version`: data version should always match with the current system version. Otherwise, the transaction will be reverted with `InvalidVersion` error.
- `params`: the method parameters. Data encoding is described below.
- `payloads`: the arbitrary off-chain data. These data format is subject to change depending on system version.
- `proof`: the data proof. It may be Validator signature or Merkle Proof depending on module and version. If the proof is not valid, the transaction will be reverted with `InvalidProof` error.
- `sender`: The origin transaction sender.
- `target`: The serviceId (check above table). Reverts with `TargetMismatch` if the target address does not match the sender's address.
- `method`: The methodId (check above table). Reverts with `MethodMismatch` if the method does not match the expected method.

### Sign request

```javascript
const hash = ethers.toBeArray(await this.requestVerifier.getHash(vdata))
let signatures = '0x'
for (let signer of [validator1, validator2]) {
  signatures += (await signer.signMessage(hash)).substring(2)
}
```

## Modules

## [Account Module](contracts/account/AccountHandler.sol)

The AccountHandler contract is responsible for managing accounts and groups within a registry system. It allows for the creation of accounts, binding wallets, group management, and delegator assignments while ensuring secure access control through request verificatio

### Features

#### Account Management

- `createAccount(IRequestVerifier.VerifiableData calldata vdata)`: Binds a wallet address to a unique tid.

  Encode parameters:

  ```solidity
  abi.encode(address wallet, uint256 tid, Group initialGroup)
  ```

  Event emitted:

  `AccountCreated(address indexed wallet, uint256 tid, Group initialGroup, uint64 nonce, bytes32 hash)`

  <mark>**Note** `initialGroup.tid` must equal to the `tid`. Set `initialGroup.gid` to `0` if there is no initial group</mark>

- `initialAccountsMigration(IRequestVerifier.VerifiableData calldata vdata)`: Migrates existing V1 accounts from off-chain into the current on-chain contract

  Encode parameters:

  ```solidity
  abi.encode(address[] wallets, uint256[] tids, Group[] initialGroups)
  ```

  Event emitted:

  `AccountMigrationCompleted(address[] indexed wallets, uint256[] tids, Group[] initialGroups,  uint64 nonce, bytes32 hash)`

  <mark>**Note** `initialGroups[i].tid` must equal to the `tids[i]`. Set `initialGroups[i].gid` to `0` if there is no initial group</mark>

- `rebindWallet(IRequestVerifier.VerifiableData calldata vdata)`: Updates the wallet associated with a tid.

  Get old wallet and new wallet signatures:

  ```javascript
  const request = ethers.AbiCoder.defaultAbiCoder().encode(
    ['uint256', 'address', 'uint64', 'address', 'address', 'uint256'],
    [chainId, accountHandlerAddress, vdata.nonce, oldWallet, newWallet, tid]
  )
  const hash = ethers.toBeArray(await ethers.keccak256(request))
  const oldWalletSig = await oldWallet.signMessage(hash)
  ```

  Encode parameters:

  ```solidity
  abi.encode(address newWallet, uint256 tid, bytes oldWalletSig)
  ```

  Event emitted: `WalletRebound(uint256 tid, address wallet, uint64 nonce, bytes32 hash)`

#### Group Management

- `createGroup(IRequestVerifier.VerifiableData calldata vdata)`: Registers a new group.

  Encode parameters:

  ```solidity
  abi.encode(Group group)
  ```

  Event emitted:
  `GroupCreated(uint256 tid, uint256 gid, uint64 nonce, bytes32 hash)`

- `assignDelegator(IRequestVerifier.VerifiableData calldata vdata)`: Assigns a delegator to a group. Cloud Host assigns a Delegator to manage staking via the platform's UI

  Encode parameters:

  ```solidity
  abi.encode(uint256 tid, uint256 gid, address delegator)
  ```

  Event emitted:
  `DelegatorAssigned(address indexed delegator, uint256 tid, uint256 gid, uint64 nonce, bytes32 hash)`

- `revokeDelegator(IRequestVerifier.VerifiableData calldata vdata)`: Removes a delegator from a group. Cloud Host initiates Delegator revocation via the platform's UI

  Encode parameters:

  ```solidity
  abi.encode(uint256 tid, uint256 gid)
  ```

  Event emitted:
  `DelegatorRevoked(uint256 tid, uint256 gid, uint64 nonce, bytes32 hash)`

- `setFeeReceiver(IRequestVerifier.VerifiableData calldata vdata)`: Sets a fee receiver for a group.

  Encode parameters:

  ```solidity
  abi.encode(uint256 tid, uint256 gid, address feeReceiver)
  ```

  Event emitted:
  `FeeReceiverSet(address indexed feeReceiver, uint256 tid, uint256 gid, uint64 nonce, bytes32 hash)`

- `revokeFeeReceiver(IRequestVerifier.VerifiableData calldata vdata)`: Removes a fee receiver.

  Encode parameters:

  ```solidity
  abi.encode(uint256 tid, uint256 gid)
  ```

  Event emitted:
  `FeeReceiverRevoked(uint256 tid, uint256 gid, uint64 nonce, bytes32 hash)`

- `setRewardReceiver(IRequestVerifier.VerifiableData calldata vdata)`: Sets a reward receiver for a group. Depending on the
  `DelegatorSetsRewardReceiver` setting, either the Cloud Host or Delegator can set the Reward Receiver via the platform's UI

  Encode parameters:

  ```solidity
    abi.encode(uint256 tid, uint256 gid, address rewardReceiver)
  ```

  Event emitted:
  `RewardReceiverSet(address indexed rewardReceiver, uint256 tid, uint256 gid, uint64 nonce, bytes32 hash)`

- `revokeRewardReceiver(IRequestVerifier.VerifiableData calldata vdata)`: Removes a reward receiver. Depending on the `DelegatorSetsRewardReceiver` setting, either the Cloud Host or Delegator can revoke the Reward Receiver via the platform's UI

  Encode parameters:

  ```solidity
  abi.encode(uint256 tid, uint256 gid)
  ```

  Event emitted: `RewardReceiverRevoked(uint256 tid, uint256 gid, uint64 nonce, bytes32 hash)`

- `updatePolicy(uint256 tid, uint256 gid, bool delegatorSetFeeReceiver, bool delegatorSetRewardReceiver)`: Updates group policies regarding fee and reward receivers.

  Event emitted: `GroupPolicyUpdated(uint256 tid, uint256 gid, bool delegatorSetFeeReceiver, bool delegatorSetRewardReceiver)`

- `batchUpdateGroupSettings(IRequestVerifier.VerifiableData calldata vdata)`: Updates settings for multiple groups at once.

  Encode parameters:

  ```solidity
  abi.encode(Group[] groups)
  ```

  Event emitted:
  `GroupsUpdated(Group[] group, uint64 nonce, bytes32 hash)`

- `batchSetReceivers(IRequestVerifier.VerifiableData calldata vdata)`: Sets fee and reward receivers for multiple groups at once.

  Encode parameters:

  ```solidity
  abi.encode(uint256[] tids, uint256[] gids, address[] feeReceivers, address[] rewardReceivers)
  ```

  Event emitted:
  `ReceiversSet(Receiver[] receivers, uint64 nonce, bytes32 hash)`

  `Receiver` structure:

  ```solidity
  struct Receiver {
    address feeReceiver;
    address rewardReceiver;
    uint256 tid;
    uint256 gid;
    bool setFeeReceiver;
    bool setRewardReceiver;
  }
  ```

## [KYC Module](contracts/account/KYCWhitelist.sol)

The KYCWhitelist maintains and continuously updates a KYC whitelist based on wallet addresses. For any claim or withdraw function, the token receiver's wallet address is verified against the KYC whitelist; if not approved, the request is rejected.

### Functions and Usage

- `updateKYC(IRequestVerifier.VerifiableData calldata vdata)`: Updates the on-chain KYC whitelist.

  Encode parameters:

  ```solidity
  abi.encode(address[] wallets, bool[] verified)
  ```

  Event emitted:
  `KYCUpdated(address[] wallets, bool[] verified, uint64 nonce, bytes32 hash)`

## [Reward Module](contracts/reward/RewardHandler.sol)

The RewardHandler contract is responsible for managing the reward distribution system within a blockchain-based ecosystem. It sets the emission schedule, settles rewards, and handles vesting processes.

### Params

[VestingRecord](contracts/vesting/IVestingHandler.sol#L12)

```solidity
/// @notice Data structure for vesting record
/// @param amounts Array of amounts
/// @param vestingDays Array of vesting days
struct VestingRecord {
  uint256[] amounts;
  uint32[] vestingDays;
}
```

### Functions and Usage

- `setEmissionSchedule(IRequestVerifier.VerifiableData calldata vdata)`: Sets the reward emission schedule.

  Encode parameters:

  ```solidity
   abi.encode(uint256[] epochs, uint256[] amounts);
  ```

  - `Epochs`: is the array of unix timestamps without milliseconds. It cannot be in the past. It should be in GMT timezone. Any time in a day is valid. The contract will convert it to the date index and store it in the same order as the input.
    It allows to set for current day if the schedule is not set yet.
  - `Amounts`: is the array of reward amounts corresponding to each epoch. It should be in the same order as epochs.

    - Example value:

      ```solidity
        uint256[] epochs = [
          1635678000,  // 2021-10-31 11:00:00 UTC
          1635724800,  // 2021-11-01 00:00:00 UTC
        ];
        uint256[] amounts = [1000, 2000];
      ```

    - Contract will store it as below:

      ```solidity
        _emissionAmounts = [
          (18931, 1000),
          (18932, 2000)
        ];
      ```

  Event emitted:
  `EmissionScheduleSet(uint256[] epochs, uint256[] amounts, uint64 nonce, bytes32 hash)`

- `settleReward(IRequestVerifier.VerifiableData calldata vdata)`: Allocates and distributes rewards after verification.

  Encode parameters:

  ```solidity
  abi.encode(uint256[] tids, uint256[] gids, uint256[] amounts, uint256[] slashAmount)
  ```

  Event emitted:
  `RewardSettled(uint256[] tids, uint256[] gids, uint256[] amounts, uint64 nonce, bytes32 hash)`

- `initialSettleReward(IRequestVerifier.VerifiableData calldata vdata)`: Handles the initial vesting of rewards.

  Encode parameters:

  ```solidity
  abi.encode(uint256[] tids, uint256[] gids, VestingRecord[] records)
  ```

  - Example value of `VestingRecord` parameter please refer to [VestingStorage](#vestingstorage)

  Event emitted:
  `RewardInitialSettled(uint256[] tids, uint256[] gids, VestingRecord[] records, uint64 nonce, bytes32 vhash)`

## [Service Fee Module](contracts/servicefee/ServiceFeeHandler.sol)

The `ServiceFeeHandler` contract manages the deposit, withdrawal, locking, unlocking, and settlement of service fees within a blockchain-based system.

### Params

[ServiceFeeSettleParams](contracts/servicefee/IServiceFeeHandler.sol#34)

```solidity
/// @notice Data structure for service fee settlement
/// @param tenants Array of tenant IDs
/// @param tenantAmounts Array of tenant amounts
/// @param hosts Array of cloud hosts. Use to create a new vesting record.
/// @param groups Array of host groups. Use to create a new vesting record.
/// @param hostGroupAmounts Array of host group with amount. Use to create a new vesting record.
/// @param grantAmount Deducts used grants from the Grant Pool
/// @param slashAmount The slash amount. Use to Allocates daily slash penalties
struct ServiceFeeSettleParams {
  uint256[] tenants;
  uint256[] tenantAmounts;
  uint256[] hosts;
  uint256[] groups;
  uint256[] hostGroupAmounts;
  uint256 grantAmount;
  uint256 slashAmount;
}
```

### Functions and Usage

- `depositServiceFee(uint256 tid, uint256 amount)`: Deposits a specified service fee amount. Tenant initiates ATH deposit via UI

  Event emitted:
  `ServiceFeeDeposited(address indexed sender, uint256 tid, uint256 amount)`

  <mark>**Note** The clients should call `approve(address spender, uint256 value)` before calling </mark>

- `withdrawServiceFee(uint256 tid, uint256 amount)`: Withdraws a specified service fee amount. Tenant initiates ATH withdrawal via UI

  Event emitted:
  `ServiceFeeWithdrawn(address indexed sender, uint256 tid, uint256 amount)`

- `lockServiceFee(IRequestVerifier.VerifiableData calldata vdata)`: Locks service fees based on verified request data.

  Encode parameters:

  ```solidity
  abi.encode(uint256[] tids, uint256[] amounts)
  ```

  Event emitted:
  `ServiceFeeLocked(uint256[] tids, uint256[] amounts, uint64 nonce, bytes32 hash)`

- `unlockServiceFee(IRequestVerifier.VerifiableData calldata vdata)`: Unlocks previously locked service fees.

  Encode parameters:

  ```solidity
  abi.encode(uint256 tids[], uint256 amounts[])
  ```

  Event emitted:
  `ServiceFeeUnlocked(uint256[] tids, uint256[] amounts, uint64 nonce, bytes32 hash)`

- `settleServiceFee(IRequestVerifier.VerifiableData calldata vdata)`: Settles service fees, distributing them to appropriate recipients.

  Encode parameters:

  ```solidity
  abi.encode(ServiceFeeSettleParams)
  ```

  Event emitted:
  `ServiceFeeSettled(ServiceFeeSettleParams params, uint64 nonce, bytes32 hash)`

- `initialSettleServiceFee(IRequestVerifier.VerifiableData calldata vdata)`: Handles the initial settlement and vesting of service fees.

  Encode parameters:

  ```solidity
  abi.encode(uint256[] tids, uint256[] gids, VestingRecord[] memory records)
  ```

  [VestingRecord](contracts/vesting/IVestingHandler.sol#L12)

  Event emitted:
  `ServiceFeeInitialSettled(uint256[] tids, uint256[] gids, VestingRecord[] records, uint64 nonce, bytes32 vhash)`

- `initialTenantsServiceFee(IRequestVerifier.VerifiableData calldata vdata)`: Handles the initial deposit of service fees for multiple tenants.

  Encode parameters:

  ```solidity
  abi.encode(uint256[] tids, uint256[] amounts)
  ```

  - Require
    - The caller must be the initiator
    - `tids` array must not be empty
    - Length of `tids` must equal length of `amounts`

  Event emitted:
  `ServiceFeeInitialDeposited(uint256[] tids, uint256[] amounts, uint64 nonce, bytes32 hash)`

## [Slash Module](contracts/slash/TicketManager.sol)

The `TicketManager` contract is responsible for managing the creation and tracking of penalty tickets in a decentralized system. It is implemented as part of a modular architecture, interacting with various components such as the `IRegistry`, `IRequestVerifier`, `ISlashHandler`, and `ISlashStorage` to ensure penalties are properly recorded, settled, deducted, and canceled.

### Functions and Usage

- `addPenalty(IRequestVerifier.VerifiableData calldata vdata)`: Adds a new penalty ticket after verifying the request.

  Encode parameters:

  ```solidity
  abi.encode(uint256 tid, uint256 gid, uint256 amount, uint256 expiration, uint256 container)
  ```

  Event emitted:
  `TicketCreated(uint256 tid, uint256 gid, uint256 container, uint256 amount, uint64 nonce, bytes32 hash)`

- `settlePenalty(IRequestVerifier.VerifiableData calldata vdata)`: Marks a penalty as settled after verification.

  Encode parameters:

  ```solidity
  abi.encode(uint256 tid, uint256 gid, uint256 container)
  ```

  Event emitted:
  `TicketSettled(uint256 tid, uint256 gid, uint256 container, uint256 amount, uint64 nonce, bytes32 hash)`

  <mark>**Note** The clients should call `approve(address `spender`, uint256 value)` before calling </mark>

  <mark>**Note** `spender`: is the address of the `SlashHandler` contract</mark>

- `deductPenalty(IRequestVerifier.VerifiableData calldata vdata)`: Deducts penalties with associated fees, rewards, and stakes.

  Encode parameters:

  ```solidity
  abi.encode(uint256 tid, uint256 gid, uint256 container, VestingRecord memory fees, VestingRecord memory rewards)
  ```

  [VestingRecord](contracts/vesting/IVestingHandler.sol#L12)

  Event emitted:
  `TicketDeducted(uint256 tid, uint256 gid, uint256 container, uint256 amount, uint256 stakedAmount, uint64 nonce, bytes32 hash)`

  <mark>**Note** The clients should call `approve(address `spender`, uint256 value)` before calling </mark>

  <mark>**Note** `spender`: is the address of the `SlashHandler` contract</mark>

- `cancelPenalty(IRequestVerifier.VerifiableData calldata vdata)`: Cancels an existing penalty ticket after verification.

  Encode parameters:

  ```solidity
  abi.encode(uint256 tid, uint256 gid, uint256 container, uint256 amount)
  ```

  Event emitted:
  `TicketCancelled(uint256 tid, uint256 gid, uint256 container, uint256 amount, uint64 nonce, bytes32 hash)`

- `refundTenants(IRequestVerifier.VerifiableData calldata vdata)`: Refunds tenants to the Grant Pool

  Encode parameters:

  ```solidity
  abi.encode(uint256[] tids, uint256[] amounts)
  ```

  Event emitted:

  `TenantRefunded(uint256[] tids, uint256[] amounts, uint256 totalAmount, uint64 nonce, bytes32 hash)`

## [Stake Module](contracts/stake/StakeHandler.sol)

The `StakeHandler` contract is responsible for managing staking and unstaking operations in a blockchain-based system. It enables standard staking, delegation staking, forced unstaking, and integration with a vesting system. The contract ensures that all staking-related operations are validated and securely processed.

### Functions and Usage

- `stake(IRequestVerifier.VerifiableData calldata vdata)`: Stakes a specified amount of tokens.

  Encode parameters:

  ```solidity
  abi.encode(uint256 tid, uint256 gid, uint256[] cids, uint256[] amounts, VestingRecord memory record)
  ```

  `record` are [vested records](contracts/vesting/IVestingHandler.sol#L12) that used for restaking (Check [VestingStorage](#vestingstorage) section on how to retrieve it). If `record` is empty, all the require token will be transfer from the host. Restake amount (sum of `record.amounts`) minus restake fee must be less than or equal to require stake amount. If they are equal, no additional tokens are required during the staking process.

  Event emitted:
  `StandardStake(address indexed sender, uint256 tid, uint256 gid, uint256[] cids, uint256[] amounts, uint256 totalAmount, uint64 nonce, bytes32 hash)`

  <mark>**Note** The clients should call `approve(address spender, uint256 value)` before calling </mark>

- `delegationStake(IRequestVerifier.VerifiableData calldata vdata)`: Allows a delegator to stake tokens.

  Encode parameters:

  ```solidity
  abi.encode(uint256 tid, uint256 gid, uint256[] cids, uint256[] amounts, VestingRecord memory record)
  ```

  `record` are [vested records](contracts/vesting/IVestingHandler.sol#L12) that used for restaking (Check [VestingStorage](#vestingstorage) section on how to retrieve it). If `record` is empty, all the require token will be transfer from the delegator. Restake amount (sum of `record.amounts`) minus restake fee must be less than or equal to require stake amount. If they are equal, no additional tokens are required during the staking process.

  Event emitted:
  `DelegationStake(address indexed sender, uint256 tid, uint256 gid, uint256[] cids, uint256[] amounts, uint256 totalAmount, uint64 nonce, bytes32 hash)`

  <mark>**Note** The clients should call `approve(address spender, uint256 value)` before calling </mark>

- `unStake(IRequestVerifier.VerifiableData calldata vdata)`: Allows users to unstake their tokens.

  Encode parameters:

  ```solidity
  abi.encode(uint256 tid, uint256 gid, uint256[] cids)
  ```

  Event emitted:
  `UnStake(address indexed sender, uint256 tid, uint256 gid, uint256[] cids, uint256[] amounts, uint256 totalAmount, uint64 nonce, bytes32 hash)`

- `delegationUnstake(IRequestVerifier.VerifiableData calldata vdata)`: Allows a delegator to unstake their tokens.

  Encode parameters:

  ```solidity
  abi.encode(uint256 tid, uint256 gid, uint256[] cids)
  ```

  Event emitted:
  `DelegationUnstake(address indexed account, uint256 tid, uint256 gid, uint256[] cids, uint256[] amounts, uint256 totalAmount, uint64 nonce, bytes32 vhash)`

- `forceUnstake(IRequestVerifier.VerifiableData calldata vdata)`: Forces the unstaking of tokens.

  Encode parameters:

  ```solidity
  abi.encode(uint256 tid, uint256 gid, uint256[] cids)
  ```

  Event emitted:
  `ForceUnStake(address indexed sender, uint256 tid, uint256 gid, uint256[] cids, uint256[] amounts, uint256 totalAmount, uint64 nonce, bytes32 hash)`

- `initialSettleStakingRecords(IRequestVerifier.VerifiableData calldata vdata)`: Migrates accumulated V1 staking records from off-chain into the current on-chain contrac

  Encode parameters:

  ```solidity
  abi.encode(uint256[] tids, uint256[] gids, uint256[][] cids, uint256[][] amounts)
  ```

  Event emitted:
  `InitialStake(address indexed delegator, uint256 tid, uint256 gid, uint256[] cids, uint256[] amounts, uint256 totalAmount, uint64 nonce, bytes32 hash)`

- `initialSettleVestingRecords(IRequestVerifier.VerifiableData calldata vdata)`: Migrates accumulated V1 vesting records from off-chain into the current on-chain contract

  Encode parameters:

  ```solidity
  abi.encode(uint256[] tids, uint256[] gids, VestingRecord[] memory record)
  ```

  [VestingRecord](contracts/vesting/IVestingHandler.sol#L12)

  Event emitted:
  `UnstakeInitialSettled(uint256[] tids, uint256[] gids, VestingRecord[] records, uint64 nonce, bytes32 vhash)`

## [Vesting Module](contracts/vesting/vestingHandler.sol)

The `VestingHandler` contract handles all vesting scenarios for Unstake, Service Fee, and Reward. It provides visibility into vested and vesting information for each host and total amounts. Additionally, it manages deductions from Vested Fee and Vested Reward during Slash operations.

### Functions and Usage

- `releaseHostVestedToken(uint256[] calldata tids, uint256[] calldata gids, VestingRecord[] calldata fees, VestingRecord[] calldata rewards, VestingRecord[] calldata stakes)`: Claim vested tokens

  - Require
    - System is not paused
    - The caller is not blacklisted
    - Caller is valid host for tid
    - Host has not outstanding penalties
    - `fees`, `rewards`, and `stakes` records are valid dates (not in the future)

  Event emitted:
  `VestingReleased(address indexed beneficiary, VestingType vestingType, uint256 tid, uint256 gid, VestingRecord records)`

  <mark>**Note** The beneficiary will be address(0) as the vested tokens go to the host</mark>
  <mark>**Note** The transaction can be sent from any address, not necessarily the host address</mark>

- `releaseDelegatorVestedToken(uint256[] calldata tids, uint256[] calldata gids, VestingRecord[] calldata stakes)`: Release vested tokens to delegator

  - Require
    - System is not paused
    - The caller is not blacklisted
    - Caller is valid delegator for tid and gid
    - `stakes` records is valid dates(not in the future)

  Event emitted:
  `VestingReleased(address indexed beneficiary, VestingType vestingType, uint256 tid, uint256 gid, VestingRecord records)`

  <mark>**Note** The transaction can be sent from any address, not necessarily the delegator address</mark>

- `releaseReceiverVestedToken(uint256[] calldata tids, uint256[] calldata gids, VestingRecord[] calldata fees, VestingRecord[] calldata rewards)`: Release vested tokens to receiver

  - Require
    - System is not paused
    - The caller is not blacklisted
    - `fees` and `rewards` records are valid dates (not in the future)
    - `feeReceiver` and `rewardReceiver` addresses are valid for tid and gid

  Event emitted:
  `VestingReleased(address indexed beneficiary, VestingType vestingType, uint256 tid, uint256 gid, VestingRecord records)`

  <mark>**Note** The transaction can be sent from any address, not necessarily the receiver address</mark>

- `hostEarlyClaim(uint256[] calldata tids, uint256[] calldata gids, VestingType[] calldata vestingTypes, VestingRecord[] calldata records, uint32 earlyClaimDays)`: Host early claim

  - Require
    - System is not paused
    - The caller is not blacklisted
    - Caller is valid host for tid
    - Host has not outstanding penalties
    - `records` are valid dates (not in the future)
    - `earlyClaimDays` must match one of the configured penalty days

  Event emitted:
  `EarlyClaimed(address indexed beneficiary, VestingType vestingType, uint256 tid, uint256 gid, VestingRecord records, uint256 penaltyAmount, uint256 penaltyPercentage, uint256 earlyClaimDays)`

  <mark>**Note** The beneficiary will be address(0) as the vested tokens go to the host</mark>

- `delegateEarlyClaim(uint256[] calldata tids, uint256[] calldata gids, VestingRecord[] calldata records, uint32 earlyClaimDays)`: Delegate early claim unstake

  - Require
    - System is not paused
    - The caller is not blacklisted
    - Caller is valid delegator for tid and gid
    - `records` are valid dates (not in the future)
    - `earlyClaimDays` must match one of the configured penalty days

  Event emitted:
  `EarlyClaimed(address indexed beneficiary, VestingType vestingType, uint256 tid, uint256 gid, VestingRecord records, uint256 penaltyAmount, uint256 penaltyPercentage, uint256 earlyClaimDays)`

- `receiverEarlyClaim(uint256[] calldata tids, uint256[] calldata gids, VestingType[] calldata vestingTypes, VestingRecord[] calldata records, uint32 earlyClaimDays)`: Receiver early claim

  - Require
    - System is not paused
    - The caller is not blacklisted
    - `records` are valid dates (not in the future)
    - `earlyClaimDays` must match one of the configured penalty days
    - For ServiceFee vesting: caller must be feeReceiver
    - For Reward vesting: caller must be rewardReceiver

  Event emitted:
  `EarlyClaimed(address indexed beneficiary, VestingType vestingType, uint256 tid, uint256 gid, VestingRecord records, uint256 penaltyAmount, uint256 penaltyPercentage, uint256 earlyClaimDays)`

- `restakeVestedToken(uint256 tid, uint256 gid, VestingRecord calldata stakes, uint256 restakeFeeAmount)`: Restake vested tokens

  - Require
    - System is not paused
    - The caller is not blacklisted
    - Caller is valid delegator for tid and gid
    - `stakes` records is valid dates(not in the future)
    - `restakeFeeAmount` must be less than or equal to the total amount in `stakes`

  Event emitted:
  `VestingRestaked(address indexed delegator, uint256 tid, uint256 gid, VestingRecord records, uint256 restakeFeeAmount)`

- `settleSlash(uint256 tid, uint256 gid, VestingRecord calldata fees, VestingRecord calldata rewards, VestingRecord calldata stakes)`: Settle slash penalty

  - Require
    - System is not paused
    - The caller is not blacklisted
    - Caller is valid host for tid
    - `fees`, `rewards`, and `stakes` records are valid dates (not in the future)

  Event emitted:
  `VestingSlashed(address indexed host, VestingType vestingType, uint256 tid, uint256 gid, VestingRecord records)`

- `releaseHostAllVestedToken(uint256[] calldata tids, uint256[] calldata gids, bool[] calldata releaseServiceFees, bool[] calldata releaseRewards, bool[] calldata releaseUnstakes)`: Release all vested tokens for host

  - Require
    - System is not paused
    - The caller is not blacklisted
    - Caller is valid host for tid
    - Host has not outstanding penalties
    - All vesting records are valid dates (not in the future)
    - Length of arrays must match: `tids.length == gids.length == releaseServiceFees.length == releaseRewards.length == releaseUnstakes.length`

  Event emitted:
  `VestingReleased(address indexed beneficiary, VestingType vestingType, uint256 tid, uint256 gid, VestingRecord records)`

  <mark>**Note** The beneficiary will be address(0) as the vested tokens go to the host</mark>
  <mark>**Note** The transaction can be sent from any address, not necessarily the host address</mark>

- `releaseDelegatorAllVestedToken(uint256[] calldata tids, uint256[] calldata gids)`: Release all vested tokens for delegator

  - Require
    - System is not paused
    - The caller is not blacklisted
    - Caller is valid delegator for tid and gid
    - All vesting records are valid dates (not in the future)
    - Length of arrays must match: `tids.length == gids.length`

  Event emitted:
  `VestingReleased(address indexed beneficiary, VestingType vestingType, uint256 tid, uint256 gid, VestingRecord records)`

  <mark>**Note** The transaction can be sent from any address, not necessarily the delegator address</mark>

- `releaseReceiverAllVestedToken(uint256[] calldata tids, uint256[] calldata gids, bool[] calldata releaseServiceFees, bool[] calldata releaseRewards)`: Release all vested tokens for receiver

  - Require
    - System is not paused
    - The caller is not blacklisted
    - All vesting records are valid dates (not in the future)
    - `feeReceiver` and `rewardReceiver` addresses are valid for tid and gid
    - Length of arrays must match: `tids.length == gids.length == releaseServiceFees.length == releaseRewards.length`

  Event emitted:
  `VestingReleased(address indexed beneficiary, VestingType vestingType, uint256 tid, uint256 gid, VestingRecord records)`

  <mark>**Note** The transaction can be sent from any address, not necessarily the receiver address</mark>

### References

[VestingType](contracts/vesting/IVestingHandler.sol#L5)

[VestingRecord](contracts/vesting/IVestingHandler.sol#L12)

## Administrative Function

## [RewardCommissionReceiver](contracts/reward/RewardCommissionReceiver.sol)

The `RewardCommissionReceiver` contract is responsible for holding the reward commission and allowing the admin to withdraw it.

### Functions and Usage

- `withdrawRewardCommission(address recipient, uint256 amount)`: Withdraws the reward commission from the contract.

  - Require the caller to have the `DEFAULT_ADMIN_ROLE` role.

  Event emitted:
  `RewardCommissionWithdrawn(address indexed recipient, uint256 amount)`

## [RewardConfigurator](contracts/reward/RewardConfigurator.sol)

The `RewardConfigurator` contract is responsible for configuring reward-related parameters, such as the reward commission percentage.

### Functions and Usage

- `setRewardCommissionPercentage(uint256 percentage)`: Sets the reward commission percentage. The percentage only accepts whole numbers without decimals.

  - Example:
    - 10% should be set as 10.
    - 55% should be set as 55.
  - Require the caller to have the `CONFIGURATION_ADMIN_ROLE` role.

  Event emitted:
  `RewardCommissionChanged(uint256 percentage)`

## [RewardFundHolder](contracts/reward/RewardFundHolder.sol)

The `RewardFundHolder` contract is responsible for holding the reward fund and allowing the admin to withdraw it.

### Functions and Usage

- `withdrawRewardToken(address recipient, uint256 amount)`: Withdraws the reward fund from the contract.

  - Require the caller to have the `DEFAULT_ADMIN_ROLE` or `FUND_WITHDRAW_ADMIN_ROLE` role.

    Event emitted: `RewardTokenWithdrawn(address indexed recipient, uint256 amount)`

- `sendRewardToken(address beneficiary, uint256 amount)`: Sends reward tokens to a beneficiary.

  Event emitted: `RewardTokenSent(address indexed beneficiary, uint256 amount)`

- `sendCommissionToken(uint256 amount)`: Sends commission tokens to the commission receiver address.

  Event emitted: `RewardCommissionTokenSent(uint256 amount)`

- `sendVestingToken(uint256 amount)`: Sends vesting tokens to the vesting fund holder address.

  Event emitted: `RewardVestingTokenSent(uint256 amount)`

- `sendSlashedToken(uint256 amount)`: Sends slash penalty tokens to the slash reduction receiver address.

  Event emitted: `RewardSlashedTokenSent(uint256 amount)`

## [BlackListManager](contracts/riskmanager/BlackListManager.sol)

The `BlackListManager` contract is responsible for managing blacklisted accounts and their tiers.

### Functions and Usage

- `setBlackListed(address account, uint8 tier)`: Blacklists an account with a specified tier.

  - Require the caller to have the `CONFIGURATION_ADMIN_ROLE` role.

    Event emitted:
    `BlackListed(address indexed account, uint8 tier)`

- `isAllowed(address account, bytes4 functionSelector)`: Checks if an account is allowed to call a specific function.

## [EmergencySwitch](contracts/riskmanager/EmergencySwitch.sol)

The `EmergencySwitch` contract is responsible for pausing and unpausing the contract in emergency situations.

### Functions and Usage

- `pause(uint8 tier)`: Pauses the contract with a specified tier.

  - Require the caller to have the `DEFAULT_ADMIN_ROLE` role.

    Event emitted: `TierChanged(uint8 tier)`

- `isAllowed(bytes4 functionSelector)`: Checks if a function is allowed to be called.

## [TierController](contracts/riskmanager/TierController.sol)

The `TierController` contract is responsible for managing function tiers

### Functions and Usage

- `setFunctionTier(bytes4 functionSelector, uint8 tier)`: Sets the tier for a specific function.

  - Require the caller to have the `DEFAULT_ADMIN_ROLE` role.

    Event emitted: `TierChanged(bytes4 functionSelector, uint8 tier)`

- `getTier(bytes4 functionSelector)`: Returns the tier for a specific function.

- `setDefaultTier(uint8 tier)`: Sets the default tier for functions.

  - Require the caller to have the `DEFAULT_ADMIN_ROLE` role.

    Event emitted: `DefaultTierChanged(uint8 tier)`

- `getDefaultTier()`: Returns the default tier for functions.

## [GrantPool](contracts/servicefee/GrantPool.sol)

The `GrantPool` contract is responsible for managing the grant pool and allowing the admin to withdraw it.

### Functions and Usage

- `withdrawGrantFund(address recipient, uint256 amount)`: Withdraws the grant fund from the contract.

  - Require the caller to have the `DEFAULT_ADMIN_ROLE` role.

    Event emitted: `GrantWithdrawn(address indexed recipient, uint256 amount)`

## [ServiceFeeCommissionReceiver](contracts/servicefee/ServiceFeeCommissionReceiver.sol)

The `ServiceFeeCommissionReceiver` contract is responsible for holding the service fee commission and allowing the admin to withdraw it.

### Functions and Usage

- `withdrawServiceFeeCommission(address recipient, uint256 amount)`: Withdraws the service fee commission from the contract.

  - Require the caller to have the `DEFAULT_ADMIN_ROLE` role.

    Event emitted: `ServiceFeeCommissionWithdrawn(address indexed recipient, uint256 amount)`

## [ServiceFeeConfigurator](contracts/servicefee/ServiceFeeConfigurator.sol)

The `ServiceFeeConfigurator` contract is responsible for configuring service fee-related parameters, such as the service fee commission percentage.

### Functions and Usage

- `setCommissionPercentage(uint256 percentage)`: Sets the service fee commission percentage. The percentage only accepts whole numbers without decimals.

  - Example:

    - 10% should be set as 10.
    - 55% should be set as 55.

  - Require the caller to have the `CONFIGURATION_ADMIN_ROLE` role.

    Event emitted: `CommissionPercentageChanged(uint256 percentage)`

## [SlashDeductionReceiver](contracts/slash/SlashDeductionReceiver.sol)

The `SlashDeductionReceiver` contract is responsible for holding the slash deduction fee and allowing the admin to withdraw it.

### Functions and Usage

- `withdrawSlashPenalty(address recipient, uint256 amount)`: Withdraws the slash deduction fee from the contract.

  - Require the caller to have the `DEFAULT_ADMIN_ROLE` role.

    Event emitted: `PenaltySlashWithdrawn(address indexed recipient, uint256 amount)`

## [RestakeFeeReceiver](contracts/stake/RestakeFeeReceiver.sol)

The `RestakeFeeReceiver` contract is responsible for holding the restake transaction fee and allowing the admin to withdraw it.

### Functions and Usage

- `withdrawRestakeFee(address recipient, uint256 amount)`: Withdraws the restake transaction fee from the contract.

  - Require the caller to have the `DEFAULT_ADMIN_ROLE` role.

    Event emitted: `RestakeFeeWithdrawn(address indexed recipient, uint256 amount)`

## [StakeConfigurator](contracts/stake/StakeConfigurator.sol)

The `StakeConfigurator` contract is responsible for configuring stake-related parameters, such as the restake transaction fee percentage.

### Functions and Usage

- `setRestakingTransactionFeePercentage(uint256 percentage)`: Sets the restake transaction fee percentage. The percentage only accepts whole numbers without decimals.

  - Example:
    - 10% should be set as 10.
    - 55% should be set as 55.
  - Require the caller to have the `CONFIGURATION_ADMIN_ROLE` role.

    Event emitted: `RestakingTransactionFeePercentageChanged(uint256 percentage)`

## [VestingConfigurator](contracts/vesting/VestingConfigurator.sol)

The `VestingConfigurator` contract is responsible for configuring vesting-related parameters, such as early claim the vesting penalty percentage.

### Functions and Usage

- `setEarlyClaimPenaltyPercentage(uint16 percentage)`: Sets the early claim penalty percentage. The percentage only accepts whole numbers without decimals.

  - Example:

    - 10% should be set as 10.
    - 55% should be set as 55.

  - Require the caller to have the `CONFIGURATION_ADMIN_ROLE` role.

    Event emitted: `EarlyClaimPenaltyPercentageChanged(uint256 percentage)`

- `setMinimumEarlyClaimAmount(uint256 amount)`: Sets the minimum early claim amount.

  - Require the caller to have the `CONFIGURATION_ADMIN_ROLE` role.

    Event emitted: `MinimumEarlyClaimAmountChanged(uint256 amount)`

- `setMinimumClaimAmount(uint256 amount)`: Sets the minimum claim amount.

  - Require the caller to have the `CONFIGURATION_ADMIN_ROLE` role.

    Event emitted: `MinimumClaimAmountChanged(uint256 amount)`

- `getEarlyClaimPenaltyPercentage()`: Returns the early claim penalty percentage.
- `getMinimumEarlyClaimAmount()`: Returns the minimum early claim amount.
- `getMinimumClaimAmount()`: Returns the minimum claim amount.

## [VestingPenaltyReceiver](contracts/vesting/VestingPenaltyReceiver.sol)

The `VestingPenaltyReceiver` contract is responsible for holding the vesting penalty and allowing the admin to withdraw it.

### Functions and Usage

- `withdrawEarlyClaimPenalty (address recipient, uint256 amount)`: Withdraws the vesting penalty from the contract.

  - Require the caller to have the `DEFAULT_ADMIN_ROLE` role.

    Event emitted: `EarlyClaimPenaltyWithdrawn(address indexed recipient, uint256 amount)`

## [VestingSchemeManager](contracts/vesting/VestingSchemeManager.sol)

The `VestingSchemeManager` contract is responsible for managing vesting schemes and their parameters.

### Functions and Usage

- `setVestingScheme(VestingType vestingType, uint32[] memory percentages, uint32[] memory dates)` : Sets the vesting scheme.

  - Require the caller to have the `CONFIGURATION_ADMIN_ROLE` role.

    Event emitted: `VestingSchemeSet(VestingType vestingType, uint32[] percentages, uint32[] dates)`

- `getVestingScheme(VestingType vestingType) returns (uint32[] memory, uint32[] memory)`: Returns the vesting scheme for a specific type.
- `getVestingAmount(VestingType vestingType, uint256 amount) return (uint256[] memory, uint32[] memory)`: Returns the vesting amount for a specific type.

  #### References

  [VestingType](contracts/vesting/IVestingHandler.sol#L5)

## [VestingStorage](contracts/vesting/VestingStorage.sol)

The `VestingStorage` contract is responsible for storing vesting records.

### Functions and Usage

- `getVestingAmounts(VestingType vestingType, uint256 tid, uint256 gid, address account,uint32[] calldata vestingDays))`: Retrieves the vesting amounts for a given account over specified vesting days. The `vestingDays` array must be in strictly increasing order. Each element must be greater than the previous one. This ensures consistent and predictable vesting schedules.

  - Example usage:

    ```solidity
    uint32[] memory vestingDays = new uint32[](3);
    vestingDays[0] = 30;
    vestingDays[1] = 60;
    vestingDays[2] = 90;
    uint256[] memory amounts = VestingStorage(vestingStorageAddress);
    getVestingAmounts(VestingType.REWARD, tid, gid, account, vestingDays);
    // output: [100, 200, 300]
    ```

- `getRange(VestingType vestingType, uint256 tid, uint256 gid, address account)`: Retrieves the range of vesting days for a given account.

  - Example usage:

  ```solidity
  uint32[] memory range = VestingStorage(vestingStorageAddress);
  getRange(VestingType.REWARD, tid, gid, account);
  // output: [30, 90]
  ```

- `batchGetRange(VestingType vestingType, uint256[] calldata tids, uint256[] calldata gids, address[] calldata accounts)`: Retrieves the range of vesting days for multiple accounts in a single call.

  - Example usage:

  ```solidity
  VestingType[] memory vestingTypes = new VestingType[](2);
  uint256[] memory tids = new uint256[](2);
  uint256[] memory gids = new uint256[](2);
  address[] memory accounts = new address[](2);
  vestingTypes[0] = VestingType.REWARD; tids[0] = 1; gids[0] = 1; accounts[0] = address1;
  vestingTypes[1] = VestingType.UNSTAKE; tids[1] = 2; gids[1] = 2; accounts[1] = address2;
  uint32[][] memory ranges = VestingStorage(vestingStorageAddress);
  batchGetRange(vestingTypes, tids, gids, accounts);
  // output: [[30, 90], [45, 120]]
  ```

- `batchGetVestingAmounts(VestingType[] calldata vestingTypes, uint256[] calldata tids, uint256[] calldata gids, address[] calldata accounts, uint32[][] calldata vestingDays)`: Retrieves the vesting amounts for multiple accounts over specified vesting days in a single call.

  - Example usage:

  ```solidity
  VestingType[] memory vestingTypes = new VestingType[](2);
  uint256[] memory tids = new uint256[](2);
  uint256[] memory gids = new uint256[](2);
  address[] memory accounts = new address[](2);
  uint32[][] memory vestingDays = new uint32[][](2);

  // First account
  vestingTypes[0] = VestingType.REWARD;
  tids[0] = 1;
  gids[0] = 1;
  accounts[0] = address1;
  vestingDays[0] = new uint32[](3);
  vestingDays[0][0] = 30;
  vestingDays[0][1] = 60;
  vestingDays[0][2] = 90;

  // Second account
  vestingTypes[1] = VestingType.UNSTAKE;
  tids[1] = 2;
  gids[1] = 2;
  accounts[1] = address2;
  vestingDays[1] = new uint32[](2);
  vestingDays[1][0] = 45;
  vestingDays[1][1] = 120;

  uint256[][] memory amounts = VestingStorage(vestingStorageAddress);
  batchGetVestingAmounts(vestingTypes, tids, gids, accounts, vestingDays);
  // output: [[100, 200, 300], [150, 250]]
  ```

## [ServiceFeeFundHolder](contracts/servicefee/ServiceFeeFundHolder.sol)

The `ServiceFeeFundHolder` contract is responsible for holding the service fee fund and allowing the admin to withdraw it.

### Functions and Usage

- `withdrawServiceFeeToken(address recipient, uint256 amount)`: Withdraws the service fee fund from the contract.

  - Require the caller to have the `DEFAULT_ADMIN_ROLE` or `FUND_WITHDRAW_ADMIN_ROLE` role.

    Event emitted: `ServiceFeeTokenWithdrawn(address indexed recipient, uint256 amount)`

- `sendServiceFeeToken(address beneficiary, uint256 amount)`: Sends service fee tokens to a beneficiary.

  Event emitted: `ServiceFeeTokenSent(address indexed beneficiary, uint256 amount)`

- `sendCommissionToken(uint256 amount)`: Sends commission tokens to the commission receiver address.

  Event emitted: `ServiceFeeCommissionTokenSent(uint256 amount)`

- `sendVestingToken(uint256 amount)`: Sends vesting tokens to the vesting fund holder address.

  Event emitted: `ServiceFeeVestingTokenSent(uint256 amount)`

- `sendSlashedToken(uint256 amount)`: Sends slash penalty tokens to the slash reduction receiver address.

  Event emitted: `ServiceFeeSlashedTokenSent(uint256 amount)`

## [RewardFundHolder](contracts/reward/RewardFundHolder.sol)

The `RewardFundHolder` contract is responsible for holding the reward fund and allowing the admin to withdraw it.

### Functions and Usage

- `withdrawRewardToken(address recipient, uint256 amount)`: Withdraws the reward fund from the contract.

  - Require the caller to have the `DEFAULT_ADMIN_ROLE` or `FUND_WITHDRAW_ADMIN_ROLE` role.

    Event emitted: `RewardTokenWithdrawn(address indexed recipient, uint256 amount)`

- `sendRewardToken(address beneficiary, uint256 amount)`: Sends reward tokens to a beneficiary.

  Event emitted: `RewardTokenSent(address indexed beneficiary, uint256 amount)`

- `sendCommissionToken(uint256 amount)`: Sends commission tokens to the commission receiver address.

  Event emitted: `RewardCommissionTokenSent(uint256 amount)`

- `sendVestingToken(uint256 amount)`: Sends vesting tokens to the vesting fund holder address.

  Event emitted: `RewardVestingTokenSent(uint256 amount)`

- `sendSlashedToken(uint256 amount)`: Sends slash penalty tokens to the slash reduction receiver address.

  Event emitted: `RewardSlashedTokenSent(uint256 amount)`

## [VestingFundHolder](contracts/vesting/VestingFundHolder.sol)

The `VestingFundHolder` contract is responsible for holding the vesting fund and allowing the admin to withdraw it.

### Functions and Usage

- `withdrawVestingToken(address recipient, uint256 amount)`: Withdraws the vesting fund from the contract.

  - Require the caller to have the `DEFAULT_ADMIN_ROLE` or `FUND_WITHDRAW_ADMIN_ROLE` role.

    Event emitted: `VestingTokenWithdrawn(address indexed recipient, uint256 amount)`

- `sendVestedToken(address beneficiary, uint256 amount)`: Sends vested tokens to a beneficiary.

  Event emitted: `VestedTokenSent(address indexed beneficiary, uint256 amount)`

- `sendRestakeFeeToken(uint256 amount)`: Sends restake fee tokens to the restake fee receiver address.

  Event emitted: `RestakeFeeTokenSent(uint256 amount)`

- `sendRestakeToken(uint256 amount)`: Sends restake tokens to the restake fund holder address.

  Event emitted: `RestakeTokenSent(uint256 amount)`

- `sendPenaltyToken(uint256 amount)`: Sends penalty tokens to the penalty holder address.

  Event emitted: `PenaltyTokenSent(uint256 amount)`

- `sendSettleSlashToken(uint256 amount)`: Sends slash penalty tokens to the slash reduction receiver address.

  Event emitted: `SettleSlashTokenSent(uint256 amount)`

## VestingPenaltyManager

Manages penalty rates for early token withdrawals in different vesting types.

#### Functions

- `setVestingPenalties(VestingType vestingType, uint32[] percentages, uint32[] dates)`: Sets penalty rates for a vesting type

  - Requires `CONFIGURATION_ADMIN_ROLE` permission
  - `percentages`: Array of penalty percentages corresponding to each level
  - `dates`: Array of days corresponding to each penalty level
  - Emits: `VestingPenaltySet(VestingType vestingType, uint32[] percentages, uint32[] dates)`

- `getVestingPenalties(VestingType vestingType)`: Gets the list of penalty rates for a vesting type

  - Returns: `(uint32[] percentages, uint32[] dates)`

- `getVestingPenalty(VestingType vestingType, uint32 daysToClaim)`: Gets the penalty percentage for a specific withdrawal day
  - Returns: `uint256 percentage`

#### Default Penalties

1. Service Fee Vesting:

   - 7 days: 40% penalty
   - 45 days: 0% penalty

2. Unstake Vesting:

   - 7 days: 80% penalty
   - 60 days: 50% penalty
   - 180 days: 0% penalty

3. Reward Vesting:
   - 7 days: 80% penalty
   - 60 days: 50% penalty
   - 180 days: 0% penalty
