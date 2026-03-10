const { expect } = require('chai')
const { ethers } = require('hardhat')

describe('Registry', () => {
  before(async function () {
    this.wallets = await ethers.getSigners()
    this.dev = this.wallets[0]
    this.governor = this.wallets[1]
    this.migrator = this.wallets[2]
    this.dummyservice = this.wallets[3]
  })

  beforeEach(async function () {
    const ACLManager = await ethers.getContractFactory('ACLManager', this.dev)
    this.acl = await ACLManager.deploy(this.governor.address)
    await this.acl.waitForDeployment()
    await this.acl.connect(this.governor).addMigrator(this.migrator.address)

    const AethirToken = await ethers.getContractFactory('AethirToken', this.dev)
    this.token = await AethirToken.deploy()
    await this.token.waitForDeployment()

    const Registry = await ethers.getContractFactory('Registry', this.dev)
    this.registry = await Registry.deploy(this.acl.target, this.token.target)
    await this.registry.waitForDeployment()
  })

  it('should return acl manager', async function () {
    expect(await this.registry.getACLManager()).to.equal(this.acl.target)
  })

  it('should return aethir token', async function () {
    expect(await this.registry.getATHToken()).to.equal(this.token.target)
  })

  it('should set/get version', async function () {
    expect(await this.registry.getVersion()).to.equal(0)
    await expect(this.registry.setVersion('0')).to.be.revertedWith('Registry: invalid version')
    await expect(this.registry.setVersion('1')).to.be.revertedWith('Migrator only')
    await expect(this.registry.connect(this.migrator).setVersion('1')).to.not.be.reverted
    expect(await this.registry.getVersion()).to.equal(1)
  })

  it('should only allow deployer call initialize', async function () {
    const dummyid = '0x11111111'
    await expect(
      this.registry.connect(this.migrator).initialize([dummyid], [this.dummyservice.address]),
    ).to.be.revertedWith('Registry: not deployer')
    await expect(this.registry.initialize([dummyid], [])).to.be.revertedWith('Registry: input length mismatch')
    await expect(this.registry.initialize([dummyid], [this.dummyservice.address])).to.not.be.reverted
    expect(await this.registry.getVersion()).to.equal(1)
    expect(await this.registry.getFunction('getAddress')(dummyid)).to.equal(this.dummyservice.address)
  })

  it('should set/get service address', async function () {
    const dummyid = '0x11111111'
    expect(await this.registry.getFunction('getAddress')(dummyid)).to.equal(ethers.ZeroAddress)
    await expect(this.registry.setAddress(dummyid, this.dummyservice.address)).to.be.revertedWith('Migrator only')
    await expect(this.registry.connect(this.migrator).setAddress(dummyid, this.dummyservice.address)).to.not.be.reverted
    expect(await this.registry.getFunction('getAddress')(dummyid)).to.equal(this.dummyservice.address)
  })

  it('should allow self-register', async function () {
    const UserStorage = await ethers.getContractFactory('UserStorage', this.dev)
    const service = await UserStorage.deploy(this.registry.target)
    await service.waitForDeployment()
    expect(await this.registry.getFunction('getAddress')(await service.getServiceId())).to.equal(service.target)
  })

  it('should only allow contract deploy by deployer self-register', async function () {
    const UserStorage = await ethers.getContractFactory('UserStorage', this.migrator)
    await expect(UserStorage.deploy(this.registry.target)).to.be.revertedWith('Registry: not deployer')
  })

  it('should not allow self-register after initialized', async function () {
    await this.registry.initialize([], [])
    const UserStorage = await ethers.getContractFactory('UserStorage', this.dev)
    await expect(UserStorage.deploy(this.registry.target)).to.be.revertedWith('Registry: initialized')
  })

  it('should not allow multiple contracts self-register with a same id', async function () {
    const UserStorage = await ethers.getContractFactory('UserStorage', this.dev)
    await UserStorage.deploy(this.registry.target)
    await expect(UserStorage.deploy(this.registry.target)).to.be.revertedWith('Registry: service exists')
  })
})
