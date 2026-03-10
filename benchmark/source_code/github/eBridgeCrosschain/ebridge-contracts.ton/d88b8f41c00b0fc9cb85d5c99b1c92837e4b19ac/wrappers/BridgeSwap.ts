import {
    Address,
    beginCell,
    Cell,
    Contract,
    contractAddress,
    ContractProvider,
    Dictionary,
    Sender,
    SendMode
} from '@ton/core';
import {Errors, Op} from "./constants";

export type BridgeSwapConfig = {
    bridgePoolAddress: Address,
    jettonAddress: Address,
    bridgeAddress: Address,
    admin: Address,
    owner: Address,
    tempUpgrade: Cell,
    swapDic: Dictionary<any, any>
    receiptDic: Dictionary<any, any>
};

export function BridgeSwapConfigToCell(config: BridgeSwapConfig): Cell {
    return beginCell()
        .storeAddress(config.jettonAddress)
        .storeRef(beginCell()
            .storeAddress(config.bridgePoolAddress)
            .storeAddress(config.bridgeAddress)
            .endCell())
        .storeRef(beginCell()
            .storeAddress(config.admin)
            .storeAddress(config.owner)
            .endCell())
        .storeRef(beginCell()
            .storeDict(config.swapDic)
            .storeDict(config.receiptDic)
            .endCell())
        // .storeRef(beginCell().endCell())
        // .storeRef(beginCell()
        //     .storeMaybeRef(null)
        //     .storeMaybeRef(null)
        //     .endCell())
        .storeRef(config.tempUpgrade)
        .endCell();
}

export type SwapConfig = {
    fromChainId: number,
    originShare: number,
    targetShare: number
}

export class BridgeSwap implements Contract {
    constructor(readonly address: Address, readonly init?: { code: Cell; data: Cell }) {
    }

    static createFromAddress(address: Address) {
        return new BridgeSwap(address);
    }

    static createFromConfig(config: BridgeSwapConfig, code: Cell, workchain = 0) {
        const data = BridgeSwapConfigToCell(config);
        const init = {code, data};
        return new BridgeSwap(contractAddress(workchain, init), init);
    }

    async sendDeploy(provider: ContractProvider, via: Sender, value: bigint) {
        await provider.internal(via, {
            value,
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: beginCell().endCell(),
        });
    }

    static getQueryId() {
        return Math.round(Math.random() * (2000 - 1000) + 1000);
    }

    static getRandomId() {
        return Math.round(Math.random() * (9999999 - 100) + 1000);
    }

    static PackCreateSwapBody(swapInfos: SwapConfig[]): Cell {
        let queryId = BridgeSwap.getQueryId();
        const root = beginCell()
            .storeUint(Op.bridge_swap.create_swap, 32) // op
            .storeUint(queryId, 64) // query_id;
            .storeUint(swapInfos[0].fromChainId, 32)
            .storeUint(swapInfos[0].originShare, 64)
            .storeUint(swapInfos[0].targetShare, 64);

        let cell: Cell | null = null;

        for (let i = swapInfos.length - 1; i >= 1; i--) {
            const newCell = beginCell().storeUint(swapInfos[i].fromChainId, 32).storeUint(swapInfos[i].originShare, 64).storeUint(swapInfos[i].targetShare, 64);

            if (cell) {
                newCell.storeRef(cell);
            }

            cell = newCell.endCell();
        }

        if (cell) {
            root.storeRef(cell);
        }

        return root.endCell();
    }

    static PackSwapBody(swapId: Cell, receiptIdToken: Buffer, receiptIndex: bigint, receiptHash: Buffer, targetAddress: Address, receiptAmount: bigint): Cell {
        let queryId = BridgeSwap.getQueryId();
        let messageId = BridgeSwap.getRandomId();
        console.log(receiptHash.length);
        return beginCell()
            .storeUint(Op.bridge_swap.swap, 32) // op
            .storeUint(queryId, 64) // query_id;
            .storeRef(swapId)
            .storeUint(messageId, 256)
            .storeRef(beginCell()
                .storeRef(beginCell().storeBuffer(receiptIdToken).storeUint(receiptIndex, 256).endCell())
                .storeBuffer(receiptHash, 32)
                .storeAddress(targetAddress)
                .endCell())
            .storeUint(receiptAmount, 256)
            .endCell();
    }

    static PackSwapFailedBody(receiptId: Cell, receiptHash: Buffer, error: number, waitSeconds: bigint): Cell {
        let queryId = BridgeSwap.getQueryId();
        let messageId = BridgeSwap.getRandomId();
        console.log(receiptHash.length);
        return beginCell()
            .storeUint(Op.bridge_swap.swap_failed, 32) // op
            .storeUint(queryId, 64) // query_id;
            .storeRef(beginCell()
                .storeRef(receiptId)
                .storeBuffer(receiptHash, 32)
                .endCell())
            .storeUint(messageId, 256)
            .storeUint(error, 32)
            .storeUint(waitSeconds, 64)
            .endCell();
    }

    static PackRecordSwapBody(swapId: Cell,
                              receiptId: Cell,
                              amount: number | bigint): Cell {
        let queryId = BridgeSwap.getQueryId();
        return beginCell()
            .storeUint(Op.bridge_swap.record_swap, 32) // op
            .storeUint(queryId, 64) // query_id;
            .storeRef(swapId)
            .storeRef(receiptId)
            .storeCoins(amount)
            .endCell();
    }

    async sendCreateSwap(provider: ContractProvider, via: Sender, value: bigint, swapInfos: SwapConfig[]) {
        await provider.internal(via, {
            value,
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: BridgeSwap.PackCreateSwapBody(swapInfos)
        });
    }

    async sendSwap(provider: ContractProvider, via: Sender, value: bigint, swapId: Cell, receiptIdToken: Buffer, receiptIndex: bigint, receiptHash: Buffer, targetAddress: Address, receiptAmount: bigint) {
        await provider.internal(via, {
            value,
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: BridgeSwap.PackSwapBody(swapId, receiptIdToken, receiptIndex, receiptHash, targetAddress, receiptAmount)
        });
    }

    async sendSwapFailed(provider: ContractProvider, via: Sender, value: bigint, receiptId: Cell, receiptHash: Buffer) {
        await provider.internal(via, {
            value,
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: BridgeSwap.PackSwapFailedBody(receiptId, receiptHash, Errors.bridge_pool.DAILY_LIMIT_EXCEEDED, 86400n)
        });
    }

    async sendRecordSwap(provider: ContractProvider, via: Sender, value: bigint, swapId: Cell, receiptId: Cell, amount: number | bigint) {
        await provider.internal(via, {
            value,
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: BridgeSwap.PackRecordSwapBody(swapId, receiptId, amount)
        });
    }

    async getAdmin(provider: ContractProvider) {
        const result = await provider.get('get_admin', []);
        return result.stack.readAddress();
    }

    async getSwapData(provider: ContractProvider, chainId: number) {
        const {stack} = await provider.get('get_swap_data', [
            {
                type: 'int',
                value: BigInt(chainId)
            }
        ]);
        // return stack.readNumber();
        return {
            swapId: stack.readBuffer(),
            fromChainId: stack.readNumber(),
            originShare: stack.readNumber(),
            targetShare: stack.readNumber(),
            swappedAmount: stack.readBigNumber(),
            swappedTimes: stack.readBigNumber()
        }
    }
    
    async getFeeData(provider: ContractProvider) {
        const res = await provider.get('get_gas_fee', [
        ]);
        return res.stack.readBigNumber();
    }


}


