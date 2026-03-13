/**
 * Execute TRANSFER_TOKEN_OWNER governance action on EVM BridgeMultisig
 *
 * This script transfers ownership of a token contract.
 * Requires 3-of-5 governance signatures.
 *
 * Usage:
 *   # Transfer BridgedSIXR ownership to a new address
 *   NEW_OWNER=0x... npx hardhat run scripts/evm/transfer-token-owner.ts --network bsc
 *
 *   # Transfer back to BridgeMultisig
 *   NEW_OWNER=multisig npx hardhat run scripts/evm/transfer-token-owner.ts --network bsc
 *
 * Environment variables:
 *   EVM_GOV_KEY_0, EVM_GOV_KEY_1, EVM_GOV_KEY_2 - At least 3 governance private keys
 *   TOKEN_ADDRESS - Token contract address (default: BridgedSIXR from deployments)
 *   NEW_OWNER - New owner address, or "multisig" to transfer back to BridgeMultisig
 */

import { ethers } from "hardhat";

async function main() {
  console.log("=== EVM TRANSFER TOKEN OWNER ===\n");

  // Get BridgeMultisig contract
  const { deployments } = await import("hardhat");
  const msDeployment = await deployments.get("BridgeMultisig");
  const multisigAddress = msDeployment.address;

  // Get token address
  let tokenAddress = process.env.TOKEN_ADDRESS;
  if (!tokenAddress) {
    const tokenDeployment = await deployments.get("BridgedSIXR");
    tokenAddress = tokenDeployment.address;
  }

  // Get new owner
  let newOwner = process.env.NEW_OWNER;
  if (!newOwner) {
    throw new Error("NEW_OWNER environment variable is required");
  }

  if (newOwner.toLowerCase() === "multisig") {
    newOwner = multisigAddress;
  }

  console.log(`BridgeMultisig: ${multisigAddress}`);
  console.log(`Token: ${tokenAddress}`);
  console.log(`New Owner: ${newOwner}\n`);

  const BridgeMultisig = await ethers.getContractFactory("BridgeMultisig");
  const multisig = BridgeMultisig.attach(multisigAddress);

  // Get current token owner
  const token = await ethers.getContractAt("BridgedSIXR", tokenAddress);
  const currentOwner = await token.owner();
  console.log(`Current token owner: ${currentOwner}`);

  if (currentOwner.toLowerCase() === newOwner.toLowerCase()) {
    console.log(`\nToken is already owned by ${newOwner}. Nothing to do.`);
    return;
  }

  // Get current governance state
  const currentGovNonce = await multisig.governanceNonce();
  const nextGovNonce = currentGovNonce.add(1);
  const currentEpoch = await multisig.governanceEpoch();

  console.log(`\nCurrent governance nonce: ${currentGovNonce.toString()}`);
  console.log(`Next governance nonce: ${nextGovNonce.toString()}`);
  console.log(`Current epoch: ${currentEpoch.toString()}\n`);

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

  console.log(`Loaded ${govKeys.length} governance keys`);

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
  const ACTION_TRANSFER_TOKEN_OWNER = ethers.utils.keccak256(
    ethers.utils.toUtf8Bytes("ACTION_TRANSFER_TOKEN_OWNER")
  );

  const actionData = ethers.utils.defaultAbiCoder.encode(
    ["address", "address"],
    [tokenAddress, newOwner]
  );

  const action = {
    actionType: ACTION_TRANSFER_TOKEN_OWNER,
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
  console.log("\n🚨 Executing governance action (transferring token ownership)...");

  const [deployer] = await ethers.getSigners();
  const tx = await multisig.connect(deployer).executeGovernanceAction(action, signatures);

  console.log(`Transaction hash: ${tx.hash}`);
  console.log("Waiting for confirmation...");

  const receipt = await tx.wait();
  console.log(`\n✅ Transaction confirmed in block ${receipt.blockNumber}`);

  // Wait for state to propagate
  await new Promise((resolve) => setTimeout(resolve, 2000));

  // Verify new owner
  const updatedOwner = await token.owner();
  console.log(`\nNew token owner: ${updatedOwner}`);

  if (updatedOwner.toLowerCase() === newOwner.toLowerCase()) {
    console.log("\n✅ Token ownership transferred successfully!");
  } else {
    console.log("\n❌ Token ownership transfer failed!");
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
