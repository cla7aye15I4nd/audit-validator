const { expect } = require('chai')

describe('EmergencySwitch', function () {
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

    const TierController = await ethers.getContractFactory('TierController', this.dev)
    this.tierController = await TierController.deploy(this.registry.target)
    await this.tierController.waitForDeployment()

    // Deploy EmergencySwitch
    const EmergencySwitch = await ethers.getContractFactory('EmergencySwitch', this.dev)
    this.emergencySwitch = await EmergencySwitch.deploy(this.registry.target)
    await this.emergencySwitch.waitForDeployment()
  })

  describe('pause', function () {
    it('should allow the default admin to pause with a specific tier', async function () {
      await this.emergencySwitch.connect(this.governor).pause(2)
      expect(await this.emergencySwitch.pausedTier()).to.equal(2)
    })

    it('should emit TierChanged event when paused', async function () {
      await expect(this.emergencySwitch.connect(this.governor).pause(2))
        .to.emit(this.emergencySwitch, 'TierChanged')
        .withArgs(2)
    })

    it('should revert if non-admin tries to pause', async function () {
      await expect(this.emergencySwitch.connect(this.dev).pause(2)).to.be.revertedWith('Default admin only')
    })
  })

  describe('isAllowed', function () {
    it("should return true if the functionSelector's tier is greater than or equal to the current tier", async function () {
      await this.tierController.connect(this.governor).setFunctionTier('0x12345678', 3)
      await this.emergencySwitch.connect(this.governor).pause(2)
      expect(await this.emergencySwitch.isAllowed('0x12345678')).to.be.true
    })

    it("should return false if the functionSelector's tier is less than the current tier", async function () {
      await this.tierController.connect(this.governor).setFunctionTier('0x12345678', 1)
      await this.emergencySwitch.connect(this.governor).pause(2)
      expect(await this.emergencySwitch.isAllowed('0x12345678')).to.be.false
    })
  })
})
