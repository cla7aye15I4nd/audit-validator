const { expect } = require('chai')

describe('StakeStorage', function () {
  before(async function () {
    this.wallets = await ethers.getSigners()
    this.dev = this.wallets[0]
    this.governor = this.wallets[1]
    this.handler = this.wallets[2]
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

    const ServiceIdList = await ethers.getContractFactory('ServiceIdList', this.dev)
    this.serviceIdList = await ServiceIdList.deploy()
    await this.serviceIdList.waitForDeployment()

    await this.acl.connect(this.governor).addMigrator(this.governor.address)
    await this.registry
      .connect(this.governor)
      .setAddress(await this.serviceIdList.STAKE_HANDLER_ID(), this.handler.address)

    const StakeStorage = await ethers.getContractFactory('StakeStorage', this.dev)
    this.stakeStorage = await StakeStorage.deploy(this.registry.target)
    await this.stakeStorage.waitForDeployment()
  })

  it('should allow staking by handler', async function () {
    const tid = 1
    const gid = 1
    const container = 1
    const amount = 100
    const delegator = '0x0000000000000000000000000000000000000002'

    await this.stakeStorage.connect(this.handler).stake(tid, gid, [container], [amount], delegator)

    const stakeData = await this.stakeStorage.getStakeData(tid, gid, container)
    expect(stakeData.tid).to.equal(tid)
    expect(stakeData.gid).to.equal(gid)
    expect(stakeData.cid).to.equal(container)
    expect(stakeData.amount).to.equal(amount)
    expect(stakeData.delegator).to.equal(delegator)
  })

  it("should revert staked amount if there's already a stake", async function () {
    const tid = 1
    const gid = 1
    const container = 1
    const amount = 100
    const delegator = '0x0000000000000000000000000000000000000002'

    await this.stakeStorage.connect(this.handler).stake(tid, gid, [container], [amount], delegator)
    await expect(
      this.stakeStorage.connect(this.handler).stake(tid, gid, [container], [amount], delegator),
    ).to.be.revertedWith('StakeStorage: stake exists')
  })

  it('should allow unstaking by handler', async function () {
    const tid = 1
    const gid = 1
    const container = 1
    const amount = 100
    const delegator = '0x0000000000000000000000000000000000000002'

    await this.stakeStorage.connect(this.handler).stake(tid, gid, [container], [amount], delegator)
    await this.stakeStorage.connect(this.handler).unstake(tid, gid, [container])

    const stakeData = await this.stakeStorage.getStakeData(tid, gid, container)
    expect(stakeData.amount).to.equal(0)
  })

  it('should not allow staking by non-handler', async function () {
    const tid = 1
    const gid = 1
    const container = 1
    const amount = 100
    const delegator = '0x0000000000000000000000000000000000000002'

    await expect(this.stakeStorage.stake(tid, gid, [container], [amount], delegator)).to.be.revertedWith(
      'StakeStorage: handler only',
    )
  })
})
