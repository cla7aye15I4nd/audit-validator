const { expect } = require('chai')
const { ethers } = require('hardhat')
const { TestDeployment } = require('../utils')

describe('AccountHandler', () => {
  before(async function () {
    this.d = new TestDeployment(await ethers.getSigners())
    await this.d.deploy()
  })

  beforeEach(async function () {})

  it('should create account', async function () {
    const tid = 1
    const delegator = ethers.ZeroAddress
    const feeReceiver = ethers.ZeroAddress
    const rewardReceiver = ethers.ZeroAddress
    const delegatorSetFeeReceiver = false
    const delegatorSetRewardReceiver = false

    const wallet = this.d.user2.address
    const vdata = await this.d.getVerifiableData(
      this.d.backend.address,
      'ACCOUNT_HANDLER_ID',
      'CREATE_ACCOUNT',
      ethers.AbiCoder.defaultAbiCoder().encode(
        ['address', 'uint256', '(uint256,uint256,address,address,address,bool,bool)'],
        [
          wallet,
          tid,
          [0, 0, delegator, feeReceiver, rewardReceiver, delegatorSetFeeReceiver, delegatorSetRewardReceiver],
        ],
      ),
    )
    expect(await this.d.accountStorage.getTid(wallet)).to.be.equal(0n)
    expect(await this.d.accountStorage.getWallet(tid)).to.be.equal(ethers.ZeroAddress)
    await expect(this.d.accountHandler.connect(this.d.backend).createAccount(vdata)).to.emit(
      this.d.accountHandler,
      'AccountCreated',
    )
    expect(await this.d.accountStorage.getTid(wallet)).to.be.equal(tid)
    expect(await this.d.accountStorage.getWallet(tid)).to.be.equal(wallet)
  })

  it('should rebind account', async function () {
    const tid = 1
    const oldWallet = this.d.user2.address
    const newWallet = this.d.user.address
    const messageHash = ethers.toBeArray(
      ethers.keccak256(
        ethers.AbiCoder.defaultAbiCoder().encode(
          ['uint256', 'address', 'uint64', 'address', 'address', 'uint256'],
          [
            (await ethers.provider.getNetwork()).chainId, // chainId
            await this.d.getServiceAddress('ACCOUNT_HANDLER_ID'), // contract address
            (await this.d.getUserNonce(this.d.user.address)) + 1n, // nonce
            oldWallet,
            newWallet,
            tid,
          ],
        ),
      ),
    )
    const oldWalletSig = await this.d.user2.signMessage(messageHash)
    const vdata = await this.d.getVerifiableData(
      this.d.user.address,
      'ACCOUNT_HANDLER_ID',
      'REBIND_WALLET',
      ethers.AbiCoder.defaultAbiCoder().encode(['address', 'uint256', 'bytes'], [newWallet, tid, oldWalletSig]),
    )
    expect(await this.d.accountStorage.getTid(oldWallet)).to.be.equal(tid)
    expect(await this.d.accountStorage.getWallet(tid)).to.be.equal(oldWallet)
    await expect(this.d.accountHandler.connect(this.d.user).rebindWallet(vdata)).to.emit(
      this.d.accountHandler,
      'WalletRebound',
    )
    expect(await this.d.accountStorage.getTid(oldWallet)).to.be.equal(0)
    expect(await this.d.accountStorage.getTid(newWallet)).to.be.equal(tid)
    expect(await this.d.accountStorage.getWallet(tid)).to.be.equal(newWallet)
  })

  it('should create account with initial group', async function () {
    const tid = 2
    const gid = 3
    const delegator = this.d.delegator.address
    const feeReceiver = this.d.delegator.address
    const rewardReceiver = this.d.delegator.address
    const delegatorSetFeeReceiver = false
    const delegatorSetRewardReceiver = false

    const wallet = this.d.user2.address
    const vdata = await this.d.getVerifiableData(
      this.d.backend.address,
      'ACCOUNT_HANDLER_ID',
      'CREATE_ACCOUNT',
      ethers.AbiCoder.defaultAbiCoder().encode(
        ['address', 'uint256', '(uint256,uint256,address,address,address,bool,bool)'],
        [
          wallet,
          tid,
          [tid, gid, delegator, feeReceiver, rewardReceiver, delegatorSetFeeReceiver, delegatorSetRewardReceiver],
        ],
      ),
    )
    expect(await this.d.accountStorage.getTid(wallet)).to.be.equal(0n)
    expect(await this.d.accountStorage.getWallet(tid)).to.be.equal(ethers.ZeroAddress)
    await expect(this.d.accountHandler.connect(this.d.backend).createAccount(vdata)).to.emit(
      this.d.accountHandler,
      'AccountCreated',
    )
    expect(await this.d.accountStorage.getTid(wallet)).to.be.equal(tid)
    expect(await this.d.accountStorage.getWallet(tid)).to.be.equal(wallet)
  })

  it('should create group', async function () {
    const tid = 1
    const gid = 1
    const delegator = ethers.ZeroAddress
    const feeReceiver = ethers.ZeroAddress
    const rewardReceiver = ethers.ZeroAddress
    const delegatorSetFeeReceiver = false
    const delegatorSetRewardReceiver = false
    const vdata = await this.d.getVerifiableData(
      this.d.backend.address,
      'ACCOUNT_HANDLER_ID',
      'CREATE_GROUP',
      ethers.AbiCoder.defaultAbiCoder().encode(
        ['(uint256,uint256,address,address,address,bool,bool)'],
        [[tid, gid, delegator, feeReceiver, rewardReceiver, delegatorSetFeeReceiver, delegatorSetRewardReceiver]],
      ),
    )
    await expect(this.d.accountHandler.getGroup(1, 1)).to.be.revertedWith('Group not found')
    await expect(this.d.accountHandler.connect(this.d.backend).createGroup(vdata)).to.emit(
      this.d.accountHandler,
      'GroupCreated',
    )
    await expect(this.d.accountHandler.getGroup(1, 1)).to.not.be.reverted
  })

  it('should check for group exist', async function () {
    const tid = 1
    const gid = 1
    const delegator = ethers.ZeroAddress
    const feeReceiver = ethers.ZeroAddress
    const rewardReceiver = ethers.ZeroAddress
    const delegatorSetFeeReceiver = false
    const delegatorSetRewardReceiver = false

    await expect(
      this.d.accountHandler
        .connect(this.d.backend)
        .createGroup(
          await this.d.getVerifiableData(
            this.d.backend.address,
            'ACCOUNT_HANDLER_ID',
            'CREATE_GROUP',
            ethers.AbiCoder.defaultAbiCoder().encode(
              ['(uint256,uint256,address,address,address,bool,bool)'],
              [[tid, gid, delegator, feeReceiver, rewardReceiver, delegatorSetFeeReceiver, delegatorSetRewardReceiver]],
            ),
          ),
        ),
    ).to.be.revertedWith('Group already exists')
  })

  it('should check valid tid and gid', async function () {
    const tid = 1
    const gid = 2
    const delegator = ethers.ZeroAddress
    const feeReceiver = ethers.ZeroAddress
    const rewardReceiver = ethers.ZeroAddress
    const delegatorSetFeeReceiver = false
    const delegatorSetRewardReceiver = false

    // Invalid gid
    await expect(
      this.d.accountHandler
        .connect(this.d.backend)
        .createGroup(
          await this.d.getVerifiableData(
            this.d.backend.address,
            'ACCOUNT_HANDLER_ID',
            'CREATE_GROUP',
            ethers.AbiCoder.defaultAbiCoder().encode(
              ['(uint256,uint256,address,address,address,bool,bool)'],
              [[tid, 0, delegator, feeReceiver, rewardReceiver, delegatorSetFeeReceiver, delegatorSetRewardReceiver]],
            ),
          ),
        ),
    ).to.be.revertedWith('Invalid gid')
    // Invalid tid
    await expect(
      this.d.accountHandler
        .connect(this.d.backend)
        .createGroup(
          await this.d.getVerifiableData(
            this.d.backend.address,
            'ACCOUNT_HANDLER_ID',
            'CREATE_GROUP',
            ethers.AbiCoder.defaultAbiCoder().encode(
              ['(uint256,uint256,address,address,address,bool,bool)'],
              [[0, gid, delegator, feeReceiver, rewardReceiver, delegatorSetFeeReceiver, delegatorSetRewardReceiver]],
            ),
          ),
        ),
    ).to.be.revertedWith('Invalid tid')
  })

  it('should check for logical conflict when creating group', async function () {
    const tid = 1
    const gid = 2
    const delegator = this.d.delegator.address
    const receiver = this.d.user2.address

    // Group configuration specifies that only the Delegator can set receivers, but receiver parameters are also provided
    await expect(
      this.d.accountHandler
        .connect(this.d.backend)
        .createGroup(
          await this.d.getVerifiableData(
            this.d.backend.address,
            'ACCOUNT_HANDLER_ID',
            'CREATE_GROUP',
            ethers.AbiCoder.defaultAbiCoder().encode(
              ['(uint256,uint256,address,address,address,bool,bool)'],
              [[tid, gid, delegator, receiver, ethers.ZeroAddress, true, true]],
            ),
          ),
        ),
    ).to.be.revertedWith('Logical conflict')

    await expect(
      this.d.accountHandler
        .connect(this.d.backend)
        .createGroup(
          await this.d.getVerifiableData(
            this.d.backend.address,
            'ACCOUNT_HANDLER_ID',
            'CREATE_GROUP',
            ethers.AbiCoder.defaultAbiCoder().encode(
              ['(uint256,uint256,address,address,address,bool,bool)'],
              [[tid, gid, delegator, ethers.ZeroAddress, receiver, true, true]],
            ),
          ),
        ),
    ).to.be.revertedWith('Logical conflict')
  })

  it('should check for delegator if enable delegatorSet(Fee/Reward)Receiver', async function () {
    const tid = 1
    const gid = 2
    const delegator = ethers.ZeroAddress
    const receiver = this.d.user2.address

    // Delegator not set but enable delegatorSetFeeReceiver or delegatorSetRewardReceiver
    await expect(
      this.d.accountHandler
        .connect(this.d.backend)
        .createGroup(
          await this.d.getVerifiableData(
            this.d.backend.address,
            'ACCOUNT_HANDLER_ID',
            'CREATE_GROUP',
            ethers.AbiCoder.defaultAbiCoder().encode(
              ['(uint256,uint256,address,address,address,bool,bool)'],
              [[tid, gid, delegator, receiver, receiver, true, false]],
            ),
          ),
        ),
    ).to.be.revertedWith('Delegator not set')

    await expect(
      this.d.accountHandler
        .connect(this.d.backend)
        .createGroup(
          await this.d.getVerifiableData(
            this.d.backend.address,
            'ACCOUNT_HANDLER_ID',
            'CREATE_GROUP',
            ethers.AbiCoder.defaultAbiCoder().encode(
              ['(uint256,uint256,address,address,address,bool,bool)'],
              [[tid, gid, delegator, receiver, receiver, false, true]],
            ),
          ),
        ),
    ).to.be.revertedWith('Delegator not set')
  })

  it('should assign delegator', async function () {
    const vdata = await this.d.getVerifiableData(
      this.d.user.address,
      'ACCOUNT_HANDLER_ID',
      'ASSIGN_DELEGATOR',
      ethers.AbiCoder.defaultAbiCoder().encode(['uint256', 'uint256', 'address'], [1, 1, this.d.delegator.address]),
    )
    await expect(this.d.accountHandler.connect(this.d.user).assignDelegator(vdata)).to.emit(
      this.d.accountHandler,
      'DelegatorAssigned',
    )
    expect((await this.d.accountHandler.getGroup(1, 1)).delegator).to.be.equal(this.d.delegator.address)
  })

  it('should update policy', async function () {
    await expect(this.d.accountHandler.connect(this.d.user).updatePolicy(1, 1, true, true)).to.emit(
      this.d.accountHandler,
      'PolicyUpdated',
    )
    expect((await this.d.accountHandler.getGroup(1, 1)).delegatorSetFeeReceiver).to.be.true
    expect((await this.d.accountHandler.getGroup(1, 1)).delegatorSetRewardReceiver).to.be.true
  })

  it('should revoke delegator', async function () {
    const vdata = await this.d.getVerifiableData(
      this.d.user.address,
      'ACCOUNT_HANDLER_ID',
      'REVOKE_DELEGATOR',
      ethers.AbiCoder.defaultAbiCoder().encode(['uint256', 'uint256'], [1, 1]),
    )
    await expect(this.d.accountHandler.connect(this.d.user).revokeDelegator(vdata)).to.emit(
      this.d.accountHandler,
      'DelegatorRevoked',
    )
    expect((await this.d.accountHandler.getGroup(1, 1)).delegator).to.be.equal(ethers.ZeroAddress)
  })

  it('should set service fee receiver', async function () {
    const vdata = await this.d.getVerifiableData(
      this.d.user.address,
      'ACCOUNT_HANDLER_ID',
      'SET_FEE_RECEIVER',
      ethers.AbiCoder.defaultAbiCoder().encode(['uint256', 'uint256', 'address'], [1, 1, this.d.delegator.address]),
    )
    await expect(this.d.accountHandler.connect(this.d.user).setFeeReceiver(vdata)).to.emit(
      this.d.accountHandler,
      'FeeReceiverSet',
    )
    expect((await this.d.accountHandler.getGroup(1, 1)).feeReceiver).to.be.equal(this.d.delegator.address)
  })

  it('should revoke service fee receiver', async function () {
    const vdata = await this.d.getVerifiableData(
      this.d.user.address,
      'ACCOUNT_HANDLER_ID',
      'REVOKE_FEE_RECEIVER',
      ethers.AbiCoder.defaultAbiCoder().encode(['uint256', 'uint256'], [1, 1]),
    )
    await expect(this.d.accountHandler.connect(this.d.user).revokeFeeReceiver(vdata)).to.emit(
      this.d.accountHandler,
      'FeeReceiverRevoked',
    )
    expect((await this.d.accountHandler.getGroup(1, 1)).feeReceiver).to.be.equal(ethers.ZeroAddress)
  })

  it('should set reward receiver', async function () {
    const vdata = await this.d.getVerifiableData(
      this.d.user.address,
      'ACCOUNT_HANDLER_ID',
      'SET_REWARD_RECEIVER',
      ethers.AbiCoder.defaultAbiCoder().encode(['uint256', 'uint256', 'address'], [1, 1, this.d.delegator.address]),
    )
    await expect(this.d.accountHandler.connect(this.d.user).setRewardReceiver(vdata)).to.emit(
      this.d.accountHandler,
      'RewardReceiverSet',
    )
    expect((await this.d.accountHandler.getGroup(1, 1)).rewardReceiver).to.be.equal(this.d.delegator.address)
  })

  it('should revoke reward receiver', async function () {
    const vdata = await this.d.getVerifiableData(
      this.d.user.address,
      'ACCOUNT_HANDLER_ID',
      'REVOKE_REWARD_RECEIVER',
      ethers.AbiCoder.defaultAbiCoder().encode(['uint256', 'uint256'], [1, 1]),
    )
    await expect(this.d.accountHandler.connect(this.d.user).revokeRewardReceiver(vdata)).to.emit(
      this.d.accountHandler,
      'RewardReceiverRevoked',
    )
    expect((await this.d.accountHandler.getGroup(1, 1)).rewardReceiver).to.be.equal(ethers.ZeroAddress)
  })
})
