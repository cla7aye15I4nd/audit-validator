/**
 * Execute UPDATE_WATCHERS governance action on EVM BridgeMultisig
 *
 * This script updates the watcher set. WARNING: This increments governanceEpoch!
 * Requires 3-of-5 governance signatures.
 *
 * Usage:
 *   # Rotate watchers (swap first two positions)
 *   ROTATE_WATCHERS=true npx hardhat run scripts/evm/update-watchers.ts --network bsc
 *
 *   # Set specific watchers (comma-separated, must be exactly 5)
 *   NEW_WATCHERS=0x...,0x...,0x...,0x...,0x... npx hardhat run scripts/evm/update-watchers.ts --network bsc
 *
 * Environment variables:
 *   EVM_GOV_KEY_0, EVM_GOV_KEY_1, EVM_GOV_KEY_2 - At least 3 governance private keys
 *   ROTATE_WATCHERS - If "true", swaps first two watcher positions
 *   NEW_WATCHERS - Comma-separated list of 5 watcher addresses
 */

import { ethers } from "hardhat";

async function main() {
  console.log("=== EVM UPDATE WATCHERS ===\n");
  console.log("⚠️  WARNING: This action increments governanceEpoch!\n");

  // Get BridgeMultisig contract
  const { deployments } = await import("hardhat");
  const deployment = await deployments.get("BridgeMultisig");
  const multisigAddress = deployment.address;

  console.log(`BridgeMultisig: ${multisigAddress}\n`);

  const BridgeMultisig = await ethers.getContractFactory("BridgeMultisig");
  const multisig = BridgeMultisig.attach(multisigAddress);

  // Get current state
  const currentWatchers = await multisig.getWatchers();
  const currentGovNonce = await multisig.governanceNonce();
  const nextGovNonce = currentGovNonce.add(1);
  const currentEpoch = await multisig.governanceEpoch();

  console.log("Current watchers:");
  currentWatchers.forEach((w: string, i: number) => console.log(`  ${i}: ${w}`));
  console.log(`\nCurrent governance nonce: ${currentGovNonce.toString()}`);
  console.log(`Next governance nonce: ${nextGovNonce.toString()}`);
  console.log(`Current epoch: ${currentEpoch.toString()}`);
  console.log(`New epoch after execution: ${currentEpoch.add(1).toString()}\n`);

  // Determine new watchers
  let newWatchers: string[];

  if (process.env.NEW_WATCHERS) {
    newWatchers = process.env.NEW_WATCHERS.split(",").map(w => w.trim());
    if (newWatchers.length !== 5) {
      throw new Error(`NEW_WATCHERS must have exactly 5 addresses, got ${newWatchers.length}`);
    }
    console.log("Using NEW_WATCHERS from environment");
  } else if (process.env.ROTATE_WATCHERS === "true") {
    // Swap first two positions
    newWatchers = [...currentWatchers];
    [newWatchers[0], newWatchers[1]] = [newWatchers[1], newWatchers[0]];
    console.log("Rotating watchers (swapping positions 0 and 1)");
  } else {
    throw new Error("Set ROTATE_WATCHERS=true or provide NEW_WATCHERS=0x...,0x...,0x...,0x...,0x...");
  }

  console.log("\nNew watchers:");
  newWatchers.forEach((w: string, i: number) => console.log(`  ${i}: ${w}`));

  // Load governance keys
  const govKeys: string[] = [];
  for (let i = 0; i < 5; i++) {
    const key = process.env[`EVM_GOV_KEY_${i}`];
    if (key) {
      govKeys.push(key);
    }
  }

  if (govKeys.length < 3) {
    throw new Error(`Need at least 3 governance keys, found ${govKeys.length}`);
  }

  console.log(`\nLoaded ${govKeys.length} governance keys`);

  // Create signers
  const signers = govKeys.map((key) => new ethers.Wallet(key, ethers.provider));

  // Verify signers are governance members
  const governance = await multisig.getGovernance();
  console.log("\nVerifying signers are governance members...");
  for (const signer of signers) {
    const addr = await signer.getAddress();
    const isGov = governance.map((a: string) => a.toLowerCase()).includes(addr.toLowerCase());
    if (!isGov) {
      throw new Error(`Signer ${addr} is not a governance member`);
    }
    console.log(`  ✓ ${addr}`);
  }

  // Build governance action
  const ACTION_UPDATE_WATCHERS = ethers.utils.keccak256(
    ethers.utils.toUtf8Bytes("ACTION_UPDATE_WATCHERS")
  );

  const actionData = ethers.utils.defaultAbiCoder.encode(
    ["address[]"],
    [newWatchers]
  );

  const action = {
    actionType: ACTION_UPDATE_WATCHERS,
    data: actionData,
    nonce: nextGovNonce,
    epoch: currentEpoch,
  };

  // Get the digest from contract
  const digest = await multisig.governanceDigest(action);
  console.log(`\nDigest to sign: ${digest}`);

  // Sign the digest
  console.log("\nCollecting signatures...");
  const signatures: string[] = [];

  for (let i = 0; i < 3; i++) {
    const signer = signers[i];
    const addr = await signer.getAddress();
    const keyHex = govKeys[i].startsWith("0x") ? govKeys[i] : `0x${govKeys[i]}`;
    const signingKey = new ethers.utils.SigningKey(keyHex);
    const sig = signingKey.signDigest(digest);
    const signature = ethers.utils.joinSignature(sig);
    signatures.push(signature);
    console.log(`  ✓ Signed by ${addr}`);
  }

  // Execute governance action
  console.log("\n🚨 Executing governance action (epoch will increment)...");

  const [deployer] = await ethers.getSigners();
  const tx = await multisig.connect(deployer).executeGovernanceAction(action, signatures);

  console.log(`Transaction hash: ${tx.hash}`);
  console.log("Waiting for confirmation...");

  const receipt = await tx.wait();
  console.log(`\n✅ Transaction confirmed in block ${receipt.blockNumber}`);

  // Wait for state to propagate
  await new Promise((resolve) => setTimeout(resolve, 2000));

  // Verify new state
  const updatedWatchers = await multisig.getWatchers();
  const newEpoch = await multisig.governanceEpoch();

  console.log("\nUpdated watchers:");
  updatedWatchers.forEach((w: string, i: number) => console.log(`  ${i}: ${w}`));
  console.log(`\nNew epoch: ${newEpoch.toString()}`);

  // Verify
  const watchersMatch = newWatchers.every(
    (w, i) => w.toLowerCase() === updatedWatchers[i].toLowerCase()
  );

  if (watchersMatch && newEpoch.eq(currentEpoch.add(1))) {
    console.log("\n✅ Watchers updated successfully!");
  } else {
    console.log("\n❌ Watcher update verification failed!");
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
