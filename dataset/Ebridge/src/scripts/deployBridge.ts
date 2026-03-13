import {Address, beginCell, Cell, Dictionary, toNano} from '@ton/core';
import {Bridge} from '../wrappers/Bridge';
import {compile, NetworkProvider} from '@ton/blueprint';

export async function run(provider: NetworkProvider) {
    console.log(provider.sender().address);
    const oracle_address = "EQBCOuvczf29HIGNxrJdsmTKIabHQ1j4dW2ojlYkcru3IOYy";
    let poolContractDicDefault = Dictionary.empty(Dictionary.Keys.BigUint(256), Dictionary.Values.Address());
    let swapContractDicDefault = Dictionary.empty(Dictionary.Keys.BigUint(256), Dictionary.Values.Address());
    let jettonWhitelistDicDefault = Dictionary.empty(Dictionary.Keys.BigUint(256), Dictionary.Values.Cell());
    let targetContractDicDefault = Dictionary.empty();
    let tempUpgrade = beginCell()
        .storeUint(0, 64)
        .storeUint(0, 64)
        .storeUint(0, 64)
        .storeAddress(null)
        .storeRef(beginCell().endCell())
        .storeAddress(null)
        .endCell();
    let bridgeReceiptAccountCode = await compile('BridgeReceiptAccount');

    const bridge = provider.open(Bridge.createFromConfig({
        bridge_swap_address_dic: swapContractDicDefault,
        bridge_pool_address_dic: poolContractDicDefault,
        jetton_whitelist_dic: jettonWhitelistDicDefault,
        oracle_address: Address.parseFriendly(oracle_address).address,
        is_pause: false,
        pause_controller: provider.sender().address!,
        admin: provider.sender().address!,
        owner: provider.sender().address!,
        temp_upgrade: tempUpgrade,
        bridge_receipt_account_code: bridgeReceiptAccountCode,
        target_contract_dic: targetContractDicDefault
    }, await compile('Bridge')));

    await bridge.sendDeploy(provider.sender(), toNano('0.05'));

    await provider.waitForDeploy(bridge.address);

    // run methods on `ebridgeContractsTon`

}
