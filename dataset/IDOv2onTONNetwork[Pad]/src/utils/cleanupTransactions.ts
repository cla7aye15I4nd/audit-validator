import { Address } from "@ton/core"
import { BlockchainTransaction } from "@ton/sandbox";

export function cleanupTransactions(transactions: BlockchainTransaction[]): any[] {
    const out: any[] = [];
    transactions.forEach(
        (transaction) => {
            const outTx: any = transaction;
            try {
                outTx.address = Address.parseRaw(`0:${transaction.address.toString(16)}`)
            } catch (error) {}
            delete outTx.parent;
            delete outTx.raw;
            delete outTx.vmLogs;
            outTx.inMessage = transaction.inMessage?.info;
            outTx.outMessages = transaction.outMessages.values();
            if (transaction.oldStatus !== transaction.endStatus) {
                outTx.statusChange = true;
            }
            out.push(outTx);
        }
    )
    return out;
}
