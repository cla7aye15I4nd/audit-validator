const { expect } = require('chai')
const { TestDeployment } = require('../utils')

describe('SlashConfigurator', function () {
  before(async function () {
    this.d = new TestDeployment(await ethers.getSigners())
    await this.d.deploy()
  })

  describe('getTicketExpireTime', function () {
    it('should return the default ticket expire time', async function () {
      expect(await this.d.slashConfigurator.getTicketExpireTime()).to.equal(30 * 24 * 60 * 60) // 30 days in seconds
    })
  })

  describe('setTicketExpireTime', function () {
    it('should allow the configuration admin to set the ticket expire time', async function () {
      await this.d.slashConfigurator.connect(this.d.configurator).setTicketExpireTime(60 * 24 * 60 * 60) // 60 days in seconds
      expect(await this.d.slashConfigurator.getTicketExpireTime()).to.equal(60 * 24 * 60 * 60)
    })

    it('should emit TicketExpireTimeSet event', async function () {
      await expect(this.d.slashConfigurator.connect(this.d.configurator).setTicketExpireTime(60 * 24 * 60 * 60))
        .to.emit(this.d.slashConfigurator, 'TicketExpireTimeSet')
        .withArgs(60 * 24 * 60 * 60)
    })

    it('should revert if a non-admin tries to set the ticket expire time', async function () {
      await expect(
        this.d.slashConfigurator.connect(this.d.dev).setTicketExpireTime(60 * 24 * 60 * 60),
      ).to.be.revertedWith('Configuration admin only')
    })
  })
})
