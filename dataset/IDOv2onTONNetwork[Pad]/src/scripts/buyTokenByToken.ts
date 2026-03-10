import { Address, Cell, toNano } from '@ton/core';
import { NetworkProvider, sleep } from '@ton/blueprint';
import { keyPairFromSeed, sign } from '@ton/crypto';
import { JettonMinter } from '../wrappers/JettonMinter';
import { JettonWallet } from '../wrappers/JettonWallet';
import { createIDOPoolSwapByTokenMessage } from '../wrappers/IDOPool';

export async function run(provider: NetworkProvider, args: string[]) {

    const ui = provider.ui();

    const senderAddress = provider.sender().address;
    if (senderAddress === undefined) {
        ui.write(`Error: Provider does not have a sender address!`);
        return;
    }

    const iDOPoolAddress = Address.parse(args.length > 0 ? args[0] : await ui.input('IDOPool address'));

    if (!(await provider.isContractDeployed(iDOPoolAddress))) {
        ui.write(`Error: Contract at address ${iDOPoolAddress} is not deployed!`);
        return;
    }

    const seed: Buffer = Buffer.from([154,201,103,88,174,208,178,225,243,100,2,42,115,151,248,96,34,167,117,251,183,128,47,67,251,238,134,236,79,15,120,122]);
    const signer = keyPairFromSeed(seed);
    const signerAddr = BigInt(`0x${signer.publicKey.toString('hex')}`);

    const maxAmount = toNano('1');
    const minAmount = toNano('0');
    const buyCurrAddr = Address.parse('EQCB2U3vOM5GDFhC0tpMQp06TCLnScrWIf_cJk2-mgyoTIZF');
    const candidate = senderAddress
    const jettonAmount = 10n;

    const buyMint = provider.open(JettonMinter.createFromAddress(buyCurrAddr));
    const buyerBuyMintWallet = provider.open(JettonWallet.createFromAddress(await buyMint.getWalletAddress(candidate)));

    var _signature = sign(
        new Cell()
            .asBuilder()
            .storeAddress(candidate)
            .storeCoins(maxAmount)
            .storeCoins(minAmount)
            .storeAddress(iDOPoolAddress)
            .storeUint(0, 32) // workchain id
            .endCell()
            .hash()
            ,
        signer.secretKey
    );
    var signature = BigInt(`0x${_signature.toString('hex')}`);

    await buyerBuyMintWallet.sendTransfer(
        provider.sender(),
        toNano('0.2'),
        jettonAmount,
        iDOPoolAddress,
        candidate,
        new Cell()
            ,
        toNano('0.1'),
        createIDOPoolSwapByTokenMessage({
            buyCurrency: buyCurrAddr,
            maxAmount,
            minAmount,
            signature
        })
    )

    ui.write("Swap message sent!");

}
