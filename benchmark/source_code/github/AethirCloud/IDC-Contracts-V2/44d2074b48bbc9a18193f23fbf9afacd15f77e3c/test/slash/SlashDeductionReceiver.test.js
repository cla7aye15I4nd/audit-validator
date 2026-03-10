const { expect } = require('chai')

describe('SlashDeductionReceiver', function () {
  before(async function () {
    this.wallets = await ethers.getSigners()
    this.dev = this.wallets[0]
    this.governor = this.wallets[1]
    this.receiver = this.wallets[2]
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

    // Deploy the RewardCommissionReceiver contract
    const SlashDeductionReceiver = await ethers.getContractFactory('SlashDeductionReceiver')
    this.slashDeductionReceiver = await SlashDeductionReceiver.deploy(this.registry.target)
    await this.slashDeductionReceiver.waitForDeployment()
  })

  describe('withdrawSlashPenalty', function () {
    it('should allow the default admin to withdraw slash penalty', async function () {
      const amount = ethers.parseEther('10')

      // transfer from dev to rewardCommissionReceiver
      await this.ath.connect(this.dev).transfer(this.slashDeductionReceiver.target, amount)

      await this.acl.connect(this.governor).addFundWithdrawAdmin(this.governor.address)
      // Withdraw the reward commission
      await expect(
        this.slashDeductionReceiver.connect(this.governor).withdrawSlashPenalty(this.receiver.address, amount),
      )
        .to.emit(this.slashDeductionReceiver, 'PenaltySlashWithdrawn')
        .withArgs(this.receiver.address, amount)

      // // Check the recipient's balance
      expect(await this.ath.balanceOf(this.receiver.address)).to.equal(amount)
    })

    it('should not allow non-admins to withdraw reward commission', async function () {
      const amount = ethers.parseEther('10')

      // transfer from dev to rewardCommissionReceiver
      await this.ath.connect(this.dev).transfer(this.slashDeductionReceiver.target, amount)

      // Try to withdraw the reward commission as a non-admin
      await expect(
        this.slashDeductionReceiver.connect(this.receiver).withdrawSlashPenalty(this.receiver.address, amount),
      ).to.be.revertedWith('Fund withdraw admin only')
    })
  })
})
