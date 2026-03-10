import { ethers, run, upgrades } from "hardhat";
import readline from "readline/promises";
import { stdin as input, stdout as output } from "process";
import { getValidatedTokenAddress, getTokenDecimals } from "./helper/deployment.helper";
import { RewardVault } from "../typechain-types";

async function validateRewardVaultAddress(rewardVaultAddress: string): Promise<boolean> {
  try {
    // Check if the address is valid
    if (!ethers.isAddress(rewardVaultAddress)) {
      console.log("❌ Invalid address format");
      return false;
    }

    // Check if the contract exists
    const code = await ethers.provider.getCode(rewardVaultAddress);
    if (code === "0x") {
      console.log("❌ No contract found at the provided address");
      return false;
    }

    // Try to create a contract instance and check if it has the expected interface
    try {
      const RewardVaultFactory = await ethers.getContractFactory("RewardVault");
      const rewardVault = RewardVaultFactory.attach(rewardVaultAddress) as RewardVault;
      
      // Check if the contract has the expected functions by calling them
      // We'll use a try-catch to check if the functions exist
      try {
        // Try to call a function that should exist in RewardVault
        const stakingAddress = await rewardVault.staking();
        console.log("stakingAddress: ", stakingAddress);
        console.log("✅ Valid RewardVault contract found");
        return true;
      } catch (error) {
        console.log(error);
        console.log("❌ Contract at the provided address is not a valid RewardVault");
        return false;
      }
    } catch (error) {
      console.log("❌ Error creating RewardVault contract instance");
      return false;
    }
  } catch (error) {
    console.log("❌ Error validating RewardVault address:", error);
    return false;
  }
}

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying MWXStaking with the account:", deployer.address);

  const rl = readline.createInterface({ input, output });

  // Get and validate Staking Token address
  const stakingToken = await getValidatedTokenAddress(rl, "Staking Token");
  const stakingTokenDecimals = await getTokenDecimals(stakingToken);
  console.log(`📊 Staking Token decimals: ${stakingTokenDecimals}\n`);

  // Get and validate Reward Token address
  const rewardToken = await getValidatedTokenAddress(rl, "Reward Token");
  const rewardTokenDecimals = await getTokenDecimals(rewardToken);
  console.log(`📊 Reward Token decimals: ${rewardTokenDecimals}\n`);

  // Get and validate RewardVault address
  let rewardVaultAddress = "";
  let isValidRewardVault = false;
  
  while (!isValidRewardVault) {
    const inputAddress = await rl.question("Enter RewardVault contract address: ");
    console.log(`\nValidating RewardVault address: ${inputAddress}`);
    isValidRewardVault = await validateRewardVaultAddress(inputAddress);
    
    if (isValidRewardVault) {
      rewardVaultAddress = inputAddress;
    } else {
      console.log("Please provide a valid RewardVault contract address.\n");
    }
  }

  // Get reward pool parameters
  console.log("\nEnter reward pool parameters:");
  const rewardPoolAmount = await rl.question("  Reward pool amount (e.g., 1000000 for 1M tokens): ");
  const forYear = Number(await rl.question("  Number of years for reward pool (default: 1): ") || "1");

  // Validate inputs
  if (!rewardPoolAmount || isNaN(Number(rewardPoolAmount)) || Number(rewardPoolAmount) <= 0) {
    throw new Error("Invalid reward pool amount");
  }
  if (forYear <= 0) {
    throw new Error("Invalid number of years");
  }

  // Convert reward pool amount to wei (assuming 18 decimals for reward token)
  const rewardPoolInWei = ethers.parseUnits(rewardPoolAmount, rewardTokenDecimals);

  rl.close();

  console.log(`\n📋 Deployment Summary:`);
  console.log(`   Staking Token: ${stakingToken} (${stakingTokenDecimals} decimals)`);
  console.log(`   Reward Token: ${rewardToken} (${rewardTokenDecimals} decimals)`);
  console.log(`   RewardVault: ${rewardVaultAddress}`);
  console.log(`   Reward Pool: ${rewardPoolAmount} tokens (${rewardPoolInWei} wei)`);
  console.log(`   Reward Pool Duration: ${forYear} year(s)`);
  console.log(`   Deployer: ${deployer.address}`);

  // Deploy MWXStaking
  console.log("\nDeploying MWXStaking...");
  const MWXStaking = await ethers.getContractFactory("MWXStaking");
  const mwxStaking = await upgrades.deployProxy(MWXStaking, [
    stakingToken,
    rewardToken,
    rewardVaultAddress,
    rewardPoolInWei,
    forYear
  ]);
  await mwxStaking.waitForDeployment();
  const stakingAddress = await mwxStaking.getAddress();
  console.log("MWXStaking deployed to:", stakingAddress);

  // Set up connections between contracts
  console.log("\nSetting up contract connections...");
  
  // Get RewardVault instance and set staking address
  console.log("Setting staking address in RewardVault...");
  const RewardVault = await ethers.getContractFactory("RewardVault");
  const rewardVault = RewardVault.attach(rewardVaultAddress) as any;
  const setStakingAddressTx = await rewardVault.setStakingAddress(mwxStaking);
  await setStakingAddressTx.wait();
  console.log("✅ Staking address set in RewardVault");

  // Approve reward tokens in RewardVault
  console.log("Approving reward tokens in RewardVault...");
  const approveTx = await rewardVault.approve();
  await approveTx.wait();
  console.log("✅ Reward tokens approved in RewardVault");

  // Get contract info for verification
  console.log("\n=== Deployment Summary ===");
  console.log("Staking Token:", stakingToken);
  console.log("Reward Token:", rewardToken);
  console.log("MWXStaking:", stakingAddress);
  console.log("RewardVault:", rewardVaultAddress);
  console.log("Annual Reward Pool:", rewardPoolAmount, "tokens");
  console.log("Reward Pool Duration:", forYear, "year(s)");
  console.log("Deployer:", deployer.address);

  // Display default locked options
  console.log("\n=== Default Locked Options ===");
  const lockOption1 = await mwxStaking.getLockedOption(1);
  const lockOption2 = await mwxStaking.getLockedOption(2);
  const lockOption3 = await mwxStaking.getLockedOption(3);
  
  console.log("Lock Option 1: 3 months, 1.25x multiplier");
  console.log("Lock Option 2: 6 months, 1.5x multiplier");
  console.log("Lock Option 3: 12 months, 2x multiplier");

  // Verify MWXStaking contract
  console.log("\nVerifying MWXStaking...");
  await run("verify:verify", {
    address: stakingAddress,
    constructorArguments: [],
  });

  console.log("\n✅ MWXStaking deployment completed successfully!");
  console.log("\n📝 Next Steps:");
  console.log("1. Transfer reward tokens to RewardVault:", rewardVaultAddress);
  console.log("2. Users can now stake tokens and earn rewards");
  console.log("3. RewardVault will automatically distribute rewards to stakers");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  }); 