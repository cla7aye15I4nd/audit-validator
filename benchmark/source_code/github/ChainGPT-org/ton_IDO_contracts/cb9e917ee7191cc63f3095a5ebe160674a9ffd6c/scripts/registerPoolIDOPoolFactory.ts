import { Address, toNano } from '@ton/core';
import { IDOPoolFactory } from '../wrappers/IDOPoolFactory';
import { NetworkProvider, sleep } from '@ton/blueprint';
import { getSecureRandomBytes, keyPairFromSeed } from '@ton/crypto';
import { JettonMinter } from '../wrappers/JettonMinter';

export async function run(provider: NetworkProvider, args: string[]) {

    const ui = provider.ui();

    const senderAddress = provider.sender().address;
    if (senderAddress === undefined) {
        ui.write(`Error: Provider does not have a sender address!`);
        return;
    }

    const address = Address.parse(args.length > 0 ? args[0] : await ui.input('IDOPoolFactory address'));

    if (!(await provider.isContractDeployed(address))) {
        ui.write(`Error: Contract at address ${address} is not deployed!`);
        return;
    }

    const seed: Buffer = await getSecureRandomBytes(32); // Seed is always 32 bytes
    const signerSeedJSON = JSON.stringify(Array.from(seed));
    const signer = keyPairFromSeed(seed);
    const signerAddr = BigInt(`0x${signer.publicKey.toString('hex')}`);
    ui.write("signer seed: " + signerSeedJSON);

    const sellTokenMintAddr = Address.parse('EQAZzmUxHVnh1Z-83Vjz2kxb2Iv2BGw-xVmdZZCHc9M5lw-D');
    const fundingWalletAddr = Address.parse('0QCHsFtsC4beido0MlfuI8fBEsLt6MMQzswAC1K6YsYGAF0R');
    const openTime = Math.floor(Date.now() / 1000);
    const duration = 60 * 60 * 24 * 7; // 1 week
    const buyCurrAddr = Address.parse('EQCB2U3vOM5GDFhC0tpMQp06TCLnScrWIf_cJk2-mgyoTIZF');
    const buyCurrDecimals = 9;
    const buyCurrRate = 1000000000n;

    const iDOPoolFactory = provider.open(IDOPoolFactory.createFromAddress(address));

    const iDOPoolAddress = await iDOPoolFactory.getNextPoolAddress(
        senderAddress,
        signerAddr,
        sellTokenMintAddr,
        fundingWalletAddr,
        openTime,
        duration,
        buyCurrAddr,
        buyCurrDecimals,
        buyCurrRate
    );

    const sellToken = provider.open(JettonMinter.createFromAddress(sellTokenMintAddr));
    const buyToken = provider.open(JettonMinter.createFromAddress(buyCurrAddr));
    const sellTokenAccountAddr = await sellToken.getWalletAddress(iDOPoolAddress);
    const buyCurrTokenAccountAddr = await buyToken.getWalletAddress(iDOPoolAddress);

    await iDOPoolFactory.sendRegisterPool(provider.sender(), {
        buyCurrDecimals,
        buyCurrRate,
        buyCurrTokenAccountAddr,
        duration,
        fundingWalletAddr,
        openTime,
        queryID: 0,
        sellTokenAccountAddr,
        sellTokenMintAddr,
        signerAddr,
        buyCurrAddr,
        value: toNano('0.1')
    });

    ui.write("Pool deployed successfully at address: " + iDOPoolAddress.toString());

}
