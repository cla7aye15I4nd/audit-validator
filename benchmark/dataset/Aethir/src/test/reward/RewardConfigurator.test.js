const { expect } = require('chai')

describe('RewardConfigurator', function () {
  before(async function () {
    this.wallets = await ethers.getSigners()
    this.dev = this.wallets[0]
    this.governor = this.wallets[1]
    this.configurator = this.wallets[2]
  })

  beforeEach(async function () {
    const ACLManager = await ethers.getContractFactory('ACLManager', this.dev)
    this.acl = await ACLManager.deploy(this.governor.address)
    await this.acl.waitForDeployment()

    this.acl.connect(this.governor).addConfigurationAdmin(this.configurator.address)

    const ATHToken = await ethers.getContractFactory('AethirToken', this.dev)
    this.ath = await ATHToken.deploy()
    await this.ath.waitForDeployment()

    const Registry = await ethers.getContractFactory('Registry', this.dev)
    this.registry = await Registry.deploy(this.acl.target, this.ath.target)
    await this.registry.waitForDeployment()

    const RewardConfigurator = await ethers.getContractFactory('RewardConfigurator', this.dev)
    this.rewardConfigurator = await RewardConfigurator.deploy(this.registry.target)
    await this.rewardConfigurator.waitForDeployment()
  })

  it('should set and get reward commission percentage', async function () {
    const percentage = 50
    await this.rewardConfigurator.connect(this.configurator).setRewardCommissionPercentage(percentage)
    const rewardCommissionPercentage = await this.rewardConfigurator.getRewardCommissionPercentage()
    expect(rewardCommissionPercentage).to.equal(percentage)
  })

  it('should revert if percentage is greater than 10000', async function () {
    await expect(
      this.rewardConfigurator.connect(this.configurator).setRewardCommissionPercentage(10001),
    ).to.be.revertedWith('Value exceeds maximum')
  })
})
