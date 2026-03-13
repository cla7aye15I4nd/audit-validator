import { compile } from '@ton/blueprint';
import { Address, beginCell, Cell, SendMode, toNano } from '@ton/core';
import { getSecureRandomBytes, KeyPair, keyPairFromSeed } from '@ton/crypto';
import { Blockchain, SandboxContract, TreasuryContract } from '@ton/sandbox';
import '@ton/test-utils';
import { fail } from 'assert';
import { objectToString } from '../utils/objectToString';
import { IDOPool } from '../wrappers/IDOPool';
import { IDOPoolFactory } from '../wrappers/IDOPoolFactory';
import { jettonContentToCell, JettonMinter } from '../wrappers/JettonMinter';
import { JettonWallet } from '../wrappers/JettonWallet';
import { error } from '../wrappers/utils/errors';

describe('IDOPool', () => {
    let factoryCode: Cell;
    let poolCode: Cell;

    let blockchain: Blockchain;
    let factoryDeployer: SandboxContract<TreasuryContract>;
    let iDOPoolFactory: SandboxContract<IDOPoolFactory>;
    let buyMint: SandboxContract<JettonMinter>;
    let buyMintOwner: SandboxContract<TreasuryContract>;
    let sellMint: SandboxContract<JettonMinter>;
    let sellMintOwner: SandboxContract<TreasuryContract>;
    let buyer: SandboxContract<TreasuryContract>;
    let buyerBuyMintWallet: SandboxContract<JettonWallet>;
    let poolSellMintWallet: SandboxContract<JettonWallet>;
    let iDOPool: SandboxContract<IDOPool>;
    let signer: KeyPair;

    beforeAll(async () => {
        factoryCode = await compile('IDOPoolFactory');
        poolCode = await compile('IDOPool');

        blockchain = await Blockchain.create();

        iDOPoolFactory = blockchain.openContract(
            IDOPoolFactory.createFromConfig(
                {
                    poolCode,
                    zeroAddress: Address.parse('0QAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACkT'),
                },
                factoryCode,
            ),
        );

        factoryDeployer = await blockchain.treasury('deployer');

        const deployResult = await iDOPoolFactory.sendDeploy(factoryDeployer.getSender(), toNano('0.05'));

        expect(deployResult.transactions).toHaveTransaction({
            from: factoryDeployer.address,
            to: iDOPoolFactory.address,
            deploy: true,
            success: true,
        });

        //// create mints for buy and sell tokens
        buyMintOwner = await blockchain.treasury('buyMintOwner');
        sellMintOwner = await blockchain.treasury('sellMintOwner');

        buyMint = blockchain.openContract(
            JettonMinter.createFromConfig(
                {
                    admin: buyMintOwner.address,
                    content: jettonContentToCell({
                        type: 0,
                        uri: 'testURI',
                    }),
                    wallet_code: await compile('JettonWallet'),
                },
                await compile('JettonMinter'),
            ),
        );

        sellMint = blockchain.openContract(
            JettonMinter.createFromConfig(
                {
                    admin: sellMintOwner.address,
                    content: jettonContentToCell({
                        type: 0,
                        uri: 'testURI',
                    }),
                    wallet_code: await compile('JettonWallet'),
                },
                await compile('JettonMinter'),
            ),
        );

        //// get future address of pool
        const poolDeployer = await blockchain.treasury('poolDeployer');
        const sellTokenMintAddr = sellMint.address;
        const seed: Buffer = await getSecureRandomBytes(32); // Seed is always 32 bytes
        signer = keyPairFromSeed(seed);
        const signerAddr = BigInt(`0x${signer.publicKey.toString('hex')}`);
        const fundingWalletAddr = poolDeployer.address;
        const openTime = Math.floor(Date.now() / 1000);
        const duration = 1000;
        const buyCurrAddr = buyMint.address;
        const buyCurrDecimals = 9;
        const buyCurrRate = 1000000000n;

        const _iDOPoolAddress = await iDOPoolFactory.getNextPoolAddress(
            poolDeployer.address,
            signerAddr,
            sellTokenMintAddr,
            fundingWalletAddr,
            openTime,
            duration,
            buyCurrAddr,
            buyCurrDecimals,
            buyCurrRate,
        );

        //// mint tokens to required accounts
        sellMintOwner = await blockchain.treasury('sellMintOwner');
        buyMintOwner = await blockchain.treasury('buyMintOwner');
        buyer = await blockchain.treasury('buyer');

        await sellMint.sendDeploy(sellMintOwner.getSender(), toNano('100'));
        var { events } = await sellMint.sendMint(
            sellMintOwner.getSender(),
            _iDOPoolAddress,
            1000n,
            toNano('5'),
            toNano('10'),
        );
        var accountCreationEvent = events.filter((x) => x.type === 'account_created');
        expect(accountCreationEvent.length).toBeGreaterThan(0);
        poolSellMintWallet = blockchain.openContract(JettonWallet.createFromAddress(accountCreationEvent[0].account));

        var { events } = await buyMint.sendMint(
            buyMintOwner.getSender(),
            buyer.address,
            1000n,
            toNano('5'),
            toNano('10'),
        );
        var accountCreationEvent = events.filter((x) => x.type === 'account_created');
        expect(accountCreationEvent.length).toBeGreaterThan(0);
        // buyerBuyMintWallet = blockchain.openContract(JettonWallet.createFromAddress(accountCreationEvent[0].account));
        buyerBuyMintWallet = blockchain.openContract(
            JettonWallet.createFromAddress(await buyMint.getWalletAddress(buyer.address)),
        );

        const buyCurrTokenAccountAddr = await buyMint.getWalletAddress(_iDOPoolAddress);
        const sellTokenAccountAddr = await sellMint.getWalletAddress(_iDOPoolAddress);

        const createResult = await iDOPoolFactory.sendRegisterPool(poolDeployer.getSender(), {
            value: toNano('100'),
            queryID: 0,
            openTime,
            duration,
            fundingWalletAddr,
            sellTokenMintAddr,
            signerAddr,
            buyCurrAddr,
            buyCurrDecimals,
            buyCurrRate,
            buyCurrTokenAccountAddr,
            sellTokenAccountAddr,
        });

        const iDOPoolAddress = await iDOPoolFactory.getPoolAddress(0);
        if (!iDOPoolAddress) {
            console.log('IDO Pool Address came out null');
            return;
        }
        iDOPool = blockchain.openContract(IDOPool.createFromAddress(iDOPoolAddress));

        expect(createResult.transactions).toHaveTransaction({
            from: poolDeployer.address,
            to: iDOPoolFactory.address,
            success: true,
        });

        expect(createResult.transactions).toHaveTransaction({
            from: iDOPoolFactory.address,
            to: iDOPoolAddress,
            deploy: true,
            success: true,
        });
        expect(((await iDOPool.getOwner()) || '').toString()).toBe(poolDeployer.address.toString());
    }, 30000);

    it('should deploy pool', async () => {}, 30000); // done in beforeAll

    it('should read the value of PerBuyCurr Rate and Decimals', async () => {
        const poolDeployer = await blockchain.treasury('poolDeployer');
        const buyCurrency = buyMint.address;
        const decimal = 8;
        const rate = 2000000000n;

        const setPerBuyCurr = await iDOPool.sendSetPerBuyCurrency(poolDeployer.getSender(), {
            value: toNano('100'),
            queryID: 0,
            buyCurrency,
            buyCurrencyDecimals: decimal,
            buyCurrencyRate: rate,
            buyCurrencyTokenAccountAddr: await buyMint.getWalletAddress(iDOPool.address),
            buyCurrencyTokenAccountBalance: 0n,
        });

        expect(setPerBuyCurr.transactions).toHaveTransaction({
            from: poolDeployer.address,
            to: iDOPool.address,
            success: true,
        });

        const getPerBuyCurr = await iDOPool.getPerBuyCurr(buyCurrency);

        expect(objectToString(getPerBuyCurr)).toEqual(
            objectToString({
                buyCurrRaised: 0n,
                buyCurrRefundedTotal: 0n,
                buyCurrRefundedLeft: 0n,
                buyCurrAddr: buyCurrency,
                buyCurrDecimals: decimal,
                buyCurrRate: rate,
                buyCurrBalance: 0n,
                buyCurrTokenAccountAddr: await buyMint.getWalletAddress(iDOPool.address),
            }),
        );
    }, 30000);
    it('should not set value if sender is not owner of pool', async () => {
        const poolDeployer = await blockchain.treasury('notOwner');
        const buyCurrency = buyMint.address;
        const decimal = 8;
        const rate = 2000000000n;

        const setPerBuyCurr = await iDOPool.sendSetPerBuyCurrency(poolDeployer.getSender(), {
            value: toNano('100'),
            queryID: 0,
            buyCurrency,
            buyCurrencyDecimals: decimal,
            buyCurrencyRate: rate,
            buyCurrencyTokenAccountAddr: await buyMint.getWalletAddress(iDOPool.address),
            buyCurrencyTokenAccountBalance: 0n,
        });

        expect(setPerBuyCurr.transactions).toHaveTransaction({
            from: poolDeployer.address,
            to: iDOPool.address,
            success: false,
            exitCode: error.POOL.NOT_OWNER,
        });
    }, 30000);

    it('should read the value of PerBuyCurr Rate', async () => {
        const poolDeployer = await blockchain.treasury('poolDeployer');
        const buyCurrency = buyMint.address;
        const rate = 5000000000n;

        var balBefore = await poolDeployer.getBalance();
        var contractBalBefore = await iDOPoolFactory.getBalance();

        const setPerBuyCurr = await iDOPool.sendSetPerBuyCurrencyRate(poolDeployer.getSender(), {
            value: toNano('100'),
            queryID: 0,
            buyCurrency,
            buyCurrencyRate: rate,
        });

        var balAfter = await poolDeployer.getBalance();
        var contractBalAfter = await iDOPoolFactory.getBalance();
        expect(balBefore - balAfter).toBeLessThan(500000000n);
        expect(contractBalBefore - contractBalAfter).toBeLessThanOrEqual(0n);

        expect(setPerBuyCurr.transactions).toHaveTransaction({
            from: poolDeployer.address,
            to: iDOPool.address,
            success: true,
        });

        const getPerBuyCurr = await iDOPool.getPerBuyCurr(buyCurrency);

        expect(getPerBuyCurr.buyCurrRate).toEqual(rate);
    }, 30000);

    it('should read the value of PerBuyCurr Decimals', async () => {
        const poolDeployer = await blockchain.treasury('poolDeployer');
        const buyCurrency = buyMint.address;
        const decimals = 18;

        var balBefore = await poolDeployer.getBalance();
        var contractBalBefore = await iDOPoolFactory.getBalance();

        const setPerBuyCurr = await iDOPool.sendSetPerBuyCurrencyDecimals(poolDeployer.getSender(), {
            value: toNano('100'),
            queryID: 0,
            buyCurrency,
            buyCurrencyDecimals: decimals,
        });

        var balAfter = await poolDeployer.getBalance();
        var contractBalAfter = await iDOPoolFactory.getBalance();
        expect(balBefore - balAfter).toBeLessThan(500000000n);
        expect(contractBalBefore - contractBalAfter).toBeLessThanOrEqual(0n);

        expect(setPerBuyCurr.transactions).toHaveTransaction({
            from: poolDeployer.address,
            to: iDOPool.address,
            success: true,
        });

        const getPerBuyCurr = await iDOPool.getPerBuyCurr(buyCurrency);

        expect(getPerBuyCurr.buyCurrDecimals).toEqual(decimals);
    }, 30000);

    it('should set and read new signer', async () => {
        const poolDeployer = await blockchain.treasury('poolDeployer');
        const seed: Buffer = await getSecureRandomBytes(32); // Seed is always 32 bytes
        const newSigner = BigInt(`0x${keyPairFromSeed(seed).publicKey.toString('hex')}`);

        var balBefore = await poolDeployer.getBalance();
        var contractBalBefore = await iDOPoolFactory.getBalance();

        const setPerBuyCurr = await iDOPool.sendSetNewSigner(poolDeployer.getSender(), {
            value: toNano('100'),
            queryID: 0,
            newSigner: newSigner,
        });

        var balAfter = await poolDeployer.getBalance();
        var contractBalAfter = await iDOPoolFactory.getBalance();
        expect(balBefore - balAfter).toBeLessThan(500000000n);
        expect(contractBalBefore - contractBalAfter).toBeLessThanOrEqual(0n);

        expect(setPerBuyCurr.transactions).toHaveTransaction({
            from: poolDeployer.address,
            to: iDOPool.address,
            success: true,
        });

        const signer = await iDOPool.getSigner();
        if (!signer) fail("Couldn't read signer");
        expect(newSigner).toEqual(signer);
    }, 30000);

    it('should not set new signer if sender is not owner', async () => {
        const poolDeployer = await blockchain.treasury('notOwner');
        const seed: Buffer = await getSecureRandomBytes(32); // Seed is always 32 bytes
        const newSigner = BigInt(`0x${keyPairFromSeed(seed).publicKey.toString('hex')}`);

        const setPerBuyCurr = await iDOPool.sendSetNewSigner(poolDeployer.getSender(), {
            value: toNano('100'),
            queryID: 0,
            newSigner: newSigner,
        });

        expect(setPerBuyCurr.transactions).toHaveTransaction({
            from: poolDeployer.address,
            to: iDOPool.address,
            success: false,
            exitCode: error.POOL.NOT_OWNER,
        });
    }, 30000);
    it('should set new close time', async () => {
        const poolDeployer = await blockchain.treasury('poolDeployer');
        const newCloseTime = Math.floor(Date.now() / 1000) + 3600; // 1 hour

        var balBefore = await poolDeployer.getBalance();
        var contractBalBefore = await iDOPoolFactory.getBalance();

        const setPerBuyCurr = await iDOPool.sendSetCloseTime(poolDeployer.getSender(), {
            value: toNano('100'),
            queryID: 0,
            newCloseTime,
        });

        var balAfter = await poolDeployer.getBalance();
        var contractBalAfter = await iDOPoolFactory.getBalance();
        expect(balBefore - balAfter).toBeLessThan(500000000n);
        expect(contractBalBefore - contractBalAfter).toBeLessThanOrEqual(0n);

        expect(setPerBuyCurr.transactions).toHaveTransaction({
            from: poolDeployer.address,
            to: iDOPool.address,
            success: true,
        });

        const closeTime = await iDOPool.getCloseTime();
        if (!closeTime) fail("Couldn't read close time");
        expect(closeTime).toEqual(newCloseTime);
    }, 30000);
    it('should not set new close time if it is in past', async () => {
        const poolDeployer = await blockchain.treasury('poolDeployer');
        const newCloseTime = Math.floor(Date.now() / 1000) - 3600; // -1 hour

        const setPerBuyCurr = await iDOPool.sendSetCloseTime(poolDeployer.getSender(), {
            value: toNano('100'),
            queryID: 0,
            newCloseTime,
        });

        expect(setPerBuyCurr.transactions).toHaveTransaction({
            from: poolDeployer.address,
            to: iDOPool.address,
            success: false,
            exitCode: error.POOL.INVALID_TIME,
        });
    }, 30000);
    it('should set new open time', async () => {
        const poolDeployer = await blockchain.treasury('poolDeployer');
        const newOpenTime = Math.floor(Date.now() / 1000) - 3600; // -1 hour

        var balBefore = await poolDeployer.getBalance();
        var contractBalBefore = await iDOPoolFactory.getBalance();

        const setPerBuyCurr = await iDOPool.sendSetOpenTime(poolDeployer.getSender(), {
            value: toNano('100'),
            queryID: 0,
            newOpenTime,
        });

        var balAfter = await poolDeployer.getBalance();
        var contractBalAfter = await iDOPoolFactory.getBalance();
        expect(balBefore - balAfter).toBeLessThan(500000000n);
        expect(contractBalBefore - contractBalAfter).toBeLessThanOrEqual(0n);

        expect(setPerBuyCurr.transactions).toHaveTransaction({
            from: poolDeployer.address,
            to: iDOPool.address,
            success: true,
        });

        const openTime = await iDOPool.getOpenTime();
        if (!openTime) fail("Couldn't read open time");
        expect(openTime).toEqual(newOpenTime);
    }, 30000);

    it('should set new sell Token', async () => {
        const poolDeployer = await blockchain.treasury('poolDeployer');
        const newSellMintOwner = await blockchain.treasury('newSellMintOwner');

        const newSellMint = blockchain.openContract(
            JettonMinter.createFromConfig(
                {
                    admin: newSellMintOwner.address,
                    content: jettonContentToCell({
                        type: 0,
                        uri: 'testURI',
                    }),
                    wallet_code: await compile('JettonWallet'),
                },
                await compile('JettonMinter'),
            ),
        );
        const newSellTokenAccountAddr = await sellMint.getWalletAddress(iDOPool.address);

        var balBefore = await poolDeployer.getBalance();
        var contractBalBefore = await iDOPoolFactory.getBalance();

        const setSellToken = await iDOPool.sendSetSellToken(poolDeployer.getSender(), {
            value: toNano('100'),
            queryID: 0,
            sellTokenMint: newSellMint.address,
            sellTokenAccount: newSellTokenAccountAddr,
        });

        var balAfter = await poolDeployer.getBalance();
        var contractBalAfter = await iDOPoolFactory.getBalance();
        expect(balBefore - balAfter).toBeLessThan(500000000n);
        expect(contractBalBefore - contractBalAfter).toBeLessThanOrEqual(0n);

        expect(setSellToken.transactions).toHaveTransaction({
            from: poolDeployer.address,
            to: iDOPool.address,
            success: true,
        });

        const sellTokenMint = await iDOPool.getSellTokenMint();
        const sellTokenAccountAddr = await iDOPool.getSellTokenAccountAddr();
        if (!sellTokenMint) fail("Couldn't read sellTokenMint");
        if (!sellTokenAccountAddr) fail("Couldn't read sellTokenAccountAddr");

        expect(sellTokenAccountAddr).toEqualAddress(newSellTokenAccountAddr);
        expect(sellTokenMint).toEqualAddress(newSellMint.address);
    }, 30000);

    it('should not set new open time if it is greater than close time', async () => {
        const poolDeployer = await blockchain.treasury('poolDeployer');
        const closeTime = await iDOPool.getCloseTime();
        const newOpenTime = closeTime + 3600; // +1 hour

        const setPerBuyCurr = await iDOPool.sendSetOpenTime(poolDeployer.getSender(), {
            value: toNano('100'),
            queryID: 0,
            newOpenTime,
        });

        expect(setPerBuyCurr.transactions).toHaveTransaction({
            from: poolDeployer.address,
            to: iDOPool.address,
            success: false,
            exitCode: error.POOL.INVALID_TIME,
        });
    }, 30000);
    it('should not set invalid signer address', async () => {
        const poolDeployer = await blockchain.treasury('poolDeployer');

        const setPerBuyCurr = await iDOPool.sendSetNewSigner(poolDeployer.getSender(), {
            value: toNano('100'),
            queryID: 0,
            newSigner: 0n,
        });

        expect(setPerBuyCurr.transactions).toHaveTransaction({
            from: poolDeployer.address,
            to: iDOPool.address,
            success: false,
            exitCode: error.POOL.ZERO_ADDRESS,
        });
    }, 30000);

    it('should not refund remaining tons by non owner address', async () => {
        const notOwner = await blockchain.treasury('notOwner');
        const receiver = await blockchain.treasury('receiver');

        // send the refund ton request to contract
        const refundTxn = await iDOPool.sendRefundRemainingTon(notOwner.getSender(), {
            value: toNano('0.1'),
            queryID: 0,
            receiverAddress: receiver.address,
        });
        expect(refundTxn.transactions).toHaveTransaction({
            success: false,
            exitCode:error.POOL.NOT_OWNER
        });

    }, 30000);

    it('should refund remaining tons to receiver address', async () => {
        const poolDeployer = await blockchain.treasury('poolDeployer');
        const sender = await blockchain.treasury('sender');
        const receiver = await blockchain.treasury('receiver');
        const receiverInitBalance = await receiver.getBalance();
        const valueToSend = toNano('100');

        // send some ton to the contract
        const sendTonToContract = await sender.send({
            to: iDOPool.address,
            value: valueToSend,
            sendMode: SendMode.PAY_GAS_SEPARATELY,
        });
        expect(sendTonToContract.transactions).toHaveTransaction({
            success: true,
        });
        // set close the pool time to past to make it finalized.
        const newCloseTime = Math.floor(Date.now() / 1000) + 1;
        const setCloseTime = await iDOPool.sendSetCloseTime(poolDeployer.getSender(), {
            value: toNano('100'),
            queryID: 0,
            newCloseTime,
        });
        expect(setCloseTime.transactions).toHaveTransaction({
            from: poolDeployer.address,
            to: iDOPool.address,
            success: true,
        });

        // await to pass the close time
        await new Promise((resolve) => setTimeout(resolve, 2000));

        // send the refund ton request to contract
        const refundTxn = await iDOPool.sendRefundRemainingTon(poolDeployer.getSender(), {
            value: toNano('0.1'),
            queryID: 0,
            receiverAddress: receiver.address,
        });
        expect(refundTxn.transactions).toHaveTransaction({
            success: true,
        });

        // Check receiver balance increase to verify successful refund
        const receiverPostBalance = await receiver.getBalance();
        const expectedBalance = Number(receiverInitBalance) + Number(valueToSend);
        expect(Number(receiverPostBalance)).toBeGreaterThan(expectedBalance);
    }, 30000);

    it('should not refund remaining jettons by non owner address', async () => {
        const notOwner = await blockchain.treasury('notOwner');
        const receiver = await blockchain.treasury('receiver');

        // await to pass the close time
        await new Promise((resolve) => setTimeout(resolve, 2000));

        // send the refund jetton request to contract
        const refundTxn = await iDOPool.sendRefundRemainingJetton(notOwner.getSender(), {
            value: toNano('1'),
            queryID: 0,
            receiverAddress: receiver.address,
            jettonAddress: buyMint.address,
        });
        expect(refundTxn.transactions).toHaveTransaction({
            to: iDOPool.address,
            success: false,
            exitCode: error.POOL.NOT_OWNER
        });

    }, 30000);

    it('should refund remaining jettons to receiver address', async () => {
        const poolDeployer = await blockchain.treasury('poolDeployer');
        const receiver = await blockchain.treasury('receiver');
        const jettonToTransfer = 5n;
        const receiverBuyMintWallet = blockchain.openContract(
            JettonWallet.createFromAddress(await buyMint.getWalletAddress(receiver.address)),
        );

        var balBefore = await poolDeployer.getBalance();
        var contractBalBefore = await iDOPoolFactory.getBalance();

        // transfer some jetton to contract
        const jettonTransfer = await buyerBuyMintWallet.sendTransfer(
            buyer.getSender(),
            toNano('1'),
            jettonToTransfer,
            iDOPool.address,
            buyer.address,
            beginCell().endCell(),
            toNano('0.1'),
            beginCell().endCell(),
        );

        var balAfter = await poolDeployer.getBalance();
        var contractBalAfter = await iDOPoolFactory.getBalance();
        expect(balBefore - balAfter).toBeLessThan(500000000n);
        expect(contractBalBefore - contractBalAfter).toBeLessThanOrEqual(0n);

        expect(jettonTransfer.transactions).toHaveTransaction({
            to: iDOPool.address,
            success: true,
        });

        // set close the pool time to past to make it finalized.
        const newCloseTime = Math.floor(Date.now() / 1000) + 1;
        const setCloseTime = await iDOPool.sendSetCloseTime(poolDeployer.getSender(), {
            value: toNano('100'),
            queryID: 0,
            newCloseTime,
        });
        expect(setCloseTime.transactions).toHaveTransaction({
            from: poolDeployer.address,
            to: iDOPool.address,
            success: true,
        });

        // await to pass the close time
        await new Promise((resolve) => setTimeout(resolve, 2000));

        // send the refund jetton request to contract
        const refundTxn = await iDOPool.sendRefundRemainingJetton(poolDeployer.getSender(), {
            value: toNano('1'),
            queryID: 0,
            receiverAddress: receiver.address,
            jettonAddress: buyMint.address,
        });
        expect(refundTxn.transactions).toHaveTransaction({
            to: iDOPool.address,
            success: true,
        });

        // verify refund amount of jetton
        const receiverPostBalance = await receiverBuyMintWallet.getJettonBalance();
        expect(receiverPostBalance).toBeGreaterThanOrEqual(jettonToTransfer);
    }, 30000);

    it('should set new Owner', async () => {
        const poolDeployer = await blockchain.treasury('poolDeployer');
        const newOwner = await blockchain.treasury('newOwner');

        const setNewOwner = await iDOPool.sendSetNewOwner(poolDeployer.getSender(), {
            value: toNano('1'),
            queryID: 0,
            newOwner: newOwner.address,
        });

        expect(setNewOwner.transactions).toHaveTransaction({
            from: poolDeployer.address,
            to: iDOPool.address,
            success: true,
        });

        const owner = await iDOPool.getOwner();
        if (!owner) fail("Couldn't read contract owner");

        expect(owner).toEqualAddress(newOwner.address);
    }, 30000);
});
