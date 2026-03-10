const { expect } = require('chai')

describe('SlashStorage', function () {
  before(async function () {
    this.wallets = await ethers.getSigners()
    this.dev = this.wallets[0]
    this.governor = this.wallets[1]
    this.receiver = this.wallets[2]
    this.other = this.wallets[3]
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

    const ServiceIdList = await ethers.getContractFactory('ServiceIdList', this.dev)
    this.serviceIdList = await ServiceIdList.deploy()
    await this.serviceIdList.waitForDeployment()

    await this.acl.connect(this.governor).addMigrator(this.governor.address)
    await this.registry
      .connect(this.governor)
      .setAddress(await this.serviceIdList.SLASH_HANDLER_ID(), this.handler.address)

    const SlashStorage = await ethers.getContractFactory('SlashStorage', this.dev)
    this.slashStorage = await SlashStorage.deploy(this.registry.target)
    await this.slashStorage.waitForDeployment()
  })

  it('should store a ticket', async function () {
    const tid = 1
    const gid = 1
    const amount = 100
    const container = 1

    await this.slashStorage.connect(this.handler).increaseTicket(tid, gid, container, amount)

    const ticket = await this.slashStorage.getTicket(tid, gid, container)
    expect(ticket.amount).to.equal(amount)
  })

  it('should decrease a ticket', async function () {
    const tid = 1
    const gid = 1
    const amount = 100
    const container = 1

    await this.slashStorage.connect(this.handler).increaseTicket(tid, gid, container, amount)

    const newAmount = 50

    await this.slashStorage.connect(this.handler).decreaseTicket(tid, gid, container, newAmount)

    const ticket = await this.slashStorage.getTicket(tid, gid, container)
    expect(ticket.amount).to.equal(amount - newAmount)
  })

  it('should delete a ticket', async function () {
    const tid = 1
    const gid = 1
    const amount = 100
    const container = 1

    await this.slashStorage.connect(this.handler).increaseTicket(tid, gid, container, amount)

    await this.slashStorage.connect(this.handler).deleteTicket(tid, gid, container)

    const ticket = await this.slashStorage.getTicket(tid, gid, container)
    expect(ticket.amount).to.equal(0)
  })

  it('should revert if non-handler tries to store a ticket', async function () {
    const tid = 1
    const gid = 1
    const amount = 100
    const container = 1

    await expect(this.slashStorage.connect(this.other).increaseTicket(tid, gid, container, amount)).to.be.revertedWith(
      'SlashStorage: handler only',
    )
  })

  it('should revert if non-handler tries to update a ticket', async function () {
    const tid = 1
    const gid = 1
    const amount = 100
    const container = 1

    await this.slashStorage.connect(this.handler).increaseTicket(tid, gid, container, amount)

    const newAmount = 200

    await expect(
      this.slashStorage.connect(this.other).decreaseTicket(tid, gid, container, newAmount),
    ).to.be.revertedWith('SlashStorage: handler only')
  })

  it('should revert if non-handler tries to delete a ticket', async function () {
    const tid = 1
    const gid = 1
    const amount = 100
    const container = 1

    await this.slashStorage.connect(this.handler).increaseTicket(tid, gid, container, amount)

    await expect(this.slashStorage.connect(this.other).decreaseTicket(tid, gid, container, amount)).to.be.revertedWith(
      'SlashStorage: handler only',
    )
  })
})
