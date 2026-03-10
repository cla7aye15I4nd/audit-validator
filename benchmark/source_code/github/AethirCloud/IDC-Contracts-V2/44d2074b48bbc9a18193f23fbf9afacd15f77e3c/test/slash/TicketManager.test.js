const { expect } = require('chai')
const { TestDeployment } = require('../utils')

describe('TicketManager', function () {
  before(async function () {
    this.wallets = await ethers.getSigners()

    this.d = new TestDeployment(this.wallets)
    await this.d.deploy()

    this.user = this.wallets[12]
  })

  it('should add a penalty', async function () {
    const tid = 1
    const gid = 1
    const amount = 100
    const container = 1
    const vdata = await this.d.getVerifiableData(
      this.d.backend.address,
      'TICKET_MANAGER_ID',
      'ADD_PENALTY',
      ethers.AbiCoder.defaultAbiCoder().encode(
        ['uint256', 'uint256', 'uint256', 'uint256'],
        [tid, gid, amount, container],
      ),
      '0x',
    )

    await expect(this.d.ticketManager.connect(this.d.backend).addPenalty(vdata)).to.emit(
      this.d.ticketManager,
      'TicketCreated',
    )
  })

  it('should cancel a penalty', async function () {
    const tid = 1
    const gid = 1
    const container = 1
    const amount = 50

    const vdata = await this.d.getVerifiableData(
      this.d.backend.address,
      'TICKET_MANAGER_ID',
      'CANCEL_PENALTY',
      ethers.AbiCoder.defaultAbiCoder().encode(
        ['uint256', 'uint256', 'uint256', 'uint256'],
        [tid, gid, container, amount],
      ),
      '0x',
    )

    await expect(this.d.ticketManager.connect(this.d.backend).cancelPenalty(vdata)).to.emit(
      this.d.ticketManager,
      'TicketCancelled',
    )
  })

  it('should settle a penalty', async function () {
    const tid = 1
    const gid = 1
    const container = 1

    await this.d.createGroup(tid, gid)
    await this.d.createAccount(this.user.address, tid)

    await this.d.getTestToken(this.user.address, ethers.parseEther('1000'))
    await this.d.token.connect(this.user).approve(this.d.slashHandler.target, ethers.parseEther('1000'))

    const vdata = await this.d.getVerifiableData(
      this.user.address,
      'TICKET_MANAGER_ID',
      'SETTLE_PENALTY',
      ethers.AbiCoder.defaultAbiCoder().encode(['uint256', 'uint256', 'uint256'], [tid, gid, container]),
      '0x',
    )
    await expect(this.d.ticketManager.connect(this.user).settlePenalty(vdata)).to.emit(
      this.d.ticketManager,
      'TicketSettled',
    )
  })

  // it('should deduct a penalty', async function () {
  //   const tid = 1
  //   const gid = 1
  //   const container = 1
  //   const amount = 100
  //   const amounts = [1000, 2000, 3000]
  //   const vestingDays = [0, 2, 4]

  //   await this.d.createGroup(tid, gid)
  //   await this.d.createAccount(this.user.address, tid)

  //   const initialVData = await this.d.getVerifiableData(
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
  //   await this.d.serviceFeeHandler.connect(this.d.backend).initialSettleServiceFee(initialVData)

  //   const createTickerVData = await this.d.getVerifiableData(
  //     this.d.backend.address,
  //     'TICKET_MANAGER_ID',
  //     'ADD_PENALTY',
  //     ethers.AbiCoder.defaultAbiCoder().encode(['uint256', 'uint256', 'uint256', 'uint256'], [tid, gid, amount, container]),
  //     '0x'
  //   )

  //   await this.d.ticketManager.addPenalty(createTickerVData)

  //   const ticketExpireTime = await this.d.slashConfigurator.getTicketExpireTime()

  //   await time.increase(ticketExpireTime)

  //   const fees = { amounts: [1, 1], vestingDays: [0, 2] }
  //   const rewards = { amounts: [], vestingDays: [] }
  //   const stakes = { amounts: [], vestingDays: [] }

  //   const vdata = await this.d.getVerifiableData(
  //     this.d.backend.address,
  //     'TICKET_MANAGER_ID',
  //     'DEDUCT_PENALTY',
  //     ethers.AbiCoder.defaultAbiCoder().encode(
  //       [
  //         'uint256',
  //         'uint256',
  //         'uint256',
  //         'tuple(uint256[], uint32[])',
  //         'tuple(uint256[], uint32[])',
  //         'tuple(uint256[], uint32[])',
  //       ],
  //       [
  //         tid,
  //         gid,
  //         container,
  //         [fees.amounts, fees.vestingDays],
  //         [rewards.amounts, rewards.vestingDays],
  //         [stakes.amounts, stakes.vestingDays],
  //       ]
  //     ),
  //     '0x'
  //   )

  //   const totalAmount =
  //     fees.amounts.reduce((a, b) => a + b, 0) +
  //     rewards.amounts.reduce((a, b) => a + b, 0) +
  //     stakes.amounts.reduce((a, b) => a + b, 0)

  //   await this.d.getTestToken(this.d.vestingFundHolder.address, totalAmount)

  //   await this.d.token.connect(this.user).approve(this.d.slashHandler.address, totalAmount)

  //   await expect(this.d.ticketManager.deductPenalty(vdata)).to.emit(this.d.ticketManager, 'TicketDeducted')
  // })
})
