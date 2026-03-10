import { Address, beginCell, Cell, Contract, contractAddress, ContractProvider, Sender, SendMode } from '@ton/core';
import {Op} from "./constants";
import {Bridge} from "./Bridge";

export type BridgePoolLiquidityAccountConfig = {
    owner: Address,
    bridgePoolAddress: Address,
    jettonAddress: Address
};

export function BridgePoolLiquidityAccountConfigToCell(config: BridgePoolLiquidityAccountConfig): Cell {
    return beginCell()
        .storeAddress(config.owner)
        .storeAddress(config.bridgePoolAddress)
        .storeAddress(config.jettonAddress)
        .storeUint(0, 256)
        .endCell();
}

export class BridgePoolLiquidityAccount implements Contract {
    constructor(readonly address: Address, readonly init?: { code: Cell; data: Cell }) {}

    static createFromAddress(address: Address) {
        return new BridgePoolLiquidityAccount(address);
    }

    static createFromConfig(config: BridgePoolLiquidityAccountConfig, code: Cell, workchain = 0) {
        const data = BridgePoolLiquidityAccountConfigToCell(config);
        const init = { code, data };
        return new BridgePoolLiquidityAccount(contractAddress(workchain, init), init);
    }
    
    static packRemoveLiquidityBody(amount:number|bigint,isNative:boolean=false){
        let queryId = Bridge.getQueryId();
        return beginCell()
            .storeUint(Op.bridge_pool_liquidity_account.account_remove_liquidity, 32)
            .storeUint(queryId,64)
            .storeCoins(amount)
            .storeBit(isNative)
            .endCell();
    }

    async sendDeploy(provider: ContractProvider, via: Sender, value: bigint) {
        await provider.internal(via, {
            value,
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: beginCell().endCell(),
        });
    }
    
    async sendRemoveLiquidity(provider: ContractProvider, via: Sender, value: bigint, amount: bigint,isNative:boolean=false) {
        await provider.internal(via, {
            value,
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: BridgePoolLiquidityAccount.packRemoveLiquidityBody(amount,isNative),
        });
    }
    
    async getLiquidity(provider: ContractProvider){
        const {stack} = await provider.get('get_lp_account_data',[]);
        return {
            owner:stack.readAddress(),
            bridgePoolAddress:stack.readAddress(),
            jettonAddress:stack.readAddress(),
            liquidity:stack.readBigNumber()
        }
    }
}


