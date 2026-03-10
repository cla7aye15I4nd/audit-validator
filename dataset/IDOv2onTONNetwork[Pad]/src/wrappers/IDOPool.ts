import {
    Address,
    beginCell,
    Cell,
    Contract,
    contractAddress,
    ContractGetMethodResult,
    ContractProvider,
    Dictionary,
    Sender,
    SendMode,
    TupleReader,
} from '@ton/core';
import { sha256 } from '@ton/crypto';
import { TonClient } from '@ton/ton';

export type IDOPoolConfig = {
    poolId: number;
    factoryAddr: Address;
    ownerAddr: Address;
    signerAddr: Address;
    openTime: number;
    closeTime: number;
    sellTokenAddr: Address;
    fundingWalletAddr: Address;
    buyCurrency: Address;
    buyCurrencyDecimal: number;
    buyCurrencyRate: bigint;
};

export type IDOPoolSwapByTokenContent = {
    buyCurrency: Address;
    maxAmount: bigint;
    minAmount: bigint;
    signature: bigint;
};

export function createIDOPoolSwapByTokenMessage(content: IDOPoolSwapByTokenContent) {
    return new Cell()
        .asBuilder()
        .storeAddress(content.buyCurrency) // 267 bits
        .storeCoins(content.maxAmount) // 257 bits
        .storeCoins(content.minAmount) // 257 bits
        .storeRef(
            new Cell()
                .asBuilder()
                .storeUint(content.signature, 512) // 512 bits
                .endCell(),
        )
        .endCell();
}

export async function iDOPoolConfigToCell(config: IDOPoolConfig): Promise<Cell> {
    throw new Error('UNIMPLEMENTED FUNCTIONALITY');
    const perBuyDict = Dictionary.empty<Buffer, Cell>();
    perBuyDict.set(
        await sha256(config.buyCurrency.toString()),
        new Cell().asBuilder().storeUint(config.buyCurrencyDecimal, 8).storeCoins(config.buyCurrencyRate).endCell(),
    );

    return beginCell()
        .storeUint(config.poolId, 32)
        .storeAddress(config.factoryAddr)
        .storeAddress(config.ownerAddr)
        .storeAddress(config.signerAddr)
        .storeUint(config.openTime, 32)
        .storeUint(config.closeTime, 32)
        .storeRef(
            new Cell()
                .asBuilder()
                .storeAddress(config.sellTokenAddr)
                .storeAddress(config.fundingWalletAddr)
                .storeCoins(0)
                .storeCoins(0)
                .storeCoins(0)
                .endCell(),
        )
        .storeMaybeRef()
        .storeMaybeRef()
        .storeDict(perBuyDict)
        .endCell();
}

export const Opcodes = {
    buyTokenByTonWithPermission: 0xa1e4d24c,
    buyTokenByTokenWithPermission: 0xe95d7aaa,
    setPerBuyCurr: 0xcd26b66a,
    setPerBuyCurrRate: 0x5256f4e1,
    setPerBuyCurrDecimals: 0x920666ae,
    setNewSigner: 0x6feb7316,
    setCloseTime: 0xbb5dfbf1,
    setOpenTime: 0x997fb567,
    claimTokens: 0x9836c13e,
    refundTokens: 0x3018d6ba,
    claimRefundTokens: 0x97666bde,
    refundRemainingJetton: 0x7854eb78,
    refundRemainingTon: 0x609e4cce,
    setSellToken: 0x2c5e6100,
    setNewOwner: 0x2e4eba2e,
    refundRemainingSellToken: 0x57b7e0b3,
};

export class IDOPool implements Contract {
    constructor(
        readonly address: Address,
        readonly init?: { code: Cell; data: Cell },
        readonly provider?: TonClient,
        readonly client: 'ContractProvider' | 'TonClient' = 'ContractProvider',
    ) {}

    static createFromAddress(address: Address, options?: { provider: TonClient }) {
        if (options?.provider) {
            return new IDOPool(address, undefined, options.provider, 'TonClient');
        }
        return new IDOPool(address);
    }

    static async createFromConfig(config: IDOPoolConfig, code: Cell, workchain = 0) {
        const data = await iDOPoolConfigToCell(config);
        const init = { code, data };
        return new IDOPool(contractAddress(workchain, init), init);
    }

    async sendDeploy(provider: ContractProvider, via: Sender, value: bigint) {
        await provider.internal(via, {
            value,
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: beginCell().endCell(),
        });
    }

    async sendSwapByTon(
        provider: ContractProvider,
        via: Sender,
        opts: {
            queryID: number;
            value: bigint;
            tonAmount: bigint;
            maxAmount: bigint;
            minAmount: bigint;
            signature: bigint;
        },
    ) {
        const body = beginCell()
            .storeUint(Opcodes.buyTokenByTonWithPermission, 32)
            .storeUint(opts.queryID ?? 0, 64)
            .storeRef(
                beginCell()
                    .storeCoins(opts.tonAmount)
                    .storeCoins(opts.maxAmount)
                    .storeCoins(opts.minAmount)
                    .storeRef(new Cell().asBuilder().storeUint(opts.signature, 512).endCell())
                    .endCell(),
            )
            .endCell();

        if (this.client === 'TonClient') {
            return body;
        }

        await provider.internal(via, {
            value: opts.value,
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: body,
        });
    }

    async sendClaimTokens(
        provider: ContractProvider,
        via: Sender,
        opts: {
            queryID: number;
            value: bigint;
            claimAmount: bigint;
            signature: bigint;
        },
    ) {
        const body = beginCell()
            .storeUint(Opcodes.claimTokens, 32)
            .storeUint(opts.queryID ?? 0, 64)
            .storeCoins(opts.claimAmount)
            .storeRef(new Cell().asBuilder().storeUint(opts.signature, 512).endCell())
            .endCell();

        if (this.client === 'TonClient') {
            return body;
        }

        await provider.internal(via, {
            value: opts.value,
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: body,
        });
    }

    async sendRefundTokens(
        provider: ContractProvider,
        via: Sender,
        opts: {
            queryID: number;
            value: bigint;
            refundCurrency: Address;
            deadline: number;
            signature: bigint;
        },
    ) {
        const body = beginCell()
            .storeUint(Opcodes.refundTokens, 32)
            .storeUint(opts.queryID ?? 0, 64)
            .storeAddress(opts.refundCurrency)
            .storeUint(opts.deadline, 32)
            .storeRef(new Cell().asBuilder().storeUint(opts.signature, 512).endCell())
            .endCell();

        if (this.client === 'TonClient') {
            return body;
        }

        await provider.internal(via, {
            value: opts.value,
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: body,
        });
    }

    async sendClaimRefundTokens(
        provider: ContractProvider,
        via: Sender,
        opts: {
            queryID: number;
            value: bigint;
            refundCurrency: Address;
            signature: bigint;
        },
    ) {
        const body = beginCell()
            .storeUint(Opcodes.claimRefundTokens, 32)
            .storeUint(opts.queryID ?? 0, 64)
            .storeAddress(opts.refundCurrency)
            .storeRef(new Cell().asBuilder().storeUint(opts.signature, 512).endCell())
            .endCell();

        if (this.client === 'TonClient') {
            return body;
        }

        await provider.internal(via, {
            value: opts.value,
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: body,
        });
    }

    async getBalance(provider: ContractProvider) {
        return (await provider.getState()).balance;
    }

    async getId(provider: ContractProvider) {
        const result = await this.readContract('get_id', [], provider);
        return result.stack.readNumber();
    }

    async getFactory(provider: ContractProvider) {
        const result = await this.readContract('get_factory', [], provider);
        return result.stack.readAddressOpt();
    }

    async getOwner(provider: ContractProvider) {
        const result = await this.readContract('get_owner', [], provider);
        return result.stack.readAddressOpt();
    }

    async getSigner(provider: ContractProvider) {
        const result = await this.readContract('get_signer', [], provider);
        return result.stack.readBigNumber();
    }

    async getOpenTime(provider: ContractProvider) {
        const result = await this.readContract('get_open_time', [], provider);
        return result.stack.readNumber();
    }

    async getCloseTime(provider: ContractProvider) {
        const result = await this.readContract('get_close_time', [], provider);
        return result.stack.readNumber();
    }

    async getSellTokenAccountAddr(provider: ContractProvider) {
        const result = await this.readContract('get_sell_token_account_addr', [], provider);
        return result.stack.readAddressOpt();
    }

    async getSellTokenMint(provider: ContractProvider) {
        const result = await this.readContract('get_sell_token_mint', [], provider);
        return result.stack.readAddressOpt();
    }

    async getSellTokenAccountBalance(provider: ContractProvider) {
        const result = await this.readContract('get_sell_token_account_balance', [], provider);
        return result.stack.readBigNumber();
    }

    async getFundingWallet(provider: ContractProvider) {
        const result = await this.readContract('get_funding_wallet', [], provider);
        return result.stack.readAddressOpt();
    }

    async getTokenSold(provider: ContractProvider) {
        const result = await this.readContract('get_token_sold', [], provider);
        return result.stack.readBigNumber();
    }

    async getTotalUnclaimed(provider: ContractProvider) {
        const result = await this.readContract('get_total_unclaimed', [], provider);
        return result.stack.readBigNumber();
    }

    async getTotalRefunded(provider: ContractProvider) {
        const result = await this.readContract('get_total_refunded', [], provider);
        return result.stack.readBigNumber();
    }

    async getPerUserPerBuyCurr(provider: ContractProvider, userAddr: Address, buyCurrencyAddr: Address) {
        const result = await this.readContract(
            'get_per_user_per_buy_curr',
            [
                {
                    type: 'slice',
                    cell: new Cell().asBuilder().storeAddress(userAddr).endCell(),
                },
                {
                    type: 'slice',
                    cell: new Cell().asBuilder().storeAddress(buyCurrencyAddr).endCell(),
                },
            ],
            provider,
        );
        return {
            sellCurrBought: result.stack.readBigNumber(),
            buyCurrSold: result.stack.readBigNumber(),
            refundAmount: result.stack.readBigNumber(),
            isRefundClaimed: result.stack.readNumber() === 1,
        };
    }

    async getPerUser(provider: ContractProvider, userAddr: Address) {
        const result = await this.readContract(
            'get_per_user',
            [
                {
                    type: 'slice',
                    cell: new Cell().asBuilder().storeAddress(userAddr).endCell(),
                },
            ],
            provider,
        );
        return {
            sellCurrBought: result.stack.readBigNumber(),
            sellCurrClaimed: result.stack.readBigNumber(),
        };
    }

    async getPerBuyCurr(provider: ContractProvider, buyCurrencyAddr: Address) {
        const result = await this.readContract(
            'get_per_buy_curr',
            [
                {
                    type: 'slice',
                    cell: new Cell().asBuilder().storeAddress(buyCurrencyAddr).endCell(),
                },
            ],
            provider,
        );
        return {
            buyCurrRaised: result.stack.readBigNumber(),
            buyCurrRefundedTotal: result.stack.readBigNumber(),
            buyCurrRefundedLeft: result.stack.readBigNumber(),
            buyCurrAddr: result.stack.readAddress(),
            buyCurrDecimals: result.stack.readNumber(),
            buyCurrRate: result.stack.readBigNumber(),
            buyCurrBalance: result.stack.readBigNumber(),
            buyCurrTokenAccountAddr: result.stack.readAddress(),
        };
    }

    async sendSetPerBuyCurrency(
        provider: ContractProvider,
        via: Sender,
        opts: {
            queryID: number;
            value: bigint;
            buyCurrency: Address;
            buyCurrencyTokenAccountAddr: Address;
            buyCurrencyTokenAccountBalance: bigint;
            buyCurrencyDecimals: number;
            buyCurrencyRate: bigint;
        },
    ) {
        const body = beginCell()
            .storeUint(Opcodes.setPerBuyCurr, 32)
            .storeUint(opts.queryID ?? 0, 64)
            .storeAddress(opts.buyCurrency)
            .storeAddress(opts.buyCurrencyTokenAccountAddr)
            .storeCoins(opts.buyCurrencyTokenAccountBalance)
            .storeUint(opts.buyCurrencyDecimals, 8)
            .storeCoins(opts.buyCurrencyRate)
            .endCell();

        if (this.client === 'TonClient') {
            return body;
        }

        await provider.internal(via, {
            value: opts.value,
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: body,
        });
    }
    async sendSetPerBuyCurrencyRate(
        provider: ContractProvider,
        via: Sender,
        opts: {
            queryID: number;
            value: bigint;
            buyCurrency: Address;
            buyCurrencyRate: bigint;
        },
    ) {
        const body = beginCell()
            .storeUint(Opcodes.setPerBuyCurrRate, 32)
            .storeUint(opts.queryID ?? 0, 64)
            .storeAddress(opts.buyCurrency)
            .storeCoins(opts.buyCurrencyRate)
            .endCell();

        if (this.client === 'TonClient') {
            return body;
        }

        await provider.internal(via, {
            value: opts.value,
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: body,
        });
    }
    async sendSetPerBuyCurrencyDecimals(
        provider: ContractProvider,
        via: Sender,
        opts: {
            queryID: number;
            value: bigint;
            buyCurrency: Address;
            buyCurrencyDecimals: number;
        },
    ) {
        const body = beginCell()
            .storeUint(Opcodes.setPerBuyCurrDecimals, 32)
            .storeUint(opts.queryID ?? 0, 64)
            .storeAddress(opts.buyCurrency)
            .storeUint(opts.buyCurrencyDecimals, 8)
            .endCell();

        if (this.client === 'TonClient') {
            return body;
        }

        await provider.internal(via, {
            value: opts.value,
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: body,
        });
    }

    async sendSetNewSigner(
        provider: ContractProvider,
        via: Sender,
        opts: {
            queryID: number;
            value: bigint;
            newSigner: bigint;
        },
    ) {
        const body = beginCell()
            .storeUint(Opcodes.setNewSigner, 32)
            .storeUint(opts.queryID ?? 0, 64)
            .storeUint(opts.newSigner, 256)
            .endCell();

        if (this.client === 'TonClient') {
            return {
                address: this.address.toString(),
                amount: opts.value.toString(),
                payload: body.toBoc().toString('base64'),
            };
        }

        await provider.internal(via, {
            value: opts.value,
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: body,
        });
    }
    async sendSetNewOwner(
        provider: ContractProvider,
        via: Sender,
        opts: {
            queryID: number;
            value: bigint;
            newOwner: Address;
        },
    ) {
        const body = beginCell()
            .storeUint(Opcodes.setNewOwner, 32)
            .storeUint(opts.queryID ?? 0, 64)
            .storeAddress(opts.newOwner)
            .endCell();

        if (this.client === 'TonClient') {
            return {
                address: this.address.toString(),
                amount: opts.value.toString(),
                payload: body.toBoc().toString('base64'),
            };
        }

        await provider.internal(via, {
            value: opts.value,
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: body,
        });
    }
    async sendSetCloseTime(
        provider: ContractProvider,
        via: Sender,
        opts: {
            queryID: number;
            value: bigint;
            newCloseTime: number;
        },
    ) {
        const body = beginCell()
            .storeUint(Opcodes.setCloseTime, 32)
            .storeUint(opts.queryID ?? 0, 64)
            .storeUint(opts.newCloseTime, 32)
            .endCell();

        if (this.client === 'TonClient') {
            return body;
        }

        await provider.internal(via, {
            value: opts.value,
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: body,
        });
    }
    async sendSetOpenTime(
        provider: ContractProvider,
        via: Sender,
        opts: {
            queryID: number;
            value: bigint;
            newOpenTime: number;
        },
    ) {
        const body = beginCell()
            .storeUint(Opcodes.setOpenTime, 32)
            .storeUint(opts.queryID ?? 0, 64)
            .storeUint(opts.newOpenTime, 32)
            .endCell();

        if (this.client === 'TonClient') {
            return body;
        }

        await provider.internal(via, {
            value: opts.value,
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: body,
        });
    }
    async sendSetSellToken(
        provider: ContractProvider,
        via: Sender,
        opts: {
            queryID: number;
            value: bigint;
            sellTokenMint: Address;
            sellTokenAccount: Address;
        },
    ) {
        const body = beginCell()
            .storeUint(Opcodes.setSellToken, 32)
            .storeUint(opts.queryID ?? 0, 64)
            .storeAddress(opts.sellTokenMint)
            .storeAddress(opts.sellTokenAccount)
            .endCell();

        if (this.client === 'TonClient') {
            return body;
        }

        await provider.internal(via, {
            value: opts.value,
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: body,
        });
    }

    async sendRefundRemainingJetton(
        provider: ContractProvider,
        via: Sender,
        opts: {
            queryID: number;
            value: bigint;
            receiverAddress: Address;
            jettonAddress: Address;
        },
    ) {
        const body = beginCell()
            .storeUint(Opcodes.refundRemainingJetton, 32)
            .storeUint(opts.queryID ?? 0, 64)
            .storeAddress(opts.receiverAddress)
            .storeAddress(opts.jettonAddress)
            .endCell();

        if (this.client === 'TonClient') {
            return body;
        }

        await provider.internal(via, {
            value: opts.value,
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: body,
        });
    }
    async sendRefundRemainingSellToken(
        provider: ContractProvider,
        via: Sender,
        opts: {
            queryID: number;
            value: bigint;
            receiverAddress: Address;
        },
    ) {
        const body = beginCell()
            .storeUint(Opcodes.refundRemainingSellToken, 32)
            .storeUint(opts.queryID ?? 0, 64)
            .storeAddress(opts.receiverAddress)
            .endCell();

        if (this.client === 'TonClient') {
            return body;
        }

        await provider.internal(via, {
            value: opts.value,
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: body,
        });
    }
    async sendRefundRemainingTon(
        provider: ContractProvider,
        via: Sender,
        opts: {
            queryID: number;
            value: bigint;
            receiverAddress: Address;
        },
    ) {
        const body = beginCell()
            .storeUint(Opcodes.refundRemainingTon, 32)
            .storeUint(opts.queryID ?? 0, 64)
            .storeAddress(opts.receiverAddress)
            .endCell();

        if (this.client === 'TonClient') {
            return body;
        }

        await provider.internal(via, {
            value: opts.value,
            sendMode: SendMode.PAY_GAS_SEPARATELY,
            body: body,
        });
    }

    private readContract = async (
        method: string,
        params: any[] = [],
        provider: ContractProvider,
    ): Promise<
        | {
              gas_used: number;
              stack: TupleReader;
          }
        | ContractGetMethodResult
    > => {
        if (this.client === 'TonClient') {
            if (this.provider) {
                return await this.provider.runMethod(this.address, method, params);
            } else {
                throw new Error('Invalid Provider');
            }
        }
        return await provider.get(method, params);
    };
}
