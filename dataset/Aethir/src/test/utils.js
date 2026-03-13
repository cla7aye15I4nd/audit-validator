const { ethers } = require('hardhat')

const VALIDATOR1_MNEMONIC = 'person mango drill weapon color online lunar require expire element oval wisdom'
const VALIDATOR2_MNEMONIC = 'coffee timber jewel guard position address uphold vivid goose else syrup furnace'
const INITATOR1_MNEMONIC = 'advance cinnamon rifle mad dilemma bounce orchard opera peace couple hobby ramp'
const INITATOR2_MNEMONIC = 'doctor cup move hurt clutch onion wild total dutch shy top digital'

class TestDeployment {
  constructor(wallets) {
    this.wallets = wallets
    this.dev = this.wallets[0]
    this.governor = this.wallets[1]
    this.configurator = this.wallets[2]
    this.migrator = this.wallets[3]
    this.backend = this.wallets[4]
    this.user = this.wallets[5]
    this.delegator = this.wallets[6]
    this.dummyhandler = this.wallets[7]
    this.user2 = this.wallets[8]

    this.validator1 = ethers.Wallet.fromPhrase(VALIDATOR1_MNEMONIC)
    this.validator2 = ethers.Wallet.fromPhrase(VALIDATOR2_MNEMONIC)
    this.initiator1 = ethers.Wallet.fromPhrase(INITATOR1_MNEMONIC)
    this.initiator2 = ethers.Wallet.fromPhrase(INITATOR2_MNEMONIC)
  }

  async getNonce(address) {
    return (await this.userStorage.getUserData(address)).nonce
  }

  async getServiceAddress(name) {
    const serviceId = await this.serviceIds[name]()
    return this.registry.getFunction('getAddress')(serviceId)
  }

  async getServiceId(name) {
    return this.serviceIds[name]()
  }

  async getMethodId(name) {
    return this.methodIds[name]()
  }

  async signWithValidators(vdata) {
    const hash = ethers.toBeArray(await this.requestVerifier.getHash(vdata))
    let proof = '0x'
    for (let signer of [this.validator1, this.validator2]) {
      proof += (await signer.signMessage(hash)).substring(2)
    }
    return proof
  }

  async signWithInitiators(vdata) {
    const hash = ethers.toBeArray(await this.requestVerifier.getHash(vdata))
    let proof = '0x'
    for (let signer of [this.initiator1, this.initiator2]) {
      proof += (await signer.signMessage(hash)).substring(2)
    }
    return proof
  }

  async getUserNonce(sender) {
    return (await this.userStorage.getUserData(sender)).nonce
  }

  async getVerifiableData(sender, target, method, params, payloads = '0x', isInitiator = false) {
    const userData = await this.userStorage.getUserData(sender)
    const vdata = {
      nonce: userData.nonce + 1n,
      deadline: Date.now() + 10000,
      lastUpdateBlock: userData.lastUpdateBlock,
      version: 1,
      sender,
      target: await this.getServiceAddress(target),
      method: await this.getMethodId(method),
      params,
      payloads,
      proof: '0x',
    }
    vdata.proof = isInitiator ? await this.signWithInitiators(vdata) : await this.signWithValidators(vdata)
    return vdata
  }

  async getTestToken(receiver, amount) {
    return this.token.connect(this.dev).transfer(receiver, amount)
  }

  async createAccount(wallet, tid) {
    const delegator = ethers.ZeroAddress
    const feeReceiver = ethers.ZeroAddress
    const rewardReceiver = ethers.ZeroAddress
    const delegatorSetFeeReceiver = false
    const delegatorSetRewardReceiver = false

    const vdata = await this.getVerifiableData(
      this.backend.address,
      'ACCOUNT_HANDLER_ID',
      'CREATE_ACCOUNT',
      ethers.AbiCoder.defaultAbiCoder().encode(
        ['address', 'uint256', '(uint256,uint256,address,address,address,bool,bool)'],
        [
          wallet,
          tid,
          [0, 0, delegator, feeReceiver, rewardReceiver, delegatorSetFeeReceiver, delegatorSetRewardReceiver],
        ],
      ),
    )
    return this.accountHandler
      .connect(this.backend)
      .createAccount(vdata)
      .catch((e) => undefined)
  }

  async createGroup(tid, gid) {
    const delegator = ethers.ZeroAddress
    const feeReceiver = ethers.ZeroAddress
    const rewardReceiver = ethers.ZeroAddress
    const delegatorSetFeeReceiver = false
    const delegatorSetRewardReceiver = false

    const vdata = await this.getVerifiableData(
      this.backend.address,
      'ACCOUNT_HANDLER_ID',
      'CREATE_GROUP',
      ethers.AbiCoder.defaultAbiCoder().encode(
        ['(uint256,uint256,address,address,address,bool,bool)'],
        [[tid, gid, delegator, feeReceiver, rewardReceiver, delegatorSetFeeReceiver, delegatorSetRewardReceiver]],
      ),
    )
    return this.accountHandler
      .connect(this.backend)
      .createGroup(vdata)
      .catch((e) => undefined)
  }

  async updateKYC(wallet, enable) {
    const vdata = await this.getVerifiableData(
      this.backend.address,
      'KYC_WHITELIST_ID',
      'UPDATE_KYC',
      ethers.AbiCoder.defaultAbiCoder().encode(['address[]', 'bool[]'], [[wallet], [enable]]),
    )
    return this.kycWhitelist
      .connect(this.backend)
      .updateKYC(vdata)
      .catch((e) => undefined)
  }

  async deploy() {
    const ACLManager = await ethers.getContractFactory('ACLManager', this.dev)
    this.acl = await ACLManager.deploy(this.governor.address)
    await this.acl.waitForDeployment()
    await this.acl.connect(this.governor).addMigrator(this.migrator.address)
    await this.acl.connect(this.governor).addConfigurationAdmin(this.configurator.address)
    await this.acl.connect(this.governor).addValidator(this.validator1.address)
    await this.acl.connect(this.governor).addValidator(this.validator2.address)
    await this.acl.connect(this.governor).addInitSettlementOperator(this.initiator1.address)
    await this.acl.connect(this.governor).addInitSettlementOperator(this.initiator2.address)

    const MethodIdList = await ethers.getContractFactory('MethodIdList', this.dev)
    this.methodIds = await MethodIdList.deploy()
    await this.methodIds.waitForDeployment()

    const ServiceIdList = await ethers.getContractFactory('ServiceIdList', this.dev)
    this.serviceIds = await ServiceIdList.deploy()
    await this.serviceIds.waitForDeployment()

    const AethirToken = await ethers.getContractFactory('AethirToken', this.dev)
    this.token = await AethirToken.deploy()
    await this.token.waitForDeployment()

    const Registry = await ethers.getContractFactory('Registry', this.dev)
    this.registry = await Registry.deploy(this.acl.target, this.token.target)
    await this.registry.waitForDeployment()

    const UserStorage = await ethers.getContractFactory('UserStorage', this.dev)
    this.userStorage = await UserStorage.deploy(this.registry.target)
    await this.userStorage.waitForDeployment()

    const EmergencySwitch = await ethers.getContractFactory('EmergencySwitch', this.dev)
    this.emergencySwitch = await EmergencySwitch.deploy(this.registry.target)
    await this.emergencySwitch.waitForDeployment()

    const BlackListManager = await ethers.getContractFactory('BlackListManager', this.dev)
    this.blackListManager = await BlackListManager.deploy(this.registry.target)
    await this.blackListManager.waitForDeployment()

    const TierController = await ethers.getContractFactory('TierController', this.dev)
    this.tierController = await TierController.deploy(this.registry.target)
    await this.tierController.waitForDeployment()

    const RequestVerifier = await ethers.getContractFactory('RequestVerifier', this.dev)
    this.requestVerifier = await RequestVerifier.deploy(this.registry.target)
    await this.requestVerifier.waitForDeployment()

    const AccountStorage = await ethers.getContractFactory('AccountStorage', this.dev)
    this.accountStorage = await AccountStorage.deploy(this.registry.target)
    await this.accountStorage.waitForDeployment()

    const AccountHandler = await ethers.getContractFactory('AccountHandler', this.dev)
    this.accountHandler = await AccountHandler.deploy(this.registry.target)
    await this.accountHandler.waitForDeployment()

    const RewardCommissionReceiver = await ethers.getContractFactory('RewardCommissionReceiver', this.dev)
    this.rewardCommissionReceiver = await RewardCommissionReceiver.deploy(this.registry.target)
    await this.rewardCommissionReceiver.waitForDeployment()

    const RewardConfigurator = await ethers.getContractFactory('RewardConfigurator', this.dev)
    this.rewardConfigurator = await RewardConfigurator.deploy(this.registry.target)
    await this.rewardConfigurator.waitForDeployment()

    const RewardFundHolder = await ethers.getContractFactory('RewardFundHolder', this.dev)
    this.rewardFundHolder = await RewardFundHolder.deploy(this.registry.target)
    await this.rewardFundHolder.waitForDeployment()

    const RewardHandler = await ethers.getContractFactory('RewardHandler', this.dev)
    this.rewardHandler = await RewardHandler.deploy(this.registry.target)
    await this.rewardHandler.waitForDeployment()

    const RewardStorage = await ethers.getContractFactory('RewardStorage', this.dev)
    this.rewardStorage = await RewardStorage.deploy(this.registry.target)
    await this.rewardStorage.waitForDeployment()

    const GrantPool = await ethers.getContractFactory('GrantPool', this.dev)
    this.grantPool = await GrantPool.deploy(this.registry.target)
    await this.grantPool.waitForDeployment()

    const ServiceFeeCommissionReceiver = await ethers.getContractFactory('ServiceFeeCommissionReceiver', this.dev)
    this.serviceFeeCommissionReceiver = await ServiceFeeCommissionReceiver.deploy(this.registry.target)
    await this.serviceFeeCommissionReceiver.waitForDeployment()

    const ServiceFeeConfigurator = await ethers.getContractFactory('ServiceFeeConfigurator', this.dev)
    this.serviceFeeConfigurator = await ServiceFeeConfigurator.deploy(this.registry.target)
    await this.serviceFeeConfigurator.waitForDeployment()

    const ServiceFeeFundHolder = await ethers.getContractFactory('ServiceFeeFundHolder', this.dev)
    this.serviceFeeFundHolder = await ServiceFeeFundHolder.deploy(this.registry.target)
    await this.serviceFeeFundHolder.waitForDeployment()

    const ServiceFeeHandler = await ethers.getContractFactory('ServiceFeeHandler', this.dev)
    this.serviceFeeHandler = await ServiceFeeHandler.deploy(this.registry.target)
    await this.serviceFeeHandler.waitForDeployment()

    const ServiceFeeStorage = await ethers.getContractFactory('ServiceFeeStorage', this.dev)
    this.serviceFeeStorage = await ServiceFeeStorage.deploy(this.registry.target)
    await this.serviceFeeStorage.waitForDeployment()

    const SlashConfigurator = await ethers.getContractFactory('SlashConfigurator', this.dev)
    this.slashConfigurator = await SlashConfigurator.deploy(this.registry.target)
    await this.slashConfigurator.waitForDeployment()

    const SlashDeductionReceiver = await ethers.getContractFactory('SlashDeductionReceiver', this.dev)
    this.slashDeductionReceiver = await SlashDeductionReceiver.deploy(this.registry.target)
    await this.slashDeductionReceiver.waitForDeployment()

    const SlashHandler = await ethers.getContractFactory('SlashHandler', this.dev)
    this.slashHandler = await SlashHandler.deploy(this.registry.target)
    await this.slashHandler.waitForDeployment()

    const SlashStorage = await ethers.getContractFactory('SlashStorage', this.dev)
    this.slashStorage = await SlashStorage.deploy(this.registry.target)
    await this.slashStorage.waitForDeployment()

    const TicketManager = await ethers.getContractFactory('TicketManager', this.dev)
    this.ticketManager = await TicketManager.deploy(this.registry.target)
    await this.ticketManager.waitForDeployment()

    const RestakeFeeReceiver = await ethers.getContractFactory('RestakeFeeReceiver', this.dev)
    this.restakeFeeReceiver = await RestakeFeeReceiver.deploy(this.registry.target)
    await this.restakeFeeReceiver.waitForDeployment()

    const StakeConfigurator = await ethers.getContractFactory('StakeConfigurator', this.dev)
    this.stakeConfigurator = await StakeConfigurator.deploy(this.registry.target)
    await this.stakeConfigurator.waitForDeployment()

    const StakeFundHolder = await ethers.getContractFactory('StakeFundHolder', this.dev)
    this.stakeFundHolder = await StakeFundHolder.deploy(this.registry.target)
    await this.stakeFundHolder.waitForDeployment()

    const StakeHandler = await ethers.getContractFactory('StakeHandler', this.dev)
    this.stakeHandler = await StakeHandler.deploy(this.registry.target)
    await this.stakeHandler.waitForDeployment()

    const StakeStorage = await ethers.getContractFactory('StakeStorage', this.dev)
    this.stakeStorage = await StakeStorage.deploy(this.registry.target)
    await this.stakeStorage.waitForDeployment()

    const VestingConfigurator = await ethers.getContractFactory('VestingConfigurator', this.dev)
    this.vestingConfigurator = await VestingConfigurator.deploy(this.registry.target)
    await this.vestingConfigurator.waitForDeployment()

    const VestingFundHolder = await ethers.getContractFactory('VestingFundHolder', this.dev)
    this.vestingFundHolder = await VestingFundHolder.deploy(this.registry.target)
    await this.vestingFundHolder.waitForDeployment()

    const VestingHandler = await ethers.getContractFactory('VestingHandler', this.dev)
    this.vestingHandler = await VestingHandler.deploy(this.registry.target)
    await this.vestingHandler.waitForDeployment()

    const VestingPenaltyReceiver = await ethers.getContractFactory('VestingPenaltyReceiver', this.dev)
    this.vestingPenaltyReceiver = await VestingPenaltyReceiver.deploy(this.registry.target)
    await this.vestingPenaltyReceiver.waitForDeployment()

    const VestingSchemeManager = await ethers.getContractFactory('VestingSchemeManager', this.dev)
    this.vestingSchemeManager = await VestingSchemeManager.deploy(this.registry.target)
    await this.vestingSchemeManager.waitForDeployment()

    const VestingStorage = await ethers.getContractFactory('VestingStorage', this.dev)
    this.vestingStorage = await VestingStorage.deploy(this.registry.target)
    await this.vestingStorage.waitForDeployment()

    const KYCWhitelist = await ethers.getContractFactory('KYCWhitelist', this.dev)
    this.kycWhitelist = await KYCWhitelist.deploy(this.registry.target)
    await this.kycWhitelist.waitForDeployment()

    await this.registry.initialize([], [])
  }
}

module.exports = {
  TestDeployment,
}
