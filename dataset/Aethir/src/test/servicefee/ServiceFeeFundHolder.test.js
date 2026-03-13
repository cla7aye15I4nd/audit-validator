const { expect } = require('chai')

describe('ServiceFeeFundHolder', () => {
  before(async function () {
    this.wallets = await ethers.getSigners()
    this.dev = this.wallets[0]
    this.governor = this.wallets[1]
    this.migrator = this.wallets[2]
    this.user = this.wallets[3]
    this.dummyhandler = this.wallets[4]
  })

  beforeEach(async function () {
    const ACLManager = await ethers.getContractFactory('ACLManager', this.dev)
    this.acl = await ACLManager.deploy(this.governor.address)
    await this.acl.waitForDeployment()
    await this.acl.connect(this.governor).addMigrator(this.migrator.address)

    const AethirToken = await ethers.getContractFactory('AethirToken', this.dev)
    this.token = await AethirToken.deploy()
    await this.token.waitForDeployment()

    const ServiceIdList = await ethers.getContractFactory('ServiceIdList', this.dev)
    this.serviceIdList = await ServiceIdList.deploy()
    await this.serviceIdList.waitForDeployment()

    const Registry = await ethers.getContractFactory('Registry', this.dev)
    this.registry = await Registry.deploy(this.acl.target, this.token.target)
    await this.registry.waitForDeployment()
    await this.registry
      .connect(this.migrator)
      .setAddress(await this.serviceIdList.SERVICE_FEE_HANDLER_ID(), this.dummyhandler.address)

    const MockKYC = await ethers.getContractFactory('MockKYC', this.dev)
    this.kycWhitelist = await MockKYC.deploy(this.registry.target)
    await this.kycWhitelist.waitForDeployment()

    const MockRequestVerifier = await ethers.getContractFactory('MockRequestVerifier', this.dev)
    this.requestVerifier = await MockRequestVerifier.deploy(this.registry.target)
    await this.requestVerifier.waitForDeployment()

    const ServiceFeeFundHolder = await ethers.getContractFactory('ServiceFeeFundHolder', this.dev)
    this.serviceFeeFundHolder = await ServiceFeeFundHolder.deploy(this.registry.target)
    await this.serviceFeeFundHolder.waitForDeployment()
  })

  it('should send grant fund to ServiceFeeFundHolder', async function () {
    await this.token.transfer(this.serviceFeeFundHolder.target, 1000)
    expect(await this.token.balanceOf(this.serviceFeeFundHolder.target)).to.equal(1000)
    expect(await this.token.balanceOf(this.user.address)).to.equal(0)

    await expect(this.serviceFeeFundHolder.sendServiceFeeToken(this.user.address, 100)).to.be.revertedWith(
      'ServiceFeeHandler only',
    )
    await expect(this.serviceFeeFundHolder.connect(this.dummyhandler).sendServiceFeeToken(this.user.address, 100)).to
      .not.be.reverted

    expect(await this.token.balanceOf(this.serviceFeeFundHolder.target)).to.equal(900)
    expect(await this.token.balanceOf(this.user.address)).to.equal(100)
  })
})
