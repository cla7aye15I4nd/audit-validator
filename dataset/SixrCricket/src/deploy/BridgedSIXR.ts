import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { ethers } from "ethers";

const func: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const { deployments, getNamedAccounts, network } = hre;
  const { deploy, log, get, getOrNull } = deployments;
  const { deployer } = await getNamedAccounts();

  // Check for existing deployment and FORCE_BRIDGEDSIXR_DEPLOY flag
  const existing = await getOrNull("BridgedSIXR");
  if (existing && !process.env.FORCE_BRIDGEDSIXR_DEPLOY) {
    log(`BridgedSIXR already deployed at ${existing.address} on ${network.name}`);
    log(`Set FORCE_BRIDGEDSIXR_DEPLOY=true to force re-deployment`);
    return;
  }

  // Token configuration
  const name = process.env.BRIDGED_SIXR_NAME || "SIXRTEST";
  const symbol = process.env.BRIDGED_SIXR_SYMBOL || "SIXRTEST";

  // Fee configuration (default 1% = 100 basis points)
  const feeBasisPoints = parseInt(process.env.BRIDGED_SIXR_FEE_BPS || "100", 10);

  // Fee recipient - required
  const feeRecipient = process.env.BRIDGED_SIXR_FEE_RECIPIENT;
  if (!feeRecipient) {
    throw new Error("BRIDGED_SIXR_FEE_RECIPIENT environment variable is required");
  }
  if (!ethers.utils.isAddress(feeRecipient)) {
    throw new Error(`Invalid fee recipient address: ${feeRecipient}`);
  }

  // Owner - use BridgeMultisig if deployed, otherwise use explicit env var
  let owner: string;
  const explicitOwner = process.env.BRIDGED_SIXR_OWNER;

  if (explicitOwner) {
    if (!ethers.utils.isAddress(explicitOwner)) {
      throw new Error(`Invalid owner address: ${explicitOwner}`);
    }
    owner = explicitOwner;
    log(`Using explicit owner from BRIDGED_SIXR_OWNER: ${owner}`);
  } else {
    try {
      const bridgeMultisig = await get("BridgeMultisig");
      owner = bridgeMultisig.address;
      log(`Using BridgeMultisig as owner: ${owner}`);
    } catch {
      throw new Error(
        "BridgeMultisig not deployed and BRIDGED_SIXR_OWNER not set. " +
        "Either deploy BridgeMultisig first or set BRIDGED_SIXR_OWNER explicitly."
      );
    }
  }

  log(`\n========================================`);
  log(`Deploying BridgedSIXR to ${network.name}`);
  log(`========================================`);
  log(`Deployer: ${deployer}`);
  log(`Name: ${name}`);
  log(`Symbol: ${symbol}`);
  log(`Owner (can mint): ${owner}`);
  log(`Fee Recipient: ${feeRecipient}`);
  log(`Fee: ${feeBasisPoints} bps (${feeBasisPoints / 100}%)`);
  log(`========================================\n`);

  const args = [name, symbol, owner, feeRecipient, feeBasisPoints];
  const res = await deploy("BridgedSIXR", {
    from: deployer,
    args,
    log: true,
    waitConfirmations: 2,
  });

  log(`\n========================================`);
  log(`BridgedSIXR deployed successfully!`);
  log(`========================================`);
  log(`Address: ${res.address}`);
  log(`Transaction Hash: ${res.transactionHash || "N/A"}`);
  log(`Network: ${network.name}`);
  log(`========================================\n`);
};

func.tags = ["BridgedSIXR"];
func.dependencies = []; // Optional: add "BridgeMultisig" if you want to enforce order

export default func;
