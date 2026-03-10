const { expect } = require('chai')
const { ethers } = require('hardhat')
const { TestDeployment } = require('../utils')

describe('VestingConfigurator', () => {
  before(async function () {
    this.d = new TestDeployment(await ethers.getSigners())
    await this.d.deploy()
  })

  beforeEach(async function () {})

  it('should set/get minimum claim amount', async function () {
    expect(await this.d.vestingConfigurator.getMinimumClaimAmount()).to.be.equal(0) // Default value
    await expect(this.d.vestingConfigurator.connect(this.d.user).setMinimumClaimAmount(40)).to.be.revertedWith(
      'Configuration admin only',
    )
    await expect(this.d.vestingConfigurator.connect(this.d.configurator).setMinimumClaimAmount(40)).to.emit(
      this.d.vestingConfigurator,
      'MinimumClaimAmountChanged',
    )
    expect(await this.d.vestingConfigurator.getMinimumClaimAmount()).to.be.equal(40)
  })
})
