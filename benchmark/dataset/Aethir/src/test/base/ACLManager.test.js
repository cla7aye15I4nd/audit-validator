const { expect } = require('chai')

describe('ACLManager', () => {
  before(async function () {
    this.wallets = await ethers.getSigners()
    this.dev = this.wallets[0]
    this.governor = this.wallets[1]
  })

  beforeEach(async function () {
    console.log(this.dev)
    const ACLManager = await ethers.getContractFactory('ACLManager', this.dev)
    this.acl = await ACLManager.deploy(this.governor.address)
    await this.acl.waitForDeployment()
  })

  it('should not allow 0x00 governor', async function () {
    const ACLManager = await ethers.getContractFactory('ACLManager', this.dev)
    await expect(ACLManager.deploy('0x0000000000000000000000000000000000000000')).to.be.revertedWith(
      'Governor cannot be zero',
    )
  })

  it('should grant default roles', async function () {
    expect(await this.acl.hasRole(await this.acl.DEFAULT_ADMIN_ROLE(), this.dev.address)).to.equal(false)
    expect(await this.acl.hasRole(await this.acl.DEFAULT_ADMIN_ROLE(), this.governor.address)).to.equal(true)
  })

  it('should add/remove Configuration Admin', async function () {
    await expect(this.acl.addConfigurationAdmin(this.dev.address)).to.be.revertedWithCustomError(
      this.acl,
      'AccessControlUnauthorizedAccount',
    )
    await expect(this.acl.connect(this.governor).addConfigurationAdmin(this.dev.address)).to.not.be.reverted
    await expect(this.acl.requireConfigurationAdmin(this.dev.address)).to.not.be.reverted

    await expect(this.acl.removeConfigurationAdmin(this.dev.address)).to.be.revertedWithCustomError(
      this.acl,
      'AccessControlUnauthorizedAccount',
    )
    await expect(this.acl.connect(this.governor).removeConfigurationAdmin(this.dev.address)).to.not.be.reverted
    await expect(this.acl.requireConfigurationAdmin(this.dev.address)).to.be.revertedWith('Configuration admin only')
  })

  it('should add/remove Migrator', async function () {
    await expect(this.acl.addMigrator(this.dev.address)).to.be.revertedWithCustomError(
      this.acl,
      'AccessControlUnauthorizedAccount',
    )
    await expect(this.acl.connect(this.governor).addMigrator(this.dev.address)).to.not.be.reverted
    await expect(this.acl.requireMigrator(this.dev.address)).to.not.be.reverted

    await expect(this.acl.removeMigrator(this.dev.address)).to.be.revertedWithCustomError(
      this.acl,
      'AccessControlUnauthorizedAccount',
    )
    await expect(this.acl.connect(this.governor).removeMigrator(this.dev.address)).to.not.be.reverted
    await expect(this.acl.requireMigrator(this.dev.address)).to.be.revertedWith('Migrator only')
  })

  it('should add/remove Validator', async function () {
    await expect(this.acl.addValidator(this.dev.address)).to.be.revertedWithCustomError(
      this.acl,
      'AccessControlUnauthorizedAccount',
    )
    await expect(this.acl.connect(this.governor).addValidator(this.dev.address)).to.not.be.reverted
    await expect(this.acl.requireValidator(this.dev.address)).to.not.be.reverted

    await expect(this.acl.removeValidator(this.dev.address)).to.be.revertedWithCustomError(
      this.acl,
      'AccessControlUnauthorizedAccount',
    )
    await expect(this.acl.connect(this.governor).removeValidator(this.dev.address)).to.not.be.reverted
    await expect(this.acl.requireValidator(this.dev.address)).to.be.revertedWith('Validator only')
  })

  it('should add/remove Init Settlement Operator', async function () {
    await expect(this.acl.addInitSettlementOperator(this.dev.address)).to.be.revertedWithCustomError(
      this.acl,
      'AccessControlUnauthorizedAccount',
    )
    await expect(this.acl.connect(this.governor).addInitSettlementOperator(this.dev.address)).to.not.be.reverted
    await expect(this.acl.requireInitSettlementOperator(this.dev.address)).to.not.be.reverted

    await expect(this.acl.removeInitSettlementOperator(this.dev.address)).to.be.revertedWithCustomError(
      this.acl,
      'AccessControlUnauthorizedAccount',
    )
    await expect(this.acl.connect(this.governor).removeInitSettlementOperator(this.dev.address)).to.not.be.reverted
    await expect(this.acl.requireInitSettlementOperator(this.dev.address)).to.be.revertedWith(
      'Init settlement operator only',
    )
  })

  it('should get/set required signatures', async function () {
    await expect(this.acl.setRequiredSignatures(3)).to.be.revertedWithCustomError(
      this.acl,
      'AccessControlUnauthorizedAccount',
    )
    await expect(this.acl.connect(this.governor).setRequiredSignatures(3)).to.not.be.reverted
    expect(await this.acl.getRequiredSignatures()).to.equal(3)
  })

  it('should get/set required initiator signatures', async function () {
    await expect(this.acl.setRequiredInitiatorSignatures(3)).to.be.revertedWithCustomError(
      this.acl,
      'AccessControlUnauthorizedAccount',
    )
    await expect(this.acl.connect(this.governor).setRequiredInitiatorSignatures(3)).to.not.be.reverted
    expect(await this.acl.getRequiredInitiatorSignatures()).to.equal(3)
  })
})
