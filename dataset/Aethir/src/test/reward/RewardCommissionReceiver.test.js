const { expect } = require('chai')

describe('RewardCommissionReceiver', function () {
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

    await this.acl.connect(this.governor).addFundWithdrawAdmin(this.governor.address)

    const ATHToken = await ethers.getContractFactory('AethirToken', this.dev)
    this.ath = await ATHToken.deploy()
    await this.ath.waitForDeployment()

    const Registry = await ethers.getContractFactory('Registry', this.dev)
    this.registry = await Registry.deploy(this.acl.target, this.ath.target)
    await this.registry.waitForDeployment()

    // Deploy the RewardCommissionReceiver contract
    const RewardCommissionReceiver = await ethers.getContractFactory('RewardCommissionReceiver')
    this.rewardCommissionReceiver = await RewardCommissionReceiver.deploy(this.registry.target)
    await this.rewardCommissionReceiver.waitForDeployment()
  })

  describe('withdrawRewardCommission', function () {
    it('should allow the default admin to withdraw reward commission', async function () {
      const amount = ethers.parseEther('10')

      // transfer from dev to rewardCommissionReceiver
      await this.ath.connect(this.dev).transfer(this.rewardCommissionReceiver.target, amount)

      // Withdraw the reward commission
      await expect(
        this.rewardCommissionReceiver.connect(this.governor).withdrawRewardCommission(this.receiver.address, amount),
      )
        .to.emit(this.rewardCommissionReceiver, 'RewardCommissionWithdrawn')
        .withArgs(this.receiver.address, amount)

      // // Check the recipient's balance
      expect(await this.ath.balanceOf(this.receiver.address)).to.equal(amount)
    })

    it('should not allow non-admins to withdraw reward commission', async function () {
      const amount = ethers.parseEther('10')

      // transfer from dev to rewardCommissionReceiver
      await this.ath.connect(this.dev).transfer(this.rewardCommissionReceiver.target, amount)

      // Try to withdraw the reward commission as a non-admin
      await expect(
        this.rewardCommissionReceiver.connect(this.receiver).withdrawRewardCommission(this.receiver.address, amount),
      ).to.be.revertedWith('Fund withdraw admin only')
    })
  })
})
