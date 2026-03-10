/**
 * Execute MAP_TOKEN governance action on EVM BridgeMultisig
 *
 * This script maps a TON jetton to an EVM token address for TON→EVM bridge direction.
 * Requires 3-of-5 governance signatures.
 *
 * Usage:
 *   npx hardhat run scripts/evm/map-token.ts --network base
 *
 * Environment variables:
 *   EVM_GOV_KEY_0, EVM_GOV_KEY_1, EVM_GOV_KEY_2 - At least 3 governance private keys
 *   TON_JETTON_ROOT - TON jetton root address (e.g., EQxxx...)
 *   EVM_TOKEN_ADDRESS - EVM token address to map to
 */

import { ethers } from "hardhat";

async function main() {
  console.log("=== EVM MAP TOKEN ===\n");

  // Get TON jetton root from env
  const tonJettonRoot = process.env.TON_JETTON_ROOT;
  if (!tonJettonRoot) {
    throw new Error("TON_JETTON_ROOT environment variable is required");
  }

  // Get EVM token address from env
  const evmTokenAddress = process.env.EVM_TOKEN_ADDRESS;
  if (!evmTokenAddress) {
    throw new Error("EVM_TOKEN_ADDRESS environment variable is required");
  }

  // Compute TON jetton hash (keccak256 of the address string)
  const tonJettonHash = ethers.utils.keccak256(ethers.utils.toUtf8Bytes(tonJettonRoot));

  console.log(`TON Jetton Root: ${tonJettonRoot}`);
  console.log(`TON Jetton Hash: ${tonJettonHash}`);
  console.log(`EVM Token: ${evmTokenAddress}\n`);

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

  // Check current mapping
  const currentMapping = await multisig.tokenMappings(tonJettonHash);
  console.log(`Current mapping: ${currentMapping}`);

  if (currentMapping.toLowerCase() === evmTokenAddress.toLowerCase()) {
    console.log(`\nToken is already mapped to ${evmTokenAddress}. Nothing to do.`);
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
  const ACTION_MAP_TOKEN = ethers.utils.keccak256(
    ethers.utils.toUtf8Bytes("ACTION_MAP_TOKEN")
  );

  const actionData = ethers.utils.defaultAbiCoder.encode(
    ["bytes32", "address"],
    [tonJettonHash, evmTokenAddress]
  );

  const action = {
    actionType: ACTION_MAP_TOKEN,
    data: actionData,
    nonce: nextNonce,
    epoch: currentEpoch,
  };

  // Get the digest from contract (ensures exact same hash computation)
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
  console.log("\nExecuting governance action...");

  const [deployer] = await ethers.getSigners();
  const tx = await multisig.connect(deployer).executeGovernanceAction(action, signatures);

  console.log(`Transaction hash: ${tx.hash}`);
  console.log("Waiting for confirmation...");

  const receipt = await tx.wait();
  console.log(`\n✅ Transaction confirmed in block ${receipt.blockNumber}`);

  // Wait a bit for state to propagate
  await new Promise((resolve) => setTimeout(resolve, 2000));

  // Verify new mapping
  const newMapping = await multisig.tokenMappings(tonJettonHash);
  console.log(`\nNew mapping: ${newMapping}`);

  if (newMapping.toLowerCase() === evmTokenAddress.toLowerCase()) {
    console.log("\n✅ Token mapping created successfully!");
    console.log(`\n${tonJettonRoot} => ${evmTokenAddress}`);
  } else {
    console.log("\n❌ Token mapping failed!");
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
