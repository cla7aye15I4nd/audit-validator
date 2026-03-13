const { expect } = require('chai')
const { ethers } = require('hardhat')
const { TestDeployment } = require('../utils')

describe('VestingSchemeManager', () => {
  before(async function () {
    this.d = new TestDeployment(await ethers.getSigners())
    await this.d.deploy()
  })

  beforeEach(async function () {})

  it('should return default vesting scheme', async function () {
    const unstakeScheme = await this.d.vestingSchemeManager.getVestingScheme(1)
    expect(unstakeScheme[0]).to.deep.equal([100])
    expect(unstakeScheme[1]).to.deep.equal([180])

    const serviceFeeScheme = await this.d.vestingSchemeManager.getVestingScheme(2)
    expect(serviceFeeScheme[0]).to.deep.equal([100])
    expect(serviceFeeScheme[1]).to.deep.equal([45])

    const rewardScheme = await this.d.vestingSchemeManager.getVestingScheme(3)
    expect(rewardScheme[0]).to.deep.equal([30, 30, 40])
    expect(rewardScheme[1]).to.deep.equal([0, 90, 180])
  })

  it('should set/get vesting scheme', async function () {
    const percentages = [10, 20, 30, 40]
    const dates = [0, 30, 90, 120]
    await expect(
      this.d.vestingSchemeManager.connect(this.d.user).setVestingScheme(0, percentages, dates),
    ).to.be.revertedWith('Configuration admin only')
    await expect(
      this.d.vestingSchemeManager.connect(this.d.configurator).setVestingScheme(0, percentages, dates),
    ).to.emit(this.d.vestingSchemeManager, 'VestingSchemeSet')
    const scheme = await this.d.vestingSchemeManager.getVestingScheme(0)
    expect(scheme[0]).to.deep.equal(percentages)
    expect(scheme[1]).to.deep.equal(dates)
  })

  it('should return vesting amounts', async function () {
    const scheme = await this.d.vestingSchemeManager.getVestingScheme(0)
    const amounts = await this.d.vestingSchemeManager.getVestingAmount(0, 1000)
    const today = await this.d.vestingSchemeManager.today()
    expect(amounts[0]).to.deep.equal(scheme[0].map((p) => (p * 1000n) / 100n))
    expect(amounts[1]).to.deep.equal(scheme[1].map((d) => d + today))
  })
})
