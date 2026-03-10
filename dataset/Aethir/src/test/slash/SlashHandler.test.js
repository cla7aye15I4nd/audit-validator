const { expect } = require('chai')
const { TestDeployment } = require('../utils')
const { ethers } = require('hardhat')

describe('SlashHandler', () => {
  before(async function () {
    this.wallets = await ethers.getSigners()
    this.d = new TestDeployment(this.wallets)
    await this.d.deploy()
    this.dummyTicketManager = this.wallets[10]
    this.user = this.wallets[12]

    await this.d.registry
      .connect(this.d.migrator)
      .setAddress(await this.d.serviceIds.TICKET_MANAGER_ID(), this.dummyTicketManager.address)
  })

  it('should createTicket', async function () {
    const tid = 1
    const gid = 1
    const container = 1
    const amount = ethers.parseEther('1')

    expect(await this.d.slashHandler.connect(this.dummyTicketManager).createTicket(tid, gid, container, amount)).emit(
      this.d.slashHandler,
      'TicketCreated',
    )
  })

  it('should settlePenalty', async function () {
    const tid = 1
    const gid = 1
    const container = 1
    const amount = 100
    const caller = this.user.address

    await this.d.createGroup(tid, gid)
    await this.d.createAccount(this.user.address, tid)

    await this.d.getTestToken(this.user.address, ethers.parseEther('1000'))
    await this.d.token.connect(this.user).approve(this.d.slashHandler.target, ethers.parseEther('1000'))

    await this.d.slashHandler.connect(this.dummyTicketManager).createTicket(tid, gid, container, amount)
    expect(await this.d.slashHandler.connect(this.dummyTicketManager).settlePenalty(tid, gid, container, caller)).emit(
      this.d.slashHandler,
      'PenaltySettled',
    )
  })

  it('should cancelPenalty', async function () {
    const tid = 1
    const gid = 1
    const container = 1
    const amount = 100

    await this.d.slashHandler.connect(this.dummyTicketManager).createTicket(tid, gid, container, amount)
    expect(await this.d.slashHandler.connect(this.dummyTicketManager).cancelPenalty(tid, gid, container, amount)).emit(
      this.d.slashHandler,
      'PenaltyCancelled',
    )
  })

  // it('should deduct penalty', async function () {
  //   const tid = 1
  //   const gid = 1
  //   const amounts = [1000, 2000, 3000]
  //   const vestingDays = [0, 2, 4]
  //   const container = 1

  //   await this.d.createGroup(tid, gid)
  //   await this.d.createAccount(this.user.address, tid)

  //   const vdata = await this.d.getVerifiableData(
  //     this.d.backend.address,
  //     'SERVICE_FEE_HANDLER_ID',
  //     'INITIAL_SETTLE_SERVICE_FEE',
  //     ethers.AbiCoder.defaultAbiCoder().encode(
  //       ['uint256[]', 'uint256[]', '(uint256[],uint32[])[]'],
  //       [[tid], [gid], [[amounts, vestingDays]]]
  //     ),
  //     '0x',
  //     true
  //   )
  //   await this.d.serviceFeeHandler.connect(this.d.backend).initialSettleServiceFee(vdata)

  //   await this.d.slashHandler.connect(this.dummyTicketManager).createTicket(tid, gid, container, 100)

  //   const ticketExpireTime = await this.d.slashConfigurator.getTicketExpireTime()

  //   await time.increase(ticketExpireTime)

  //   const fees = { amounts: [1, 1], vestingDays: [0, 2] }
  //   const rewards = { amounts: [], vestingDays: [] }
  //   const stakes = { amounts: [], vestingDays: [] }

  //   const totalAmount =
  //     fees.amounts.reduce((a, b) => a + b, 0) +
  //     rewards.amounts.reduce((a, b) => a + b, 0) +
  //     stakes.amounts.reduce((a, b) => a + b, 0)

  //   await this.d.getTestToken(this.d.vestingFundHolder.address, totalAmount)

  //   await this.d.token.connect(this.user).approve(this.d.slashHandler.address, totalAmount)

  //   await expect(
  //     this.d.slashHandler.connect(this.dummyTicketManager).deductPenalty(tid, gid, container, fees, rewards, stakes)
  //   ).to.emit(this.d.slashHandler, 'PenaltyDeducted')
  // })
})
