/**
 * Execute SET_TOKEN_STATUS governance action on EVM BridgeMultisig
 *
 * This script whitelists or blacklists a token in the EVM BridgeMultisig.
 * Requires 3-of-5 governance signatures.
 *
 * Usage:
 *   npx hardhat run scripts/evm-set-token-status.ts --network base
 *
 * Environment variables:
 *   EVM_GOV_KEY_0, EVM_GOV_KEY_1, EVM_GOV_KEY_2 - At least 3 governance private keys
 *   MULTISIG_ALLOWED_TOKENS - Token to whitelist/blacklist
 *   TOKEN_STATUS  - "true" to allow, "false" to disallow (default: true)
 */

import { ethers } from "hardhat";

async function main() {
  console.log("=== EVM SET TOKEN STATUS ===\n");

  // Get token address from env
  const tokenAddress = process.env.MULTISIG_ALLOWED_TOKENS;
  if (!tokenAddress) {
    throw new Error("MULTISIG_ALLOWED_TOKENS environment variable is required");
  }

  const tokenStatus = process.env.TOKEN_STATUS !== "false"; // default true

  console.log(`Token: ${tokenAddress}`);
  console.log(`Status: ${tokenStatus ? "ALLOWED" : "NOT ALLOWED"}\n`);

  // Get BridgeMultisig contract from current network's deployment
  const { deployments } = await import("hardhat");
  const deployment = await deployments.get("BridgeMultisig");
  const multisigAddress = deployment.address;

  console.log(`BridgeMultisig: ${multisigAddress}\n`);

  const BridgeMultisig = await ethers.getContractFactory("BridgeMultisig");
  const multisig = BridgeMultisig.attach(multisigAddress);

  // Get current governance nonce and epoch
  const currentNonce = await multisig.governanceNonce();
  const nextNonce = currentNonce.add(1);
  const currentEpoch = await multisig.governanceEpoch();
  console.log(`Current governance nonce: ${currentNonce.toString()}`);
  console.log(`Next nonce: ${nextNonce.toString()}`);
  console.log(`Current epoch: ${currentEpoch.toString()}\n`);

  // Check current token status
  const currentStatus = await multisig.allowedTokens(tokenAddress);
  console.log(`Current token status: ${currentStatus ? "ALLOWED" : "NOT ALLOWED"}`);

  if (currentStatus === tokenStatus) {
    console.log(`\nToken is already ${tokenStatus ? "ALLOWED" : "NOT ALLOWED"}. Nothing to do.`);
    return;
  }

  // Load governance keys
  const govKeys: string[] = [];
  for (let i = 0; i < 5; i++) {
    const key = process.env[`EVM_GOV_KEY_${i}`];
    if (key) {
      govKeys.push(key);
    }
  }

  if (govKeys.length < 3) {
    throw new Error(`Need at least 3 governance keys, found ${govKeys.length}. Set EVM_GOV_KEY_0, EVM_GOV_KEY_1, EVM_GOV_KEY_2`);
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
  const ACTION_SET_TOKEN_STATUS = ethers.utils.keccak256(
    ethers.utils.toUtf8Bytes("ACTION_SET_TOKEN_STATUS")
  );

  const actionData = ethers.utils.defaultAbiCoder.encode(
    ["address", "bool"],
    [tokenAddress, tokenStatus]
  );

  const action = {
    actionType: ACTION_SET_TOKEN_STATUS,
    data: actionData,
    nonce: nextNonce,
    epoch: currentEpoch,
  };

  // Get the digest from contract (ensures exact same hash computation)
  const digest = await multisig.governanceDigest(action);
  console.log(`\nDigest to sign: ${digest}`);

  // Sign the digest directly (as personal_sign, then recover in contract)
  console.log("\nCollecting signatures...");
  const signatures: string[] = [];

  for (let i = 0; i < 3; i++) {
    const signer = signers[i];
    const addr = await signer.getAddress();
    // Sign using signMessage which adds "\x19Ethereum Signed Message:\n32" prefix
    // But contract uses ECDSA.recover which expects raw signature on digest
    // So we need to use a raw signing approach
    const keyHex = govKeys[i].startsWith("0x") ? govKeys[i] : `0x${govKeys[i]}`;
    const signingKey = new ethers.utils.SigningKey(keyHex);
    const sig = signingKey.signDigest(digest);
    const signature = ethers.utils.joinSignature(sig);
    signatures.push(signature);
    console.log(`  ✓ Signed by ${addr}`);
  }

  // Execute governance action
  console.log("\nExecuting governance action...");

  const [deployer] = await ethers.getSigners();
  const tx = await multisig.connect(deployer).executeGovernanceAction(action, signatures);

  console.log(`Transaction hash: ${tx.hash}`);
  console.log("Waiting for confirmation...");

  const receipt = await tx.wait();
  console.log(`\n✅ Transaction confirmed in block ${receipt.blockNumber}`);

  // Wait a bit for state to propagate
  await new Promise((resolve) => setTimeout(resolve, 2000));

  // Verify new status
  const newStatus = await multisig.allowedTokens(tokenAddress);
  console.log(`\nNew token status: ${newStatus ? "ALLOWED" : "NOT ALLOWED"}`);

  if (newStatus === tokenStatus) {
    console.log("\n✅ Token status updated successfully!");
  } else {
    console.log("\n❌ Token status update failed!");
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
