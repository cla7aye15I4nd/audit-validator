import { Address, beginCell, Cell, Contract, contractAddress, ContractProvider, Sender, SendMode } from '@ton/core';

export type MultiSigConfig = {};

export function MultiSigConfigToCell(config: MultiSigConfig): Cell {
    return beginCell().endCell();
}

export class MultiSig implements Contract {
    constructor(readonly address: Address, readonly init?: { code: Cell; data: Cell }) {}

    static createFromAddress(address: Address) {
        return new MultiSig(address);
    }

    static createFromConfig(config: MultiSigConfig, code: Cell, workchain = 0) {
        const data = MultiSigConfigToCell(config);
        const init = { code, data };
        return new MultiSig(contractAddress(workchain, init), init);
    }

    async sendDeploy(provider: ContractProvider, via: Sender, value: bigint) {
        await provider.internal(via, {
            value,
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: beginCell().endCell(),
        });
    }
}


