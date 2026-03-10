import { Blockchain, BlockchainContractProvider, SandboxContract, TreasuryContract } from '@ton/sandbox';
import { Address, beginCell, Cell, toNano } from '@ton/core';
import { IDOPoolFactory } from '../wrappers/IDOPoolFactory';
import { createIDOPoolSwapByTokenMessage, IDOPool } from '../wrappers/IDOPool';
import '@ton/test-utils';
import { compile } from '@ton/blueprint';
import { jettonContentToCell, JettonMinter } from '../wrappers/JettonMinter';
import { JettonWallet } from '../wrappers/JettonWallet';
import { cleanupTransactions } from '../utils/cleanupTransactions';
import { getSecureRandomBytes, KeyPair, keyPairFromSecretKey, keyPairFromSeed, sign } from '@ton/crypto';
import { objectToString } from '../utils/objectToString';

describe('IDOPool', () => {
    let factoryCode: Cell;
    let poolCode: Cell;

    beforeAll(async () => {
        factoryCode = await compile('IDOPoolFactory');
        poolCode = await compile('IDOPool');

    });

    let blockchain: Blockchain;
    let factoryDeployer: SandboxContract<TreasuryContract>;
    let iDOPoolFactory: SandboxContract<IDOPoolFactory>;
    let iDOPool: SandboxContract<IDOPool>;
    let buyMint: SandboxContract<JettonMinter>;
    let buyMintOwner: SandboxContract<TreasuryContract>;
    let sellMint: SandboxContract<JettonMinter>;
    let sellMintOwner: SandboxContract<TreasuryContract>;
    let extraMint: SandboxContract<JettonMinter>;
    let extraMintOwner: SandboxContract<TreasuryContract>;
    let buyer: SandboxContract<TreasuryContract>;
    let buyerBuyMintWallet: SandboxContract<JettonWallet>;
    let buyerSellMintWallet: SandboxContract<JettonWallet>;
    let buyerExtraMintWallet: SandboxContract<JettonWallet>;
    let poolSellMintWallet: SandboxContract<JettonWallet>;
    let poolBuyMintWallet: SandboxContract<JettonWallet>;
    let poolDeployer: SandboxContract<TreasuryContract>;
    let signer: KeyPair;
    let fundingWalletAddr: Address;
    let fundingWalletBuyMintWallet: SandboxContract<JettonWallet>;
    let buyCurrDecimals: number;
    let buyCurrRate: bigint;
    let buyCurrTokenAccountAddr: Address;
    let sellTokenAccountAddr: Address;


    beforeEach(async () => {

        blockchain = await Blockchain.create();

        iDOPoolFactory = blockchain.openContract(
            IDOPoolFactory.createFromConfig(
                {
                    poolCode,
                    zeroAddress: Address.parse('0QAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACkT')
                },
                factoryCode,
            ),
        );

        factoryDeployer = await blockchain.treasury('deployer');

        const deployResult = await iDOPoolFactory.sendDeploy(factoryDeployer.getSender(), toNano('0.1'));

        expect(deployResult.transactions).toHaveTransaction({
            from: factoryDeployer.address,
            to: iDOPoolFactory.address,
            deploy: true,
            success: true,
        });

        //// create mints for buy and sell tokens
        buyMintOwner = await blockchain.treasury('buyMintOwner');
        sellMintOwner = await blockchain.treasury('sellMintOwner');
        extraMintOwner = await blockchain.treasury('extraMintOwner');

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

        await buyMint.sendDeploy(buyMintOwner.getSender(), toNano('0.1'));

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
        await sellMint.sendDeploy(sellMintOwner.getSender(), toNano('0.1'));

        extraMint = blockchain.openContract(
            JettonMinter.createFromConfig(
                {
                    admin: extraMintOwner.address,
                    content: jettonContentToCell({
                        type: 0,
                        uri: 'testURI',
                    }),
                    wallet_code: await compile('JettonWallet'),
                },
                await compile('JettonMinter'),
            ),
        );
        await extraMint.sendDeploy(extraMintOwner.getSender(), toNano('0.1'));

        //// get future address of pool
        poolDeployer = await blockchain.treasury('poolDeployer');
        const sellTokenMintAddr = sellMint.address;
        const seed: Buffer = await getSecureRandomBytes(32); // Seed is always 32 bytes
        signer = keyPairFromSeed(seed);
        const signerAddr = BigInt(`0x${signer.publicKey.toString('hex')}`);
        fundingWalletAddr = poolDeployer.address;
        const openTime = Math.floor(Date.now() / 1000);
        const duration = 1000;
        const buyCurrAddr = buyMint.address;
        buyCurrDecimals = 9;
        buyCurrRate = 1000000000n;

        const _iDOPoolAddress = await iDOPoolFactory.getNextPoolAddress(
            poolDeployer.address,
            signerAddr,
            sellTokenMintAddr,
            fundingWalletAddr,
            openTime,
            duration,
            buyCurrAddr,
            buyCurrDecimals,
            buyCurrRate
        );

        //// mint tokens to required accounts
        buyer = await blockchain.treasury('buyer');

        fundingWalletBuyMintWallet = blockchain.openContract(JettonWallet.createFromAddress(await buyMint.getWalletAddress(fundingWalletAddr)));

        await sellMint.sendMint(sellMintOwner.getSender(), buyer.address, 999n, toNano('5'), toNano('100'));

        buyerSellMintWallet = blockchain.openContract(JettonWallet.createFromAddress(await sellMint.getWalletAddress(buyer.address)));

        expect(await buyerSellMintWallet.getJettonBalance()).toBe(999n);

        await buyMint.sendMint(buyMintOwner.getSender(), buyer.address, 998n, toNano('5'), toNano('10'));

        buyerBuyMintWallet = blockchain.openContract(JettonWallet.createFromAddress(await buyMint.getWalletAddress(buyer.address)));

        expect(await buyerBuyMintWallet.getJettonBalance()).toBe(998n);

        await extraMint.sendMint(extraMintOwner.getSender(), buyer.address, 100n, toNano('10'), toNano('11'));

        buyerExtraMintWallet = blockchain.openContract(JettonWallet.createFromAddress(await extraMint.getWalletAddress(buyer.address)));

        expect(await buyerExtraMintWallet.getJettonBalance()).toBe(100n);

        buyCurrTokenAccountAddr = await buyMint.getWalletAddress(_iDOPoolAddress);
        sellTokenAccountAddr = await sellMint.getWalletAddress(_iDOPoolAddress);

        var senderBalBefore = await poolDeployer.getBalance();
        var poolBalBefore = await iDOPoolFactory.getBalance();

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
            sellTokenAccountAddr
        });

        var senderBalAfter = await poolDeployer.getBalance();
        var poolBalAfter = await iDOPoolFactory.getBalance();
        expect(senderBalBefore - senderBalAfter).toBeLessThan(500000000n);
        expect(poolBalBefore - poolBalAfter).toBeLessThanOrEqual(0n);

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

        await sellMint.sendMint(sellMintOwner.getSender(), _iDOPoolAddress, 1000n, toNano('5'), toNano('10'));
        poolSellMintWallet = blockchain.openContract(JettonWallet.createFromAddress(await sellMint.getWalletAddress(_iDOPoolAddress)));
        await buyMint.sendMint(buyMintOwner.getSender(), _iDOPoolAddress, 997n, toNano('5'), toNano('10'));
        poolBuyMintWallet = blockchain.openContract(JettonWallet.createFromAddress(await buyMint.getWalletAddress(_iDOPoolAddress)));
        expect(await poolSellMintWallet.getJettonBalance()).toBe(1000n);
        expect(await poolBuyMintWallet.getJettonBalance()).toBe(997n);
        expect(objectToString(await iDOPool.getPerBuyCurr(buyMint.address))).toEqual(objectToString({
            buyCurrRaised: 0n,
            buyCurrRefundedTotal: 0n,
            buyCurrRefundedLeft: 0n,
            buyCurrAddr: buyMint.address,
            buyCurrDecimals,
            buyCurrRate,
            buyCurrBalance: 997n,
            buyCurrTokenAccountAddr
        }));
        expect(await iDOPool.getSellTokenAccountBalance()).toEqual(1000n);

    }, 30000);

    it('should maintain token balance when relevant jettons are sent', async () => {

        const transferResponse1 = await buyerBuyMintWallet.sendTransfer(
            buyer.getSender(),
            toNano('1'),
            2n,
            iDOPool.address,
            buyer.address,
            beginCell().endCell(),
            toNano('0.1'),
            beginCell().endCell()
        );

        expect(transferResponse1.transactions).toHaveTransaction({
            to: iDOPool.address,
            success: true
        });

        expect(objectToString(await iDOPool.getPerBuyCurr(buyMint.address))).toEqual(objectToString({
            buyCurrRaised: 0n,
            buyCurrRefundedTotal: 0n,
            buyCurrRefundedLeft: 0n,
            buyCurrAddr: buyMint.address,
            buyCurrDecimals,
            buyCurrRate,
            buyCurrBalance: 999n,
            buyCurrTokenAccountAddr
        }));

        const transferResponse2 = await buyerBuyMintWallet.sendTransfer(
            buyer.getSender(),
            toNano('1'),
            5n,
            iDOPool.address,
            buyer.address,
            beginCell().endCell(),
            toNano('0.1'),
            beginCell().endCell()
        );

        expect(transferResponse2.transactions).toHaveTransaction({
            to: iDOPool.address,
            success: true
        });

        expect(objectToString(await iDOPool.getPerBuyCurr(buyMint.address))).toEqual(objectToString({
            buyCurrRaised: 0n,
            buyCurrRefundedTotal: 0n,
            buyCurrRefundedLeft: 0n,
            buyCurrAddr: buyMint.address,
            buyCurrDecimals,
            buyCurrRate,
            buyCurrBalance: 1004n,
            buyCurrTokenAccountAddr
        }));

        const transferResponse3 = await buyerSellMintWallet.sendTransfer(
            buyer.getSender(),
            toNano('1'),
            5n,
            iDOPool.address,
            buyer.address,
            beginCell().endCell(),
            toNano('0.1'),
            beginCell().endCell()
        );

        expect(transferResponse3.transactions).toHaveTransaction({
            to: iDOPool.address,
            success: true
        });

        expect(await iDOPool.getSellTokenAccountBalance()).toEqual(1005n);

        const transferResponse4 = await buyerExtraMintWallet.sendTransfer(
            buyer.getSender(),
            toNano('1'),
            5n,
            iDOPool.address,
            buyer.address,
            beginCell().endCell(),
            toNano('0.1'),
            beginCell().endCell()
        );

        expect(transferResponse4.transactions).toHaveTransaction({
            to: iDOPool.address,
            success: false,
            exitCode: 813
        });
    }, 30000);

    it('should perform swap by token functionality. request a refund and then claim the refund', async () => {

        // ------------------------
        // -------SWAPPING---------
        // ------------------------

        const maxAmount = toNano('1');
        const minAmount = toNano('0');
        const buyCurrency = buyMint.address;
        const candidate = buyer.address;
        const jettonAmount = 10n;

        var _signature = sign(
            new Cell()
                .asBuilder()
                .storeAddress(candidate)
                .storeCoins(maxAmount)
                .storeCoins(minAmount)
                .storeAddress(iDOPool.address)
                .storeUint(0, 32) // workchain id
                .endCell()
                .hash()
                ,
            signer.secretKey
        );
        var signature = BigInt(`0x${_signature.toString('hex')}`);

        var balBefore = await buyer.getBalance();
        var poolBalBefore = await iDOPool.getBalance();

        const swapResult = await buyerBuyMintWallet.sendTransfer(
            buyer.getSender(),
            toNano('1.1'),
            jettonAmount,
            iDOPool.address,
            candidate,
            new Cell()
                ,
            toNano('1'),
            createIDOPoolSwapByTokenMessage({
                buyCurrency,
                maxAmount,
                minAmount,
                signature
            })
        )

        var balAfter = await buyer.getBalance();
        var poolBalAfter = await iDOPool.getBalance();
        expect(balBefore - balAfter).toBeLessThanOrEqual(500000000n);
        expect(poolBalBefore - poolBalAfter).toBeLessThanOrEqual(0n);

        expect(swapResult.transactions).toHaveTransaction({
            to: iDOPool.address,
            success: true
        });
        expect(swapResult.transactions).toHaveTransaction({
            to: fundingWalletBuyMintWallet.address,
            success: true
        });
        expect(await iDOPool.getTotalUnclaimed()).toBe(jettonAmount);
        expect(await iDOPool.getTokenSold()).toBe(jettonAmount);
        expect(objectToString(await iDOPool.getPerBuyCurr(buyCurrency))).toEqual(objectToString({
            buyCurrRaised: jettonAmount,
            buyCurrRefundedTotal: 0n,
            buyCurrRefundedLeft: 0n,
            buyCurrAddr: buyMint.address,
            buyCurrDecimals: 9,
            buyCurrRate: 1000000000n,
            buyCurrBalance: 997n,
            buyCurrTokenAccountAddr
        }));
        expect(await fundingWalletBuyMintWallet.getJettonBalance()).toBe(jettonAmount);
        expect(await iDOPool.getPerUser(buyer.address)).toEqual({
            sellCurrBought: jettonAmount,
            sellCurrClaimed: 0n
        });
        expect(await iDOPool.getPerUserPerBuyCurr(buyer.address, buyCurrency)).toEqual({
            sellCurrBought: jettonAmount,
            buyCurrSold: jettonAmount,
            refundAmount: 0n,
            isRefundClaimed: false
        });

        var balBefore = await poolDeployer.getBalance();
        var poolbalAfter = await iDOPool.getBalance();

        // change close time to move to next phase of pool
        const newCloseTime = Math.floor(Date.now() / 1000) + 1;
        const setCloseTimeResult = await iDOPool.sendSetCloseTime(
            poolDeployer.getSender(),
            {
                queryID: 0,
                value: toNano('1'),
                newCloseTime
            }
        );

        var balAfter = await poolDeployer.getBalance();
        var poolBalAfter = await iDOPool.getBalance();
        expect(balBefore - balAfter).toBeLessThanOrEqual(500000000n);
        expect(poolBalBefore - poolBalAfter).toBeLessThanOrEqual(0n);

        expect(setCloseTimeResult.transactions).toHaveTransaction({
            to: iDOPool.address,
            success: true,
        });
        expect(await iDOPool.getCloseTime()).toBe(newCloseTime);

        while (Math.floor(Date.now() / 1000) <= newCloseTime) {
            await new Promise((resolve) => setTimeout(resolve, 250));
        }

        // ------------------------
        // ----REQUEST-REFUND------
        // ------------------------

        const deadline = Math.floor(Date.now() / 1000) + 10;
        const refundCurrency = buyCurrency;
        var _signature = sign(
            new Cell()
                .asBuilder()
                .storeAddress(candidate)
                .storeAddress(refundCurrency)
                .storeUint(deadline, 32)
                .storeAddress(iDOPool.address)
                .storeUint(0, 32) // workchain id
                .endCell()
                .hash()
                ,
            signer.secretKey
        );
        var signature = BigInt(`0x${_signature.toString('hex')}`);

        var balBefore = await buyer.getBalance();
        var poolBalBefore = await iDOPool.getBalance();

        const refundResult = await iDOPool.sendRefundTokens(
            buyer.getSender(),
            {
                deadline,
                refundCurrency,
                signature,
                queryID: 0,
                value: toNano('10')
            }
        );

        var balAfter = await buyer.getBalance();
        var poolBalAfter = await iDOPool.getBalance();
        expect(balBefore - balAfter).toBeLessThanOrEqual(500000000n);
        expect(poolBalBefore - poolBalAfter).toBeLessThanOrEqual(0n);

        expect(refundResult.transactions).toHaveTransaction({
            to: iDOPool.address,
            success: true
        });

        expect(objectToString(await iDOPool.getPerBuyCurr(refundCurrency))).toEqual(objectToString({
            buyCurrRaised: 0n,
            buyCurrRefundedTotal: jettonAmount,
            buyCurrRefundedLeft: jettonAmount,
            buyCurrAddr: refundCurrency,
            buyCurrDecimals: buyCurrDecimals,
            buyCurrRate: buyCurrRate,
            buyCurrBalance: 997n,
            buyCurrTokenAccountAddr
        }));
        expect(await iDOPool.getPerUser(buyer.address)).toEqual({
            sellCurrBought: 0n,
            sellCurrClaimed: 0n
        });
        expect(await iDOPool.getPerUserPerBuyCurr(buyer.address, refundCurrency)).toEqual({
            sellCurrBought: 0n,
            buyCurrSold: 0n,
            refundAmount: jettonAmount,
            isRefundClaimed: false
        });
        expect(await iDOPool.getTotalUnclaimed()).toBe(0n);
        expect(await iDOPool.getTokenSold()).toBe(0n);
        expect(await iDOPool.getTotalRefunded()).toBe(jettonAmount);

        // ------------------------
        // ----CLAIM-REFUND------
        // ------------------------

        const claimRefundCurrency = buyCurrency;
        var _signature = sign(
            new Cell()
                .asBuilder()
                .storeAddress(candidate)
                .storeAddress(claimRefundCurrency)
                .storeAddress(iDOPool.address)
                .storeUint(0, 32) // workchain id
                .endCell()
                .hash()
                ,
            signer.secretKey
        );
        var signature = BigInt(`0x${_signature.toString('hex')}`);

        var balBefore = await buyer.getBalance();
        var poolBalBefore = await iDOPool.getBalance();

        const claimRefundResult = await iDOPool.sendClaimRefundTokens(
            buyer.getSender(),
            {
                refundCurrency,
                signature,
                queryID: 0,
                value: toNano('10')
            }
        );

        var balAfter = await buyer.getBalance();
        var poolBalAfter = await iDOPool.getBalance();
        expect(balBefore - balAfter).toBeLessThanOrEqual(500000000n);
        expect(poolBalBefore - poolBalAfter).toBeLessThanOrEqual(0n);

        expect(claimRefundResult.transactions).toHaveTransaction({
            to: iDOPool.address,
            success: true
        });

        expect(objectToString(await iDOPool.getPerBuyCurr(claimRefundCurrency))).toEqual(objectToString({
            buyCurrRaised: 0n,
            buyCurrRefundedTotal: jettonAmount,
            buyCurrRefundedLeft: 0n,
            buyCurrAddr: claimRefundCurrency,
            buyCurrDecimals,
            buyCurrRate,
            buyCurrBalance: 997n - jettonAmount,
            buyCurrTokenAccountAddr
        }));
        expect(await iDOPool.getPerUser(buyer.address)).toEqual({
            sellCurrBought: 0n,
            sellCurrClaimed: 0n
        });
        expect(await iDOPool.getPerUserPerBuyCurr(buyer.address, refundCurrency)).toEqual({
            sellCurrBought: 0n,
            buyCurrSold: 0n,
            refundAmount: jettonAmount,
            isRefundClaimed: true
        });
        expect(await iDOPool.getTotalUnclaimed()).toBe(0n);
        expect(await iDOPool.getTokenSold()).toBe(0n);
        expect(await iDOPool.getTotalRefunded()).toBe(jettonAmount);
        expect(await buyerBuyMintWallet.getJettonBalance()).toBe(998n);

    }, 30000);

    it('should perform withdraw sell token, and verify amount', async () => {

        /**
         * -----------------------------------------
         * -------Get Init Sell Token Balance-------
         * -----------------------------------------
         */
        const sellTokenInitBalance = await iDOPool.getSellTokenAccountBalance();
        if(!sellTokenInitBalance){
            throw new Error("Error: fail to get sellTokenInitBalance")
        }


        // ------------------------
        // -------SWAPPING---------
        // ------------------------

        const maxAmount = toNano('1');
        const minAmount = toNano('0');
        const buyCurrency = buyMint.address;
        const candidate = buyer.address;
        const jettonAmount = 10n;


        var _signature = sign(
            new Cell()
                .asBuilder()
                .storeAddress(candidate)
                .storeCoins(maxAmount)
                .storeCoins(minAmount)
                .storeAddress(iDOPool.address)
                .storeUint(0, 32) // workchain id
                .endCell()
                .hash()
                ,
            signer.secretKey
        );
        var signature = BigInt(`0x${_signature.toString('hex')}`);

        var balBefore = await buyer.getBalance();
        var poolBalBefore = await iDOPool.getBalance();



        const swapResult = await buyerBuyMintWallet.sendTransfer(
            buyer.getSender(),
            toNano('1.1'),
            jettonAmount,
            iDOPool.address,
            candidate,
            new Cell()
                ,
            toNano('1'),
            createIDOPoolSwapByTokenMessage({
                buyCurrency,
                maxAmount,
                minAmount,
                signature
            })
        )



        var balAfter = await buyer.getBalance();
        var poolBalAfter = await iDOPool.getBalance();
        expect(balBefore - balAfter).toBeLessThanOrEqual(500000000n);
        expect(poolBalBefore - poolBalAfter).toBeLessThanOrEqual(0n);

        expect(swapResult.transactions).toHaveTransaction({
            to: iDOPool.address,
            success: true
        });
        expect(swapResult.transactions).toHaveTransaction({
            to: fundingWalletBuyMintWallet.address,
            success: true
        });
        expect(await iDOPool.getTotalUnclaimed()).toBe(jettonAmount);
        expect(await iDOPool.getTokenSold()).toBe(jettonAmount);
        expect(objectToString(await iDOPool.getPerBuyCurr(buyCurrency))).toEqual(objectToString({
            buyCurrRaised: jettonAmount,
            buyCurrRefundedTotal: 0n,
            buyCurrRefundedLeft: 0n,
            buyCurrAddr: buyMint.address,
            buyCurrDecimals: 9,
            buyCurrRate: 1000000000n,
            buyCurrBalance: 997n,
            buyCurrTokenAccountAddr
        }));
        expect(await fundingWalletBuyMintWallet.getJettonBalance()).toBe(jettonAmount);
        expect(await iDOPool.getPerUser(buyer.address)).toEqual({
            sellCurrBought: jettonAmount,
            sellCurrClaimed: 0n
        });
        expect(await iDOPool.getPerUserPerBuyCurr(buyer.address, buyCurrency)).toEqual({
            sellCurrBought: jettonAmount,
            buyCurrSold: jettonAmount,
            refundAmount: 0n,
            isRefundClaimed: false
        });

        /**
         * ----------------------------------
         * -------Set Close Pool Time -------
         * ----------------------------------
         */

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

        /**
         * ---------------------------------------
         * ---Call sendRefundRemainingSellToken---
         * ---------------------------------------
         */

        const receiver = await blockchain.treasury('receiver');

        const refundTxn = await iDOPool.sendRefundRemainingSellToken(poolDeployer.getSender(), {
            value: toNano('1'),
            queryID: 0,
            receiverAddress: receiver.address,
        });
        expect(refundTxn.transactions).toHaveTransaction({
            to: iDOPool.address,
            success: true,
        });


        /**
         * ----------------------------------------
         * ----Get Post Balance of Sell Token------
         * ----------------------------------------
         */

         // get Sell Token balance
         const sellTokenPostBalance = await iDOPool.getSellTokenAccountBalance();
         if(!sellTokenPostBalance){
             throw new Error("Error: fail to get sellTokenPostBalance")
         }

         expect(sellTokenPostBalance).toEqual(jettonAmount);

    }, 30000);

    it('should perform swap by token functionality. and then claim it. twice.', async () => {

        // ------------------------
        // -------SWAPPING---------
        // ------------------------

        const maxAmount = toNano('1');
        const minAmount = toNano('0');
        const buyCurrency = buyMint.address;
        const candidate = buyer.address;
        const jettonAmount = 10n;

        var _signature = sign(
            new Cell()
                .asBuilder()
                .storeAddress(candidate)
                .storeCoins(maxAmount)
                .storeCoins(minAmount)
                .storeAddress(iDOPool.address)
                .storeUint(0, 32) // workchain id
                .endCell()
                .hash()
                ,
            signer.secretKey
        );
        var signature = BigInt(`0x${_signature.toString('hex')}`);

        var balBefore = await buyer.getBalance();
        var poolBalBefore = await iDOPool.getBalance();

        const swapResult = await buyerBuyMintWallet.sendTransfer(
            buyer.getSender(),
            toNano('1.1'),
            jettonAmount,
            iDOPool.address,
            candidate,
            new Cell()
                ,
            toNano('1'),
            createIDOPoolSwapByTokenMessage({
                buyCurrency,
                maxAmount,
                minAmount,
                signature
            })
        );

        var balAfter = await buyer.getBalance();
        var poolBalAfter = await iDOPool.getBalance();
        expect(balBefore - balAfter).toBeLessThanOrEqual(500000000n);
        expect(poolBalBefore - poolBalAfter).toBeLessThanOrEqual(0n);

        expect(swapResult.transactions).toHaveTransaction({
            to: iDOPool.address,
            success: true
        });
        expect(swapResult.transactions).toHaveTransaction({
            to: fundingWalletBuyMintWallet.address,
            success: true
        });
        expect(await iDOPool.getTotalUnclaimed()).toBe(jettonAmount);
        expect(await iDOPool.getTokenSold()).toBe(jettonAmount);
        expect(objectToString(await iDOPool.getPerBuyCurr(buyCurrency))).toEqual(objectToString({
            buyCurrRaised: jettonAmount,
            buyCurrRefundedTotal: 0n,
            buyCurrRefundedLeft: 0n,
            buyCurrAddr: buyMint.address,
            buyCurrDecimals: 9,
            buyCurrRate: 1000000000n,
            buyCurrBalance: 997n,
            buyCurrTokenAccountAddr
        }));
        expect(await fundingWalletBuyMintWallet.getJettonBalance()).toBe(jettonAmount);
        expect(await iDOPool.getPerUser(buyer.address)).toEqual({
            sellCurrBought: jettonAmount,
            sellCurrClaimed: 0n
        });
        expect(await iDOPool.getPerUserPerBuyCurr(buyer.address, buyCurrency)).toEqual({
            sellCurrBought: jettonAmount,
            buyCurrSold: jettonAmount,
            refundAmount: 0n,
            isRefundClaimed: false
        });

        var balBefore = await poolDeployer.getBalance();
        var poolBalBefore = await iDOPool.getBalance();

        // change close time to move to next phase of pool
        const newCloseTime = Math.floor(Date.now() / 1000) + 2;
        const setCloseTimeResult = await iDOPool.sendSetCloseTime(
            poolDeployer.getSender(),
            {
                queryID: 0,
                value: toNano('1'),
                newCloseTime
            }
        );

        var balAfter = await poolDeployer.getBalance();
        var poolBalAfter = await iDOPool.getBalance();
        expect(balBefore - balAfter).toBeLessThanOrEqual(500000000n);
        expect(poolBalBefore - poolBalAfter).toBeLessThanOrEqual(0n);

        expect(setCloseTimeResult.transactions).toHaveTransaction({
            to: iDOPool.address,
            success: true,
        });
        expect(await iDOPool.getCloseTime()).toBe(newCloseTime);

        while (Math.floor(Date.now() / 1000) <= newCloseTime) {
            await new Promise((resolve) => setTimeout(resolve, 250));
        }

        // ------------------------
        // -------CLAIMING-1-------
        // ------------------------
        const claimAmount = jettonAmount - 5n;
        var _signature = sign(
            new Cell()
                .asBuilder()
                .storeAddress(candidate)
                .storeCoins(claimAmount)
                .storeAddress(iDOPool.address)
                .storeUint(0, 32) // workchain id
                .endCell()
                .hash()
                ,
            signer.secretKey
        );
        var signature = BigInt(`0x${_signature.toString('hex')}`);

        var balBefore = await buyer.getBalance();
        var poolBalBefore = await iDOPool.getBalance();

        const claimResult = await iDOPool.sendClaimTokens(
            buyer.getSender(),
            {
                claimAmount,
                queryID: 0,
                signature,
                value: toNano('10')
            }
        );

        var balAfter = await buyer.getBalance();
        var poolBalAfter = await iDOPool.getBalance();
        expect(balBefore - balAfter).toBeLessThanOrEqual(500000000n);
        expect(poolBalBefore - poolBalAfter).toBeLessThanOrEqual(0n);

        expect(claimResult.transactions).toHaveTransaction({
            to: iDOPool.address,
            success: true
        });

        expect(await iDOPool.getTotalUnclaimed()).toBe(jettonAmount - claimAmount);
        expect(objectToString(await iDOPool.getPerBuyCurr(buyMint.address))).toEqual(objectToString({
            buyCurrRaised: jettonAmount,
            buyCurrRefundedTotal: 0n,
            buyCurrRefundedLeft: 0n,
            buyCurrAddr: buyMint.address,
            buyCurrDecimals: 9,
            buyCurrRate: 1000000000n,
            buyCurrBalance: 997n,
            buyCurrTokenAccountAddr: poolBuyMintWallet.address
        }));
        expect(await iDOPool.getPerUserPerBuyCurr(buyer.address, buyMint.address)).toEqual({
            sellCurrBought: jettonAmount,
            buyCurrSold: jettonAmount,
            refundAmount: 0n,
            isRefundClaimed: false
        });
        expect(await iDOPool.getPerUser(buyer.address)).toEqual({
            sellCurrBought: jettonAmount,
            sellCurrClaimed: claimAmount
        });
        expect(await iDOPool.getTotalUnclaimed()).toBe(jettonAmount - claimAmount);
        expect(await iDOPool.getSellTokenAccountBalance()).toBe(1000n - claimAmount);
        expect(claimResult.transactions).toHaveTransaction({
            to: buyerSellMintWallet.address,
            success: true
        });
        expect(await buyerSellMintWallet.getJettonBalance()).toBe(999n + claimAmount);

        // ------------------------
        // -------CLAIMING-2-------
        // ------------------------

        const claimAmount1 = jettonAmount - 3n;
        var _signature = sign(
            new Cell()
                .asBuilder()
                .storeAddress(candidate)
                .storeCoins(claimAmount1)
                .storeAddress(iDOPool.address)
                .storeUint(0, 32) // workchain id
                .endCell()
                .hash()
                ,
            signer.secretKey
        );
        var signature = BigInt(`0x${_signature.toString('hex')}`);

        var balBefore = await buyer.getBalance();
        var poolBalBefore = await iDOPool.getBalance();

        const claimResult1 = await iDOPool.sendClaimTokens(
            buyer.getSender(),
            {
                claimAmount: claimAmount1,
                queryID: 0,
                signature,
                value: toNano('10')
            }
        );

        var balAfter = await buyer.getBalance();
        var poolBalAfter = await iDOPool.getBalance();
        expect(balBefore - balAfter).toBeLessThanOrEqual(500000000n);
        expect(poolBalBefore - poolBalAfter).toBeLessThanOrEqual(0n);

        expect(claimResult1.transactions).toHaveTransaction({
            to: iDOPool.address,
            success: true
        });

        expect(await iDOPool.getTotalUnclaimed()).toBe(jettonAmount - claimAmount1);
        expect(objectToString(await iDOPool.getPerBuyCurr(buyMint.address))).toEqual(objectToString({
            buyCurrRaised: jettonAmount,
            buyCurrRefundedTotal: 0n,
            buyCurrRefundedLeft: 0n,
            buyCurrAddr: buyMint.address,
            buyCurrDecimals: 9,
            buyCurrRate: 1000000000n,
            buyCurrBalance: 997n,
            buyCurrTokenAccountAddr: poolBuyMintWallet.address
        }));
        expect(await iDOPool.getPerUserPerBuyCurr(buyer.address, buyMint.address)).toEqual({
            sellCurrBought: jettonAmount,
            buyCurrSold: jettonAmount,
            refundAmount: 0n,
            isRefundClaimed: false
        });
        expect(await iDOPool.getPerUser(buyer.address)).toEqual({
            sellCurrBought: jettonAmount,
            sellCurrClaimed: claimAmount1
        });
        expect(await iDOPool.getTotalUnclaimed()).toBe(jettonAmount - claimAmount1);
        expect(await iDOPool.getSellTokenAccountBalance()).toBe(1000n - claimAmount1);
        expect(claimResult.transactions).toHaveTransaction({
            to: buyerSellMintWallet.address,
            success: true
        });
        expect(await buyerSellMintWallet.getJettonBalance()).toBe(999n + claimAmount1);

    }, 30000);

    it('should perform swap by ton functionality. and then claim it. twice.', async () => {

        // ------------------------
        // -------SWAPPING---------
        // ------------------------

        const zeroAddress = Address.parse('0QAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACkT');

        const setPerBuyResult = await iDOPool.sendSetPerBuyCurrency(
            poolDeployer.getSender(),
            {
                buyCurrency: zeroAddress,
                buyCurrencyDecimals: 9,
                buyCurrencyRate: 1000000000n,
                buyCurrencyTokenAccountAddr: zeroAddress,
                buyCurrencyTokenAccountBalance: 0n,
                queryID: 0,
                value: toNano('1')
            }
        )

        expect(setPerBuyResult.transactions).toHaveTransaction({
            to: iDOPool.address,
            success: true
        });

        const maxAmount = toNano('1');
        const minAmount = toNano('0');
        const candidate = buyer.address;
        const tonAmount = 10n;

        var _signature = sign(
            new Cell()
                .asBuilder()
                .storeAddress(candidate)
                .storeCoins(maxAmount)
                .storeCoins(minAmount)
                .storeAddress(iDOPool.address)
                .storeUint(0, 32) // workchain id
                .endCell()
                .hash()
                ,
            signer.secretKey
        );
        var signature = BigInt(`0x${_signature.toString('hex')}`);

        var balBefore = await buyer.getBalance();
        var poolBalBefore = await iDOPool.getBalance();

        const swapResult = await iDOPool.sendSwapByTon(
            buyer.getSender(),
            {
                maxAmount,
                minAmount,
                queryID: 0,
                signature,
                tonAmount,
                value: tonAmount + toNano('1')
            }
        );

        var balAfter = await buyer.getBalance();
        var poolBalAfter = await iDOPool.getBalance();
        expect(balBefore - balAfter).toBeLessThanOrEqual(500000000n);
        expect(poolBalBefore - poolBalAfter).toBeLessThanOrEqual(0n);

        expect(swapResult.transactions).toHaveTransaction({
            to: iDOPool.address,
            success: true
        });
        expect(await iDOPool.getTotalUnclaimed()).toBe(tonAmount);
        expect(await iDOPool.getTokenSold()).toBe(tonAmount);
        expect(objectToString(await iDOPool.getPerBuyCurr(zeroAddress))).toEqual(objectToString({
            buyCurrRaised: tonAmount,
            buyCurrRefundedTotal: 0n,
            buyCurrRefundedLeft: 0n,
            buyCurrAddr: zeroAddress,
            buyCurrDecimals: 9,
            buyCurrRate: 1000000000n,
            buyCurrBalance: 0n,
            buyCurrTokenAccountAddr: zeroAddress
        }));
        // expect(swapResult.transactions).toHaveTransaction({
        //     to: fundingWalletAddr,
        //     success: true
        // })
        expect(await iDOPool.getPerUser(buyer.address)).toEqual({
            sellCurrBought: tonAmount,
            sellCurrClaimed: 0n
        });
        expect(await iDOPool.getPerUserPerBuyCurr(buyer.address, zeroAddress)).toEqual({
            sellCurrBought: tonAmount,
            buyCurrSold: tonAmount,
            refundAmount: 0n,
            isRefundClaimed: false
        });

        var balBefore = await poolDeployer.getBalance();
        var poolBalBefore = await iDOPool.getBalance();

        // change close time to move to next phase of pool
        const newCloseTime = Math.floor(Date.now() / 1000) + 2;
        const setCloseTimeResult = await iDOPool.sendSetCloseTime(
            poolDeployer.getSender(),
            {
                queryID: 0,
                value: toNano('1'),
                newCloseTime
            }
        );

        var balAfter = await poolDeployer.getBalance();
        var poolBalAfter = await iDOPool.getBalance();
        expect(balBefore - balAfter).toBeLessThanOrEqual(500000000n);
        expect(poolBalBefore - poolBalAfter).toBeLessThanOrEqual(0n);

        expect(setCloseTimeResult.transactions).toHaveTransaction({
            to: iDOPool.address,
            success: true,
        });
        expect(await iDOPool.getCloseTime()).toBe(newCloseTime);

        while (Math.floor(Date.now() / 1000) <= newCloseTime) {
            await new Promise((resolve) => setTimeout(resolve, 250));
        }

        // ------------------------
        // -------CLAIMING-1-------
        // ------------------------
        const claimAmount = tonAmount - 5n;
        var _signature = sign(
            new Cell()
                .asBuilder()
                .storeAddress(candidate)
                .storeCoins(claimAmount)
                .storeAddress(iDOPool.address)
                .storeUint(0, 32) // workchain id
                .endCell()
                .hash()
                ,
            signer.secretKey
        );
        var signature = BigInt(`0x${_signature.toString('hex')}`);

        var balBefore = await buyer.getBalance();
        var poolBalBefore = await iDOPool.getBalance();

        const claimResult = await iDOPool.sendClaimTokens(
            buyer.getSender(),
            {
                claimAmount,
                queryID: 0,
                signature,
                value: toNano('10')
            }
        );

        var balAfter = await buyer.getBalance();
        var poolBalAfter = await iDOPool.getBalance();
        expect(balBefore - balAfter).toBeLessThanOrEqual(500000000n);
        expect(poolBalBefore - poolBalAfter).toBeLessThanOrEqual(0n);

        expect(claimResult.transactions).toHaveTransaction({
            to: iDOPool.address,
            success: true
        });

        expect(await iDOPool.getTotalUnclaimed()).toBe(tonAmount - claimAmount);
        expect(objectToString(await iDOPool.getPerBuyCurr(zeroAddress))).toEqual(objectToString({
            buyCurrRaised: tonAmount,
            buyCurrRefundedTotal: 0n,
            buyCurrRefundedLeft: 0n,
            buyCurrAddr: zeroAddress,
            buyCurrDecimals: 9,
            buyCurrRate: 1000000000n,
            buyCurrBalance: 0n,
            buyCurrTokenAccountAddr: zeroAddress
        }));
        expect(await iDOPool.getPerUserPerBuyCurr(buyer.address, zeroAddress)).toEqual({
            sellCurrBought: tonAmount,
            buyCurrSold: tonAmount,
            refundAmount: 0n,
            isRefundClaimed: false
        });
        expect(await iDOPool.getPerUser(buyer.address)).toEqual({
            sellCurrBought: tonAmount,
            sellCurrClaimed: claimAmount
        });
        expect(await iDOPool.getTotalUnclaimed()).toBe(tonAmount - claimAmount);
        expect(await iDOPool.getSellTokenAccountBalance()).toBe(1000n - claimAmount);
        expect(claimResult.transactions).toHaveTransaction({
            to: buyerSellMintWallet.address,
            success: true
        });
        expect(await buyerSellMintWallet.getJettonBalance()).toBe(999n + claimAmount);

        // ------------------------
        // -------CLAIMING-2-------
        // ------------------------

        const claimAmount1 = tonAmount - 3n;
        var _signature = sign(
            new Cell()
                .asBuilder()
                .storeAddress(candidate)
                .storeCoins(claimAmount1)
                .storeAddress(iDOPool.address)
                .storeUint(0, 32) // workchain id
                .endCell()
                .hash()
                ,
            signer.secretKey
        );
        var signature = BigInt(`0x${_signature.toString('hex')}`);

        var balBefore = await buyer.getBalance();
        var poolBalBefore = await iDOPool.getBalance();

        const claimResult1 = await iDOPool.sendClaimTokens(
            buyer.getSender(),
            {
                claimAmount: claimAmount1,
                queryID: 0,
                signature,
                value: toNano('10')
            }
        );

        var balAfter = await buyer.getBalance();
        var poolBalAfter = await iDOPool.getBalance();
        expect(balBefore - balAfter).toBeLessThanOrEqual(500000000n);
        expect(poolBalBefore - poolBalAfter).toBeLessThanOrEqual(0n);

        expect(claimResult1.transactions).toHaveTransaction({
            to: iDOPool.address,
            success: true
        });

        expect(await iDOPool.getTotalUnclaimed()).toBe(tonAmount - claimAmount1);
        expect(objectToString(await iDOPool.getPerBuyCurr(zeroAddress))).toEqual(objectToString({
            buyCurrRaised: tonAmount,
            buyCurrRefundedTotal: 0n,
            buyCurrRefundedLeft: 0n,
            buyCurrAddr: zeroAddress,
            buyCurrDecimals: 9,
            buyCurrRate: 1000000000n,
            buyCurrBalance: 0n,
            buyCurrTokenAccountAddr: zeroAddress
        }));
        expect(await iDOPool.getPerUserPerBuyCurr(buyer.address, zeroAddress)).toEqual({
            sellCurrBought: tonAmount,
            buyCurrSold: tonAmount,
            refundAmount: 0n,
            isRefundClaimed: false
        });
        expect(await iDOPool.getPerUser(buyer.address)).toEqual({
            sellCurrBought: tonAmount,
            sellCurrClaimed: claimAmount1
        });
        expect(await iDOPool.getTotalUnclaimed()).toBe(tonAmount - claimAmount1);
        expect(await iDOPool.getSellTokenAccountBalance()).toBe(1000n - claimAmount1);
        expect(claimResult.transactions).toHaveTransaction({
            to: buyerSellMintWallet.address,
            success: true
        });
        expect(await buyerSellMintWallet.getJettonBalance()).toBe(999n + claimAmount1);

    }, 30000);

});
