import { Address, toNano } from '@ton/core';
import { NetworkProvider, sleep } from '@ton/blueprint';
import { JettonMinter } from '../wrappers/JettonMinter';

export async function run(provider: NetworkProvider, args: string[]) {

    const ui = provider.ui();

    const senderAddress = provider.sender().address;
    if (senderAddress === undefined) {
        ui.write(`Error: Provider does not have a sender address!`);
        return;
    }

    const address = Address.parse(args.length > 0 ? args[0] : await ui.input('Minter address'));
    const mintTo = Address.parse(args.length > 0 ? args[0] : await ui.input('Mint To address'));
    const mintAmount = toNano(await ui.input('Mint Amount (will be multiplied by 1e9)'));

    if (!(await provider.isContractDeployed(address))) {
        ui.write(`Error: Contract at address ${address} is not deployed!`);
        return;
    }

    const minter = provider.open(JettonMinter.createFromAddress(address));
    await minter.sendMint(provider.sender(), mintTo, mintAmount, 0n, toNano('0.05'));


}
