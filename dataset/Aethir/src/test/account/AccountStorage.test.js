const { expect } = require('chai')
const { ethers } = require('hardhat')

describe('AccountStorage', () => {
  const groupexample = {
    tid: 1,
    gid: 2,
    delegator: ethers.ZeroAddress,
    feeReceiver: ethers.ZeroAddress,
    rewardReceiver: ethers.ZeroAddress,
    delegatorSetFeeReceiver: false,
    delegatorSetRewardReceiver: false,
  }

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

    const Registry = await ethers.getContractFactory('Registry', this.dev)
    this.registry = await Registry.deploy(this.acl.target, this.token.target)
    await this.registry.waitForDeployment()
    await this.registry
      .connect(this.migrator)
      .setAddress(await this.serviceIdList.ACCOUNT_HANDLER_ID(), this.dummyhandler.address)

    const AccountStorage = await ethers.getContractFactory('AccountStorage', this.dev)
    this.accountStorage = await AccountStorage.deploy(this.registry.target)
    await this.accountStorage.waitForDeployment()
  })

  it('should not revert if wallet or tid is not bound', async function () {
    expect(await this.accountStorage.getTid(this.user.address)).to.be.equal(0)
    expect(await this.accountStorage.getWallet(1)).to.be.equal(ethers.ZeroAddress)
  })

  it('should only allow AccountHandler to bind wallet', async function () {
    await expect(this.accountStorage.bindWallet(1, this.user.address)).to.be.revertedWith(
      'AccountStorage: handler only',
    )
  })

  it('should bind wallet to tid', async function () {
    await expect(this.accountStorage.connect(this.dummyhandler).bindWallet(1, ethers.ZeroAddress)).to.be.revertedWith(
      'Invalid wallet address',
    )
    await expect(this.accountStorage.connect(this.dummyhandler).bindWallet(1, this.user.address)).to.not.be.reverted
    await expect(this.accountStorage.connect(this.dummyhandler).bindWallet(2, this.user.address)).to.be.revertedWith(
      'Wallet already bound',
    )

    expect(await this.accountStorage.getTid(this.user.address)).to.equal(1)
    expect(await this.accountStorage.getWallet(1)).to.equal(this.user.address)
  })

  it('should allow bind other wallet to tid', async function () {
    await expect(this.accountStorage.connect(this.dummyhandler).bindWallet(1, this.user.address)).to.not.be.reverted
    await expect(this.accountStorage.connect(this.dummyhandler).bindWallet(1, this.dev.address)).to.not.be.reverted
    expect(await this.accountStorage.getTid(this.dev.address)).to.equal(1)
    expect(await this.accountStorage.getWallet(1)).to.equal(this.dev.address)
  })

  it('should revert if group is not existed', async function () {
    await expect(this.accountStorage.getGroup(1, 1)).to.be.revertedWith('Group not found')
  })

  it('should only allow AccountHandler to set group info', async function () {
    await expect(this.accountStorage.setGroup(groupexample)).to.be.revertedWith('AccountStorage: handler only')
  })

  it('should set/get group info', async function () {
    expect(await this.accountStorage.isGroupExist(1, 2)).to.be.false
    await expect(this.accountStorage.connect(this.dummyhandler).setGroup(groupexample)).to.not.be.reverted
    expect(await this.accountStorage.isGroupExist(1, 2)).to.be.true

    const group = await this.accountStorage.getGroup(1, 2)
    expect(group.tid).to.equal(groupexample.tid)
    expect(group.gid).to.equal(groupexample.gid)
    expect(group.delegator).to.equal(groupexample.delegator)
    expect(group.feeReceiver).to.equal(groupexample.feeReceiver)
    expect(group.rewardReceiver).to.equal(groupexample.rewardReceiver)
    expect(group.delegatorSetFeeReceiver).to.equal(groupexample.delegatorSetFeeReceiver)
    expect(group.delegatorSetRewardReceiver).to.equal(groupexample.delegatorSetRewardReceiver)
  })
})
