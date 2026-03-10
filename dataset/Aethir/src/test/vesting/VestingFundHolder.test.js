const { expect } = require('chai')
const { ethers } = require('hardhat')
const { TestDeployment } = require('../utils')

describe('VestingFundHolder', () => {
  before(async function () {
    this.d = new TestDeployment(await ethers.getSigners())
    await this.d.deploy()
    await this.d.registry
      .connect(this.d.migrator)
      .setAddress(await this.d.getServiceId('VESTING_HANDLER_ID'), this.d.dummyhandler.address)
    await this.d.getTestToken(this.d.getServiceAddress('VESTING_FUND_HOLDER_ID'), 1000)
  })

  beforeEach(async function () {})

  it('should send vested token', async function () {
    await expect(
      this.d.vestingFundHolder.connect(this.d.user).sendVestedToken(this.d.user.address, 10),
    ).to.be.revertedWith('VestingFundHolder: handler only')

    await this.d.updateKYC(this.d.user.address, true)
    await expect(
      this.d.vestingFundHolder.connect(this.d.dummyhandler).sendVestedToken(this.d.user.address, 10),
    ).to.emit(this.d.vestingFundHolder, 'VestedTokenSent')
  })

  it('should send penalty token', async function () {
    await expect(this.d.vestingFundHolder.connect(this.d.user).sendPenaltyToken(10)).to.be.revertedWith(
      'VestingFundHolder: handler only',
    )
    await expect(this.d.vestingFundHolder.connect(this.d.dummyhandler).sendPenaltyToken(10)).to.emit(
      this.d.vestingFundHolder,
      'PenaltyTokenSent',
    )
  })
})
