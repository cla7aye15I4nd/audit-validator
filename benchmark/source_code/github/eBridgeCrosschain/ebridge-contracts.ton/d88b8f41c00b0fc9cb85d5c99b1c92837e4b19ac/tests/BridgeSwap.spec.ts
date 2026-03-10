import {Blockchain, BlockchainSnapshot, SandboxContract, TreasuryContract} from '@ton/sandbox';
import {Address, beginCell, BitString, Cell, Dictionary, toNano, Slice} from '@ton/core';
import {BridgeSwap, SwapConfig} from '../wrappers/BridgeSwap';
import '@ton/test-utils';
import {compile} from '@ton/blueprint';
import {randomAddress} from "@ton/test-utils";
import {Buffer} from "buffer";

describe('BridgeSwap', () => {
    let code: Cell;
    let blockchain: Blockchain;
    let deployer: SandboxContract<TreasuryContract>;
    let swap: SandboxContract<BridgeSwap>;
    let testJettonAddress: Address;
    let testJettonAddress1: Address;
    let bridge: SandboxContract<TreasuryContract>;
    let bridgePool: SandboxContract<TreasuryContract>;
    let oracle: Address;
    let admin: SandboxContract<TreasuryContract>;
    let owner: Address;
    let tempUpgrade: Cell;
    let initialState: BlockchainSnapshot;
    let curTime: number;
    const chainId = 9992731;
    const chainIdSide = 6662731;
    const chainIdSide2 = 3332731;
    let swapId: Cell;

    beforeAll(async () => {
        code = await compile('BridgeSwap');
        blockchain = await Blockchain.create();

        curTime = blockchain.now ?? Math.floor(Date.now() / 1000);

        testJettonAddress1 = randomAddress();
        testJettonAddress = randomAddress();
        admin = await blockchain.treasury('admin');
        owner = randomAddress();
        bridgePool = await blockchain.treasury('BridgePool');
        bridge = await blockchain.treasury('Bridge');
        oracle = randomAddress();
        tempUpgrade = beginCell().endCell();

        // let swap_cell = beginCell().storeUint(chainId, 32).storeAddress(testJettonAddress).endCell();
        // let hash = swap_cell.hash();
        // let hashInt = BigInt("0x" + hash.toString('hex'));
        // let value = beginCell().storeUint(1n, 64).storeUint(1000n, 64).storeUint(0n, 256).storeUint(0n, 256).endCell();
        let dic = Dictionary.empty(Dictionary.Keys.BigUint(256), Dictionary.Values.Cell());
        // dic.set(hashInt,value);
        // let receiptDic = Dictionary.empty(Dictionary.Keys.Buffer(32), Dictionary.Values.Cell());
        swap = blockchain.openContract(BridgeSwap.createFromConfig({
            bridgePoolAddress: bridgePool.address,
            jettonAddress: testJettonAddress,
            bridgeAddress: bridge.address,
            admin: admin.address,
            owner: owner,
            tempUpgrade: tempUpgrade,
            swapDic: dic,
            receiptDic: dic
        }, code));

        deployer = await blockchain.treasury('deployer');

        const deployResult = await swap.sendDeploy(deployer.getSender(), toNano('0.1'));

        expect(deployResult.transactions).toHaveTransaction({
            from: deployer.address,
            to: swap.address,
            deploy: true,
            success: true,
        });
        initialState = blockchain.snapshot();

        // create swap
        const result = await swap.sendCreateSwap(admin.getSender(), toNano('2'), [{
            fromChainId: chainId,
            originShare: 1000,
            targetShare: 1
        }]);

        expect(result.transactions).toHaveTransaction({
            from: admin.address,
            to: swap.address,
            success: true,
        });

        let body = result.transactions[1].outMessages.get(0)?.body;
        if (body != undefined) {
            let info = body.asSlice();
            let swapInfo = info.loadRef().asSlice();
            let fromChainId = swapInfo.loadUint(32);
            let swapId_log = swapInfo.loadRef();
            console.log(fromChainId);
            console.log(swapId_log.asSlice().loadBuffer(32).toString('base64'));
            swapId = swapId_log;
        }
    });

    afterEach(async () => await blockchain.loadFrom(initialState));


    it('should deploy', async () => {
        // the check is done inside beforeEach
        // blockchain and ebridgeContractsTon are ready to use
    });
    it('get_admin', async () => {
        const res = await swap.getAdmin();
        expect(res).toEqualAddress(admin.address);
    });

    it('send_create_swap', async () => {
        const result = await swap.sendCreateSwap(admin.getSender(), toNano('2'), [{
            fromChainId: chainIdSide2,
            originShare: 1,
            targetShare: 1000
        }, {
            fromChainId: chainIdSide,
            originShare: 1,
            targetShare: 100000
        }]);

        expect(result.transactions).toHaveTransaction({
            from: admin.address,
            to: swap.address,
            success: true,
        });
        let body = result.transactions[1].outMessages.get(0)?.body;
        if (body != undefined) {
            let info = body.asSlice();
            let refNumbers = info.remainingRefs;
            for (let i = 0; i < refNumbers; i++) {
                let swapInfo = info.loadRef().asSlice();
                let fromChainId = swapInfo.loadUint(32);
                let swapId = swapInfo.loadRef().asSlice();
                console.log(fromChainId);
                console.log(swapId.loadBuffer(32).toString('base64'));
            }
        }
        let res1 = await swap.getSwapData(chainIdSide2);
        console.log(res1.swapId.toString('hex'));
    });

    it('send_swap', async () => {
        let receiptIdToken = "d9a68135766c7ad54a84d37c8714a46a33a5a20fb68f8017dc3e1d5fbb3e8a0b";
        let receiptIdTokenBuffer = Buffer.from(receiptIdToken, 'hex');
        let receiptHash = "232bae4714830a2457e91d83365d8cc1362f214bb57fe4923c8765cdca36ab17";
        let receiptHashBuffer = Buffer.from(receiptHash, 'hex');
        let targetAddress = randomAddress();
        console.log(swapId);
        console.log(targetAddress);
        const result = await swap.sendSwap(
            bridge.getSender(), 
            toNano('1'), 
            swapId,
            receiptIdTokenBuffer,
            1n,
            receiptHashBuffer,
            targetAddress,
            100000000n);
        expect(result.transactions).toHaveTransaction({
            from: bridge.address,
            to: swap.address,
            success: true,
        });
        
        let body = result.transactions[1].outMessages.get(0)?.body;
        if (body != undefined) {
            let info = body.asSlice();
            let fromChainId = info.loadUint(32);
            let amount = info.loadCoins();
            console.log(fromChainId);
            console.log(amount);
        }
    });
    
    it('swap failed resend', async () => {
        let receiptIdToken = "d9a68135766c7ad54a84d37c8714a46a33a5a20fb68f8017dc3e1d5fbb3e8a0b";
        let receiptIdTokenBuffer = Buffer.from(receiptIdToken, 'hex');
        let receiptHash = "232bae4714830a2457e91d83365d8cc1362f214bb57fe4923c8765cdca36ab17";
        let receiptHashBuffer = Buffer.from(receiptHash, 'hex');
        let receiptId = beginCell()
            .storeBuffer(receiptIdTokenBuffer,32)
            .storeUint(1,256)
            .endCell();
        let result = await swap.sendSwapFailed(
            bridgePool.getSender(), 
            toNano('0.5'),
            receiptId,
            receiptHashBuffer);
        expect(result.transactions).toHaveTransaction({
            from: bridgePool.address,
            to: swap.address,
            success: true,
        });
        let outMessage = result.transactions[1].outMessages.get(0);
        console.log(bridge.address);
        console.log(outMessage?.info.dest);
        expect(outMessage?.info.dest).toEqualAddress(bridge.address);
        if (outMessage != undefined) {
            let body = outMessage.body;
            let info = body.asSlice();
            
            console.log(info);
        }
    });
    
    it('record swap',async () => {
        let receiptIdToken = "d9a68135766c7ad54a84d37c8714a46a33a5a20fb68f8017dc3e1d5fbb3e8a0b";
        let receiptIdTokenBuffer = Buffer.from(receiptIdToken, 'hex');
        let receiptHash = "232bae4714830a2457e91d83365d8cc1362f214bb57fe4923c8765cdca36ab17";
        let receiptHashBuffer = Buffer.from(receiptHash, 'hex');
        let targetAddress = randomAddress();
        console.log(swapId);
        console.log(targetAddress);
        let receiptId = beginCell()
            .storeBuffer(receiptIdTokenBuffer,32)
            .storeUint(1,256)
            .endCell();
        const result = await swap.sendSwap(
            bridge.getSender(),
            toNano('1'),
            swapId,
            receiptIdTokenBuffer,
            1n,
            receiptHashBuffer,
            targetAddress,
            100000000n);
        expect(result.transactions).toHaveTransaction({
            from: bridge.address,
            to: swap.address,
            success: true,
        });
        let res1 = await swap.getSwapData(chainId);
        console.log(res1.swapId.toString('hex'));
        console.log(res1.fromChainId);
        expect(res1.fromChainId).toEqual(chainId);
        console.log(res1.swappedAmount);
        expect(res1.swappedAmount).toEqual(0n);
        expect(res1.swappedTimes).toEqual(0n);
        
        let amount_convert = 100000n;
       
        const res = await swap.sendRecordSwap(
            bridgePool.getSender(),
            toNano('1'),
            swapId,
            receiptId,
            amount_convert
        );
        expect(res.transactions).toHaveTransaction({
            from: bridgePool.address,
            to: swap.address,
            success: true,
        });
        let res2 = await swap.getSwapData(chainId);
        console.log(res2.swapId.toString('hex'));
        console.log(res2.fromChainId);
        expect(res2.fromChainId).toEqual(chainId);
        console.log(res2.swappedAmount);
        expect(res2.swappedAmount).toEqual(amount_convert);
        expect(res2.swappedTimes).toEqual(1n);
    });
});
