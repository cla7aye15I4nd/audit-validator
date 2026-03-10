const { expect } = require('chai')
const { ethers } = require('hardhat')
const { TestDeployment } = require('../utils')
const { time } = require('@nomicfoundation/hardhat-network-helpers')

describe('RewardHandler', () => {
  const ONE_DAY = 86400000
  const epochs = [Date.now() + ONE_DAY, Date.now() + 2 * ONE_DAY, Date.now() + 3 * ONE_DAY].map((e) =>
    Math.floor(e / 1000),
  )

  const amounts = [ethers.parseEther('1'), ethers.parseEther('2'), ethers.parseEther('3')]

  before(async function () {
    this.d = new TestDeployment(await ethers.getSigners())
    await this.d.deploy()
  })

  beforeEach(async function () {})

  const setEmissionSchedule = async function (d, epochs, amounts) {
    const vdata = await d.getVerifiableData(
      d.backend.address,
      'REWARD_HANDLER_ID',
      'SET_REWARD_EMISSION_SCHEDULE',
      ethers.AbiCoder.defaultAbiCoder().encode(['uint256[]', 'uint256[]'], [epochs, amounts]),
    )

    await d.rewardHandler.connect(d.backend).setEmissionSchedule(vdata)
  }

  it('should set emission schedule', async function () {
    await setEmissionSchedule(this.d, epochs, amounts)

    for (let i = 0; i < epochs.length; i++) {
      expect(await this.d.rewardStorage.getEmissionScheduleAt(epochs[i])).to.be.equal(amounts[i])
    }
  })

  it('should settle reward', async function () {
    const tid = 1
    const gid = 1
    const amount = ethers.parseEther('1')
    const slashAmount = ethers.parseEther('0.1')

    await this.d.createGroup(tid, gid)

    await setEmissionSchedule(this.d, epochs, amounts)

    await time.increaseTo(epochs[0])

    const vdata = await this.d.getVerifiableData(
      this.d.backend.address,
      'REWARD_HANDLER_ID',
      'SETTLE_REWARD',
      ethers.AbiCoder.defaultAbiCoder().encode(
        ['uint256[]', 'uint256[]', 'uint256[]', 'uint256[]'],
        [[tid], [gid], [amount], [slashAmount]],
      ),
    )

    await this.d.token.transfer(this.d.rewardFundHolder.target, ethers.parseEther('1000'))

    const commissionPercentage = await this.d.rewardConfigurator.getRewardCommissionPercentage()
    const commissionAmount = (amount * commissionPercentage) / 100n

    const balanceBefore = {
      rewardCommissionReceiver: await this.d.token.balanceOf(this.d.rewardCommissionReceiver.target),
      vestingFundHolder: await this.d.token.balanceOf(this.d.vestingFundHolder.target),
      slashDeductionReceiver: await this.d.token.balanceOf(this.d.slashDeductionReceiver.target),
    }

    await expect(this.d.rewardHandler.connect(this.d.backend).settleReward(vdata)).to.emit(
      this.d.rewardHandler,
      'RewardSettled',
    )

    const balanceAfter = {
      rewardCommissionReceiver: await this.d.token.balanceOf(this.d.rewardCommissionReceiver.target),
      vestingFundHolder: await this.d.token.balanceOf(this.d.vestingFundHolder.target),
      slashDeductionReceiver: await this.d.token.balanceOf(this.d.slashDeductionReceiver.target),
    }

    expect(balanceAfter.rewardCommissionReceiver - balanceBefore.rewardCommissionReceiver).to.be.equal(commissionAmount)
    expect(balanceAfter.slashDeductionReceiver - balanceBefore.slashDeductionReceiver).to.be.equal(slashAmount)
    expect(balanceAfter.vestingFundHolder - balanceBefore.vestingFundHolder).to.be.equal(
      amount - slashAmount - commissionAmount,
    )
  })

  it('should initial settle reward', async function () {
    const tid = 2
    const gid = 3
    const amounts = [ethers.parseEther('10'), ethers.parseEther('20'), ethers.parseEther('30')]
    const vestingDays = [1000, 1001, 1002]
    await this.d.createGroup(tid, gid)

    const vdata = await this.d.getVerifiableData(
      this.d.backend.address,
      'REWARD_HANDLER_ID',
      'INITIAL_SETTLE_REWARD',
      ethers.AbiCoder.defaultAbiCoder().encode(
        ['uint256[]', 'uint256[]', '(uint256[],uint32[])[]'],
        [[tid], [gid], [[amounts, vestingDays]]],
      ),
      '0x',
      true,
    )

    await expect(this.d.rewardHandler.connect(this.d.backend).initialSettleReward(vdata)).to.emit(
      this.d.rewardHandler,
      'RewardInitialSettled',
    )
  })
})
