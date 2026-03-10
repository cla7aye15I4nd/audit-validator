import { toNano } from '@ton/core';
import { compile, NetworkProvider } from '@ton/blueprint';
import { jettonContentToCell, JettonMinter } from '../wrappers/JettonMinter';

export async function run(provider: NetworkProvider) {

    const ui = provider.ui();

    const senderAddress = provider.sender().address;
    if (senderAddress === undefined) {
        ui.write(`Error: Provider does not have a sender address!`);
        return;
    }

    const jettonMinter = provider.open(
        JettonMinter.createFromConfig(
            {
                admin: senderAddress,
                content: jettonContentToCell({
                    type: 1,
                    uri: 'testURI',
                }),
                wallet_code: await compile('JettonWallet'),
            },
            await compile('JettonMinter')
        )
    );

    await jettonMinter.sendDeploy(provider.sender(), toNano('0.05'));

    await provider.waitForDeploy(jettonMinter.address);

    console.log('Minter deployed at:', jettonMinter.address);
}
