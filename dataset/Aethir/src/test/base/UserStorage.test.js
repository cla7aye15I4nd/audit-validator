const { expect } = require('chai')

describe('UserStorage', () => {
  before(async function () {
    this.wallets = await ethers.getSigners()
    this.dev = this.wallets[0]
    this.governor = this.wallets[1]
    this.migrator = this.wallets[2]
    this.user = this.wallets[3]
    this.dummyverifier = this.wallets[4]
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
      .setAddress(await this.serviceIdList.REQUEST_VERIFIER_ID(), this.dummyverifier.address)

    const UserStorage = await ethers.getContractFactory('UserStorage', this.dev)
    this.userStorage = await UserStorage.deploy(this.registry.target)
    await this.userStorage.waitForDeployment()
  })

  it('should set/get userdata', async function () {
    let userData = await this.userStorage.getUserData(this.user.address)
    expect(userData.nonce).to.equal(0)
    expect(userData.lastUpdateBlock).to.equal(0)

    await expect(this.userStorage.setUserData(this.user.address, [1, 1])).to.be.revertedWith(
      'UserStorage: verifier only',
    )
    await expect(this.userStorage.connect(this.dummyverifier).setUserData(this.user.address, [1, 1])).to.not.be.reverted

    userData = await this.userStorage.getUserData(this.user.address)
    expect(userData.nonce).to.equal(1)
    expect(userData.lastUpdateBlock).to.equal(1)
  })
})
