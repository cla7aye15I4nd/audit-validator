const { expect } = require('chai')
const { ethers } = require('hardhat')

describe('RequestVerifier', () => {
  const vdata = {
    nonce: 0,
    deadline: 0,
    lastUpdateBlock: 0,
    version: 0,
    sender: ethers.ZeroAddress,
    target: ethers.ZeroAddress,
    method: '0x00000000',
    params: '0x',
    payloads: '0x',
    proof: '0x',
  }

  const validator1 = ethers.Wallet.fromPhrase(
    'person mango drill weapon color online lunar require expire element oval wisdom',
  )
  const validator2 = ethers.Wallet.fromPhrase(
    'coffee timber jewel guard position address uphold vivid goose else syrup furnace',
  )
  const initiator1 = ethers.Wallet.fromPhrase(
    'advance cinnamon rifle mad dilemma bounce orchard opera peace couple hobby ramp',
  )
  const initiator2 = ethers.Wallet.fromPhrase('doctor cup move hurt clutch onion wild total dutch shy top digital')

  before(async function () {
    this.wallets = await ethers.getSigners()
    this.dev = this.wallets[0]
    this.governor = this.wallets[1]
    this.migrator = this.wallets[2]
    this.user = this.wallets[3]

    const ACLManager = await ethers.getContractFactory('ACLManager', this.dev)
    this.acl = await ACLManager.deploy(this.governor.address)
    await this.acl.waitForDeployment()
    await this.acl.connect(this.governor).addMigrator(this.migrator.address)
    await this.acl.connect(this.governor).addValidator(validator1.address)
    await this.acl.connect(this.governor).addValidator(validator2.address)
    await this.acl.connect(this.governor).addInitSettlementOperator(initiator1.address)
    await this.acl.connect(this.governor).addInitSettlementOperator(initiator2.address)

    const AethirToken = await ethers.getContractFactory('AethirToken', this.dev)
    this.token = await AethirToken.deploy()
    await this.token.waitForDeployment()

    const Registry = await ethers.getContractFactory('Registry', this.dev)
    this.registry = await Registry.deploy(this.acl.target, this.token.target)
    await this.registry.waitForDeployment()

    const UserStorage = await ethers.getContractFactory('UserStorage', this.dev)
    this.userStorage = await UserStorage.deploy(this.registry.target)
    await this.userStorage.waitForDeployment()

    const EmergencySwitch = await ethers.getContractFactory('EmergencySwitch', this.dev)
    this.emergencySwitch = await EmergencySwitch.deploy(this.registry.target)
    await this.emergencySwitch.waitForDeployment()

    const BlackListManager = await ethers.getContractFactory('BlackListManager', this.dev)
    this.blackListManager = await BlackListManager.deploy(this.registry.target)
    await this.blackListManager.waitForDeployment()

    const TierController = await ethers.getContractFactory('TierController', this.dev)
    this.tierController = await TierController.deploy(this.registry.target)
    await this.tierController.waitForDeployment()

    const RequestVerifier = await ethers.getContractFactory('RequestVerifier', this.dev)
    this.requestVerifier = await RequestVerifier.deploy(this.registry.target)
    await this.requestVerifier.waitForDeployment()

    await this.registry.initialize([], [])
  })

  beforeEach(async function () {})

  it('should return hash', async function () {
    const coder = ethers.AbiCoder.defaultAbiCoder()
    const network = await ethers.provider.getNetwork()

    const msg = coder.encode(
      ['uint256', 'uint256', 'uint256', 'uint256', 'uint256', 'address', 'address', 'bytes', 'bytes'],
      [
        network.chainId,
        vdata.nonce,
        vdata.deadline,
        vdata.lastUpdateBlock,
        vdata.version,
        vdata.sender,
        vdata.target,
        vdata.params,
        vdata.payloads,
      ],
    )
    const hash = ethers.keccak256(msg)
    expect(await this.requestVerifier.getHash(vdata)).to.equal(hash)
  })

  it('should check validator signatures', async function () {
    const hash = ethers.toBeArray(await this.requestVerifier.getHash(vdata))
    let signatures = '0x'
    for (let signer of [validator1, validator2]) {
      signatures += (await signer.signMessage(hash)).substring(2)
    }
    await expect(this.requestVerifier.checkValidatorSignatures(hash, signatures)).to.not.be.reverted
  })

  it('should check initiator signatures', async function () {
    const hash = ethers.toBeArray(await this.requestVerifier.getHash(vdata))
    let signatures = '0x'
    for (let signer of [initiator1, initiator2]) {
      signatures += (await signer.signMessage(hash)).substring(2)
    }
    await expect(this.requestVerifier.checkInitiatorSignatures(hash, signatures)).to.not.be.reverted
  })

  it('should check VerifiableData target', async function () {
    await expect(this.requestVerifier.verify(vdata, ethers.ZeroAddress, '0x00000001')).to.be.revertedWith(
      'TargetMismatch',
    )
    await expect(this.requestVerifier.verifyInitiator(vdata, '0x00000001')).to.be.revertedWith('TargetMismatch')
  })

  it('should check VerifiableData method', async function () {
    const mdata = { ...vdata, target: this.dev.address }
    await expect(this.requestVerifier.verify(mdata, ethers.ZeroAddress, '0x00000001')).to.be.revertedWith(
      'MethodMismatch',
    )
    await expect(this.requestVerifier.verifyInitiator(mdata, '0x00000001')).to.be.revertedWith('MethodMismatch')
  })

  it('should check VerifiableData version', async function () {
    const mdata = { ...vdata, target: this.dev.address, method: '0x00000001' }
    await expect(this.requestVerifier.verify(mdata, ethers.ZeroAddress, '0x00000001')).to.be.revertedWith(
      'InvalidVersion',
    )
    await expect(this.requestVerifier.verifyInitiator(mdata, '0x00000001')).to.be.revertedWith('InvalidVersion')
  })

  it('should check VerifiableData deadline', async function () {
    const mdata = { ...vdata, target: this.dev.address, method: '0x00000001', version: 1 }
    await expect(this.requestVerifier.verify(mdata, ethers.ZeroAddress, '0x00000001')).to.be.revertedWith('DataExpired')
    await expect(this.requestVerifier.verifyInitiator(mdata, '0x00000001')).to.be.revertedWith('DataExpired')
  })

  it('should check VerifiableData nonce', async function () {
    const mdata = { ...vdata, target: this.dev.address, method: '0x00000001', version: 1, deadline: Date.now() + 10000 }
    await expect(this.requestVerifier.verify(mdata, ethers.ZeroAddress, '0x00000001')).to.be.revertedWith('NonceTooLow')
  })

  it('should check VerifiableData signatures', async function () {
    const mdata = {
      ...vdata,
      target: this.dev.address,
      sender: this.dev.address,
      method: '0x00000001',
      version: 1,
      deadline: Date.now() + 10000,
      nonce: 1,
    }
    await expect(this.requestVerifier.verify(mdata, this.dev.address, '0x00000001')).to.be.revertedWith(
      'Invalid signature len',
    )
    await expect(this.requestVerifier.verifyInitiator(mdata, '0x00000001')).to.be.revertedWith('Invalid signature len')
  })

  it('should update UserData on success', async function () {
    let mdata = {
      ...vdata,
      target: this.dev.address,
      method: '0x00000001',
      version: 1,
      deadline: Date.now() + 10000,
      nonce: 1,
      sender: this.user.address,
    }
    const hash = ethers.toBeArray(await this.requestVerifier.getHash(mdata))
    mdata.proof = '0x'
    for (let signer of [validator1, validator2]) {
      mdata.proof += (await signer.signMessage(hash)).substring(2)
    }
    await expect(this.requestVerifier.verify(mdata, this.user.address, '0x00000001')).to.not.be.reverted
    expect((await this.userStorage.getUserData(this.user.address)).nonce).to.equal(1)
  })
})
