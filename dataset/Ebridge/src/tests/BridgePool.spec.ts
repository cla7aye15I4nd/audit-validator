import {Blockchain, BlockchainSnapshot, SandboxContract, TreasuryContract} from '@ton/sandbox';
import {Address, beginCell, BitString, Cell, Dictionary, toNano} from '@ton/core';
import {BridgePool} from '../wrappers/BridgePool';
import '@ton/test-utils';
import {compile} from '@ton/blueprint';
import {randomAddress} from "@ton/test-utils";
import {JettonMinter} from "../wrappers/JettonMinter";
import {JettonWallet} from "../wrappers/JettonWallet";
import {Buffer} from "buffer";
import {BridgeReceiptAccount} from "../wrappers/BridgeReceiptAccount";
import {BridgePoolLiquidityAccount} from "../wrappers/BridgePoolLiquidityAccount";
import aelf from "aelf-sdk";
import exp from "constants";


describe('BridgePool', () => {
    let code: Cell;
    let blockchain: Blockchain;
    let deployer: SandboxContract<TreasuryContract>;
    let bridgePool: SandboxContract<BridgePool>;
    let jwallet_code: Cell;
    let minter_code: Cell;
    let jettonMinter: SandboxContract<JettonMinter>;
    let jettonWallet: SandboxContract<JettonWallet>;
    let userWallet: any;
    let defaultContent: Cell;
    let testAccount: SandboxContract<TreasuryContract>
    let testJettonAddress: Address;
    let testJettonAddress1: Address;
    let swap: SandboxContract<TreasuryContract>;
    let bridge: SandboxContract<TreasuryContract>;
    let admin: SandboxContract<TreasuryContract>;
    let owner: SandboxContract<TreasuryContract>;
    let tempUpgrade: Cell;
    let bridgeReceiptAccountCode: Cell;
    let bridgeLiquidityAccountCode: Cell;
    let initialState: BlockchainSnapshot;
    let curTime: number;
    const chainId = 9992731;
    let bridgePoolTonCoin: SandboxContract<BridgePool>;
    let HOLEADDRESS: Address;


    beforeAll(async () => {
        code = await compile('BridgePool');
        bridgeReceiptAccountCode = await compile('BridgeReceiptAccount');
        bridgeLiquidityAccountCode = await compile('BridgePoolLiquidityAccount');
        jwallet_code = await compile('JettonWallet');
        minter_code = await compile('JettonMinter');

        blockchain = await Blockchain.create();

        curTime = blockchain.now ?? Math.floor(Date.now() / 1000);

        testJettonAddress1 = randomAddress();
        testJettonAddress = randomAddress();

        swap = await blockchain.treasury('BridgeSwap');
        bridge = await blockchain.treasury('Bridge');
        admin = await blockchain.treasury('admin');
        owner = await blockchain.treasury('admin');
        HOLEADDRESS = Address.parse("EQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAM9c");

        tempUpgrade = beginCell().endCell();
        // let dailyLimit = Dictionary.empty(Dictionary.Keys.BigUint(256),Dictionary.Values.Cell());
        let dic = Dictionary.empty(Dictionary.Keys.BigUint(256), Dictionary.Values.Cell());

        // let rateLimit = Dictionary.empty(Dictionary.Keys.BigUint(256),Dictionary.Values.Cell());
        // let key = BridgePool.PackLimitKey(chainId,0);
        // let value = BridgePool.PackDailyLimitValue(chainId,0,curTime,BigInt(1000000000000000000));
        // dailyLimit.set(key,value);
        // let rate_value = BridgePool.PackRateLimitValue(chainId,0,curTime,true,BigInt(1000000000000000),BigInt(1000000000));
        // rateLimit.set(key,rate_value);


        deployer = await blockchain.treasury('deployer');
        testAccount = await blockchain.treasury('testAccount');

        // jetton
        defaultContent = beginCell().endCell();
        jettonMinter = blockchain.openContract(
            await JettonMinter.createFromConfig(
                {
                    admin: deployer.address,
                    content: defaultContent,
                    wallet_code: jwallet_code,
                },
                minter_code));
        userWallet = async (address: Address) => blockchain.openContract(
            JettonWallet.createFromAddress(
                await jettonMinter.getWalletAddress(address)
            )
        );

        const deployMockJettonMinter = await jettonMinter.sendDeploy(deployer.getSender(), toNano('1'));

        expect(deployMockJettonMinter.transactions).toHaveTransaction({
            from: deployer.address,
            to: jettonMinter.address,
            deploy: true,
        });

        bridgePool = blockchain.openContract(BridgePool.createFromConfig({
            bridge_address: bridge.address,
            bridge_receipt_account_code: bridgeReceiptAccountCode,
            bridge_swap_address: swap.address,
            jetton_address: testJettonAddress,
            daily_limit: dic,
            rate_limit: dic,
            pool_liquidity_account_code: bridgeLiquidityAccountCode,
            admin: admin.address,
            owner: owner.address,
            temp_upgrade: tempUpgrade
        }, code));

        const deployResult = await bridgePool.sendDeploy(deployer.getSender(), toNano('0.1'));

        expect(deployResult.transactions).toHaveTransaction({
            from: deployer.address,
            to: bridgePool.address,
            deploy: true,
            success: true,
        });

        const deployerJettonWallet = await userWallet(deployer.address);
        const accountJettonWallet = await userWallet(testAccount.address);
        const bridgeJettonWallet = await userWallet(bridge.address);

        // first mint some jettons to test account
        let initialTotalSupply = await jettonMinter.getTotalSupply();
        let initialJettonBalance = toNano('1000.23');

        const mintResult = await jettonMinter.sendMint(
            deployer.getSender(),
            bridge.address,
            initialJettonBalance,
            toNano('0.05'),
            toNano('1'));

        expect(mintResult.transactions).toHaveTransaction({
            from: jettonMinter.address,
            to: bridgeJettonWallet.address,
            deploy: true,
        });
        expect(mintResult.transactions).toHaveTransaction({ // excesses
            from: bridgeJettonWallet.address,
            to: jettonMinter.address
        });
        expect(await bridgeJettonWallet.getJettonBalance()).toEqual(initialJettonBalance);
        expect(await jettonMinter.getTotalSupply()).toEqual(initialTotalSupply + initialJettonBalance);

        let res = await bridgePool.sendSetBridge(admin.getSender(), toNano('0.5'), bridge.address);
        expect(res.transactions).toHaveTransaction({
            from: admin.address,
            to: bridgePool.address,
            success: true,
        });
        const bridge1 = await bridgePool.getBridgeAddress();
        expect(bridge1).toEqualAddress(bridge.address);
        const bridgePoolJettonWallet = await userWallet(bridgePool.address);

        let res1 = await bridgePool.sendSetJetton(
            admin.getSender(), toNano('0.5'), jettonMinter.address, bridgePoolJettonWallet.address);
        expect(res1.transactions).toHaveTransaction({
            from: admin.address,
            to: bridgePool.address,
            success: true,
        });

        let refreshTime = getUTCMidnight();
        let result = await bridgePool.sendSetDailyLimit(
            admin.getSender(),
            toNano('0.5'),
            [{
                chainId: chainId,
                limitType: 0,
                refreshTime: refreshTime,
                dailyLimit: 100000000000000000n
            }]
        );
        expect(result.transactions).toHaveTransaction({
            from: admin.address,
            to: bridgePool.address,
            success: true,
        });

        let result1 = await bridgePool.sendSetRateLimit(
            admin.getSender(),
            toNano('0.5'),
            [{
                chainId: chainId,
                limitType: 0,
                tokenCapacity: 1000000000000000n,
                rate: 1000000000n,
            }]);
        expect(result1.transactions).toHaveTransaction({
            from: admin.address,
            to: bridgePool.address,
            success: true,
        });

        let result2 = await bridgePool.sendSetDailyLimit(admin.getSender(),
            toNano('0.5'),
            [{
                chainId: chainId,
                limitType: 1,
                refreshTime: refreshTime,
                dailyLimit: 100000000000000000n
            }]);
        expect(result2.transactions).toHaveTransaction({
            from: admin.address,
            to: bridgePool.address,
            success: true,
        });

        let result3 = await bridgePool.sendSetRateLimit(
            admin.getSender(), toNano('0.5'),
            [{
                chainId: chainId,
                limitType: 1,
                tokenCapacity: 1000000000000000n,
                rate: 1000000000n,
            }]);
        expect(result3.transactions).toHaveTransaction({
            from: admin.address,
            to: bridgePool.address,
            success: true,
        });
        bridgePoolTonCoin = blockchain.openContract(BridgePool.createFromConfig({
            bridge_address: bridge.address,
            bridge_receipt_account_code: bridgeReceiptAccountCode,
            bridge_swap_address: swap.address,
            jetton_address: HOLEADDRESS,
            daily_limit: dic,
            rate_limit: dic,
            pool_liquidity_account_code: bridgeLiquidityAccountCode,
            admin: admin.address,
            owner: owner.address,
            temp_upgrade: tempUpgrade
        }, code));
        const deployPoolTonCoinResult = await bridgePoolTonCoin.sendDeploy(deployer.getSender(), toNano('0.1'));

        expect(deployPoolTonCoinResult.transactions).toHaveTransaction({
            from: deployer.address,
            to: bridgePoolTonCoin.address,
            deploy: true,
            success: true,
        });

        let res11 = await bridgePoolTonCoin.sendSetBridge(admin.getSender(), toNano('0.5'), bridge.address);
        expect(res11.transactions).toHaveTransaction({
            from: admin.address,
            to: bridgePoolTonCoin.address,
            success: true,
        });

        initialState = blockchain.snapshot();

    });

    afterEach(async () => await blockchain.loadFrom(initialState));


    it('should deploy', async () => {
        // the check is done inside beforeEach
        // blockchain and ebridgeContractsTon are ready to use
    });
    it('get_admin', async () => {
        const res = await bridgePool.getAdmin();
        expect(res).toEqualAddress(admin.address);
    });

    it('set receipt daily limit', async () => {
        let refreshTime = getUTCMidnight();
        let result = await bridgePool.sendSetDailyLimit(
            admin.getSender(),
            toNano('0.5'),
            [{
                chainId: chainId,
                limitType: 0,
                refreshTime: refreshTime,
                dailyLimit: 100000000000000000n
            },
                {
                    chainId: chainId,
                    limitType: 1,
                    refreshTime: refreshTime,
                    dailyLimit: 100000000000000000n
                }]);
        expect(result.transactions).toHaveTransaction({
            from: admin.address,
            to: bridgePool.address,
            success: true,
        });

        // let body = result.transactions[1].outMessages.get(0)?.body;
        // if (body != undefined) {
        //     let limitInfo = body.asSlice();
        //     let chainIdLog = limitInfo.loadUint(32);
        //     let limitType = limitInfo.loadUint(1);
        //     let value = limitInfo.loadUintBig(256);
        //     let refreshTime = limitInfo.loadUint(64);
        //     let dailyLimit = limitInfo.loadUintBig(256);
        //     expect(chainIdLog).toBe(chainId);
        //     expect(limitType).toBe(0);
        //     expect(value).toBe(100000000000000000n);
        //     expect(refreshTime).toBe(refreshTime);
        //     expect(dailyLimit).toBe(100000000000000000n);
        // }
        //
        // let body1 = result.transactions[1].outMessages.get(1)?.body;
        // if (body1 != undefined) {
        //     let limitInfo = body1.asSlice();
        //     let chainIdLog = limitInfo.loadUint(32);
        //     let limitType = limitInfo.loadUint(1);
        //     let value = limitInfo.loadUintBig(256);
        //     let refreshTime = limitInfo.loadUint(64);
        //     let dailyLimit = limitInfo.loadUintBig(256);
        //     expect(chainIdLog).toBe(chainId);
        //     expect(limitType).toBe(1);
        //     expect(value).toBe(100000000000000000n);
        //     expect(refreshTime).toBe(refreshTime);
        //     expect(dailyLimit).toBe(100000000000000000n);
        // }

        const res = await bridgePool.getReceiptDailyLimit(chainId);
        expect(res.remainToken).toBe(BigInt(100000000000000000));
        console.log(res.refreshTime);
        expect(res.dailyLimit).toBe(BigInt(100000000000000000));
        const res1 = await bridgePool.getSwapDailyLimit(chainId);
        expect(res1.remainToken).toBe(BigInt(100000000000000000));
        console.log(res1.refreshTime);
        expect(res1.dailyLimit).toBe(BigInt(100000000000000000));
    });

    it('set swap rate limit', async () => {
        let result = await bridgePool.sendSetRateLimit(
            admin.getSender(), toNano('0.5'),
            [{
                chainId: chainId,
                limitType: 1,
                tokenCapacity: BigInt(1000000000000000),
                rate: BigInt(1000000000),
            }]);
        expect(result.transactions).toHaveTransaction({
            from: admin.address,
            to: bridgePool.address,
            success: true,
        });

        let body = result.transactions[1].outMessages.get(0)?.body;
        if (body != undefined) {
            let limitInfo = body.asSlice();
            let op = limitInfo.loadUint(32);
            let chainIdLog = limitInfo.loadUint(32);
            let limitType = limitInfo.loadUint(1);
            let valueInfo = limitInfo.loadRef().asSlice();
            let value = valueInfo.loadUintBig(256);
            let tokenCapacity = valueInfo.loadUintBig(256);
            let status = valueInfo.loadBoolean();
            let rate = valueInfo.loadUintBig(256);
            expect(chainIdLog).toBe(chainId);
            expect(limitType).toBe(1);
            expect(value).toBe(1000000000000000n);
            expect(tokenCapacity).toBe(1000000000000000n);
            expect(status).toBe(true);
            expect(rate).toBe(1000000000n);
        }

        const res = await bridgePool.getSwapRateLimit(chainId);
        expect(res.currentTokenAmount).toBe(BigInt(1000000000000000));
        expect(res.tokenCapacity).toBe(BigInt(1000000000000000));
        expect(res.rate).toBe(BigInt(1000000000));
        expect(res.isEnable).toBe(true);
    });

    it('set bridge swap', async () => {
        const res = await bridgePool.getBridgeSwapAddress();
        expect(res).toEqualAddress(swap.address);

        let new_swap = randomAddress();
        let result = await bridgePool.sendSetBridgeSwap(admin.getSender(),
            toNano('0.5'), new_swap);
        expect(result.transactions).toHaveTransaction({
            from: admin.address,
            to: bridgePool.address,
            success: true,
        });
        const res1 = await bridgePool.getBridgeSwapAddress();
        expect(res1).toEqualAddress(new_swap);
    });

    it('lock', async () => {
        const res1 = await bridgePool.getReceiptDailyLimit(chainId);
        expect(res1.remainToken).toBe(BigInt(100000000000000000));
        console.log(res1.refreshTime);
        expect(res1.dailyLimit).toBe(BigInt(100000000000000000));

        const res2 = await bridgePool.getReceiptRateLimit(chainId);
        expect(res2.currentTokenAmount).toBe(BigInt(1000000000000000));
        expect(res2.tokenCapacity).toBe(BigInt(1000000000000000));
        expect(res2.rate).toBe(BigInt(1000000000));
        expect(res2.isEnable).toBe(true);

        let targetAddress = "JKjoabe2wyrdP1P8TvNyD4GZP6z1PuMvU2y5yJ4JTeBjTMAoX";
        const targetAddressBuffer = aelf.utils.base58.decode(targetAddress);

        // first test account wallet - transfer
        const bridgeJettonWallet = await userWallet(bridge.address);
        const bridgePoolJettonWallet = await userWallet(bridgePool.address);

        let liquidityBefore = await bridgePool.getPoolLiquidity();
        expect(liquidityBefore).toBe(BigInt(0));
        let initialJettonBalance = await bridgeJettonWallet.getJettonBalance();
        expect(initialJettonBalance).toEqual(toNano('1000.23'));
        let lock_amount = toNano('10');
        let forwardAmount = toNano('0.1');
        let payload = BridgePool.packLockBody(chainId, targetAddressBuffer, testAccount.address);
        const result = await bridgeJettonWallet.sendTransfer(
            bridge.getSender(),
            toNano('2'),
            lock_amount,
            bridgePool.address,
            bridge.address,
            null,
            forwardAmount,
            payload);
        expect(result.transactions).toHaveTransaction({
            from: bridgeJettonWallet.address,
            to: bridgePoolJettonWallet.address,
            success: true,
        });

        expect(result.transactions).toHaveTransaction({
            from: bridgePoolJettonWallet.address,
            to: bridgePool.address,
            success: true,
        });


        let balance = await bridgeJettonWallet.getJettonBalance();
        expect(balance).toEqual(toNano('990.23'));
        let balance1 = await bridgePoolJettonWallet.getJettonBalance();
        expect(balance1).toEqual(toNano('10'));

        console.log(result.transactions[4].outMessages.get(0)?.body);
        let body = result.transactions[4].outMessages.get(0)?.body;
        console.log(testAccount.address);
        if (body != undefined) {
            let lockInfo = body.asSlice();
            let address = lockInfo.loadUint(32);
            console.log(address);
        }
        let liquidityAfter = await bridgePool.getPoolLiquidity();
        expect(liquidityAfter).toBe(BigInt(10000000000));

        const res3 = await bridgePool.getReceiptDailyLimit(chainId);
        expect(res3.remainToken).toBe(BigInt(100000000000000000 - 10000000000));
        console.log(res3.refreshTime);
        expect(res3.dailyLimit).toBe(BigInt(100000000000000000));

        const res4 = await bridgePool.getReceiptRateLimit(chainId);
        expect(res4.currentTokenAmount).toBe(BigInt(1000000000000000 - 10000000000));
        expect(res4.tokenCapacity).toBe(BigInt(1000000000000000));
        expect(res4.rate).toBe(BigInt(1000000000));
        expect(res4.isEnable).toBe(true);

        const bridgeReceiptAddress = await bridgePool.getReceiptAddress(testAccount.address);
        console.log(bridgeReceiptAddress);

        expect(result.transactions).toHaveTransaction({
            from: bridgePool.address,
            to: bridgeReceiptAddress,
            deploy: true,
            success: true
        });

        expect(result.transactions).toHaveTransaction({
            from: bridgeReceiptAddress,
            to: bridge.address,
            success: true
        });

        let bridgeReceiptAccount = blockchain.openContract(
            BridgeReceiptAccount.createFromAddress(bridgeReceiptAddress));
        let receipt = await bridgeReceiptAccount.getReceiptInfo(chainId);
        expect(receipt.totalAmount).toBe(toNano('10'));
        expect(receipt.index).toBe(BigInt(1));


    });

    it('add liquidity', async () => {
        // mint first 
        // testAccount add liquidity
        const testAccountJettonWallet = await userWallet(testAccount.address);
        const bridgePoolJettonWallet = await userWallet(bridgePool.address);

        let mintAmount = toNano('999.99');

        const mintResult = await jettonMinter.sendMint(
            deployer.getSender(),
            testAccount.address,
            mintAmount,
            toNano('0.05'),
            toNano('1'));

        expect(mintResult.transactions).toHaveTransaction({
            from: jettonMinter.address,
            to: testAccountJettonWallet.address,
            deploy: true,
        });
        expect(mintResult.transactions).toHaveTransaction({ // excesses
            from: testAccountJettonWallet.address,
            to: jettonMinter.address
        });


        expect(await testAccountJettonWallet.getJettonBalance()).toEqual(mintAmount);

        let liquidityBefore = await bridgePool.getPoolLiquidity();
        expect(liquidityBefore).toBe(BigInt(0));

        let amount_add_liquidity = toNano('10');
        let forwardAmount = toNano('0.05');
        let payload = BridgePool.packAddLiquidityBody();
        const result = await testAccountJettonWallet.sendTransfer(
            testAccount.getSender(),
            toNano('2'),
            amount_add_liquidity,
            bridgePool.address,
            testAccount.address,
            null,
            forwardAmount,
            payload);

        expect(result.transactions).toHaveTransaction({
            from: testAccountJettonWallet.address,
            to: bridgePoolJettonWallet.address,
            success: true,
        });

        expect(result.transactions).toHaveTransaction({
            from: bridgePoolJettonWallet.address,
            to: bridgePool.address,
            success: true,
        });
        const res = await bridgePool.getPoolLiquidityAccountAddress(testAccount.address);
        expect(result.transactions).toHaveTransaction({
            from: bridgePool.address,
            to: res,
            deploy: true,
            success: true,
        });

        let liquidityAfter = await bridgePool.getPoolLiquidity();
        expect(liquidityAfter).toBe(BigInt(10000000000));
        expect(await testAccountJettonWallet.getJettonBalance()).toEqual(mintAmount - amount_add_liquidity);
        expect(await bridgePoolJettonWallet.getJettonBalance()).toEqual(amount_add_liquidity);

    });

    it('add native liquidity', async () => {
        let res = await bridgePoolTonCoin.sendAddNativeLiquidity(testAccount.getSender(), toNano('20.05'), toNano('20'));
        expect(res.transactions).toHaveTransaction({
            from: testAccount.address,
            to: bridgePoolTonCoin.address,
            success: true,
        });
        const liquidityAccountAddress = await bridgePoolTonCoin.getPoolLiquidityAccountAddress(testAccount.address);
        expect(res.transactions).toHaveTransaction({
            from: bridgePoolTonCoin.address,
            to: liquidityAccountAddress,
            success: true,
            deploy: true
        });
        let liquidityAfter = await bridgePoolTonCoin.getPoolLiquidity();
        expect(liquidityAfter).toBe(toNano('20'));
        let balance = (await blockchain.getContract(bridgePoolTonCoin.address)).balance;
        expect(balance).toBeGreaterThanOrEqual(toNano('20'));
        let liquidityAccount = blockchain.openContract(BridgePoolLiquidityAccount.createFromAddress(liquidityAccountAddress));
        let liquidity = await liquidityAccount.getLiquidity();
        expect(liquidity.owner).toEqualAddress(testAccount.address);
        expect(liquidity.liquidity).toBe(toNano('20'));
    });

    it('remove native liquidity', async () => {
        let res = await bridgePoolTonCoin.sendAddNativeLiquidity(testAccount.getSender(), toNano('20.05'), toNano('20'));
        expect(res.transactions).toHaveTransaction({
            from: testAccount.address,
            to: bridgePoolTonCoin.address,
            success: true,
        });
        let poolLiquidityBefore = (await blockchain.getContract(bridgePoolTonCoin.address)).balance;
        expect(poolLiquidityBefore).toBeGreaterThanOrEqual(toNano('20'));
        let userLiquidityAddress = await bridgePoolTonCoin.getPoolLiquidityAccountAddress(testAccount.address);
        let user_liq = blockchain.openContract(
            BridgePoolLiquidityAccount.createFromAddress(userLiquidityAddress));
        let liquidity = await user_liq.getLiquidity();
        expect(liquidity.owner).toEqualAddress(testAccount.address);
        expect(liquidity.bridgePoolAddress).toEqualAddress(bridgePoolTonCoin.address);
        expect(liquidity.jettonAddress).toEqualAddress(HOLEADDRESS);
        expect(liquidity.liquidity).toBe(toNano('20'));
        let account_before = await testAccount.getBalance();

        let remove_result = await user_liq.sendRemoveLiquidity(
            testAccount.getSender(),
            toNano('0.05'),
            toNano('1'),
            true
        );
        expect(remove_result.transactions).toHaveTransaction({
            from: testAccount.address,
            to: userLiquidityAddress,
            success: true,
        });
        expect(remove_result.transactions).toHaveTransaction({
            from: userLiquidityAddress,
            to: bridgePoolTonCoin.address,
            success: true,
        });
        liquidity = await user_liq.getLiquidity();
        expect(liquidity.liquidity).toBe(toNano('19'));
        let poolLiquidityAfter = (await blockchain.getContract(bridgePoolTonCoin.address)).balance;
        expect(poolLiquidityAfter).toBeGreaterThanOrEqual(toNano('19'));
        expect(poolLiquidityAfter).toBeLessThanOrEqual(poolLiquidityBefore);
        let liquidityAfter1 = await bridgePoolTonCoin.getPoolLiquidity();
        expect(liquidityAfter1).toBe(toNano('19'));
        let account_after = await testAccount.getBalance();
        // expect(account_after - account_before).toBeGreaterThanOrEqual(toNano('1'));
    });

    it('remove liquidity', async () => {
        // mint first 
        // testAccount add liquidity
        const testAccountJettonWallet = await userWallet(testAccount.address);
        const bridgePoolJettonWallet = await userWallet(bridgePool.address);

        let mintAmount = toNano('999.99');

        const mintResult = await jettonMinter.sendMint(
            deployer.getSender(),
            testAccount.address,
            mintAmount,
            toNano('0.05'),
            toNano('1'));

        expect(mintResult.transactions).toHaveTransaction({
            from: jettonMinter.address,
            to: testAccountJettonWallet.address,
            deploy: true,
        });
        expect(mintResult.transactions).toHaveTransaction({ // excesses
            from: testAccountJettonWallet.address,
            to: jettonMinter.address
        });
        expect(await testAccountJettonWallet.getJettonBalance()).toEqual(mintAmount);

        let liquidityBefore = await bridgePool.getPoolLiquidity();
        expect(liquidityBefore).toBe(BigInt(0));

        let amount_add_liquidity = toNano('10');
        let forwardAmount = toNano('0.05');
        let payload = BridgePool.packAddLiquidityBody();
        const result = await testAccountJettonWallet.sendTransfer(
            testAccount.getSender(),
            toNano('2'),
            amount_add_liquidity,
            bridgePool.address,
            testAccount.address,
            null,
            forwardAmount,
            payload);

        expect(result.transactions).toHaveTransaction({
            from: testAccountJettonWallet.address,
            to: bridgePoolJettonWallet.address,
            success: true,
        });

        expect(result.transactions).toHaveTransaction({
            from: bridgePoolJettonWallet.address,
            to: bridgePool.address,
            success: true,
        });
        const userLiquidityAddress = await bridgePool.getPoolLiquidityAccountAddress(testAccount.address);
        expect(result.transactions).toHaveTransaction({
            from: bridgePool.address,
            to: userLiquidityAddress,
            deploy: true,
            success: true,
        });

        let liquidityAfter = await bridgePool.getPoolLiquidity();
        expect(liquidityAfter).toBe(BigInt(10000000000));
        expect(await testAccountJettonWallet.getJettonBalance()).toEqual(mintAmount - amount_add_liquidity);
        expect(await bridgePoolJettonWallet.getJettonBalance()).toEqual(amount_add_liquidity);

        let user_liq = blockchain.openContract(
            BridgePoolLiquidityAccount.createFromAddress(userLiquidityAddress));
        let liquidity = await user_liq.getLiquidity();
        expect(liquidity.owner).toEqualAddress(testAccount.address);
        expect(liquidity.bridgePoolAddress).toEqualAddress(bridgePool.address);
        expect(liquidity.jettonAddress).toEqualAddress(jettonMinter.address);
        expect(liquidity.liquidity).toBe(BigInt(10000000000));

        console.log(testAccount.address);
        console.log(userLiquidityAddress);
        console.log(bridgePool.address);

        let remove_result = await user_liq.sendRemoveLiquidity(
            testAccount.getSender(),
            toNano('0.5'),
            toNano('1')
        );
        expect(remove_result.transactions).toHaveTransaction({
            from: testAccount.address,
            to: userLiquidityAddress,
            success: true,
        });

        expect(remove_result.transactions).toHaveTransaction({
            from: userLiquidityAddress,
            to: bridgePool.address,
            success: true,
        });
        let liquidityAfter1 = await bridgePool.getPoolLiquidity();
        expect(liquidityAfter1).toBe(BigInt(10000000000 - 1000000000));
        expect(await testAccountJettonWallet.getJettonBalance()).toEqual(mintAmount - amount_add_liquidity + toNano('1'));
        expect(await bridgePoolJettonWallet.getJettonBalance()).toEqual(amount_add_liquidity - toNano('1'));

    });

    it('release', async () => {
        // mint first 
        // testAccount add liquidity
        const testAccountJettonWallet = await userWallet(testAccount.address);
        const bridgePoolJettonWallet = await userWallet(bridgePool.address);

        let mintAmount = toNano('999.99');

        const mintResult = await jettonMinter.sendMint(
            deployer.getSender(),
            testAccount.address,
            mintAmount,
            toNano('0.05'),
            toNano('1'));

        expect(mintResult.transactions).toHaveTransaction({
            from: jettonMinter.address,
            to: testAccountJettonWallet.address,
            deploy: true,
        });
        expect(mintResult.transactions).toHaveTransaction({ // excesses
            from: testAccountJettonWallet.address,
            to: jettonMinter.address
        });
        expect(await testAccountJettonWallet.getJettonBalance()).toEqual(mintAmount);

        let liquidityBefore = await bridgePool.getPoolLiquidity();
        expect(liquidityBefore).toBe(BigInt(0));

        let amount_add_liquidity = toNano('10');
        let forwardAmount = toNano('0.05');
        let payload = BridgePool.packAddLiquidityBody();
        const result = await testAccountJettonWallet.sendTransfer(
            testAccount.getSender(),
            toNano('2'),
            amount_add_liquidity,
            bridgePool.address,
            testAccount.address,
            null,
            forwardAmount,
            payload);

        expect(result.transactions).toHaveTransaction({
            from: testAccountJettonWallet.address,
            to: bridgePoolJettonWallet.address,
            success: true,
        });

        expect(result.transactions).toHaveTransaction({
            from: bridgePoolJettonWallet.address,
            to: bridgePool.address,
            success: true,
        });
        const res = await bridgePool.getPoolLiquidityAccountAddress(testAccount.address);
        expect(result.transactions).toHaveTransaction({
            from: bridgePool.address,
            to: res,
            deploy: true,
            success: true,
        });

        expect(await testAccountJettonWallet.getJettonBalance()).toEqual(mintAmount - amount_add_liquidity);

        let liquidityAfter = await bridgePool.getPoolLiquidity();
        expect(liquidityAfter).toBe(BigInt(10000000000));

        let receiptHash = "232bae4714830a2457e91d83365d8cc1362f214bb57fe4923c8765cdca36ab17";
        let receiptHashBuffer = Buffer.from(receiptHash, 'hex');

        let releaseResult = await bridgePool.sendRelease(
            swap.getSender(), toNano('0.5'),
            beginCell().storeUint(111, 256).endCell(),
            beginCell().storeUint(222, 256).storeUint(1, 256).endCell(),
            receiptHashBuffer,
            testAccount.address,
            chainId);

        expect(releaseResult.transactions).toHaveTransaction({
            from: swap.address,
            to: bridgePool.address,
            success: true,
        });
        expect(releaseResult.transactions).toHaveTransaction({
            from: bridgePool.address,
            to: bridgePoolJettonWallet.address,
            success: true,
        });
        expect(releaseResult.transactions).toHaveTransaction({
            from: bridgePoolJettonWallet.address,
            to: testAccountJettonWallet.address,
            success: true,
        });

        expect(releaseResult.transactions).toHaveTransaction({
            from: bridgePool.address,
            to: swap.address,
            success: true,
        });
        let liquidityAfter1 = await bridgePool.getPoolLiquidity();
        expect(liquidityAfter1).toBe(BigInt(10000000000 - 1000000000));
        expect(await testAccountJettonWallet.getJettonBalance()).toEqual(mintAmount - amount_add_liquidity + toNano('1'));
        expect(await bridgePoolJettonWallet.getJettonBalance()).toEqual(amount_add_liquidity - toNano('1'));

    });

    it('get_liquidity_account', async () => {
        const res = await bridgePool.getPoolLiquidityAccountAddress(owner.address);
        console.log(res.toRawString());
    });
});

function getUTCMidnight(): number {
    const now = new Date();
    // Create a new Date object for today's midnight in UTC
    let time = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate());
    console.log(time);
    return time / 1000;
}
