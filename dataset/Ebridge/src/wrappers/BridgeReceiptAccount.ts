import {Address, beginCell, Cell, Contract, contractAddress, ContractProvider, Sender, SendMode} from '@ton/core';
import {Bridge} from "./Bridge";
import {Op} from "./constants";

export type BridgeReceiptAccountConfig = {
    owner: Address;
    bridge: Address;
    bridgePool: Address;
    jettonAddress: Address;
};

export function BridgeReceiptAccountConfigToCell(config: BridgeReceiptAccountConfig): Cell {
    return beginCell()
        .storeAddress(config.owner)
        .storeAddress(config.jettonAddress)
        .storeRef(beginCell()
            .storeAddress(config.bridgePool)
            .storeAddress(config.bridge)
            .endCell())
        .endCell();
}

export class BridgeReceiptAccount implements Contract {
    constructor(readonly address: Address, readonly init?: { code: Cell; data: Cell }) {
    }

    static createFromAddress(address: Address) {
        return new BridgeReceiptAccount(address);
    }

    static createFromConfig(config: BridgeReceiptAccountConfig, code: Cell, workchain = 0) {
        const data = BridgeReceiptAccountConfigToCell(config);
        const init = {code, data};
        return new BridgeReceiptAccount(contractAddress(workchain, init), init);
    }

    static packRecordReceiptBody(targetChainId: number, targetAddress: Buffer, amount: number | bigint) {
        let queryId = Bridge.getQueryId();
        return beginCell()
            .storeUint(Op.bridge_receipt_account.record_receipt, 32)
            .storeUint(queryId, 64)
            .storeUint(targetChainId, 32)
            .storeBuffer(targetAddress)
            .storeCoins(amount)
            .endCell();
    }

    async sendDeploy(provider: ContractProvider, via: Sender, value: bigint, targetChainId: number, targetAddress: Buffer, amount: number | bigint) {
        await provider.internal(via, {
            value,
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: BridgeReceiptAccount.packRecordReceiptBody(targetChainId, targetAddress, amount),
        });
    }

    async sendRecordReceipt(provider: ContractProvider, via: Sender, value: bigint, targetChainId: number, targetAddress: Buffer, amount: number | bigint) {
        await provider.internal(via, {
            value,
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: BridgeReceiptAccount.packRecordReceiptBody(targetChainId, targetAddress, amount),
        });
    }
    async sendReceiptOk(
        provider: ContractProvider,
        via: Sender,
        value: bigint,
        targetChainId: number,
        owner: Address,
        jetton: Address,
        targetAddress: Buffer,
        amount: number | bigint,
        receiptId: Cell
    ) {
        await provider.internal(via, {
            value: value,
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: Bridge.packReceiptOk(targetChainId,owner,jetton,targetAddress,amount,receiptId)
        });
    }
    async getReceiptInfo(provider: ContractProvider, chainId: number) {
        const {stack} = await provider.get('get_receipt_info', [{
            type: 'int',
            value: BigInt(chainId)
        }]);
        return {
            totalAmount: stack.readBigNumber(),
            index: stack.readBigNumber()
        }
    }
}


