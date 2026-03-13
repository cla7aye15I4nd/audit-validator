/**
 * Execute UPDATE_GOVERNANCE governance action on EVM BridgeMultisig
 *
 * This script updates the governance set. WARNING: This increments governanceEpoch!
 * Requires 3-of-5 governance signatures.
 *
 * Usage:
 *   # Rotate governance (swap first two positions)
 *   ROTATE_GOVERNANCE=true npx hardhat run scripts/evm/update-governance.ts --network bsc
 *
 *   # Set specific governance (comma-separated, must be exactly 5)
 *   NEW_GOVERNANCE=0x...,0x...,0x...,0x...,0x... npx hardhat run scripts/evm/update-governance.ts --network bsc
 *
 * Environment variables:
 *   EVM_GOV_KEY_0, EVM_GOV_KEY_1, EVM_GOV_KEY_2 - At least 3 governance private keys
 *   ROTATE_GOVERNANCE - If "true", swaps first two governance positions
 *   NEW_GOVERNANCE - Comma-separated list of 5 governance addresses
 */

import { ethers } from "hardhat";

async function main() {
  console.log("=== EVM UPDATE GOVERNANCE ===\n");
  console.log("⚠️  WARNING: This action increments governanceEpoch!\n");

  // Get BridgeMultisig contract
  const { deployments } = await import("hardhat");
  const deployment = await deployments.get("BridgeMultisig");
  const multisigAddress = deployment.address;

  console.log(`BridgeMultisig: ${multisigAddress}\n`);

  const BridgeMultisig = await ethers.getContractFactory("BridgeMultisig");
  const multisig = BridgeMultisig.attach(multisigAddress);

  // Get current state
  const currentGovernance = await multisig.getGovernance();
  const currentGovNonce = await multisig.governanceNonce();
  const nextGovNonce = currentGovNonce.add(1);
  const currentEpoch = await multisig.governanceEpoch();

  console.log("Current governance:");
  currentGovernance.forEach((g: string, i: number) => console.log(`  ${i}: ${g}`));
  console.log(`\nCurrent governance nonce: ${currentGovNonce.toString()}`);
  console.log(`Next governance nonce: ${nextGovNonce.toString()}`);
  console.log(`Current epoch: ${currentEpoch.toString()}`);
  console.log(`New epoch after execution: ${currentEpoch.add(1).toString()}\n`);

  // Determine new governance
  let newGovernance: string[];

  if (process.env.NEW_GOVERNANCE) {
    newGovernance = process.env.NEW_GOVERNANCE.split(",").map(g => g.trim());
    if (newGovernance.length !== 5) {
      throw new Error(`NEW_GOVERNANCE must have exactly 5 addresses, got ${newGovernance.length}`);
    }
    console.log("Using NEW_GOVERNANCE from environment");
  } else if (process.env.ROTATE_GOVERNANCE === "true") {
    // Swap first two positions
    newGovernance = [...currentGovernance];
    [newGovernance[0], newGovernance[1]] = [newGovernance[1], newGovernance[0]];
    console.log("Rotating governance (swapping positions 0 and 1)");
  } else {
    throw new Error("Set ROTATE_GOVERNANCE=true or provide NEW_GOVERNANCE=0x...,0x...,0x...,0x...,0x...");
  }

  console.log("\nNew governance:");
  newGovernance.forEach((g: string, i: number) => console.log(`  ${i}: ${g}`));

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
  console.log("\nVerifying signers are governance members...");
  for (const signer of signers) {
    const addr = await signer.getAddress();
    const isGov = currentGovernance.map((a: string) => a.toLowerCase()).includes(addr.toLowerCase());
    if (!isGov) {
      throw new Error(`Signer ${addr} is not a governance member`);
    }
    console.log(`  ✓ ${addr}`);
  }

  // Build governance action
  const ACTION_UPDATE_GOVERNANCE = ethers.utils.keccak256(
    ethers.utils.toUtf8Bytes("ACTION_UPDATE_GOVERNANCE")
  );

  const actionData = ethers.utils.defaultAbiCoder.encode(
    ["address[]"],
    [newGovernance]
  );

  const action = {
    actionType: ACTION_UPDATE_GOVERNANCE,
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
  const updatedGovernance = await multisig.getGovernance();
  const newEpoch = await multisig.governanceEpoch();

  console.log("\nUpdated governance:");
  updatedGovernance.forEach((g: string, i: number) => console.log(`  ${i}: ${g}`));
  console.log(`\nNew epoch: ${newEpoch.toString()}`);

  // Verify
  const governanceMatch = newGovernance.every(
    (g, i) => g.toLowerCase() === updatedGovernance[i].toLowerCase()
  );

  if (governanceMatch && newEpoch.eq(currentEpoch.add(1))) {
    console.log("\n✅ Governance updated successfully!");
  } else {
    console.log("\n❌ Governance update verification failed!");
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
