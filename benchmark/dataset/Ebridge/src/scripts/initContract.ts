import {compile, NetworkProvider} from "@ton/blueprint";
import {Bridge} from "../wrappers/Bridge";
import {Address, beginCell, OpenedContract, Sender, toNano} from '@ton/core';
import {randomAddress} from "@ton/test-utils";
import bs58 from "bs58";
import {Buffer} from "buffer";
import aelf from "aelf-sdk";
import {BridgePool} from "../wrappers/BridgePool";
import {JettonMinter} from "../wrappers/JettonMinter";
import {JettonWallet} from "../wrappers/JettonWallet";
import {BridgeSwap} from "../wrappers/BridgeSwap";

export async function run(provider: NetworkProvider, args: string[]) {

    const bridgeAddress = Address.parseFriendly("EQDVfY0eShpaEvztwtIFf2a0ECwETJdhavHgF2J0tyhV69OJ");
    const bridgePoolAddress = Address.parseFriendly("EQAP_4H05mqqQBuBT0cJR9zbEOhIEHuhNVFb0hJDg_35BIe-");
    const bridgeSwapAddress = Address.parseFriendly("EQC9DDj1FWAdrENyT4tCGL975mshr8nsaIPnfoODe3DdoBdY");
    const jettonMinter = Address.parseFriendly("EQBSKUt9k20Gz8RqG71xloqnzcFHt0MdWg1UnWcyU5Xf9CsU");

    const bridge = provider.open(Bridge.createFromAddress(bridgeAddress.address));
    const bridgePool = provider.open(BridgePool.createFromAddress(bridgePoolAddress.address));
    const bridgeSwap = provider.open(BridgeSwap.createFromAddress(bridgeSwapAddress.address));
    const jetton_minter = provider.open(JettonMinter.createFromAddress(jettonMinter.address));

    const chainId = 1931928;
    const targetContract = "JKjoabe2wyrdP1P8TvNyD4GZP6z1PuMvU2y5yJ4JTeBjTMAoX";
    const userWallet = async (address: Address) => provider.open(
        JettonWallet.createFromAddress(
            await jetton_minter.getWalletAddress(address)
        )
    );

    const deployJettonWallet = await userWallet(provider.sender().address!);
    const bridgeJettonWallet = await userWallet(bridge.address);
    const bridgePoolJettonWallet = await userWallet(bridgePool.address);

    console.log('deployJettonWallet', deployJettonWallet.address);
    console.log('bridgeJettonWallet', bridgeJettonWallet.address);
    console.log('bridgePoolJettonWallet', bridgePoolJettonWallet.address);
    /*
    deployJettonWallet EQBE26_ydZ2Tq8ghgrqQ9nTC5XEPAOvDQOBMTo10cqlzXObf
    bridgeJettonWallet EQD8e9Txi4KF218oNFflXJf2biGG0Oxp-W8m35Hr_YlqXk_N
    bridgePoolJettonWallet EQC9MkOUXv0Rm4dd9hNuRnCJDO6q_vYVbMPpMm1UMS6IXBLT
     */

    let initialAccountJettonBalance = toNano('1000.23');
    // await jetton_minter.sendMint(
    //     provider.sender(),
    //     provider.sender().address!,
    //     initialAccountJettonBalance,
    //     toNano('0.05'),
    //     toNano('0.5'));
    // console.log(await deployJettonWallet.getJettonBalance());

    // bridge 
    const admin = provider.sender();
    // 1. add jetton whitelist
    // await addJettonWhitelist(bridge, admin, jettonMinter.address, chainId);
    // 2. set bridge swap
    // await setBridgeSwap(bridge, admin, jettonMinter.address, bridgeSwap.address);
    // 3. set bridge pool
    // await setBridgePool(bridge, admin, jettonMinter.address, bridgePool.address);
    // // 4. set target contract
    // await setTargetContract(bridge, admin, targetContract, chainId);
    // // 5. create swap
    // await createSwap(bridgeSwap, admin, chainId);
    // // 6. set bridge
    // await setBridge(bridgePool, admin, bridge.address);
    // // 7. set jetton
    // await setJetton(bridgePool, admin, jettonMinter.address, bridgePoolJettonWallet.address);
    // // 8. set daily limit
    // await setDailyLimit(bridgePool, admin, toNano('1000'), chainId, getUTCMidnight());
    // // 9. set rate limit
    // await setRateLimit(bridgePool, admin, toNano('1000'), toNano('100'), chainId);
    // // 10 .get config
    // let isSupport = await bridge.getIsJettonSupport(chainId, jettonMinter.address);
    // console.log(isSupport);
    // // get bridge swap
    // let swap = await bridge.getBridgeSwap(jettonMinter.address);
    // console.log(swap);
    // // get pool
    // let pool = await bridge.getBridgePool(jettonMinter.address);
    // console.log(pool);
    // // get swap info
    let swapInfo = await bridgeSwap.getSwapData(chainId);
    // // swapId:6akJ+WNN/7uYAH2YHHjbc11djaEkxzpWPI9gK/jdDns=
    console.log(swapInfo.swapId.toString('base64'));
    // console.log(swapInfo.fromChainId);
    // console.log(swapInfo.originShare);
    // console.log(swapInfo.targetShare);
    // console.log(swapInfo.swappedAmount);
    // console.log(swapInfo.swappedTimes);
    // // get bridge
    // let bridgeGet = await bridgePool.getBridgeAddress();
    // console.log(bridgeGet);
    // // get jetton
    // let jetton = await bridgePool.getJettonAddress();
    // console.log(jetton.jettonAddress);
    // console.log(jetton.poolJettonWalletAddress);
    // // get daily limit
    // let dailyLimit = await bridgePool.getReceiptDailyLimit(chainId);
    // console.log(dailyLimit.dailyLimit);
    // console.log(dailyLimit.refreshTime);
    // console.log(dailyLimit.remainToken);
    // // get rate limit
    // let rateLimit = await bridgePool.getReceiptRateLimit(chainId);
    // console.log(rateLimit.tokenCapacity);
    // console.log(rateLimit.rate);
    // console.log(rateLimit.currentTokenAmount);
    // console.log(rateLimit.isEnable);
    // console.log(rateLimit.refreshTime);
    // // get daily limit
    // dailyLimit = await bridgePool.getSwapDailyLimit(chainId);
    // console.log(dailyLimit.dailyLimit);
    // console.log(dailyLimit.refreshTime);
    // console.log(dailyLimit.remainToken);
    // // get rate limit
    // rateLimit = await bridgePool.getSwapRateLimit(chainId);
    // console.log(rateLimit.tokenCapacity);
    // console.log(rateLimit.rate);
    // console.log(rateLimit.currentTokenAmount);
    // console.log(rateLimit.isEnable);
    // console.log(rateLimit.refreshTime);

    // // add jetton liquidity
    // let amount_add_liquidity = toNano('100');
    // let forwardAmount = toNano('0.05');
    // let payload = BridgePool.packAddLiquidityBody();
    // await deployJettonWallet.sendTransfer(
    //     admin,
    //     toNano('0.1'),
    //     amount_add_liquidity,
    //     bridgePool.address,
    //     provider.sender().address!,
    //     beginCell().storeUint(0,1).endCell(),
    //     forwardAmount,
    //     payload);

    // const liquidity_account = await bridgePool.getPoolLiquidityAccountAddress(provider.sender().address!);
    // console.log(liquidity_account);
    // let liquidityAfter = await bridgePool.getPoolLiquidity();
    // console.log(liquidityAfter);
    

}

async function addJettonWhitelist(bridge: OpenedContract<Bridge>, admin: Sender, jettonAddress: Address, chainId: number) {
    await bridge.sendAddJetton(
        admin,
        toNano('0.01'), [jettonAddress], chainId);
}

async function setBridgeSwap(bridge: OpenedContract<Bridge>, admin: Sender, jettonAddress: Address, swapAddress: Address) {
    await bridge.sendSetBridgeSwap(admin, toNano('0.01'), [{
        jetton_address: jettonAddress,
        contract_address: swapAddress
    }]);
}

async function setBridgePool(bridge: OpenedContract<Bridge>, admin: Sender, jettonAddress: Address, poolAddress: Address) {
    await bridge.sendSetBridgePool(admin, toNano('0.01'), [{
        jetton_address: jettonAddress,
        contract_address: poolAddress
    }]);
}

async function setTargetContract(bridge: OpenedContract<Bridge>, admin: Sender, target: string, chainId: number) {
    const buffer = aelf.utils.base58.decode(target);
    await bridge.sendTargetContract(admin, toNano('0.01'), [
        {
            chain_id: chainId,
            bridge_address: Buffer.from(buffer)
        }]);
}

async function createSwap(bridgeSwap: OpenedContract<BridgeSwap>, admin: Sender, chainId: number) {
    await bridgeSwap.sendCreateSwap(
        admin, toNano('0.01'), [{
            fromChainId: chainId,
            originShare: 1,
            targetShare: 1
        }]);
}

async function setBridge(bridgePool: OpenedContract<BridgePool>, admin: Sender, bridgeAddress: Address) {
    await bridgePool.sendSetBridge(admin, toNano('0.01'), bridgeAddress);
}

async function setJetton(bridgePool: OpenedContract<BridgePool>, admin: Sender, jettonAddress: Address, bridgePoolJettonWallet: Address) {
    await bridgePool.sendSetJetton(admin, toNano('0.01'), jettonAddress, bridgePoolJettonWallet);
}

async function setDailyLimit(bridgePool: OpenedContract<BridgePool>, admin: Sender, dailyLimit: bigint, chainId: number, refreshTime: number) {
    await bridgePool.sendSetDailyLimit(
        admin,
        toNano('0.01'),
        [{
            chainId: chainId,
            limitType: 0,
            refreshTime: refreshTime,
            dailyLimit: dailyLimit
        }, {
            chainId: chainId,
            limitType: 1,
            refreshTime: refreshTime,
            dailyLimit: dailyLimit
        }]);
}

async function setRateLimit(bridgePool: OpenedContract<BridgePool>, admin: Sender, capacity: bigint, rateLimit: bigint, chainId: number) {
    await bridgePool.sendSetRateLimit(
        admin,
        toNano('0.01'),
        [{
            chainId: chainId,
            limitType: 0,
            tokenCapacity: capacity,
            rate: rateLimit,
        },
            {
                chainId: chainId,
                limitType: 1,
                tokenCapacity: capacity,
                rate: rateLimit,
            }]);
}

function getUTCMidnight(): number {
    const now = new Date();
    // Create a new Date object for today's midnight in UTC
    let time = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate());
    console.log(time);
    return time / 1000;
}