const { expect } = require('chai')

describe('ServiceFeeStorage', () => {
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
      .setAddress(await this.serviceIdList.SERVICE_FEE_HANDLER_ID(), this.dummyhandler.address)

    const ServiceFeeStorage = await ethers.getContractFactory('ServiceFeeStorage', this.dev)
    this.serviceFeeStorage = await ServiceFeeStorage.deploy(this.registry.target)
    await this.serviceFeeStorage.waitForDeployment()
  })

  it('should increase/decrease DepositedAmount', async function () {
    expect(await this.serviceFeeStorage.getDepositedAmount(1)).to.equal(0)

    await expect(this.serviceFeeStorage.increaseDepositedAmount(1, 100)).to.be.revertedWith('ServiceFeeHandler only')
    await expect(this.serviceFeeStorage.connect(this.dummyhandler).increaseDepositedAmount(1, 100)).to.not.be.reverted
    expect(await this.serviceFeeStorage.getDepositedAmount(1)).to.equal(100)

    await expect(this.serviceFeeStorage.decreaseDepositedAmount(1, 50)).to.be.revertedWith('ServiceFeeHandler only')
    await expect(this.serviceFeeStorage.connect(this.dummyhandler).decreaseDepositedAmount(1, 50)).to.not.be.reverted
    expect(await this.serviceFeeStorage.getDepositedAmount(1)).to.equal(50)
  })

  it('should increase/decrease DepositedAmounts', async function () {
    const tids = [1, 2, 3]
    const incAmounts = [100, 200, 300]
    const decAmounts = [50, 100, 150]
    for (let i = 0; i < tids.length; i++) {
      expect(await this.serviceFeeStorage.getDepositedAmount(tids[i])).to.equal(0)
    }

    await expect(this.serviceFeeStorage.increaseDepositedAmounts(tids, incAmounts)).to.be.revertedWith(
      'ServiceFeeHandler only',
    )
    await expect(
      this.serviceFeeStorage.connect(this.dummyhandler).increaseDepositedAmounts([1], incAmounts),
    ).to.be.revertedWith('Invalid input length')
    await expect(this.serviceFeeStorage.connect(this.dummyhandler).increaseDepositedAmounts(tids, incAmounts)).to.not.be
      .reverted
    for (let i = 0; i < tids.length; i++) {
      expect(await this.serviceFeeStorage.getDepositedAmount(tids[i])).to.equal(incAmounts[i])
    }

    await expect(this.serviceFeeStorage.decreaseDepositedAmounts(tids, decAmounts)).to.be.revertedWith(
      'ServiceFeeHandler only',
    )
    await expect(
      this.serviceFeeStorage.connect(this.dummyhandler).decreaseDepositedAmounts([1], decAmounts),
    ).to.be.revertedWith('Invalid input length')
    await expect(this.serviceFeeStorage.connect(this.dummyhandler).decreaseDepositedAmounts(tids, decAmounts)).to.not.be
      .reverted
    for (let i = 0; i < tids.length; i++) {
      expect(await this.serviceFeeStorage.getDepositedAmount(tids[i])).to.equal(incAmounts[i] - decAmounts[i])
    }
  })

  it('should increase/decrease LockedAmount', async function () {
    expect(await this.serviceFeeStorage.getLockedAmount(1)).to.equal(0)

    await expect(this.serviceFeeStorage.increaseLockedAmount(1, 100)).to.be.revertedWith('ServiceFeeHandler only')
    await expect(this.serviceFeeStorage.connect(this.dummyhandler).increaseLockedAmount(1, 100)).to.not.be.reverted
    expect(await this.serviceFeeStorage.getLockedAmount(1)).to.equal(100)

    await expect(this.serviceFeeStorage.decreaseLockedAmount(1, 50)).to.be.revertedWith('ServiceFeeHandler only')
    await expect(this.serviceFeeStorage.connect(this.dummyhandler).decreaseLockedAmount(1, 50)).to.not.be.reverted
    expect(await this.serviceFeeStorage.getLockedAmount(1)).to.equal(50)
  })

  it('should increase/decrease LockedAmounts', async function () {
    const tids = [1, 2, 3]
    const incAmounts = [100, 200, 300]
    const decAmounts = [50, 100, 150]
    for (let i = 0; i < tids.length; i++) {
      expect(await this.serviceFeeStorage.getLockedAmount(tids[i])).to.equal(0)
    }

    await expect(this.serviceFeeStorage.increaseLockedAmounts(tids, incAmounts)).to.be.revertedWith(
      'ServiceFeeHandler only',
    )
    await expect(
      this.serviceFeeStorage.connect(this.dummyhandler).increaseLockedAmounts([1], incAmounts),
    ).to.be.revertedWith('Invalid input length')
    await expect(this.serviceFeeStorage.connect(this.dummyhandler).increaseLockedAmounts(tids, incAmounts)).to.not.be
      .reverted
    for (let i = 0; i < tids.length; i++) {
      expect(await this.serviceFeeStorage.getLockedAmount(tids[i])).to.equal(incAmounts[i])
    }

    await expect(this.serviceFeeStorage.decreaseLockedAmounts(tids, decAmounts)).to.be.revertedWith(
      'ServiceFeeHandler only',
    )
    await expect(
      this.serviceFeeStorage.connect(this.dummyhandler).decreaseLockedAmounts([1], decAmounts),
    ).to.be.revertedWith('Invalid input length')
    await expect(this.serviceFeeStorage.connect(this.dummyhandler).decreaseLockedAmounts(tids, decAmounts)).to.not.be
      .reverted
    for (let i = 0; i < tids.length; i++) {
      expect(await this.serviceFeeStorage.getLockedAmount(tids[i])).to.equal(incAmounts[i] - decAmounts[i])
    }
  })
})
