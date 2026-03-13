const { expect } = require('chai')

describe('BlackListManager', function () {
  before(async function () {
    this.wallets = await ethers.getSigners()
    this.dev = this.wallets[0]
    this.governor = this.wallets[1]
    this.user = this.wallets[2]
    this.configurator = this.wallets[3]
  })

  beforeEach(async function () {
    const ACLManager = await ethers.getContractFactory('ACLManager', this.dev)
    this.acl = await ACLManager.deploy(this.governor.address)
    await this.acl.waitForDeployment()

    this.acl.connect(this.governor).addConfigurationAdmin(this.configurator.address)

    const ATHToken = await ethers.getContractFactory('AethirToken', this.dev)
    this.ath = await ATHToken.deploy()
    await this.ath.waitForDeployment()

    const Registry = await ethers.getContractFactory('Registry', this.dev)
    this.registry = await Registry.deploy(this.acl.target, this.ath.target)
    await this.registry.waitForDeployment()

    const TierController = await ethers.getContractFactory('TierController', this.dev)
    this.tierController = await TierController.deploy(this.registry.target)
    await this.tierController.waitForDeployment()

    // Deploy BlackListManager
    const BlackListManager = await ethers.getContractFactory('BlackListManager', this.dev)
    this.blackListManager = await BlackListManager.deploy(this.registry.target)
    await this.blackListManager.waitForDeployment()
  })

  it('should set blacklist tier for an address', async function () {
    await this.blackListManager.connect(this.configurator).setBlackListed(this.user.address, 2)
    const isAllowed = await this.blackListManager.isAllowed(this.user.address, '0x12345678')
    expect(isAllowed).to.be.false
  })

  it('should allow address if function tier is higher than blacklist tier', async function () {
    await this.blackListManager.connect(this.configurator).setBlackListed(this.user.address, 1)
    await this.tierController.connect(this.governor).setFunctionTier('0x12345678', 2)
    const isAllowed = await this.blackListManager.isAllowed(this.user.address, '0x12345678')
    expect(isAllowed).to.be.true
  })

  it('should not allow non-admin to set blacklist', async function () {
    await expect(this.blackListManager.connect(this.user).setBlackListed(this.user.address, 2)).to.be.revertedWith(
      'Configuration admin only',
    )
  })
})
