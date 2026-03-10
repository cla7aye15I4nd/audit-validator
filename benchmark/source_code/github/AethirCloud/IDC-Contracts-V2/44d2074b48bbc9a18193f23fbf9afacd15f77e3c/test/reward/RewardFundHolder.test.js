const { expect } = require('chai')
const { ethers } = require('hardhat')

describe('RewardFundHolder', function () {
  before(async function () {
    this.wallets = await ethers.getSigners()
    this.dev = this.wallets[0]
    this.governor = this.wallets[1]
    this.migrator = this.wallets[2]
    this.user = this.wallets[3]
    this.dummyhandler = this.wallets[4]
  })

  beforeEach(async function () {
    const ACLManager = await ethers.getContractFactory('ACLManager', this.dev)
    this.acl = await ACLManager.deploy(this.governor.address)
    await this.acl.waitForDeployment()
    await this.acl.connect(this.governor).addMigrator(this.migrator.address)

    const AethirToken = await ethers.getContractFactory('AethirToken', this.dev)
    this.token = await AethirToken.deploy()
    await this.token.waitForDeployment()

    const ServiceIdList = await ethers.getContractFactory('ServiceIdList', this.dev)
    this.serviceIdList = await ServiceIdList.deploy()
    await this.serviceIdList.waitForDeployment()

    const MethodIdList = await ethers.getContractFactory('MethodIdList', this.dev)
    this.methodIdList = await MethodIdList.deploy()
    await this.methodIdList.waitForDeployment()

    const Registry = await ethers.getContractFactory('Registry', this.dev)
    this.registry = await Registry.deploy(this.acl.target, this.token.target)
    await this.registry.waitForDeployment()
    await this.registry
      .connect(this.migrator)
      .setAddress(await this.serviceIdList.REWARD_HANDLER_ID(), this.dummyhandler.address)

    const MockKYC = await ethers.getContractFactory('MockKYC', this.dev)
    this.kycWhitelist = await MockKYC.deploy(this.registry.target)
    await this.kycWhitelist.waitForDeployment()

    const MockRequestVerifier = await ethers.getContractFactory('MockRequestVerifier', this.dev)
    this.requestVerifier = await MockRequestVerifier.deploy(this.registry.target)
    await this.requestVerifier.waitForDeployment()

    const RewardFundHolder = await ethers.getContractFactory('RewardFundHolder', this.dev)
    this.rewardFundHolder = await RewardFundHolder.deploy(this.registry.target)
    await this.rewardFundHolder.waitForDeployment()
  })

  it('should allow only RewardHandler to send reward tokens', async function () {
    await this.token.transfer(this.rewardFundHolder.target, 1000)
    expect(await this.token.balanceOf(this.rewardFundHolder.target)).to.equal(1000)
    expect(await this.token.balanceOf(this.user.address)).to.equal(0)

    await expect(this.rewardFundHolder.sendRewardToken(this.user.address, 100)).to.be.revertedWith('RewardHandler only')
    await expect(this.rewardFundHolder.connect(this.dummyhandler).sendRewardToken(this.user.address, 100)).to.not.be
      .reverted

    expect(await this.token.balanceOf(this.rewardFundHolder.target)).to.equal(900)
    expect(await this.token.balanceOf(this.user.address)).to.equal(100)
  })

  it('should send staked tokens to the beneficiary', async function () {
    const amount = ethers.parseUnits('100', 18)
    await this.token.connect(this.dev).transfer(this.rewardFundHolder.target, amount)

    await this.acl.connect(this.governor).addFundWithdrawAdmin(this.governor.address)

    await expect(this.rewardFundHolder.connect(this.governor).withdrawRewardToken(this.user.address, amount))
      .to.emit(this.rewardFundHolder, 'RewardTokenWithdrawn')
      .withArgs(this.user.address, amount)

    expect(await this.token.balanceOf(this.user.address)).to.equal(amount)
  })
})
