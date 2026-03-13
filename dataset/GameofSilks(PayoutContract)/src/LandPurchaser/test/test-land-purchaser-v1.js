const { expect } = require('chai');
const { ethers, waffle } = require('hardhat');
const {BigNumber} = require("ethers");

describe('LandPurchaser', function () {
    let landDummy;

    let index;

    let landPurchaser;
    let accounts;

    let owner;
    let addr1;
    let addr2;
    let addr3;
    let addr4
    let addrs;

    let LAND_PURCHASE_ADMIN;

    const _saleId = 'default';
    const _price = 1000;
    const _paused = false;
    const _maxPerTx = 0;
    const _expirationInSeconds = 300;
    const _valid = true;

    const getExecutionTime = ({numSecondsToSubtract = 0} = {}) => {
        return Math.floor((Date.now() - (numSecondsToSubtract*1000)) / 1000);
    }

    const setSale = async ({
                               saleId = 'sale1',
                               price = 2000,
                               paused = false,
                               maxPerTx = 2,
                               expirationTimeInSeconds = 300,
                               valid = true
    } = {}) => {
        await landPurchaser.setSale(saleId, price, paused, maxPerTx, expirationTimeInSeconds, valid);
        return {
            saleId, price, paused, maxPerTx, expirationTimeInSeconds, valid
        }
    };

    const setupIndex = async () => {
        const LandDummyFactory = await ethers.getContractFactory("LandDummy");
        landDummy = await LandDummyFactory.deploy();

        const IndexFactory = await ethers.getContractFactory("Index");
        index = await IndexFactory.deploy(["Land"], [landDummy.address]);

        return {
            indexAddress: index.address,
            landAddress: landDummy.address
        }
    }

    beforeEach(async function () {

        [owner, addr1, addr2, addr3, addr4, ...addrs] = await ethers.getSigners();

        const setupResults = await setupIndex();

        const LandPurchaserFactory = await ethers.getContractFactory('LandPurchaserV1');

        // console.log(`price in eth: ${ethers.utils.formatEther(BigNumber.from(_price))}`)
        landPurchaser = await LandPurchaserFactory.deploy(
            setupResults.indexAddress, _saleId, _price, _paused, _maxPerTx, _expirationInSeconds
        );
        await landPurchaser.deployed();

        LAND_PURCHASE_ADMIN = await landPurchaser.LAND_PURCHASE_ADMIN();
    });

    it('Should set the right admin', async function () {
        expect(await landPurchaser.hasRole(LAND_PURCHASE_ADMIN, owner.address)).to.equal(true);
    });

    it('Should pause', async function () {
        await landPurchaser.pause()
        expect(await landPurchaser.paused()).to.equal(true);
    });

    it('Should unpause', async function () {
        await landPurchaser.pause();
        await landPurchaser.unpause()
        expect(await landPurchaser.paused()).to.equal(false);
    });

    it('Should be able to set a sale', async function () {
        const testSale = await setSale();
        const sale = await landPurchaser.getSale(testSale.saleId);
        expect(sale.price).to.equal(testSale.price);
        expect(sale.paused).to.equal(testSale.paused);
        expect(sale.maxPerTx).to.equal(testSale.maxPerTx);
        expect(sale.valid).to.equal(testSale.valid);
    });

    it('Should be able to purchase land', async function () {
        const _referenceId = 'ref1';
        const _quantity = 2;

        const sale = await landPurchaser.getSale(_saleId);
        const value = sale.price.mul(_quantity).toNumber();
        const pendingTransaction = await landPurchaser.connect(addr1).purchase(_saleId, _referenceId, _quantity, getExecutionTime(), { value });
        const transaction = await pendingTransaction.wait();
        const receiptIdHex = transaction.events.find(e => e.event === "Purchased").data;
        const receiptId = ethers.BigNumber.from(receiptIdHex).toNumber();

        const receipt = await landPurchaser.getReceipt(receiptId);
        expect(receipt.buyer).to.equal(addr1.address);
        expect(receipt.saleId).to.equal(_saleId);
        expect(receipt.quantity).to.equal(_quantity);
        expect(receipt.pricePer).to.equal(sale.price);
        expect(receipt.referenceId).to.equal(_referenceId);
        expect(receipt.total).to.equal(value);

        const numTokens = await landDummy.balanceOf(addr1.address);
        expect(numTokens).to.equal(_quantity);
    });

    it('Should revert because contract paused', async function () {
        await landPurchaser.pause();
        await expect(
            landPurchaser.connect(addr1).purchase(
                _saleId, 'ref1', 1, getExecutionTime(), {value: _price}
            )
        ).to.revertedWith('Pausable: paused');
    });

    it('Should revert because sale paused', async function () {
        const testSale = await setSale({paused: true});
        await expect(
            landPurchaser.connect(addr1).purchase(
                testSale.saleId, 'ref1', 1, getExecutionTime(), {value: _price}
            )
        ).to.revertedWith('NOT_VALID_OR_PAUSED');
    });

    it('Should revert because purchase expired', async function () {
        const testSale = await setSale({expirationTimeInSeconds: 5});
        await expect(
            landPurchaser.connect(addr1).purchase(
                testSale.saleId, 'ref1', 1, getExecutionTime({numSecondsToSubtract: 10}), {value: _price}
            )
        ).to.revertedWith('EXPIRED_PURCHASE');
    });

    it('Should revert because sale not valid', async function () {
        await expect(
            landPurchaser.connect(addr1).purchase(
                'invalidSale', 'ref1', 1, getExecutionTime(), {value: _price}
            )
        ).to.revertedWith('NOT_VALID_OR_PAUSED');
    });

    it('Should revert because invalid amount of ETH sent', async function () {
        await expect(
            landPurchaser.connect(addr1).purchase(
                "default", 'ref1', 1, getExecutionTime(), {value: _price * 2    }
            )
        ).to.revertedWith('INV_ETH_TOTAL');
    });

    it('Should revert because invalid quantity of ETH sent', async function () {
        await expect(
            landPurchaser.connect(addr1).purchase(
                "default", 'ref1', 2, getExecutionTime(), {value: 1000}
            )
        ).to.revertedWith('INV_ETH_TOTAL');
    });

    it('Should update index contract address', async function () {
        const setupResults = await setupIndex();
        const transaction = await landPurchaser.setIndexContractAddress(setupResults.indexAddress);
        await transaction.wait();

        const purchaseTransaction = await landPurchaser.connect(addr1).purchase(_saleId, 'ref1', 1, getExecutionTime(), { value: _price });
        await purchaseTransaction.wait();

        const landDummy = await ethers.getContractAt("LandDummy", setupResults.landAddress);
        const numTokens = await landDummy.balanceOf(addr1.address);

        expect(numTokens).to.equal(1);
    });

    it('Should withdraw funds from contract', async function () {
        const originalBalance = await ethers.provider.getBalance(addr2.address);
        const purchaseTransaction = await landPurchaser.connect(addr1).purchase(_saleId, 'ref1', 1, getExecutionTime(), { value: _price });
        await purchaseTransaction.wait();
        const contractBalance = await ethers.provider.getBalance(landPurchaser.address)
        const tx = await landPurchaser.withdrawFunds(addr2.address);
        await tx.wait();
        const postWithdrawContractBalance = await ethers.provider.getBalance(landPurchaser.address);
        expect(postWithdrawContractBalance).to.be.equal(0);
        const postWithdrawToBalance = await ethers.provider.getBalance(addr2.address);
        const transferredAmount = postWithdrawToBalance.sub(originalBalance);
        expect(transferredAmount).to.be.equal(contractBalance);
    })
});
