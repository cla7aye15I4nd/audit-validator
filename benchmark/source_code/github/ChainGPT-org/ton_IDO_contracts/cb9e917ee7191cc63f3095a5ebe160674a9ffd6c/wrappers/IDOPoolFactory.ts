import { Address, beginCell, Cell, Contract, contractAddress, ContractProvider, Sender, SendMode } from '@ton/core';

export type IDOPoolFactoryConfig = {
    poolCode: Cell,
    zeroAddress: Address
};

export function iDOPoolFactoryConfigToCell(config: IDOPoolFactoryConfig): Cell {
    return beginCell().storeUint(0, 32).storeRef(config.poolCode).storeMaybeRef().storeAddress(config.zeroAddress).endCell();
}

export const Opcodes = {
    registerPool: 0xfcb6f52c,
};

export class IDOPoolFactory implements Contract {
    constructor(readonly address: Address, readonly init?: { code: Cell; data: Cell }) {}

    static createFromAddress(address: Address) {
        return new IDOPoolFactory(address);
    }

    static createFromConfig(config: IDOPoolFactoryConfig, code: Cell, workchain = 0) {
        const data = iDOPoolFactoryConfigToCell(config);
        const init = { code, data };
        return new IDOPoolFactory(contractAddress(workchain, init), init);
    }

    async sendDeploy(provider: ContractProvider, via: Sender, value: bigint) {
        await provider.internal(via, {
            value,
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: beginCell().endCell(),
        });
    }

    async sendRegisterPool(
        provider: ContractProvider,
        via: Sender,
        opts: {
            queryID: number,
            value: bigint,
            signerAddr: bigint,
            sellTokenAccountAddr: Address;
            sellTokenMintAddr: Address;
            fundingWalletAddr: Address;
            openTime: number,
            duration: number,
            buyCurrAddr: Address,
            buyCurrDecimals: number,
            buyCurrRate: bigint,
            buyCurrTokenAccountAddr: Address
        }
    ) {
        await provider.internal(via, {
            value: opts.value,
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: beginCell()
                .storeUint(Opcodes.registerPool, 32)
                .storeUint(opts.queryID ?? 0, 64)
                .storeAddress(opts.fundingWalletAddr)
                .storeRef(
                    new Cell()
                        .asBuilder()
                        .storeUint(opts.signerAddr, 256)
                        .storeUint(opts.openTime, 32)
                        .storeUint(opts.duration, 32)
                        .storeAddress(opts.sellTokenAccountAddr)
                        .storeAddress(opts.sellTokenMintAddr)
                )
                .storeRef(
                    new Cell()
                        .asBuilder()
                        .storeAddress(opts.buyCurrAddr)
                        .storeUint(opts.buyCurrDecimals, 8)
                        .storeCoins(opts.buyCurrRate)
                        .storeAddress(opts.buyCurrTokenAccountAddr)
                )
                .endCell(),
        });
    }

    async getBalance(provider: ContractProvider) {
        return (await provider.getState()).balance;
    }

    async getPoolCount(provider: ContractProvider) {
        const result = await provider.get('get_pool_count', []);
        return result.stack.readNumber();
    }

    async getPoolAddress(provider: ContractProvider, id: number) {
        const result = await provider.get('get_pool_address', [{type: "int", value: BigInt(id)}]);
        return result.stack.readAddressOpt();
    }

    async getNextPoolAddress(
        provider: ContractProvider,
        ownerAddr: Address,
        signerAddr: bigint,
        sellTokenMintAddr: Address,
        fundingWalletAddr: Address,
        openTime: number,
        duration: number,
        buyCurrAddr: Address,
        buyCurrDecimals: number,
        buyCurrRate: bigint
    ) {
        const result = await provider.get('get_next_pool_address', [
            {type: "slice", cell: beginCell().storeAddress(ownerAddr).endCell()},
            {type: "int", value: signerAddr},
            {type: "slice", cell: beginCell().storeAddress(sellTokenMintAddr).endCell()},
            {type: "slice", cell: beginCell().storeAddress(fundingWalletAddr).endCell()},
            {type: "int", value: BigInt(openTime)},
            {type: "int", value: BigInt(duration)},
            {type: "slice", cell: beginCell().storeAddress(buyCurrAddr).endCell()},
            {type: "int", value: BigInt(buyCurrDecimals)},
            {type: "int", value: buyCurrRate},
        ]);
        return result.stack.readAddress();
    }
}
