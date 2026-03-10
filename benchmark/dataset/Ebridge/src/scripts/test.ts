import {NetworkProvider} from "@ton/blueprint";
import {Bridge} from "../wrappers/Bridge";
import {Address, beginCell, Cell, toNano} from '@ton/core';
import {randomAddress} from "@ton/test-utils";
import {JettonMinter} from "../wrappers/JettonMinter";
import {JettonWallet} from "../wrappers/JettonWallet";
import {Buffer} from "buffer";
import bs58 from "bs58";
import aelf from "aelf-sdk";
export async function run(provider: NetworkProvider, args: string[]) {

    const address = "EQAOADR4NzUEVdZRLrq_Qg2G5mrXRZkX_NXLm_uW9W4Nqok4";
    const bridge = provider.open(Bridge.createFromAddress(Address.parseFriendly(address).address));

    const jetton_minter_address = "EQD2YshOlwLKD62kAUwPZaV4W01FpRCQzevjQjmn9Ie107XG";
    const jetton_minter = provider.open(JettonMinter.createFromAddress(Address.parseFriendly(jetton_minter_address).address));

    const userWallet = async (address: Address) => provider.open(
        JettonWallet.createFromAddress(
            await jetton_minter.getWalletAddress(address)
        )
    );

    let initialAccountJettonBalance = toNano('1000.23');

    const deployJettonWallet = await userWallet(provider.sender().address!);
    // await jetton_minter.sendMint(
    //     provider.sender(),
    //     provider.sender().address!,
    //     initialAccountJettonBalance,
    //     toNano('0.05'),
    //     toNano('0.5'));
    let receipt_amount = toNano('10');
    let forwardAmount = toNano('0.05');
    const chainId = 1931928;
    let targetAddress = "JKjoabe2wyrdP1P8TvNyD4GZP6z1PuMvU2y5yJ4JTeBjTMAoX";
    let targetAddressBuffer = aelf.utils.base58.decode(targetAddress);
    console.log(targetAddressBuffer.toString('hex'));
    // const targetAddressBuffer = bs58.decode(targetAddress);
    let payload = Bridge.PackCreateReceiptBody(
        chainId, deployJettonWallet.address,
        Buffer.from(targetAddressBuffer), jetton_minter.address);
    await deployJettonWallet.sendTransfer(
        provider.sender(),
        toNano('0.2'),
        receipt_amount,
        bridge.address,
        provider.sender().address!,
        beginCell().storeUint(0,1).endCell(),
        forwardAmount,
        payload);
}
