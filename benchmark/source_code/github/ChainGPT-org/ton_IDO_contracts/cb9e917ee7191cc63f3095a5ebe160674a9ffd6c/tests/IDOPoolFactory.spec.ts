import { Blockchain, SandboxContract, TreasuryContract } from '@ton/sandbox';
import { Address, Cell, toNano } from '@ton/core';
import { IDOPoolFactory } from '../wrappers/IDOPoolFactory';
import { IDOPool } from '../wrappers/IDOPool';
import '@ton/test-utils';
import { compile } from '@ton/blueprint';
import { getSecureRandomBytes, KeyPair, keyPairFromSeed } from '@ton/crypto';
import { objectToString } from '../utils/objectToString';
import { cleanupTransactions } from '../utils/cleanupTransactions';

describe('IDOPoolFactory', () => {
    let factoryCode: Cell;
    let poolCode: Cell;

    beforeAll(async () => {
        factoryCode = await compile('IDOPoolFactory');
        poolCode = await compile('IDOPool');
        const seed: Buffer = await getSecureRandomBytes(32); // Seed is always 32 bytes
        signer = keyPairFromSeed(seed);
    }, 30000);

    let blockchain: Blockchain;
    let deployer: SandboxContract<TreasuryContract>;
    let iDOPoolFactory: SandboxContract<IDOPoolFactory>;
    let signer: KeyPair;

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

        deployer = await blockchain.treasury('poolDeployer');

        const deployResult = await iDOPoolFactory.sendDeploy(deployer.getSender(), toNano('0.1'));

        expect(deployResult.transactions).toHaveTransaction({
            from: deployer.address,
            to: iDOPoolFactory.address,
            deploy: true,
            success: true,
        });
    }, 30000);

    it('should deploy', async () => {
        // the check is done inside beforeEach
        // blockchain and iDOPoolFactory are ready to use
    }, 30000);

    it('should deploy pool and pool should have correct values set', async () => {
        const poolDeployer = await blockchain.treasury('poolDeployer');
        console.log('deployer address', poolDeployer.getSender());

        const sellTokenMintAddr = Address.parseFriendly('kQAiboDEv_qRrcEdrYdwbVLNOXBHwShFbtKGbQVJ2OKxY_Di').address;
        const factoryAddress = iDOPoolFactory.address;
        const signerAddr = BigInt('0x'+signer.publicKey.toString('hex'));
        const fundingWalletAddr = Address.parseFriendly('0QCHsFtsC4beido0MlfuI8fBEsLt6MMQzswAC1K6YsYGAF0R').address;
        const openTime = Math.floor(Date.now() / 1000);
        const duration = 1000;
        const buyCurrAddr = (await blockchain.treasury('buyCurrency')).address;
        const buyCurrDecimals = 14;
        const buyCurrRate = 28093824903n;
        const buyCurrTokenAccountAddr: Address = poolDeployer.address; // No need for these to be proper as these are not tested
        const sellTokenAccountAddr: Address = poolDeployer.address; // No need for these to be proper as these are not tested

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

        var contractBalBefore = await iDOPoolFactory.getBalance();
        var balBefore = await poolDeployer.getBalance();

        {
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

            expect(createResult.transactions).toHaveTransaction({
                from: poolDeployer.address,
                to: iDOPoolFactory.address,
                success: true,
            });

            expect(createResult.transactions).toHaveTransaction({
                from: iDOPoolFactory.address,
                to: _iDOPoolAddress,
                deploy: true,
                success: true,
            });
        }

        var contractBalAfter = await iDOPoolFactory.getBalance();
        var balAfter = await poolDeployer.getBalance();
        expect(balBefore - balAfter).toBeLessThan(500000000n);
        expect(contractBalBefore - contractBalAfter).toBeLessThanOrEqual(0n);

        expect(await iDOPoolFactory.getPoolCount()).toBe(1);

        const iDOPoolAddress = await iDOPoolFactory.getPoolAddress(0);
        if (!iDOPoolAddress) {
            console.log('IDO Pool Address came out null');
            return;
        }

        expect(iDOPoolAddress.toString()).toBe(_iDOPoolAddress.toString());

        const iDOPool = blockchain.openContract(IDOPool.createFromAddress(iDOPoolAddress));

        expect((await iDOPoolFactory.getPoolAddress(0))?.toString()).toBe(iDOPool.address.toString());
        expect(await iDOPoolFactory.getPoolAddress(1)).toBe(null);
        expect(await iDOPool.getId()).toBe((await iDOPoolFactory.getPoolCount()) - 1);
        expect(((await iDOPool.getFactory()) || '').toString()).toBe(factoryAddress.toString());
        expect(((await iDOPool.getOwner()) || '').toString()).toBe(poolDeployer.address.toString());
        expect(((await iDOPool.getSigner()) || '').toString()).toBe(signerAddr.toString());
        expect((await iDOPool.getOpenTime()).toString()).toBe(openTime.toString());
        expect((await iDOPool.getCloseTime()).toString()).toBe((openTime + duration).toString());
        expect(((await iDOPool.getSellTokenMint()) || '').toString()).toBe(sellTokenMintAddr.toString());
        expect((await iDOPool.getSellTokenAccountAddr())?.toString()).toEqual(sellTokenAccountAddr.toString());
        expect(await iDOPool.getSellTokenAccountBalance()).toBe(0n);
        expect(((await iDOPool.getFundingWallet()) || '').toString()).toBe(fundingWalletAddr.toString());
        expect(await iDOPool.getTokenSold()).toBe(0n);
        expect(await iDOPool.getTotalUnclaimed()).toBe(0n);
        expect(await iDOPool.getTotalRefunded()).toBe(0n);
        expect(objectToString(await iDOPool.getPerBuyCurr(buyCurrAddr))).toEqual(
        objectToString({
            buyCurrRaised: 0n,
            buyCurrRefundedTotal: 0n,
            buyCurrRefundedLeft: 0n,
            buyCurrAddr,
            buyCurrDecimals,
            buyCurrRate,
            buyCurrBalance: 0n,
            buyCurrTokenAccountAddr,
        }));
        expect(await iDOPool.getPerUserPerBuyCurr(poolDeployer.address, poolDeployer.address)).toEqual({
            buyCurrSold: 0n,
            isRefundClaimed: false,
            refundAmount: 0n,
            sellCurrBought: 0n,
        });
        expect(await iDOPool.getPerUser(poolDeployer.address)).toEqual({
            sellCurrBought: 0n,
            sellCurrClaimed: 0n,
        });
    }, 30000);

});
