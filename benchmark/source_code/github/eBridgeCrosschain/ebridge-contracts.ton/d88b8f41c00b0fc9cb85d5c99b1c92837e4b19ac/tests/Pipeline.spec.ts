import {Blockchain, BlockchainSnapshot, SandboxContract, TreasuryContract} from '@ton/sandbox';
import {Address, beginCell, BitString, Cell, Dictionary, storeStateInit, toNano, Transaction} from '@ton/core';
import {Bridge} from '../wrappers/Bridge';
import {BridgePool} from '../wrappers/BridgePool';
import {BridgeSwap} from '../wrappers/BridgeSwap';
import '@ton/test-utils';
import {compile} from '@ton/blueprint';
import {Buffer} from "buffer";
import {JettonMinter} from "../wrappers/JettonMinter";
import {JettonWallet} from "../wrappers/JettonWallet";
import {BridgeReceiptAccount} from "../wrappers/BridgeReceiptAccount";
import {BridgePoolLiquidityAccount} from "../wrappers/BridgePoolLiquidityAccount";
import aelf from "aelf-sdk";
import {
    computedGeneric,
    GasPrices,
    StorageValue,
    MsgPrices,
    getMsgPrices,
    getGasPrices,
    getStoragePrices, computeGasFee, collectCellStats, computeMessageForwardFees
} from "../wrappers/gasUtils";
import {findTransactionRequired} from "@ton/test-utils";
import {Op} from "../wrappers/constants";


let send_notification_create_receipt_gas_fee: bigint;
let send_notification_lock_gas_fee: bigint;
let send_record_receipt_gas_fee: bigint;
let send_receipt_ok_gas_fee: bigint;
let send_transmit_gas_fee: bigint;
let send_swap_gas_fee: bigint;
let send_release_gas_fee: bigint;
let send_record_swap_gas_fee: bigint;
let send_swap_ok_gas_fee: bigint;
let send_transfer_to_gas_fee: bigint;
let send_receive_gas_fee: bigint;
let add_liquidity_gas_fee: bigint;
let remove_liquidity_gas_fee: bigint;
let min_tons_for_storage: bigint;


describe('Pipeline', () => {

    let blockchain: Blockchain;
    let deployer: SandboxContract<TreasuryContract>;
    let initialState: BlockchainSnapshot;
    let curTime: () => number;
    const chainId = 9992731;
    // jetton
    let jwallet_code: Cell;
    let minter_code: Cell;
    let jettonMinter: SandboxContract<JettonMinter>;
    let jettonWallet: SandboxContract<JettonWallet>;
    let userWallet: any;
    let defaultContent: Cell;
    let deployJettonWallet: any;
    let bridgeJettonWallet: any;
    let bridgePoolJettonWallet: any;
    let accountJettonWallet: any;
    let initialAccountJettonBalance = toNano('1000.23');
    // code
    let bridge_code: Cell;
    let bridgeSwap_code: Cell;
    let bridgePool_code: Cell;
    let bridgeReceiptAccountCode: Cell;
    let bridgeLiquidityAccountCode: Cell;
    // contract
    let bridge: SandboxContract<Bridge>;
    let bridgeSwap: SandboxContract<BridgeSwap>;
    let bridgeSwapTonCoin: SandboxContract<BridgeSwap>;

    let bridgePool: SandboxContract<BridgePool>;
    let bridgePoolTonCoin: SandboxContract<BridgePool>;

    let bridgeReceiptAccount: SandboxContract<BridgeReceiptAccount>;
    let bridgeLiquidityAccount: SandboxContract<BridgePoolLiquidityAccount>;
    // auth
    let admin: SandboxContract<TreasuryContract>;
    let owner: SandboxContract<TreasuryContract>;
    let testAccount: SandboxContract<TreasuryContract>;
    // bridge helper
    let oracle: SandboxContract<TreasuryContract>;
    let pauseController: SandboxContract<TreasuryContract>;

    // bridge swap
    let swapId: Cell;
    let swapIdTonCoin: Cell;

    // upgrade
    let tempUpgrade: Cell;

    let HOLEADDRESS: Address;

    let msgPrices: MsgPrices;
    let gasPrices: GasPrices;
    let storagePrices: StorageValue;
    let storageDuration: number;
    let printTxGasStats: (name: string, trans: Transaction) => bigint;

    const jettonParams = {
        name: "Mock USDT",
        symbol: "USDT",
        description: "Test jetton",
    };

    beforeAll(async () => {
        blockchain = await Blockchain.create();
        tempUpgrade = beginCell().endCell();
        deployer = await blockchain.treasury('deployer');
        admin = await blockchain.treasury('admin');
        owner = await blockchain.treasury('owner');
        testAccount = await blockchain.treasury('testAccount');

        bridge_code = await compile('Bridge');
        bridgeSwap_code = await compile('BridgeSwap');
        bridgePool_code = await compile('BridgePool');
        bridgeReceiptAccountCode = await compile('BridgeReceiptAccount');
        bridgeLiquidityAccountCode = await compile('BridgePoolLiquidityAccount');
        jwallet_code = await compile('JettonWallet');
        minter_code = await compile('JettonMinter');

        msgPrices = getMsgPrices(blockchain.config, 0);
        gasPrices = getGasPrices(blockchain.config, 0);
        storagePrices = getStoragePrices(blockchain.config);
        storageDuration = 5 * 365 * 24 * 3600;
        HOLEADDRESS = Address.parse("EQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAM9c");

        printTxGasStats = (name, transaction) => {
            const txComputed = computedGeneric(transaction);
            console.log(`${name} used ${txComputed.gasUsed} gas`);
            console.log(`${name} gas cost: ${txComputed.gasFees}`);
            return txComputed.gasFees;
        }

        // jetton
        // 1. deploy mock jetton contract
        // 2. deploy mock jetton wallet
        let metadata = JettonMinter.buildTokenMetadataCell({
            name: jettonParams.name,
            symbol: jettonParams.symbol,
            description: jettonParams.description,
        });
        jettonMinter = blockchain.openContract(
            await JettonMinter.createFromConfig(
                {
                    admin: deployer.address,
                    content: metadata,
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
        // 3. deploy bridge contract
        oracle = await blockchain.treasury('oracle');
        pauseController = await blockchain.treasury('pauseController');
        let poolContractDicDefault = Dictionary.empty(Dictionary.Keys.Address(), Dictionary.Values.Address());
        let swapContractDicDefault = Dictionary.empty(Dictionary.Keys.Address(), Dictionary.Values.Address());
        let jettonWhitelistDicDefault = Dictionary.empty(Dictionary.Keys.BigUint(256), Dictionary.Values.Cell());
        let targetContractDicDefault = Dictionary.empty();
        bridge = blockchain.openContract(Bridge.createFromConfig({
            bridge_swap_address_dic: swapContractDicDefault,
            bridge_pool_address_dic: poolContractDicDefault,
            oracle_address: oracle.address,
            jetton_whitelist_dic: jettonWhitelistDicDefault,
            is_pause: false,
            pause_controller: pauseController.address,
            admin: admin.address,
            owner: owner.address,
            temp_upgrade: tempUpgrade,
            bridge_receipt_account_code: bridgeReceiptAccountCode,
            target_contract_dic: targetContractDicDefault
        }, bridge_code));
        const deployBridgeResult = await bridge.sendDeploy(deployer.getSender(), toNano('1'));
        expect(deployBridgeResult.transactions).toHaveTransaction({
            from: deployer.address,
            to: bridge.address,
            deploy: true,
            success: true,
        });
        // 4. deploy bridge pool contract
        let dic = Dictionary.empty(Dictionary.Keys.BigUint(256), Dictionary.Values.Cell());
        bridgePool = blockchain.openContract(BridgePool.createFromConfig({
            bridge_address: bridge.address,
            bridge_receipt_account_code: bridgeReceiptAccountCode,
            bridge_swap_address: null,
            jetton_address: jettonMinter.address,
            daily_limit: dic,
            rate_limit: dic,
            pool_liquidity_account_code: bridgeLiquidityAccountCode,
            admin: admin.address,
            owner: owner.address,
            temp_upgrade: tempUpgrade
        }, bridgePool_code));
        const deployPoolResult = await bridgePool.sendDeploy(deployer.getSender(), toNano('0.1'));

        expect(deployPoolResult.transactions).toHaveTransaction({
            from: deployer.address,
            to: bridgePool.address,
            deploy: true,
            success: true,
        });

        // 4'. deploy bridge pool contract for toncoin
        bridgePoolTonCoin = blockchain.openContract(BridgePool.createFromConfig({
            bridge_address: bridge.address,
            bridge_receipt_account_code: bridgeReceiptAccountCode,
            bridge_swap_address: null,
            jetton_address: HOLEADDRESS,
            daily_limit: dic,
            rate_limit: dic,
            pool_liquidity_account_code: bridgeLiquidityAccountCode,
            admin: admin.address,
            owner: owner.address,
            temp_upgrade: tempUpgrade
        }, bridgePool_code));
        const deployPoolTonCoinResult = await bridgePoolTonCoin.sendDeploy(deployer.getSender(), toNano('0.1'));

        expect(deployPoolTonCoinResult.transactions).toHaveTransaction({
            from: deployer.address,
            to: bridgePoolTonCoin.address,
            deploy: true,
            success: true,
        });

        // 5. deploy bridge swap contract
        bridgeSwap = blockchain.openContract(BridgeSwap.createFromConfig({
            bridgePoolAddress: bridgePool.address,
            jettonAddress: jettonMinter.address,
            bridgeAddress: bridge.address,
            admin: admin.address,
            owner: owner.address,
            tempUpgrade: tempUpgrade,
            swapDic: dic,
            receiptDic: dic
        }, bridgeSwap_code));
        const deploySwapResult = await bridgeSwap.sendDeploy(deployer.getSender(), toNano('0.1'));

        expect(deploySwapResult.transactions).toHaveTransaction({
            from: deployer.address,
            to: bridgeSwap.address,
            deploy: true,
            success: true,
        });

        // 5'. deploy bridge swap contract for toncoin
        bridgeSwapTonCoin = blockchain.openContract(BridgeSwap.createFromConfig({
            bridgePoolAddress: bridgePoolTonCoin.address,
            jettonAddress: HOLEADDRESS,
            bridgeAddress: bridge.address,
            admin: admin.address,
            owner: owner.address,
            tempUpgrade: tempUpgrade,
            swapDic: dic,
            receiptDic: dic
        }, bridgeSwap_code));
        const deploySwapTonCoinResult = await bridgeSwapTonCoin.sendDeploy(deployer.getSender(), toNano('0.1'));

        expect(deploySwapTonCoinResult.transactions).toHaveTransaction({
            from: deployer.address,
            to: bridgeSwapTonCoin.address,
            deploy: true,
            success: true,
        });


        // 6. open bridge receipt account - test account
        const bridgeReceiptAddress = await bridgePool.getReceiptAddress(testAccount.address);
        bridgeReceiptAccount = blockchain.openContract(
            BridgeReceiptAccount.createFromAddress(bridgeReceiptAddress));

        // 7. open liquidity account - test account
        const userLiquidityAddress = await bridgePool.getPoolLiquidityAccountAddress(testAccount.address);
        bridgeLiquidityAccount = blockchain.openContract(
            BridgePoolLiquidityAccount.createFromAddress(userLiquidityAddress));
        // init
        // 1. mint jetton to test account 
        deployJettonWallet = await userWallet(deployer.address);
        accountJettonWallet = await userWallet(testAccount.address);
        bridgeJettonWallet = await userWallet(bridge.address);
        bridgePoolJettonWallet = await userWallet(bridgePool.address);

        let initialTotalSupply = await jettonMinter.getTotalSupply();
        const mintResult = await jettonMinter.sendMint(
            deployer.getSender(),
            testAccount.address,
            initialAccountJettonBalance,
            toNano('0.05'),
            toNano('1'));

        expect(mintResult.transactions).toHaveTransaction({
            from: jettonMinter.address,
            to: accountJettonWallet.address,
            deploy: true,
        });
        expect(mintResult.transactions).toHaveTransaction({ // excesses
            from: accountJettonWallet.address,
            to: jettonMinter.address
        });
        expect(await accountJettonWallet.getJettonBalance()).toEqual(initialAccountJettonBalance);
        expect(await jettonMinter.getTotalSupply()).toEqual(initialTotalSupply + initialAccountJettonBalance);

        // bridge 
        // 1. add jetton whitelist
        const res1 = await bridge.sendAddJetton(
            admin.getSender(),
            toNano('0.5'), [jettonMinter.address, HOLEADDRESS], chainId);
        expect(res1.transactions).toHaveTransaction({
            from: admin.address,
            to: bridge.address,
            success: true,
        });
        // 2. set bridge swap
        const res2 = await bridge.sendSetBridgeSwap(admin.getSender(), toNano('0.5'), [{
            jetton_address: jettonMinter.address,
            contract_address: bridgeSwap.address
        }, {
            jetton_address: HOLEADDRESS,
            contract_address: bridgeSwapTonCoin.address
        }]);
        expect(res2.transactions).toHaveTransaction({
            from: admin.address,
            to: bridge.address,
            success: true,
        });
        let get_res = await bridge.getBridgeSwap(jettonMinter.address);
        expect(get_res).toEqualAddress(bridgeSwap.address);
        let get_res_ton = await bridge.getBridgeSwap(HOLEADDRESS);
        expect(get_res_ton).toEqualAddress(bridgeSwapTonCoin.address);
        // 3. set bridge pool
        const res3 = await bridge.sendSetBridgePool(
            admin.getSender(), toNano('0.5'),
            [{
                jetton_address: jettonMinter.address,
                contract_address: bridgePool.address
            },
                {
                    jetton_address: HOLEADDRESS,
                    contract_address: bridgePoolTonCoin.address
                }]);
        expect(res3.transactions).toHaveTransaction({
            from: admin.address,
            to: bridge.address,
            success: true,
        });
        expect(await bridge.getBridgePool(jettonMinter.address)).toEqualAddress(bridgePool.address);
        expect(await bridge.getBridgePool(HOLEADDRESS)).toEqualAddress(bridgePoolTonCoin.address);

        // 4. set target contract address
        let targetAddress = "foDLAM2Up3xLjg43SvCy5Ed6zaY5CKG8uczj6yUVZUweqQUmz";
        const buffer = aelf.utils.base58.decode(targetAddress);
        const res4 = await bridge.sendTargetContract(admin.getSender(), toNano('0.5'), [
            {
                chain_id: chainId,
                bridge_address: Buffer.from(buffer)
            }]);
        expect(res4.transactions).toHaveTransaction({
            from: admin.address,
            to: bridge.address,
            success: true,
        });
        let contractAddress = await bridge.getTargetContractAddress(chainId);
        expect(aelf.utils.base58.encode(contractAddress)).toEqual(targetAddress);
        // bridge swap
        // 1. create swap
        const result = await bridgeSwap.sendCreateSwap(
            admin.getSender(), toNano('0.5'), [{
                fromChainId: chainId,
                originShare: 1000,
                targetShare: 1
            }]);

        expect(result.transactions).toHaveTransaction({
            from: admin.address,
            to: bridgeSwap.address,
            success: true,
        });
        let body = result.transactions[1].outMessages.get(0)?.body;
        if (body != undefined) {
            let info = body.asSlice();
            let swapInfo = info.loadRef().asSlice();
            let fromChainId = swapInfo.loadUint(32);
            let swapId_log = swapInfo.loadRef();
            console.log(fromChainId);
            console.log(swapId_log.asSlice().loadBuffer(32).toString('hex'));
            swapId = swapId_log;
        }
        // 1'. create toncoin swap
        const resultTon = await bridgeSwapTonCoin.sendCreateSwap(
            admin.getSender(), toNano('0.5'), [{
                fromChainId: chainId,
                originShare: 100,
                targetShare: 1
            }]);

        expect(resultTon.transactions).toHaveTransaction({
            from: admin.address,
            to: bridgeSwapTonCoin.address,
            success: true,
        });
        let bodyTon = resultTon.transactions[1].outMessages.get(0)?.body;
        if (bodyTon != undefined) {
            let info = bodyTon.asSlice();
            let swapInfo = info.loadRef().asSlice();
            let fromChainId = swapInfo.loadUint(32);
            let swapId_log = swapInfo.loadRef();
            console.log(fromChainId);
            console.log(swapId_log.asSlice().loadBuffer(32).toString('hex'));
            swapIdTonCoin = swapId_log;
        }
        // bridge pool
        // 1. set bridge address
        let res = await bridgePool.sendSetBridge(
            admin.getSender(), toNano('0.5'), bridge.address);
        expect(res.transactions).toHaveTransaction({
            from: admin.address,
            to: bridgePool.address,
            success: true,
        });
        const bridge1 = await bridgePool.getBridgeAddress();
        expect(bridge1).toEqualAddress(bridge.address);
        // 1.' set bridge swap address
        let r = await bridgePool.sendSetBridgeSwap(
            admin.getSender(), toNano('0.5'), bridgeSwap.address);
        expect(r.transactions).toHaveTransaction({
            from: admin.address,
            to: bridgePool.address,
            success: true,
        });
        // 2. set jetton 
        let res5 = await bridgePool.sendSetJetton(
            admin.getSender(), toNano('0.5'), jettonMinter.address, bridgePoolJettonWallet.address);
        expect(res5.transactions).toHaveTransaction({
            from: admin.address,
            to: bridgePool.address,
            success: true,
        });
        let jetton = await bridgePool.getJettonAddress();
        expect(jetton.jettonAddress).toEqualAddress(jettonMinter.address);
        expect(jetton.poolJettonWalletAddress).toEqualAddress(bridgePoolJettonWallet.address);
        // 3. set daily limit
        let refreshTime = getUTCMidnight();
        let res6 = await bridgePool.sendSetDailyLimit(
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
        expect(res6.transactions).toHaveTransaction({
            from: admin.address,
            to: bridgePool.address,
            success: true,
        });


        const res8 = await bridgePool.getReceiptDailyLimit(chainId);
        expect(res8.remainToken).toBe(BigInt(100000000000000000));
        console.log(res8.refreshTime);
        expect(res8.dailyLimit).toBe(BigInt(100000000000000000));
        const res9 = await bridgePool.getSwapDailyLimit(chainId);
        expect(res9.remainToken).toBe(BigInt(100000000000000000));
        console.log(res9.refreshTime);
        expect(res9.dailyLimit).toBe(BigInt(100000000000000000));

        // 4. set rate limit
        let res7 = await bridgePool.sendSetRateLimit(
            admin.getSender(),
            toNano('1'),
            [{
                chainId: chainId,
                limitType: 0,
                tokenCapacity: 1000000000000000n,
                rate: 1000000000n,
            },
                {
                    chainId: chainId,
                    limitType: 1,
                    tokenCapacity: 1000000000000000n,
                    rate: 1000000000n,
                }]);
        expect(res7.transactions).toHaveTransaction({
            from: admin.address,
            to: bridgePool.address,
            success: true,
        });
        const res10 = await bridgePool.getReceiptRateLimit(chainId);
        expect(res10.currentTokenAmount).toBe(BigInt(1000000000000000));
        expect(res10.tokenCapacity).toBe(BigInt(1000000000000000));
        expect(res10.rate).toBe(BigInt(1000000000));
        expect(res10.isEnable).toBe(true);

        const res11 = await bridgePool.getSwapRateLimit(chainId);
        expect(res11.currentTokenAmount).toBe(BigInt(1000000000000000));
        expect(res11.tokenCapacity).toBe(BigInt(1000000000000000));
        expect(res11.rate).toBe(BigInt(1000000000));
        expect(res11.isEnable).toBe(true);
        // add jetton liquidity
        let amount_add_liquidity = toNano('100');
        let forwardAmount = toNano('0.05');
        let payload = BridgePool.packAddLiquidityBody();
        const add_liquidity_res = await accountJettonWallet.sendTransfer(
            testAccount.getSender(),
            toNano('2'),
            amount_add_liquidity,
            bridgePool.address,
            testAccount.address,
            null,
            forwardAmount,
            payload);

        expect(add_liquidity_res.transactions).toHaveTransaction({
            from: accountJettonWallet.address,
            to: bridgePoolJettonWallet.address,
            success: true,
        });

        expect(add_liquidity_res.transactions).toHaveTransaction({
            from: bridgePoolJettonWallet.address,
            to: bridgePool.address,
            success: true,
        });
        const liquidity_account = await bridgePool.getPoolLiquidityAccountAddress(testAccount.address);
        expect(add_liquidity_res.transactions).toHaveTransaction({
            from: bridgePool.address,
            to: liquidity_account,
            deploy: true,
            success: true,
        });

        let liquidityAfter = await bridgePool.getPoolLiquidity();
        expect(liquidityAfter).toBe(BigInt(100000000000));

        // 1. set bridge address
        let resTon = await bridgePoolTonCoin.sendSetBridge(
            admin.getSender(), toNano('0.5'), bridge.address);
        expect(resTon.transactions).toHaveTransaction({
            from: admin.address,
            to: bridgePoolTonCoin.address,
            success: true,
        });
        const bridge2 = await bridgePoolTonCoin.getBridgeAddress();
        expect(bridge2).toEqualAddress(bridge.address);
        // 1.' set bridge swap address
        let r1 = await bridgePoolTonCoin.sendSetBridgeSwap(
            admin.getSender(), toNano('0.5'), bridgeSwapTonCoin.address);
        expect(r1.transactions).toHaveTransaction({
            from: admin.address,
            to: bridgePoolTonCoin.address,
            success: true,
        });
        // 2. set jetton 
        let res6ton = await bridgePoolTonCoin.sendSetJetton(
            admin.getSender(), toNano('0.5'), HOLEADDRESS, HOLEADDRESS);
        expect(res6ton.transactions).toHaveTransaction({
            from: admin.address,
            to: bridgePoolTonCoin.address,
            success: true,
        });
        let jetton1 = await bridgePoolTonCoin.getJettonAddress();
        expect(jetton1.jettonAddress).toEqualAddress(HOLEADDRESS);
        expect(jetton1.poolJettonWalletAddress).toEqualAddress(HOLEADDRESS);
        // 3. set daily limit
        let restonlimit = await bridgePoolTonCoin.sendSetDailyLimit(
            admin.getSender(),
            toNano('0.5'),
            [{
                chainId: chainId,
                limitType: 0,
                refreshTime: refreshTime,
                dailyLimit: 10000000000000000n
            },
                {
                    chainId: chainId,
                    limitType: 1,
                    refreshTime: refreshTime,
                    dailyLimit: 10000000000000000n
                }]);
        expect(restonlimit.transactions).toHaveTransaction({
            from: admin.address,
            to: bridgePoolTonCoin.address,
            success: true,
        });


        const res_get_1 = await bridgePoolTonCoin.getReceiptDailyLimit(chainId);
        expect(res_get_1.remainToken).toBe(BigInt(10000000000000000));
        console.log(res_get_1.refreshTime);
        expect(res_get_1.dailyLimit).toBe(BigInt(10000000000000000));
        const res_get_2 = await bridgePoolTonCoin.getSwapDailyLimit(chainId);
        expect(res_get_2.remainToken).toBe(BigInt(10000000000000000));
        console.log(res_get_2.refreshTime);
        expect(res_get_2.dailyLimit).toBe(BigInt(10000000000000000));

        // 4. set rate limit
        let res7ton = await bridgePoolTonCoin.sendSetRateLimit(
            admin.getSender(),
            toNano('1'),
            [{
                chainId: chainId,
                limitType: 0,
                tokenCapacity: 1000000000000000n,
                rate: 1000000000n,
            },
                {
                    chainId: chainId,
                    limitType: 1,
                    tokenCapacity: 1000000000000000n,
                    rate: 1000000000n,
                }]);
        expect(res7ton.transactions).toHaveTransaction({
            from: admin.address,
            to: bridgePoolTonCoin.address,
            success: true,
        });
        const res10_get = await bridgePoolTonCoin.getReceiptRateLimit(chainId);
        expect(res10_get.currentTokenAmount).toBe(BigInt(1000000000000000));
        expect(res10_get.tokenCapacity).toBe(BigInt(1000000000000000));
        expect(res10_get.rate).toBe(BigInt(1000000000));
        expect(res10_get.isEnable).toBe(true);

        const res11_get = await bridgePoolTonCoin.getSwapRateLimit(chainId);
        expect(res11_get.currentTokenAmount).toBe(BigInt(1000000000000000));
        expect(res11_get.tokenCapacity).toBe(BigInt(1000000000000000));
        expect(res11_get.rate).toBe(BigInt(1000000000));
        expect(res11_get.isEnable).toBe(true);
        // add native token liquidity
        let resAddLiquidity = await bridgePoolTonCoin.sendAddNativeLiquidity(testAccount.getSender(), toNano('20.05'), toNano('20'));
        expect(resAddLiquidity.transactions).toHaveTransaction({
            from: testAccount.address,
            to: bridgePoolTonCoin.address,
            success: true,
        });
        initialState = blockchain.snapshot();
        curTime = () => blockchain.now ?? Math.floor(Date.now() / 1000);
    });

    afterEach(async () => await blockchain.loadFrom(initialState));


    it('should deploy and init', async () => {
        // the check is done inside beforeEach
        // blockchain and ebridgeContractsTon are ready to use
    });
    it('create receipt', async () => {
            console.log(testAccount.address);
            console.log(accountJettonWallet.address);
            console.log(bridge.address);
            console.log(bridgeJettonWallet.address);
            console.log(bridgePool.address);
            console.log(bridgePoolJettonWallet.address);

            let targetAddress = "JKjoabe2wyrdP1P8TvNyD4GZP6z1PuMvU2y5yJ4JTeBjTMAoX";
            const targetAddressBuffer = aelf.utils.base58.decode(targetAddress);

            let receipt_amount = toNano('10');
            let forwardAmount = toNano('0.15');
            let payload = Bridge.PackCreateReceiptBody(
                chainId, accountJettonWallet.address,
                Buffer.from(targetAddressBuffer), jettonMinter.address);

            const result = await accountJettonWallet.sendTransfer(
                testAccount.getSender(),
                toNano('0.5'),
                receipt_amount,
                bridge.address,
                testAccount.address,
                beginCell().storeUint(0, 1).endCell(),
                forwardAmount,
                payload);


            expect(result.transactions).toHaveTransaction({
                from: accountJettonWallet.address,
                to: bridgeJettonWallet.address,
                success: true,
            });

            expect(result.transactions).toHaveTransaction({
                from: bridgeJettonWallet.address,
                to: bridge.address,
                success: true,
            });

            expect(result.transactions).toHaveTransaction({
                from: bridge.address,
                to: bridgeJettonWallet.address,
                success: true,
            });

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

            const bridgeReceiptAddress = await bridgePool.getReceiptAddress(testAccount.address);
            bridgeReceiptAccount = blockchain.openContract(
                BridgeReceiptAccount.createFromAddress(bridgeReceiptAddress));
            console.log(bridgeReceiptAddress);
            expect(result.transactions).toHaveTransaction({
                from: bridgePool.address,
                to: bridgeReceiptAddress,
                success: true,
            });

            expect(result.transactions).toHaveTransaction({
                from: bridgeReceiptAddress,
                to: bridge.address,
                success: true,
            });
            expect(result.transactions).toHaveTransaction({
                from: bridge.address,
                to: oracle.address,
                success: true,
            });

            let balance3 = (await blockchain.getContract(bridgeReceiptAddress)).balance;
            console.log(balance3);
            const transferNotificationCreateReceiptTx = findTransactionRequired(result.transactions, {
                on: bridge.address,
                from: bridgeJettonWallet.address,
                op: Op.jetton.transfer_notification,
                success: true
            });
            send_notification_create_receipt_gas_fee = printTxGasStats("Jetton transfer for create receipt", transferNotificationCreateReceiptTx);
            // gas used:11408
            send_notification_create_receipt_gas_fee = computeGasFee(gasPrices, 11408n);
            console.log(send_notification_create_receipt_gas_fee);
            const receiptInMessage = transferNotificationCreateReceiptTx.inMessage!
            let walletToBridgeMessageStats = computeMessageForwardFees(msgPrices, receiptInMessage).stats;
            console.log(walletToBridgeMessageStats);

            const lockTx = findTransactionRequired(result.transactions, {
                on: bridgePool.address,
                from: bridgePoolJettonWallet.address,
                op: Op.jetton.transfer_notification,
                success: true
            });
            send_notification_lock_gas_fee = printTxGasStats("Jetton transfer for lock", lockTx);
            // gas used:37330
            send_notification_lock_gas_fee = computeGasFee(gasPrices, 37330n);
            console.log(send_notification_lock_gas_fee);
            const lockInMessage = lockTx.inMessage!
            let lockMessageStats = computeMessageForwardFees(msgPrices, lockInMessage).stats;
            console.log(lockMessageStats);

            const recordReceiptTx = findTransactionRequired(result.transactions, {
                on: bridgeReceiptAddress,
                from: bridgePool.address,
                op: Op.bridge_receipt_account.record_receipt,
                success: true
            });
            send_record_receipt_gas_fee = printTxGasStats("Record receipt", recordReceiptTx);
            // gas used : 9391
            send_record_receipt_gas_fee = computeGasFee(gasPrices, 9391n);
            console.log(send_record_receipt_gas_fee);
            const recordReceiptInMessage = recordReceiptTx.inMessage!
            let recordMessageStats = computeMessageForwardFees(msgPrices, recordReceiptInMessage).stats;
            console.log(recordMessageStats);


            const receiptOkTx = findTransactionRequired(result.transactions, {
                on: bridge.address,
                from: bridgeReceiptAddress,
                op: Op.bridge.receipt_ok,
                success: true
            });
            send_receipt_ok_gas_fee = printTxGasStats("Receipt ok", receiptOkTx);
            // gas used: 22457
            send_receipt_ok_gas_fee = computeGasFee(gasPrices, 22457n);
            console.log(send_receipt_ok_gas_fee);
            const receiptOkInMessage = receiptOkTx.inMessage!
            let okMessageStats = computeMessageForwardFees(msgPrices, receiptOkInMessage).stats;
            console.log(okMessageStats);

            let balance = await accountJettonWallet.getJettonBalance();
            expect(balance).toEqual(toNano('890.23'));
            let balance1 = await bridgePoolJettonWallet.getJettonBalance();
            expect(balance1).toEqual(toNano('110'));
            let balance2 = await bridgeJettonWallet.getJettonBalance();
            expect(balance2).toEqual(0n);

            let liquidityAfter = await bridgePool.getPoolLiquidity();
            expect(liquidityAfter).toBe(BigInt(100000000000 + 10000000000));

            const res3 = await bridgePool.getReceiptDailyLimit(chainId);
            expect(res3.remainToken).toBe(BigInt(100000000000000000 - 10000000000));
            console.log(res3.refreshTime);
            expect(res3.dailyLimit).toBe(BigInt(100000000000000000));

            const res4 = await bridgePool.getReceiptRateLimit(chainId);
            expect(res4.currentTokenAmount).toBeGreaterThanOrEqual(BigInt(1000000000000000 - 10000000000));
            expect(res4.tokenCapacity).toBe(BigInt(1000000000000000));
            expect(res4.rate).toBe(BigInt(1000000000));
            expect(res4.isEnable).toBe(true);


            let receipt = await bridgeReceiptAccount.getReceiptInfo(chainId);
            expect(receipt.totalAmount).toBe(toNano('10'));
            expect(receipt.index).toBe(BigInt(1));

            let receipt_amount1 = toNano('100');
            let forwardAmount1 = toNano('0.5');
            let payload1 = Bridge.PackCreateReceiptBody(
                chainId, accountJettonWallet.address,
                Buffer.from(targetAddressBuffer), jettonMinter.address);
            const result11 = await accountJettonWallet.sendTransfer(
                testAccount.getSender(),
                toNano('1'),
                receipt_amount1,
                bridge.address,
                testAccount.address,
                beginCell().storeUint(0, 1).endCell(),
                forwardAmount1,
                payload1);
            let receipt1 = await bridgeReceiptAccount.getReceiptInfo(chainId);
            expect(receipt1.totalAmount).toBe(toNano('110'));
            expect(receipt1.index).toBe(BigInt(2));

            const smc = await blockchain.getContract(bridgeReceiptAddress);
            if (smc.accountState === undefined)
                throw new Error("Can't access wallet account state");
            if (smc.accountState.type !== "active")
                throw new Error("Wallet account is not active");
            if (smc.account.account === undefined || smc.account.account === null)
                throw new Error("Can't access wallet account!");
            console.log("bridge receipt storage stats:", smc.account.account.storageStats.used);
            const state = smc.accountState.state;
            const stateCell = beginCell().store(storeStateInit(state)).endCell();
            console.log("State init stats:", collectCellStats(stateCell, []));

            console.log(bridgeReceiptAddress);
            console.log(oracle.address);
            let transactionCount = result.transactions.length;
            console.log(transactionCount);
            for (let i = 1; i < transactionCount; i++) {
                console.log(result.transactions[i].inMessage.info.src);
                console.log(result.transactions[i].inMessage.info.dest);
                if (result.transactions[i].inMessage.info.dest.toString() == oracle.address) {
                    let inMessage = result.transactions[i].inMessage;
                    let body = inMessage.body;
                    if (body != undefined) {
                        let info = body.asSlice();
                        let op = info.loadUint(32);
                        console.log(op);
                        let chain_id = info.loadUint(64);
                        console.log(chain_id);
                        let target = info.loadRef();
                        console.log(target);
                        // message 
                        let message = info.loadRef();
                        console.log(message);
                        let messageSlice = message.asSlice();
                        console.log(messageSlice);
                        let bitlength = messageSlice.remainingBits;
                        console.log(bitlength);
                        // let index = messageSlice.loadBuffer(32);
                        // console.log(index);
                        // let keyHash = messageSlice.loadBuffer(32);
                        // let jettonAmount = messageSlice.loadBuffer(32);
                        // console.log(jettonAmount)
                        // console.log(Buffer.from(jettonAmount).toString('base64'));
                        let buf = messageSlice.loadBuffer(96);
                        console.log(Buffer.from(buf).toString('base64'));
                        //
                        //             let refs = messageSlice.remainingRefs;
                        //             console.log(refs);
                        //
                        //             let res = Buffer.from(buf);
                        //             for (let j = 0; j < refs; j++) {
                        //                 let cell1 = messageSlice.loadRef();
                        //                 let cellBuf = cell1.asSlice().loadBuffer(32);
                        //                 let buffer2 = Buffer.from(cellBuf);
                        //                 res = Buffer.concat([res, buffer2]);
                        //             }
                        //             console.log(Buffer.from(res).toString('base64'));
                        //         }
                        //     }
                    }
                }
            }
        }
    );
    it('swap', async () => {
        const userLiquidityAddress = await bridgePool.getPoolLiquidityAccountAddress(testAccount.address);
        const smc = await blockchain.getContract(userLiquidityAddress);
        if (smc.accountState === undefined)
            throw new Error("Can't access wallet account state");
        if (smc.accountState.type !== "active")
            throw new Error("Wallet account is not active");
        if (smc.account.account === undefined || smc.account.account === null)
            throw new Error("Can't access wallet account!");
        console.log("bridge liquidity storage stats:", smc.account.account.storageStats.used);
        const state = smc.accountState.state;
        const stateCell = beginCell().store(storeStateInit(state)).endCell();
        console.log("State init stats:", collectCellStats(stateCell, []));

        console.log(testAccount.address);
        console.log(accountJettonWallet.address);
        // EQBIDbk317LrsY3GE3ktW6c_1iSfNmjuKSVw5TfBeYbUqEHD
        console.log(bridge.address);
        console.log(bridgeSwap.address);
        console.log(bridgePool.address);
        console.log(bridgePoolJettonWallet.address);
        expect(await accountJettonWallet.getJettonBalance()).toEqual(BigInt(900230000000));
        let dataFull = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAFTrftWgsEIWehE9Or/iLtKXLuipEbS5x/YIrmX0HqJkAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAJUC+QAmUXSGzTyJjueaHKaCsorIlPuRZ+MzyhtwrYq4opKej0RAG8DjMpBpA6PC7sdvIeJYlTvFDLNXiGt7VherY/NVHZRPJM=";
        let dataFullBuffer = Buffer.from(dataFull, 'base64');
        let messageId = BigInt(11111);
        let sourceChainId = 9992731;
        let targetChainId = 1101;
        let sender = aelf.utils.base58.decode("foDLAM2Up3xLjg43SvCy5Ed6zaY5CKG8uczj6yUVZUweqQUmz");
        let receiver = bridge.address;
        let data = dataFullBuffer.slice(0, 96);
        let dataOther = dataFullBuffer.slice(96);
        let result = await bridge.sendTransmit(
            oracle.getSender(),
            toNano('0.01'),
            messageId,
            sourceChainId,
            targetChainId,
            sender,
            receiver,
            data,
            dataOther,
            swapId,
            jettonMinter.address
        );

        expect(result.transactions).toHaveTransaction({
            from: oracle.address,
            to: bridge.address,
            success: true,
        });
        expect(result.transactions).toHaveTransaction({
            from: bridge.address,
            to: bridgeSwap.address,
            success: true
        });

        // const tx = result.transactions[3];
        // let body2 = tx.outMessages.get(2)?.body;
        // if (body2 != undefined) {
        //     let info = body2.asSlice();
        //     let value = info.loadCoins();
        //     let value1 = info.loadCoins();
        //     console.log(value);
        //     console.log(value1);
        // }

        expect(result.transactions).toHaveTransaction({
            from: bridgeSwap.address,
            to: bridgePool.address,
            success: true
        });
        //
        // const txx = result.transactions[3];
        // let body = txx.outMessages.get(2)?.body;
        // if (body != undefined) {
        //     let info = body.asSlice();
        //     let value = info.loadCoins();
        //     console.log(value);
        // }

        expect(result.transactions).toHaveTransaction({
            from: bridgePool.address,
            to: bridgePoolJettonWallet.address,
            success: true
        });

        expect(result.transactions).toHaveTransaction({
            from: bridgePoolJettonWallet.address,
            to: accountJettonWallet.address,
            success: true
        });

        const send_transmit_tx = findTransactionRequired(result.transactions, {
            on: bridge.address,
            from: oracle.address,
            op: Op.bridge.transmit,
            success: true
        });
        send_transmit_gas_fee = printTxGasStats("transmit", send_transmit_tx);
        // gas used:17650
        send_transmit_gas_fee = computeGasFee(gasPrices, 17650n);
        console.log(send_transmit_gas_fee);

        const send_swap_tx = findTransactionRequired(result.transactions, {
            on: bridgeSwap.address,
            from: bridge.address,
            op: Op.bridge_swap.swap,
            success: true
        });
        send_swap_gas_fee = printTxGasStats("swap", send_swap_tx);
        // gas used:12558
        send_swap_gas_fee = computeGasFee(gasPrices, 12558n);
        console.log(send_swap_gas_fee);
        const swapInMessage = send_swap_tx.inMessage!
        let swapMessageStats = computeMessageForwardFees(msgPrices, swapInMessage).stats;
        console.log(swapMessageStats);

        const send_release_tx = findTransactionRequired(result.transactions, {
            on: bridgePool.address,
            from: bridgeSwap.address,
            op: Op.bridge_pool.release,
            success: true
        });
        send_release_gas_fee = printTxGasStats("release", send_release_tx);
        // gas used:34096
        send_release_gas_fee = computeGasFee(gasPrices, 34096n);
        console.log(send_release_gas_fee);
        const releaseInMessage = send_release_tx.inMessage!
        let releaseMessageStats = computeMessageForwardFees(msgPrices, releaseInMessage).stats;
        console.log(releaseMessageStats);

        const send_transfer_tx = findTransactionRequired(result.transactions, {
            on: bridgePoolJettonWallet.address,
            from: bridgePool.address,
            op: Op.jetton.transfer,
            success: true
        });
        send_transfer_to_gas_fee = printTxGasStats("transfer", send_transfer_tx);
        // gas used:8341
        send_transfer_to_gas_fee = computeGasFee(gasPrices, 8341n);
        console.log(send_transfer_to_gas_fee);
        const transferInMessage = send_transfer_tx.inMessage!
        let transferMessageStats = computeMessageForwardFees(msgPrices, transferInMessage).stats;
        console.log(transferMessageStats);

        const receive_tx = findTransactionRequired(result.transactions, {
            on: accountJettonWallet.address,
            from: bridgePoolJettonWallet.address,
            op: Op.jetton.internal_transfer,
            success: true
        });
        send_receive_gas_fee = printTxGasStats("receive", receive_tx);
        // gas used:7822
        send_receive_gas_fee = computeGasFee(gasPrices, 7822n);
        console.log(send_receive_gas_fee);
        const receiveInMessage = receive_tx.inMessage!
        let receiveMessageStats = computeMessageForwardFees(msgPrices, receiveInMessage).stats;
        console.log(receiveMessageStats);

        const send_record_swap_tx = findTransactionRequired(result.transactions, {
            on: bridgeSwap.address,
            from: bridgePool.address,
            op: Op.bridge_pool.record_swap,
            success: true
        });
        send_record_swap_gas_fee = printTxGasStats("record swap", send_record_swap_tx);
        // gas used:9706
        send_record_swap_gas_fee = computeGasFee(gasPrices, 9706n);
        console.log(send_record_swap_gas_fee);
        const recordSwapInMessage = send_record_swap_tx.inMessage!
        let recordSwapMessageStats = computeMessageForwardFees(msgPrices, recordSwapInMessage).stats;
        console.log(recordSwapMessageStats);
        const send_swap_ok_tx = findTransactionRequired(result.transactions, {
            on: bridge.address,
            from: bridgeSwap.address,
            op: Op.bridge.swap_ok,
            success: true
        });
        send_swap_ok_gas_fee = printTxGasStats("swap ok", send_swap_ok_tx);
        // gas used:6592
        send_swap_ok_gas_fee = computeGasFee(gasPrices, 6482n);
        console.log(send_swap_ok_gas_fee);
        const swapOkInMessage = send_swap_ok_tx.inMessage!
        let swapOkMessageStats = computeMessageForwardFees(msgPrices, swapOkInMessage).stats;
        console.log(swapOkMessageStats);
        expect(await accountJettonWallet.getJettonBalance()).toEqual(BigInt(900230000000 + 10000000));
        let liquidityAfter = await bridgePool.getPoolLiquidity();
        expect(liquidityAfter).toBe(BigInt(100000000000 - 10000000));
        expect(await bridgePoolJettonWallet.getJettonBalance()).toEqual(BigInt(100000000000 - 10000000));

    });

    it('fee', async () => {
        // let fee = await bridge.getEstimateCreateReceiptFee();
        // console.log(fee);
        // let fee1 = await bridge.getEstimateRecordReceiptFee();
        // console.log(fee1);
        // let fee2 = await bridge.getEstimateSwapFee();
        // console.log(fee2);
        // let fee3 = await bridge.getEstimateRecordSwapFee();
        // console.log(fee3);
        // let fee4 = await bridge.getEstimateStorageFee();
        // console.log(fee4);
        // let fee5 = await bridge.getEstimateLockFee();
        // console.log(fee5);
    });
    it("bridge max storage", async () => {
        const res1 = await bridge.sendAddJetton(
            admin.getSender(),
            toNano('0.5'), [deployer, ...await blockchain.createWallets(20)].map(s => s.address), chainId);
        expect(res1.transactions).toHaveTransaction({
            from: admin.address,
            to: bridge.address,
            success: true,
        });
        const res11 = await bridge.sendAddJetton(
            admin.getSender(),
            toNano('0.5'), [deployer, ...await blockchain.createWallets(20)].map(s => s.address), 1173);
        expect(res11.transactions).toHaveTransaction({
            from: admin.address,
            to: bridge.address,
            success: true,
        });
        // 2. set bridge swap
        let randomWallet1 = (await blockchain.createWallets(20)).map(s => s.address);
        let randomWallet2 = (await blockchain.createWallets(20)).map(s => s.address);
        const input = randomWallet1.map((address1, index) => ({
            jetton_address: address1,
            contract_address: randomWallet2[index] || ''
        }));
        const res2 = await bridge.sendSetBridgeSwap(admin.getSender(), toNano('0.5'), input);
        expect(res2.transactions).toHaveTransaction({
            from: admin.address,
            to: bridge.address,
            success: true,
        });
        // 3. set bridge pool
        const res3 = await bridge.sendSetBridgePool(
            admin.getSender(), toNano('0.5'),
            input);
        expect(res3.transactions).toHaveTransaction({
            from: admin.address,
            to: bridge.address,
            success: true,
        });

        const smc = await blockchain.getContract(bridge.address);
        if (smc.accountState === undefined)
            throw new Error("Can't access wallet account state");
        if (smc.accountState.type !== "active")
            throw new Error("Wallet account is not active");
        if (smc.account.account === undefined || smc.account.account === null)
            throw new Error("Can't access wallet account!");
        console.log("bridge max storage stats:", smc.account.account.storageStats.used);
        const state = smc.accountState.state;
        const stateCell = beginCell().store(storeStateInit(state)).endCell();
        console.log("State init stats:", collectCellStats(stateCell, []));
    });

    it("bridge pool max storage", async () => {
        const smc = await blockchain.getContract(bridgePool.address);
        if (smc.accountState === undefined)
            throw new Error("Can't access wallet account state");
        if (smc.accountState.type !== "active")
            throw new Error("Wallet account is not active");
        if (smc.account.account === undefined || smc.account.account === null)
            throw new Error("Can't access wallet account!");
        console.log("bridge pool max storage stats:", smc.account.account.storageStats.used);
        const state = smc.accountState.state;
        const stateCell = beginCell().store(storeStateInit(state)).endCell();
        console.log("State init stats:", collectCellStats(stateCell, []));
    });

    it("bridge swap max storage", async () => {
        const result = await bridgeSwap.sendCreateSwap(
            admin.getSender(), toNano('0.5'), [{
                fromChainId: 1133,
                originShare: 1000,
                targetShare: 1
            }]);

        expect(result.transactions).toHaveTransaction({
            from: admin.address,
            to: bridgeSwap.address,
            success: true,
        });
        const smc = await blockchain.getContract(bridgeSwap.address);
        if (smc.accountState === undefined)
            throw new Error("Can't access wallet account state");
        if (smc.accountState.type !== "active")
            throw new Error("Wallet account is not active");
        if (smc.account.account === undefined || smc.account.account === null)
            throw new Error("Can't access wallet account!");
        console.log("bridge swap max storage stats:", smc.account.account.storageStats.used);
        const state = smc.accountState.state;
        const stateCell = beginCell().store(storeStateInit(state)).endCell();
        console.log("State init stats:", collectCellStats(stateCell, []));
    });

    it("create native receipt", async () => {
        let targetAddress = "JKjoabe2wyrdP1P8TvNyD4GZP6z1PuMvU2y5yJ4JTeBjTMAoX";
        const targetAddressBuffer = aelf.utils.base58.decode(targetAddress);
        let receipt_amount = toNano('10');
        let res = await bridge.sendCreateNativeReceipt(testAccount.getSender(), toNano('10.5'), chainId, targetAddressBuffer, receipt_amount);
        expect(res.transactions).toHaveTransaction({
            from: testAccount.address,
            to: bridge.address,
            success: true,
        });
        expect(res.transactions).toHaveTransaction({
            from: bridge.address,
            to: bridgePoolTonCoin.address,
            success: true,
        });
        let receiptAccountAddress = await bridgePoolTonCoin.getReceiptAddress(testAccount.address);
        console.log(receiptAccountAddress);
        expect(res.transactions).toHaveTransaction({
            from: bridgePoolTonCoin.address,
            to: receiptAccountAddress,
            success: true,
        });
        expect(res.transactions).toHaveTransaction({
            from: receiptAccountAddress,
            to: bridge.address,
            success: true,
        });
        expect(res.transactions).toHaveTransaction({
            from: bridge.address,
            to: oracle.address,
            success: true,
        });

        const createReceiptTx = findTransactionRequired(res.transactions, {
            on: bridge.address,
            from: testAccount.address,
            op: Op.bridge.create_native_receipt,
            success: true
        });
        send_notification_create_receipt_gas_fee = printTxGasStats("create receipt", createReceiptTx);
        // gas used:8055
        send_notification_create_receipt_gas_fee = computeGasFee(gasPrices, 8055n);
        console.log(send_notification_create_receipt_gas_fee);
        let stat1 = computeMessageForwardFees(msgPrices, createReceiptTx.inMessage!).stats;
        console.log(stat1);

        const lockTx = findTransactionRequired(res.transactions, {
            on: bridgePoolTonCoin.address,
            from: bridge.address,
            op: Op.bridge.lock_native_token,
            success: true
        });
        send_notification_lock_gas_fee = printTxGasStats("lock", lockTx);
        // gas used:35443
        send_notification_lock_gas_fee = computeGasFee(gasPrices, 35443n);
        console.log(send_notification_lock_gas_fee);
        let stat2 = computeMessageForwardFees(msgPrices, lockTx.inMessage!).stats;
        console.log(stat2);

        const recordReceiptTx = findTransactionRequired(res.transactions, {
            on: receiptAccountAddress,
            from: bridgePoolTonCoin.address,
            op: Op.bridge_pool.record_receipt,
            success: true
        });
        send_record_receipt_gas_fee = printTxGasStats("record receipt", recordReceiptTx);
        // gas used:9969
        send_record_receipt_gas_fee = computeGasFee(gasPrices, 9969n);
        console.log(send_record_receipt_gas_fee);
        let stat3 = computeMessageForwardFees(msgPrices, recordReceiptTx.inMessage!).stats;
        console.log(stat3);

        const receiptOkTx = findTransactionRequired(res.transactions, {
            on: bridge.address,
            from: receiptAccountAddress,
            op: Op.bridge.receipt_ok,
            success: true
        });
        send_receipt_ok_gas_fee = printTxGasStats("receipt ok", receiptOkTx);
        // gas used:22652
        send_receipt_ok_gas_fee = computeGasFee(gasPrices, 22652n);
        console.log(send_receipt_ok_gas_fee);
        let stat4 = computeMessageForwardFees(msgPrices, receiptOkTx.inMessage!).stats;
        console.log(stat4);

        let liquidityAfter = await bridgePoolTonCoin.getPoolLiquidity();
        expect(liquidityAfter).toBe(toNano('30'));

        let bridgeBalance = (await blockchain.getContract(bridgePoolTonCoin.address)).balance;
        expect(bridgeBalance).toBeGreaterThanOrEqual(toNano('30'));

        const res3 = await bridgePoolTonCoin.getReceiptDailyLimit(chainId);
        expect(res3.remainToken).toBe(BigInt(10000000000000000 - 10000000000));
        console.log(res3.refreshTime);
        expect(res3.dailyLimit).toBe(BigInt(10000000000000000));

        const res4 = await bridgePoolTonCoin.getReceiptRateLimit(chainId);
        expect(res4.currentTokenAmount).toBeGreaterThanOrEqual(BigInt(1000000000000000 - 10000000000));
        expect(res4.tokenCapacity).toBe(BigInt(1000000000000000));
        expect(res4.rate).toBe(BigInt(1000000000));
        expect(res4.isEnable).toBe(true);

        bridgeReceiptAccount = blockchain.openContract(
            BridgeReceiptAccount.createFromAddress(receiptAccountAddress));
        let receipt = await bridgeReceiptAccount.getReceiptInfo(chainId);
        expect(receipt.totalAmount).toBe(toNano('10'));
        expect(receipt.index).toBe(BigInt(1));
    });

    it('swap native', async () => {
        console.log(oracle.address);
        console.log(testAccount.address);
        console.log(bridge.address);
        console.log(bridgeSwapTonCoin.address);
        console.log(bridgePoolTonCoin.address);

        let account_balance_before = await testAccount.getBalance();

        let balanceBefore = (await blockchain.getContract(bridgePoolTonCoin.address)).balance;
        expect(balanceBefore).toBeGreaterThanOrEqual(toNano('20'));
        let dataFull = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAFTrftWgsEIWehE9Or/iLtKXLuipEbS5x/YIrmX0HqJkAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAJUC+QAmUXSGzTyJjueaHKaCsorIlPuRZ+MzyhtwrYq4opKej0RAG8DjMpBpA6PC7sdvIeJYlTvFDLNXiGt7VherY/NVHZRPJM=";
        let dataFullBuffer = Buffer.from(dataFull, 'base64');
        let messageId = BigInt(11111);
        let sourceChainId = 9992731;
        let targetChainId = 1101;
        let sender = aelf.utils.base58.decode("foDLAM2Up3xLjg43SvCy5Ed6zaY5CKG8uczj6yUVZUweqQUmz");
        let receiver = bridge.address;
        let data = dataFullBuffer.slice(0, 96);
        let dataOther = dataFullBuffer.slice(96);
        let result = await bridge.sendTransmit(
            oracle.getSender(),
            toNano('0.01'),
            messageId,
            sourceChainId,
            targetChainId,
            sender,
            receiver,
            data,
            dataOther,
            swapIdTonCoin,
            HOLEADDRESS
        );
        // let tx = result.transactions[3];
        // let body = tx.outMessages.get(0)?.body;
        // if (body != undefined) {
        //     let info = body.asSlice();
        //     let value = info.loadCoins();
        //     let value1 = info.loadCoins();
        //     let value2 = info.loadCoins();
        //     console.log(value1);
        //     console.log(value);
        //     console.log(value2);
        // }

        expect(result.transactions).toHaveTransaction({
            from: oracle.address,
            to: bridge.address,
            success: true,
        });
        expect(result.transactions).toHaveTransaction({
            from: bridge.address,
            to: bridgeSwapTonCoin.address,
            success: true
        });
        expect(result.transactions).toHaveTransaction({
            from: bridgeSwapTonCoin.address,
            to: bridgePoolTonCoin.address,
            success: true
        });
        expect(result.transactions).toHaveTransaction({
            from: bridgePoolTonCoin.address,
            to: bridgeSwapTonCoin.address,
            success: true
        });
        expect(result.transactions).toHaveTransaction({
            from: bridgePoolTonCoin.address,
            to: testAccount.address,
            success: true
        });

        const transferTx = findTransactionRequired(result.transactions, {
            on: testAccount.address,
            from: bridgePoolTonCoin.address,
            success: true
        });
        let transferFee = printTxGasStats("transfer", transferTx);
        // gas used:309
        transferFee = computeGasFee(gasPrices, 309n);
        console.log(transferFee);


        let liquidityAfter = await bridgePoolTonCoin.getPoolLiquidity();
        expect(liquidityAfter).toBe(BigInt(20000000000 - 100000000));

        let balance = (await blockchain.getContract(bridgePoolTonCoin.address)).balance;
        expect(balance).toBeGreaterThanOrEqual(toNano('20') - toNano('0.1'));
        expect(balance).toBeLessThan(balanceBefore);

        let account_balance = await testAccount.getBalance();
        let diff = account_balance - account_balance_before;
        console.log(diff);
        expect(account_balance).toBe(account_balance_before + toNano('0.1'));
    });

});

function getUTCMidnight(): number {
    const now = new Date();
    // Create a new Date object for today's midnight in UTC
    let time = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate());
    console.log(time);
    return time / 1000;
}
