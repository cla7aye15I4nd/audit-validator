import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

// LayerZero Endpoint V2 (the same omni-address hash on Base and BSC)
const LZ_ENDPOINT_V2 = "0x1a44076050125825900e736c501f859c50fE728c";

const func: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const { deployments, getNamedAccounts, network } = hre;
  const { deploy, log } = deployments;
  const { deployer } = await getNamedAccounts();

  const name   = process.env.OFT_NAME   || "MOFT";
  const symbol = process.env.OFT_SYMBOL || "MOFT";
  const delegate = deployer;

  log(`Deploying MintableOFTTest to ${network.name} with owner ${delegate}`);
  const res = await deploy("MintableOFTTest", {
    from: deployer,
    contract: "MintableOFTTest",
    args: [name, symbol, LZ_ENDPOINT_V2, delegate],
    log: true,
    waitConfirmations: 2,
  });

  log(`MintableOFTTest deployed at: ${res.address}`);
};

func.tags = ["MintableOFTTest"];

export default func;
