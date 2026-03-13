import { ethers, run, upgrades } from "hardhat";

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying RewardVault with the account:", deployer.address);

  // Deploy RewardVault
  console.log("\nDeploying RewardVault...");
  const RewardVault = await ethers.getContractFactory("RewardVault");
  const rewardVault = await upgrades.deployProxy(RewardVault, []);
  await rewardVault.waitForDeployment();
  const rewardVaultAddress = await rewardVault.getAddress();
  console.log("RewardVault deployed to:", rewardVaultAddress);

  // Get contract info for verification
  console.log("\n=== Deployment Summary ===");
  console.log("RewardVault:", rewardVaultAddress);
  console.log("Deployer:", deployer.address);

  // Verify contract
  console.log("\nVerifying RewardVault...");
  await run("verify:verify", {
    address: rewardVaultAddress,
    constructorArguments: [],
  });

  console.log("\n✅ RewardVault deployment completed successfully!");
  console.log("\n📝 Next Steps:");
  console.log("1. Deploy MWXStaking and set this RewardVault address");
  console.log("2. Transfer reward tokens to RewardVault:", rewardVaultAddress);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  }); 