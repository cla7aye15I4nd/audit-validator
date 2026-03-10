import {
    Address,
    beginCell,
    Cell,
    Contract,
    contractAddress,
    ContractProvider,
    Dictionary,
    Sender,
    SendMode, toNano
} from '@ton/core';
import {Bridge} from "./Bridge";
import {Op} from "./constants";
import now = jest.now;
import {Buffer} from "buffer";

export type BridgePoolConfig = {
    bridge_address: Address,
    bridge_receipt_account_code: Cell,
    bridge_swap_address: Address | null,
    jetton_address: Address,
    daily_limit: Dictionary<any, any>,
    rate_limit: Dictionary<any, any>,
    pool_liquidity_account_code: Cell,
    admin: Address,
    owner: Address,
    temp_upgrade: Cell
};

export type dailyLimitConfig = {
    chainId: number,
    limitType: number,
    refreshTime: number,
    dailyLimit: bigint | number
};

export type rateLimitConfig = {
    chainId: number,
    limitType: number,
    tokenCapacity: bigint,
    rate: bigint
};

export function BridgePoolConfigToCell(config: BridgePoolConfig): Cell {
    return beginCell()
        .storeUint(0, 256)
        .storeAddress(config.admin)
        .storeAddress(config.owner)
        .storeRef(beginCell()
            .storeDict(config.daily_limit)
            .storeDict(config.rate_limit)
            .endCell())
        .storeRef(beginCell()
            .storeAddress(config.bridge_address)
            .storeAddress(config.bridge_swap_address)
            .storeRef(beginCell()
                .storeAddress(config.jetton_address)
                .storeAddress(null)
                .endCell())
            .endCell())
        .storeRef(beginCell()
            .storeRef(config.bridge_receipt_account_code)
            .storeRef(config.pool_liquidity_account_code)
            .endCell())
        .storeRef(config.temp_upgrade)
        .endCell();
}

export class BridgePool implements Contract {
    constructor(readonly address: Address, readonly init?: { code: Cell; data: Cell }) {
    }

    static createFromAddress(address: Address) {
        return new BridgePool(address);
    }

    static createFromConfig(config: BridgePoolConfig, code: Cell, workchain = 0) {
        const data = BridgePoolConfigToCell(config);
        const init = {code, data};
        return new BridgePool(contractAddress(workchain, init), init);
    }

    async sendDeploy(provider: ContractProvider, via: Sender, value: bigint) {
        await provider.internal(via, {
            value,
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: beginCell().endCell(),
        });
    }

    static PackSetBridgeBody(bridge: Address) {
        let query_id = Bridge.getQueryId();
        return beginCell()
            .storeUint(Op.bridge_pool.set_bridge, 32)
            .storeUint(query_id, 64)
            .storeAddress(bridge)
            .endCell();
    }

    static PackSetJettonBody(jetton: Address, jettonWalletAddress: Address) {
        let query_id = Bridge.getQueryId();
        return beginCell()
            .storeUint(Op.bridge_pool.set_jetton_wallet_address, 32)
            .storeUint(query_id, 64)
            .storeAddress(jetton)
            .storeAddress(jettonWalletAddress)
            .endCell();
    }

    static PackSetBridgeSwapBody(swap: Address) {
        let query_id = Bridge.getQueryId();
        return beginCell()
            .storeUint(Op.bridge_pool.set_bridge_swap, 32)
            .storeUint(query_id, 64)
            .storeAddress(swap)
            .endCell();
    }

    static packLockBody(targetChainId: number, targetAddress: Buffer, fromSender: Address) {
        let payload = beginCell()
            .storeUint(Op.bridge_pool.lock, 32)
            .storeUint(targetChainId, 32)
            .storeBuffer(targetAddress, 32)
            .storeAddress(fromSender)
            .endCell();
        return payload;
    }

    static packAddLiquidityBody() {
        let payload = beginCell()
            .storeUint(Op.bridge_pool.add_liquidity, 32)
            .endCell();
        return payload;
    }

    static packAddNativeLiquidityBody(amount: bigint | number) {
        let queryId = Bridge.getQueryId();
        let payload = beginCell()
            .storeUint(Op.bridge_pool.add_native_token_liquidity, 32)
            .storeUint(queryId, 64)
            .storeCoins(amount)
            .endCell();
        return payload;
    }

    static PackReleaseBody(swapId: Cell, receiptId: Cell, receiptHash: Buffer, targetAddress: Address, chainId: number) {
        let queryId = Bridge.getQueryId();
        let messageId = Bridge.getQueryId();
        let payload = beginCell()
            .storeUint(Op.bridge_pool.release, 32)
            .storeUint(queryId, 64)
            .storeRef(swapId)
            .storeUint(messageId, 256)
            .storeRef(beginCell()
                .storeRef(receiptId)
                .storeBuffer(receiptHash, 32)
                .storeAddress(targetAddress)
                .endCell())
            .storeUint(chainId, 32)
            .storeCoins(toNano('1'))
            .endCell();
        return payload;
    }

    static PackLimitKey(chainId: number, limitType: number) {
        let key = beginCell().storeUint(chainId, 32).storeUint(limitType, 1).endCell();
        let key_hash = key.hash();
        return BigInt("0x" + key_hash.toString('hex'));
    }

    static PackDailyLimitValue(chainId: number, limitType: number, refreshTime: number, dailyLimit: bigint) {
        return beginCell().storeUint(dailyLimit, 256).storeUint(refreshTime, 64).storeUint(dailyLimit, 256).endCell();
    }

    static PackRateLimitValue(chainId: number, limitType: number, time: number, isEnable: boolean, tokenCapacity: bigint, rate: bigint) {
        return beginCell().storeUint(tokenCapacity, 256).storeUint(time, 64).storeUint(tokenCapacity, 256).storeBit(isEnable).storeUint(rate, 256).endCell();
    }

    static PackSetDailyLimitBody(config: dailyLimitConfig[]) {
        let query_id = Bridge.getQueryId();
        const root = beginCell()
            .storeUint(Op.bridge_pool.set_daily_limit_config, 32)
            .storeUint(query_id, 64)
            .storeUint(config[0].chainId, 32)
            .storeUint(config[0].limitType, 1)
            .storeUint(config[0].refreshTime, 64)
            .storeUint(config[0].dailyLimit, 256);
        let cell: Cell | null = null;

        for (let i = config.length - 1; i >= 1; i--) {
            const newCell = beginCell()
                .storeUint(config[i].chainId, 32)
                .storeUint(config[i].limitType, 1)
                .storeUint(config[i].refreshTime, 64)
                .storeUint(config[i].dailyLimit, 256);

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

    static PackSetRateLimitBody(config: rateLimitConfig[]) {
        let query_id = Bridge.getQueryId();
        const root = beginCell()
            .storeUint(Op.bridge_pool.set_rate_limit_config, 32)
            .storeUint(query_id, 64)
            .storeUint(config[0].chainId, 32)
            .storeUint(config[0].limitType, 1)
            .storeBit(true)
            .storeUint(config[0].tokenCapacity, 256)
            .storeUint(config[0].rate, 256)
        let cell: Cell | null = null;

        for (let i = config.length - 1; i >= 1; i--) {
            const newCell = beginCell()
                .storeUint(config[i].chainId, 32)
                .storeUint(config[i].limitType, 1)
                .storeBit(true)
                .storeUint(config[i].tokenCapacity, 256)
                .storeUint(config[i].rate, 256);

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

    // send
    async sendSetBridge(provider: ContractProvider, via: Sender, value: bigint, bridge: Address) {
        await provider.internal(via, {
            value,
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: BridgePool.PackSetBridgeBody(bridge),
        });
    }

    async sendSetJetton(provider: ContractProvider, via: Sender, value: bigint, jetton: Address, jettonWalletAddress: Address) {
        await provider.internal(via, {
            value,
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: BridgePool.PackSetJettonBody(jetton, jettonWalletAddress),
        });
    }

    async sendSetDailyLimit(provider: ContractProvider, via: Sender, value: bigint, dailyLimitConfig: dailyLimitConfig[]) {

        await provider.internal(via, {
            value,
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: BridgePool.PackSetDailyLimitBody(dailyLimitConfig),
        });
    }

    async sendSetRateLimit(provider: ContractProvider, via: Sender, value: bigint, config: rateLimitConfig[]) {
        await provider.internal(via, {
            value,
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: BridgePool.PackSetRateLimitBody(config),
        });
    }

    async sendSetBridgeSwap(provider: ContractProvider, via: Sender, value: bigint, swap: Address) {
        await provider.internal(via, {
            value,
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: BridgePool.PackSetBridgeSwapBody(swap),
        });
    }

    async sendRelease(provider: ContractProvider, via: Sender, value: bigint, swapId: Cell, receiptId: Cell, receiptHash: Buffer, targetAddress: Address, chainId: number) {
        await provider.internal(via, {
            value,
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: BridgePool.PackReleaseBody(swapId, receiptId, receiptHash, targetAddress, chainId)
        });
    }
    
    async sendAddNativeLiquidity(provider: ContractProvider, via: Sender, value: bigint, amount: bigint | number) {
        await provider.internal(via, {
            value,
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: BridgePool.packAddNativeLiquidityBody(amount)
        });
    }
    

    async getAdmin(provider: ContractProvider) {
        const result = await provider.get('get_admin', []);
        return result.stack.readAddress();
    }

    async getBridgeAddress(provider: ContractProvider) {
        const result = await provider.get('get_bridge_address', []);
        return result.stack.readAddress();
    }

    async getBridgeSwapAddress(provider: ContractProvider) {
        const result = await provider.get('get_bridge_swap_address', []);
        return result.stack.readAddress();
    }

    async getJettonAddress(provider: ContractProvider) {
        const {stack} = await provider.get('get_jetton_address', []);
        // return stack.readNumber();
        return {
            jettonAddress: stack.readAddress(),
            poolJettonWalletAddress: stack.readAddress()
        }
    }

    async getReceiptDailyLimit(provider: ContractProvider, chainId: number) {
        const {stack} = await provider.get('get_receipt_daily_limit', [
            {
                type: 'int',
                value: BigInt(chainId)
            }
        ]);
        return {
            remainToken: stack.readBigNumber(),
            refreshTime: stack.readNumber(),
            dailyLimit: stack.readBigNumber()
        }
    }

    async getSwapDailyLimit(provider: ContractProvider, chainId: number) {
        const {stack} = await provider.get('get_swap_daily_limit', [
            {
                type: 'int',
                value: BigInt(chainId)
            }
        ]);
        return {
            remainToken: stack.readBigNumber(),
            refreshTime: stack.readNumber(),
            dailyLimit: stack.readBigNumber()
        }
    }

    async getReceiptRateLimit(provider: ContractProvider, chainId: number) {
        const {stack} = await provider.get('get_receipt_rate_limit_state', [
            {
                type: 'int',
                value: BigInt(chainId)
            }
        ]);
        return {
            currentTokenAmount: stack.readBigNumber(),
            refreshTime: stack.readNumber(),
            tokenCapacity: stack.readBigNumber(),
            isEnable: stack.readBoolean(),
            rate: stack.readBigNumber()
        }
    }

    async getSwapRateLimit(provider: ContractProvider, chainId: number) {
        const {stack} = await provider.get('get_swap_rate_limit_state', [
            {
                type: 'int',
                value: BigInt(chainId)
            }
        ]);
        return {
            currentTokenAmount: stack.readBigNumber(),
            refreshTime: stack.readNumber(),
            tokenCapacity: stack.readBigNumber(),
            isEnable: stack.readBoolean(),
            rate: stack.readBigNumber()
        }
    }

    async getPoolLiquidityAccountAddress(provider: ContractProvider, address: Address) {
        const result = await provider.get('get_pool_liquidity_account_address', [
            {
                type: 'slice',
                cell: beginCell().storeAddress(address).endCell()
            }
        ]);
        return result.stack.readAddress();
    }

    async getReceiptAddress(provider: ContractProvider, address: Address) {
        const result = await provider.get('get_bridge_receipt_address', [
            {
                type: 'slice',
                cell: beginCell().storeAddress(address).endCell()
            }
        ]);
        return result.stack.readAddress();
    }

    async getPoolLiquidity(provider: ContractProvider) {
        const result = await provider.get('get_pool_liquidity', []);
        return result.stack.readBigNumber();
    }
}

