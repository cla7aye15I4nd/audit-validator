import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

const OFT_ADDRESS: Record<number, string> = {
  8453: "0x30d5A7c3C92Ec736bfB20525D5434Cf1c4dDAfBd", // Base MOFT
  56:   "0xf386fec249A9E01Dac0D7a46Fd4313A695086195", // (BSC)
};

const func: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const { deployments, getNamedAccounts, network } = hre;
  const { deploy, log } = deployments;
  const { deployer } = await getNamedAccounts();
  const chainId = network.config.chainId as number;

  const moft = OFT_ADDRESS[chainId];
  if (!moft) throw new Error(`No MOFT address mapped for chainId=${chainId}`);

  const args = [moft, deployer];
  const res = await deploy("RedeemEmitter", {
    from: deployer,
    args,
    log: true,
    waitConfirmations: 3,
  });

  log(`RedeemEmitter deployed at: ${res.address}`);
};

export default func;
func.tags = ["RedeemEmitter"];
