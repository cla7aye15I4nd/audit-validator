const { expect } = require('chai')

describe('ServiceFeeCommissionReceiver', () => {
  before(async function () {
    this.wallets = await ethers.getSigners()
    this.dev = this.wallets[0]
    this.governor = this.wallets[1]
    this.user = this.wallets[3]
  })

  beforeEach(async function () {
    const ACLManager = await ethers.getContractFactory('ACLManager', this.dev)
    this.acl = await ACLManager.deploy(this.governor.address)
    await this.acl.waitForDeployment()

    const AethirToken = await ethers.getContractFactory('AethirToken', this.dev)
    this.token = await AethirToken.deploy()
    await this.token.waitForDeployment()

    const Registry = await ethers.getContractFactory('Registry', this.dev)
    this.registry = await Registry.deploy(this.acl.target, this.token.target)
    await this.registry.waitForDeployment()

    const MockKYC = await ethers.getContractFactory('MockKYC', this.dev)
    this.kycWhitelist = await MockKYC.deploy(this.registry.target)
    await this.kycWhitelist.waitForDeployment()

    const MockRequestVerifier = await ethers.getContractFactory('MockRequestVerifier', this.dev)
    this.requestVerifier = await MockRequestVerifier.deploy(this.registry.target)
    await this.requestVerifier.waitForDeployment()

    const ServiceFeeCommissionReceiver = await ethers.getContractFactory('ServiceFeeCommissionReceiver', this.dev)
    this.receiver = await ServiceFeeCommissionReceiver.deploy(this.registry.target)
    await this.receiver.waitForDeployment()
  })

  it('should withdraw service fee commission by governor', async function () {
    await this.token.transfer(this.receiver.target, 1000)
    expect(await this.token.balanceOf(this.user.address)).to.equal(0)
    expect(await this.token.balanceOf(this.receiver.target)).to.equal(1000)

    await expect(this.receiver.withdrawServiceFeeCommission(this.user.address, 100)).to.be.revertedWith(
      'Fund withdraw admin only',
    )
    await this.acl.connect(this.governor).addFundWithdrawAdmin(this.governor)
    await expect(this.receiver.connect(this.governor).withdrawServiceFeeCommission(this.user.address, 100)).to.not.be
      .reverted

    expect(await this.token.balanceOf(this.user.address)).to.equal(100)
    expect(await this.token.balanceOf(this.receiver.target)).to.equal(900)
  })
})
