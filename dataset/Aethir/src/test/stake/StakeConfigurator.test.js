const { expect } = require('chai')
const { ethers } = require('hardhat')

describe('StakeConfigurator', function () {
  before(async function () {
    this.wallets = await ethers.getSigners()
    this.dev = this.wallets[0]
    this.governor = this.wallets[1]
    this.receiver = this.wallets[2]
    this.configurator = this.wallets[3]
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

    // Deploy the StakeConfigurator contract
    const StakeConfigurator = await ethers.getContractFactory('StakeConfigurator')
    this.stakeConfigurator = await StakeConfigurator.deploy(this.registry.target)
    await this.stakeConfigurator.waitForDeployment()
  })

  it('Should return the correct initial restaking transaction fee percentage', async function () {
    expect(await this.stakeConfigurator.getRestakingTransactionFeePercentage()).to.equal(20)
  })

  it('Should allow the configuration admin to set the restaking transaction fee percentage', async function () {
    await this.stakeConfigurator.connect(this.configurator).setRestakingTransactionFeePercentage(15)
    expect(await this.stakeConfigurator.getRestakingTransactionFeePercentage()).to.equal(15)
  })

  it('Should revert if a non-admin tries to set the restaking transaction fee percentage', async function () {
    await expect(this.stakeConfigurator.connect(this.dev).setRestakingTransactionFeePercentage(15)).to.be.revertedWith(
      'Configuration admin only',
    )
  })

  it('Should revert if the new fee percentage exceeds the maximum value', async function () {
    await expect(
      this.stakeConfigurator.connect(this.configurator).setRestakingTransactionFeePercentage(110),
    ).to.be.revertedWith('Value exceeds maximum')
  })

  it('Should emit an event when the restaking transaction fee percentage is changed', async function () {
    await expect(this.stakeConfigurator.connect(this.configurator).setRestakingTransactionFeePercentage(15))
      .to.emit(this.stakeConfigurator, 'RestakingTransactionFeePercentageChanged')
      .withArgs(15)
  })
})
