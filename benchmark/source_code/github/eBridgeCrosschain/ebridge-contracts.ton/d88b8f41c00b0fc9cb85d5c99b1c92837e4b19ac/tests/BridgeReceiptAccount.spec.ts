import {Blockchain, BlockchainSnapshot, SandboxContract, TreasuryContract} from '@ton/sandbox';
import {Address, beginCell, BitString, Cell, Dictionary, toNano} from '@ton/core';
import '@ton/test-utils';
import {compile} from '@ton/blueprint';
import {randomAddress} from "@ton/test-utils";
import {Buffer} from "buffer";
import {BridgeReceiptAccount} from "../wrappers/BridgeReceiptAccount";
import {BridgePool} from "../wrappers/BridgePool";
import {Bridge} from "../wrappers/Bridge";
import {JettonMinter} from "../wrappers/JettonMinter";
import exp from "constants";
import aelf from "aelf-sdk";

describe('BridgeReceiptAccount', () => {
    let code: Cell;
    let blockchain: Blockchain;
    let deployer: SandboxContract<TreasuryContract>;
    let bridge: SandboxContract<TreasuryContract>;
    let owner: SandboxContract<TreasuryContract>;
    let bridgeReceiptAccount: SandboxContract<BridgeReceiptAccount>;

    let testJettonAddress: Address;

    let swapAddress: SandboxContract<TreasuryContract>;
    let poolAddress: SandboxContract<TreasuryContract>;
    let swapSideAddress: SandboxContract<TreasuryContract>;
    let poolSideAddress: SandboxContract<TreasuryContract>;
    let tempUpgrade: Cell;

    let initialState: BlockchainSnapshot;
    let curTime: () => number;
    const chainId = 9992731;
    const chainIdSide = 6662731;
    const amount = toNano('10');

    beforeAll(async () => {
        code = await compile('BridgeReceiptAccount');
        blockchain = await Blockchain.create();
        testJettonAddress = randomAddress();
        owner = await blockchain.treasury("owner");
        bridge = await blockchain.treasury('Bridge');
        swapAddress = await blockchain.treasury('BridgeSwap');
        swapSideAddress = await blockchain.treasury('BridgeSwapSide');
        poolAddress = await blockchain.treasury('BridgePool');
        poolSideAddress = await blockchain.treasury('BridgePoolSide');
        deployer = await blockchain.treasury('deployer');

        bridgeReceiptAccount = blockchain.openContract(BridgeReceiptAccount.createFromConfig({
            owner: owner.address,
            bridge: bridge.address,
            bridgePool: poolAddress.address,
            jettonAddress: testJettonAddress
        }, code));

        console.log(bridge.address);
        console.log(poolAddress.address);

        
        const deployResult = await bridgeReceiptAccount.sendDeploy(
            poolAddress.getSender(), toNano('0.1'),
            chainId, 
            aelf.utils.base58.decode("JKjoabe2wyrdP1P8TvNyD4GZP6z1PuMvU2y5yJ4JTeBjTMAoX"),
            amount);

        expect(deployResult.transactions).toHaveTransaction({
            from: poolAddress.address,
            to: bridgeReceiptAccount.address,
            deploy: true,
            success: true,
        });

        expect(deployResult.transactions).toHaveTransaction({
            from: bridgeReceiptAccount.address,
            to: bridge.address,
            success: true,
        });
        
        let body = deployResult.transactions[deployResult.transactions.length - 2].outMessages.get(0)?.body;
        if(body != undefined) {
            let bodySlice = body.asSlice();
            let receiptOk = bodySlice.loadUint(32);
            let queryId = bodySlice.loadUint(64);
            let targetChainId = bodySlice.loadUint(32);
            let ref = bodySlice.loadRef();
            let refSlice = ref.asSlice();
            let ownerSlice = refSlice.loadAddress();
            let jettonAddressSlice = refSlice.loadAddress();
            let targetAddressSlice = refSlice.loadBuffer(32);
            console.log(aelf.utils.base58.encode(targetAddressSlice));
            let jettonAmount = bodySlice.loadCoins();
            let receiptId = bodySlice.loadRef();
            let receiptIdSlice = receiptId.asSlice();
            let keyHash = receiptIdSlice.loadUintBig(256);
            let index = receiptIdSlice.loadUintBig(256);
            expect(index).toBe(BigInt(1));
        }
        
        const res = await bridgeReceiptAccount.getReceiptInfo(chainId);
        expect(res.totalAmount).toBe(amount);
        expect(res.index).toBe(BigInt(1));

        initialState = blockchain.snapshot();

        curTime = () => blockchain.now ?? Math.floor(Date.now() / 1000);

    });

    afterEach(async () => await blockchain.loadFrom(initialState));


    it('should deploy', async () => {
        // the check is done inside beforeEach
        // blockchain and ebridgeContractsTon are ready to use
    });

    it('record receipt', async () => {
        let amount = toNano('20');
        let res = await bridgeReceiptAccount.sendRecordReceipt(
            poolAddress.getSender(), 
            toNano('0.1'), 
            chainId, 
            aelf.utils.base58.decode("foDLAM2Up3xLjg43SvCy5Ed6zaY5CKG8uczj6yUVZUweqQUmz"),
            amount);
        expect(res.transactions).toHaveTransaction({
            from: poolAddress.address,
            to: bridgeReceiptAccount.address,
            success: true,
        });

        const res1 = await bridgeReceiptAccount.getReceiptInfo(chainId);
        expect(res1.totalAmount).toBe(toNano('30'));
        expect(res1.index).toBe(BigInt(2));
    });

});