const { expect } = require('chai')
const { ethers } = require('hardhat')

describe('StakeFundHolder', function () {
  before(async function () {
    this.wallets = await ethers.getSigners()
    this.dev = this.wallets[0]
    this.governor = this.wallets[1]
    this.beneficiary = this.wallets[3]
    this.handler = this.wallets[4]
  })

  beforeEach(async function () {
    const ACLManager = await ethers.getContractFactory('ACLManager', this.dev)
    this.acl = await ACLManager.deploy(this.governor.address)
    await this.acl.waitForDeployment()

    const ATHToken = await ethers.getContractFactory('AethirToken', this.dev)
    this.ath = await ATHToken.deploy()
    await this.ath.waitForDeployment()

    const Registry = await ethers.getContractFactory('Registry', this.dev)
    this.registry = await Registry.deploy(this.acl.target, this.ath.target)
    await this.registry.waitForDeployment()

    const MockKYC = await ethers.getContractFactory('MockKYC', this.dev)
    this.mockKYC = await MockKYC.deploy(this.registry.target)
    await this.mockKYC.waitForDeployment()

    const ServiceIdList = await ethers.getContractFactory('ServiceIdList', this.dev)
    this.serviceIdList = await ServiceIdList.deploy()
    await this.serviceIdList.waitForDeployment()

    await this.acl.connect(this.governor).addMigrator(this.governor.address)
    await this.registry
      .connect(this.governor)
      .setAddress(await this.serviceIdList.STAKE_HANDLER_ID(), this.handler.address)

    const StakeFundHolder = await ethers.getContractFactory('StakeFundHolder', this.dev)
    this.stakeFundHolder = await StakeFundHolder.deploy(this.registry.target)
    await this.stakeFundHolder.waitForDeployment()
  })

  it('should send staked tokens to the beneficiary', async function () {
    const amount = ethers.parseUnits('100', 18)
    // transfer from dev to rewardCommissionReceiver
    await this.ath.connect(this.dev).transfer(this.stakeFundHolder.target, amount)

    await expect(this.stakeFundHolder.connect(this.handler).sendStakedToken(this.beneficiary.address, amount))
      .to.emit(this.stakeFundHolder, 'StakedTokenSent')
      .withArgs(this.beneficiary.address, amount)

    expect(await this.ath.balanceOf(this.beneficiary.address)).to.equal(amount)
  })

  it('should revert if called by non-handler', async function () {
    const amount = ethers.parseUnits('100', 18)
    await this.ath.connect(this.dev).transfer(this.stakeFundHolder.target, amount)

    await expect(
      this.stakeFundHolder.connect(this.dev).sendStakedToken(this.beneficiary.address, amount),
    ).to.be.revertedWith('StakeFundHolder: handler only')
  })
})
