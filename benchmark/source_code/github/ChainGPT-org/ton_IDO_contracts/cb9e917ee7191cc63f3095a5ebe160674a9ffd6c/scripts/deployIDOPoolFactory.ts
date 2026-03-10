import { Address, toNano } from '@ton/core';
import { IDOPoolFactory } from '../wrappers/IDOPoolFactory';
import { compile, NetworkProvider } from '@ton/blueprint';

export async function run(provider: NetworkProvider) {
    const iDOPoolFactory = provider.open(
        IDOPoolFactory.createFromConfig(
            {
                poolCode: await compile("IDOPool"),
                zeroAddress: Address.parse('0QAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACkT')
            },
            await compile('IDOPoolFactory')
        )
    );

    await iDOPoolFactory.sendDeploy(provider.sender(), toNano('0.05'));

    await provider.waitForDeploy(iDOPoolFactory.address);

    console.log('ID', await iDOPoolFactory.getPoolCount());
}
