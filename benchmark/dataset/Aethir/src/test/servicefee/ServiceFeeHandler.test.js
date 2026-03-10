const { expect } = require('chai')
const { ethers } = require('hardhat')
const { TestDeployment } = require('../utils')

describe('ServiceFeeHandler', () => {
  before(async function () {
    this.d = new TestDeployment(await ethers.getSigners())
    await this.d.deploy()
  })

  beforeEach(async function () {})

  it('should deposit service fee', async function () {
    await this.d.getTestToken(this.d.user.address, 100)
    await this.d.token.connect(this.d.user).approve(this.d.serviceFeeHandler.target, 100)

    const tid = 1
    const amount = 100n
    await this.d.createAccount(this.d.user.address, tid)

    const userBalance = await this.d.token.balanceOf(this.d.user.address)
    const fundBalance = await this.d.token.balanceOf(this.d.serviceFeeFundHolder.target)
    const deposited = await this.d.serviceFeeStorage.getDepositedAmount(tid)
    await expect(this.d.serviceFeeHandler.connect(this.d.user).depositServiceFee(tid, amount)).to.emit(
      this.d.serviceFeeHandler,
      'ServiceFeeDeposited',
    )
    expect(await this.d.token.balanceOf(this.d.user.address)).to.be.equal(userBalance - amount)
    expect(await this.d.token.balanceOf(this.d.serviceFeeFundHolder.target)).to.be.equal(fundBalance + amount)
    expect(await this.d.serviceFeeStorage.getDepositedAmount(tid)).to.be.equal(deposited + amount)
  })

  it('should lock service fee', async function () {
    const tid = 1
    const amount = 50n
    const vdata = await this.d.getVerifiableData(
      this.d.backend.address,
      'SERVICE_FEE_HANDLER_ID',
      'LOCK_SERVICE_FEE',
      ethers.AbiCoder.defaultAbiCoder().encode(['uint256[]', 'uint256[]'], [[tid], [amount]]),
    )
    const deposited = await this.d.serviceFeeStorage.getDepositedAmount(tid)
    const locked = await this.d.serviceFeeStorage.getLockedAmount(tid)
    await expect(this.d.serviceFeeHandler.connect(this.d.backend).lockServiceFee(vdata)).to.emit(
      this.d.serviceFeeHandler,
      'ServiceFeeLocked',
    )
    expect(await this.d.serviceFeeStorage.getDepositedAmount(tid)).to.be.equal(deposited - amount)
    expect(await this.d.serviceFeeStorage.getLockedAmount(tid)).to.be.equal(locked + amount)
  })

  it('should unlock service fee', async function () {
    const tid = 1
    const amount = 30n
    const vdata = await this.d.getVerifiableData(
      this.d.backend.address,
      'SERVICE_FEE_HANDLER_ID',
      'UNLOCK_SERVICE_FEE',
      ethers.AbiCoder.defaultAbiCoder().encode(['uint256[]', 'uint256[]'], [[tid], [amount]]),
    )
    const deposited = await this.d.serviceFeeStorage.getDepositedAmount(tid)
    const locked = await this.d.serviceFeeStorage.getLockedAmount(tid)
    await expect(this.d.serviceFeeHandler.connect(this.d.backend).unlockServiceFee(vdata)).to.emit(
      this.d.serviceFeeHandler,
      'ServiceFeeUnlocked',
    )
    expect(await this.d.serviceFeeStorage.getDepositedAmount(tid)).to.be.equal(deposited + amount)
    expect(await this.d.serviceFeeStorage.getLockedAmount(tid)).to.be.equal(locked - amount)
  })

  it('should withdraw service fee', async function () {
    const tid = 1
    await this.d.createAccount(this.d.user.address, 1) // We need to create an account to withdraw service fee

    const amount = 20n
    const userBalance = await this.d.token.balanceOf(this.d.user.address)
    const fundBalance = await this.d.token.balanceOf(this.d.serviceFeeFundHolder.target)
    const deposited = await this.d.serviceFeeStorage.getDepositedAmount(tid)
    await this.d.updateKYC(this.d.user.address, true)
    await expect(this.d.serviceFeeHandler.connect(this.d.user).withdrawServiceFee(tid, amount)).to.emit(
      this.d.serviceFeeHandler,
      'ServiceFeeWithdrawn',
    )
    expect(await this.d.token.balanceOf(this.d.user.address)).to.be.equal(userBalance + amount)
    expect(await this.d.token.balanceOf(this.d.serviceFeeFundHolder.target)).to.be.equal(fundBalance - amount)
    expect(await this.d.serviceFeeStorage.getDepositedAmount(tid)).to.be.equal(deposited - amount)
  })

  it('should settle service fee', async function () {
    const tenantIds = [1]
    const tenantAmounts = [10n]
    const hostIds = [2]
    const groupIds = [3]
    const hostGroupAmounts = [10n]
    const grantAmount = 0
    const slashAmount = 0
    for (let i = 0; i < hostIds.length; i++) {
      await this.d.createGroup(hostIds[i], groupIds[i])
    }

    const vdata = await this.d.getVerifiableData(
      this.d.backend.address,
      'SERVICE_FEE_HANDLER_ID',
      'SETTLE_SERVICE_FEE',
      ethers.AbiCoder.defaultAbiCoder().encode(
        ['(uint256[],uint256[],uint256[],uint256[],uint256[],uint256,uint256)'],
        [[tenantIds, tenantAmounts, hostIds, groupIds, hostGroupAmounts, grantAmount, slashAmount]],
      ),
    )
    const locked = await this.d.serviceFeeStorage.getLockedAmount(tenantIds[0])
    await expect(this.d.serviceFeeHandler.connect(this.d.backend).settleServiceFee(vdata)).to.emit(
      this.d.serviceFeeHandler,
      'ServiceFeeSettled',
    )
    expect(await this.d.serviceFeeStorage.getLockedAmount(tenantIds[0])).to.be.equal(locked - tenantAmounts[0])
  })

  it('should initial settle service fee', async function () {
    const tid = 2
    const gid = 3
    const amounts = [10, 20, 30]
    const vestingDays = [1000, 1001, 1002]
    await this.d.createGroup(tid, gid)

    const vdata = await this.d.getVerifiableData(
      this.d.backend.address,
      'SERVICE_FEE_HANDLER_ID',
      'INITIAL_SETTLE_SERVICE_FEE',
      ethers.AbiCoder.defaultAbiCoder().encode(
        ['uint256[]', 'uint256[]', '(uint256[],uint32[])[]'],
        [[tid], [gid], [[amounts, vestingDays]]],
      ),
      '0x',
      true,
    )
    await expect(this.d.serviceFeeHandler.connect(this.d.backend).initialSettleServiceFee(vdata)).to.emit(
      this.d.serviceFeeHandler,
      'ServiceFeeInitialSettled',
    )
  })
})
