const { expect } = require('chai')

describe('GovernorTimelockController', () => {
  before(async function () {
    this.wallets = await ethers.getSigners()
    this.dev = this.wallets[0]
    this.governor = this.wallets[1]
  })

  beforeEach(async function () {
    const GovernorTimelockController = await ethers.getContractFactory('GovernorTimelockController', this.dev)
    this.governorTimelockController = await GovernorTimelockController.deploy([this.governor.address])
    await this.governorTimelockController.waitForDeployment()
  })
})
