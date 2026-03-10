import {Address, beginCell, Cell, Dictionary, toNano} from '@ton/core';
import {Bridge} from '../wrappers/Bridge';
import {compile, NetworkProvider} from '@ton/blueprint';
import {BridgeSwap} from "../wrappers/BridgeSwap";

export async function run(provider: NetworkProvider) {
    console.log(provider.sender().address);
    const bridgeAddress = Address.parseFriendly("EQDVfY0eShpaEvztwtIFf2a0ECwETJdhavHgF2J0tyhV69OJ");
    const bridgePoolAddress = Address.parseFriendly("EQAP_4H05mqqQBuBT0cJR9zbEOhIEHuhNVFb0hJDg_35BIe-");
    const jettonAddress = Address.parseFriendly("EQBSKUt9k20Gz8RqG71xloqnzcFHt0MdWg1UnWcyU5Xf9CsU");
    let tempUpgrade = beginCell()
        .storeUint(0, 64)
        .storeUint(0, 64)
        .storeUint(0, 64)
        .storeAddress(null)
        .storeRef(beginCell().endCell())
        .storeAddress(null)
        .endCell();
    let dic = Dictionary.empty(Dictionary.Keys.BigUint(256), Dictionary.Values.Cell());
    const bridgeSwap = provider.open(BridgeSwap.createFromConfig({
        bridgePoolAddress: bridgePoolAddress.address,
        jettonAddress: jettonAddress.address,
        bridgeAddress: bridgeAddress.address,
        admin: provider.sender().address!,
        owner: provider.sender().address!,
        tempUpgrade: tempUpgrade,
        swapDic: dic,
        receiptDic: dic
    }, await compile('BridgeSwap')));

    await bridgeSwap.sendDeploy(provider.sender(), toNano('0.05'));

    await provider.waitForDeploy(bridgeSwap.address);

    // run methods on `ebridgeContractsTon`

}
