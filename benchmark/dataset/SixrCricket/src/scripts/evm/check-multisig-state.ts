/**
 * Check BridgeMultisig state on current network
 */
import { ethers, deployments } from "hardhat";

async function main() {
  const msDeployment = await deployments.get("BridgeMultisig");
  const tokenDeployment = await deployments.get("BridgedSIXR");

  const multisig = await ethers.getContractAt("BridgeMultisig", msDeployment.address);

  console.log("=== BridgeMultisig State ===\n");
  console.log("BridgeMultisig:", msDeployment.address);
  console.log("BridgedSIXR:", tokenDeployment.address);
  console.log("");
  console.log("Token allowed:", await multisig.allowedTokens(tokenDeployment.address));
  console.log("Mint nonce:", (await multisig.mintNonce()).toString());
  console.log("Gov nonce:", (await multisig.governanceNonce()).toString());
  console.log("Gov epoch:", (await multisig.governanceEpoch()).toString());
  console.log("");

  const watchers = await multisig.getWatchers();
  console.log("Watchers:");
  watchers.forEach((w: string, i: number) => console.log(`  ${i}: ${w}`));

  const governance = await multisig.getGovernance();
  console.log("\nGovernance:");
  governance.forEach((g: string, i: number) => console.log(`  ${i}: ${g}`));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
