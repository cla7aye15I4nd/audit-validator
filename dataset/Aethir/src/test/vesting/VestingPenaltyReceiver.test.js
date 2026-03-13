const { expect } = require('chai')
const { ethers } = require('hardhat')
const { TestDeployment } = require('../utils')

describe('VestingPenaltyReceiver', () => {
  before(async function () {
    this.d = new TestDeployment(await ethers.getSigners())
    await this.d.deploy()
    await this.d.getTestToken(this.d.getServiceAddress('VESTING_PENALTY_RECEIVER_ID'), 1000)
  })

  beforeEach(async function () {})

  it('should withdraw early claim penalty', async function () {
    await expect(
      this.d.vestingPenaltyReceiver.connect(this.d.user).withdrawEarlyClaimPenalty(this.d.user.address, 10),
    ).to.be.revertedWith('Fund withdraw admin only')
    await this.d.acl.connect(this.d.governor).addFundWithdrawAdmin(this.d.governor.address)
    await expect(
      this.d.vestingPenaltyReceiver.connect(this.d.governor).withdrawEarlyClaimPenalty(this.d.user.address, 10),
    ).to.emit(this.d.vestingPenaltyReceiver, 'EarlyClaimPenaltyWithdrawn')
  })
})
