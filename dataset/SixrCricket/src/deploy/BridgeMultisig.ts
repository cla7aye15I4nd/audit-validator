import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { ethers } from "ethers";

const func: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const { deployments, getNamedAccounts, network } = hre;
  const { deploy, log, getOrNull } = deployments;
  const { deployer } = await getNamedAccounts();

  // Check for existing deployment and FORCE_MULTISIG_DEPLOY flag
  const existing = await getOrNull("BridgeMultisig");
  if (existing && !process.env.FORCE_MULTISIG_DEPLOY) {
    log(`BridgeMultisig already deployed at ${existing.address} on ${network.name}`);
    log(`Set FORCE_MULTISIG_DEPLOY=true to force re-deployment`);
    return;
  }

  // Read and validate environment configuration
  const watchersEnv = process.env.MULTISIG_WATCHERS;
  const governanceEnv = process.env.MULTISIG_GOVERNANCE;
  const tokensEnv = process.env.MULTISIG_ALLOWED_TOKENS;

  if (!watchersEnv) {
    throw new Error("MULTISIG_WATCHERS environment variable is required (comma-separated list of 5 addresses)");
  }
  if (!governanceEnv) {
    throw new Error("MULTISIG_GOVERNANCE environment variable is required (comma-separated list of 5 addresses)");
  }
  if (!tokensEnv) {
    throw new Error("MULTISIG_ALLOWED_TOKENS environment variable is required (comma-separated list of ERC-20 addresses)");
  }

  // Parse addresses
  const watchers = watchersEnv.split(",").map(addr => addr.trim());
  const governance = governanceEnv.split(",").map(addr => addr.trim());
  const allowedTokens = tokensEnv.split(",").map(addr => addr.trim());

  // Validate watcher count
  if (watchers.length !== 5) {
    throw new Error(`MULTISIG_WATCHERS must contain exactly 5 addresses, got ${watchers.length}`);
  }

  // Validate governance count
  if (governance.length !== 5) {
    throw new Error(`MULTISIG_GOVERNANCE must contain exactly 5 addresses, got ${governance.length}`);
  }

  // Validate all addresses are valid and not zero address
  const validateAddresses = (addresses: string[], name: string) => {
    addresses.forEach((addr, index) => {
      if (!ethers.utils.isAddress(addr)) {
        throw new Error(`Invalid address in ${name}[${index}]: ${addr}`);
      }
      if (addr === ethers.constants.AddressZero) {
        throw new Error(`${name}[${index}] cannot be zero address`);
      }
    });
  };

  validateAddresses(watchers, "MULTISIG_WATCHERS");
  validateAddresses(governance, "MULTISIG_GOVERNANCE");
  validateAddresses(allowedTokens, "MULTISIG_ALLOWED_TOKENS");

  // Check for duplicate addresses within each set
  const checkDuplicates = (addresses: string[], name: string) => {
    const uniqueAddresses = new Set(addresses.map(a => a.toLowerCase()));
    if (uniqueAddresses.size !== addresses.length) {
      throw new Error(`${name} contains duplicate addresses`);
    }
  };

  checkDuplicates(watchers, "MULTISIG_WATCHERS");
  checkDuplicates(governance, "MULTISIG_GOVERNANCE");

  log(`\n========================================`);
  log(`Deploying BridgeMultisig to ${network.name}`);
  log(`========================================`);
  log(`Deployer: ${deployer}`);
  log(`\nWatchers (5):`);
  watchers.forEach((addr, i) => log(`  [${i}] ${addr}`));
  log(`\nGovernance (5):`);
  governance.forEach((addr, i) => log(`  [${i}] ${addr}`));
  log(`\nAllowed Tokens (${allowedTokens.length}):`);
  allowedTokens.forEach((addr, i) => log(`  [${i}] ${addr}`));
  log(`========================================\n`);

  const args = [watchers, governance, allowedTokens];
  const res = await deploy("BridgeMultisig", {
    from: deployer,
    args,
    log: true,
    waitConfirmations: 3,
  });

  log(`\n========================================`);
  log(`BridgeMultisig deployed successfully!`);
  log(`========================================`);
  log(`Address: ${res.address}`);
  log(`Transaction Hash: ${res.transactionHash || 'N/A'}`);
  log(`Block Number: ${res.receipt?.blockNumber || 'N/A'}`);
  log(`Network: ${network.name}`);
  log(`========================================`);
  log(`\nDeployment Configuration Summary:`);
  log(`  Watchers:          ${watchers.length} addresses (3-of-5 threshold)`);
  log(`  Governance:        ${governance.length} addresses (3-of-5 threshold)`);
  log(`  Allowed Tokens:    ${allowedTokens.length} tokens`);
  log(`========================================\n`);

  // Append to deployments README if it exists
  try {
    const fs = await import("fs");
    const path = await import("path");
    const readmePath = path.join("docs", "deployments", network.name, "README.md");

    if (fs.existsSync(readmePath)) {
      const timestamp = new Date().toISOString();
      const entry = `\n## BridgeMultisig - ${network.name}\n` +
        `- **Deployed:** ${timestamp}\n` +
        `- **Address:** ${res.address}\n` +
        `- **Transaction:** ${res.transactionHash || 'N/A'}\n` +
        `- **Watchers:** ${watchers.length} (3-of-5 threshold)\n` +
        `- **Governance:** ${governance.length} (3-of-5 threshold)\n` +
        `- **Allowed Tokens:** ${allowedTokens.length}\n`;

      fs.appendFileSync(readmePath, entry);
      log(`Appended deployment details to ${readmePath}`);
    }
  } catch (err) {
    // Non-fatal error, just log it
    log(`Note: Could not append to deployments/README.md: ${err}`);
  }
};

func.tags = ["BridgeMultisig"];

export default func;
