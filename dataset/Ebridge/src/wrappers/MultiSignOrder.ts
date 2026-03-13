import { Address, beginCell, Cell, Contract, contractAddress, ContractProvider, Sender, SendMode } from '@ton/core';

export type MultiSigOrderConfig = {};

export function MultiSigOrderConfigToCell(config: MultiSigOrderConfig): Cell {
    return beginCell().endCell();
}

export class MultiSigOrder implements Contract {
    constructor(readonly address: Address, readonly init?: { code: Cell; data: Cell }) {}

    static createFromAddress(address: Address) {
        return new MultiSigOrder(address);
    }

    static createFromConfig(config: MultiSigOrderConfig, code: Cell, workchain = 0) {
        const data = MultiSigOrderConfigToCell(config);
        const init = { code, data };
        return new MultiSigOrder(contractAddress(workchain, init), init);
    }

    async sendDeploy(provider: ContractProvider, via: Sender, value: bigint) {
        await provider.internal(via, {
            value,
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: beginCell().endCell(),
        });
    }
}


