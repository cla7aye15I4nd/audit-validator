const { expect } = require('chai')

describe('StakeHandler', () => {
  before(async function () {
    this.wallets = await ethers.getSigners()
    this.dev = this.wallets[0]
  })

  beforeEach(async function () {})

  it('should...', async function () {})
})
