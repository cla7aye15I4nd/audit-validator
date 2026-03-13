import {Address, beginCell, Cell, Dictionary, toNano} from '@ton/core';
import {Bridge} from '../wrappers/Bridge';
import {compile, NetworkProvider} from '@ton/blueprint';
import {JettonMinter} from "../wrappers/JettonMinter";
import {Buffer} from "buffer";

export async function run(provider: NetworkProvider) {
    console.log(provider.sender().address);
    const jwallet_code = await compile('JettonWallet');
    const jettonParams = {
        name: "Mock USDT",
        symbol: "USDT",
        description: "Test jetton",
        decimals: "6"
    };
    let metadata = JettonMinter.buildTokenMetadataCell({
        name: jettonParams.name,
        symbol: jettonParams.symbol,
        description: jettonParams.description,
        decimals: jettonParams.decimals
    });
    const jettonMinter = provider.open(
        await JettonMinter.createFromConfig(
            {
                admin: provider.sender().address!,
                content: metadata,
                wallet_code: jwallet_code,
            },
            await compile('JettonMinter')));

    await jettonMinter.sendDeploy(provider.sender(), toNano('0.01'));

    await provider.waitForDeploy(jettonMinter.address);

    // run methods on `ebridgeContractsTon`

    // await bridge.getOracleAddress();
}
