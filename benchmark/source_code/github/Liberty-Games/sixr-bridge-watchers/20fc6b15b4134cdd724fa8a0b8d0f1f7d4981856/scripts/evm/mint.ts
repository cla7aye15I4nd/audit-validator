/**
 * Mint BridgedSIXR tokens via BridgeMultisig governance action
 *
 * Usage:
 *   npx hardhat run scripts/evm/mint.ts --network base
 *
 * Environment variables:
 *   EVM_GOV_KEY_0, EVM_GOV_KEY_1, EVM_GOV_KEY_2 - At least 3 governance private keys
 *   MINT_TO        - Recipient address
 *   MINT_AMOUNT    - Amount to mint (in whole tokens, e.g. "100" for 100 SIXRTEST)
 *   MINT_TOKEN     - Token address (optional, defaults to BridgedSIXR deployment)
 */

import { ethers, deployments } from "hardhat";

async function main() {
  console.log("=== EVM MINT TOKENS ===\n");

  // Get recipient
  const mintTo = process.env.MINT_TO;
  if (!mintTo) {
    throw new Error("MINT_TO environment variable is required");
  }

  // Get amount
  const amountStr = process.env.MINT_AMOUNT;
  if (!amountStr) {
    throw new Error("MINT_AMOUNT environment variable is required");
  }
  const amount = ethers.utils.parseEther(amountStr);

  // Get token address
  let tokenAddress = process.env.MINT_TOKEN;
  if (!tokenAddress) {
    const tokenDeployment = await deployments.get("BridgedSIXR");
    tokenAddress = tokenDeployment.address;
  }

  console.log(`Token: ${tokenAddress}`);
  console.log(`Recipient: ${mintTo}`);
  console.log(`Amount: ${amountStr} (${amount.toString()} wei)\n`);

  // Get BridgeMultisig
  const multisigDeployment = await deployments.get("BridgeMultisig");
  const multisigAddress = multisigDeployment.address;
  console.log(`BridgeMultisig: ${multisigAddress}\n`);

  const BridgeMultisig = await ethers.getContractFactory("BridgeMultisig");
  const multisig = BridgeMultisig.attach(multisigAddress);

  // Check token is allowed
  const isAllowed = await multisig.allowedTokens(tokenAddress);
  if (!isAllowed) {
    throw new Error(`Token ${tokenAddress} is not allowed in BridgeMultisig`);
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
    throw new Error(`Need at least 3 governance keys, found ${govKeys.length}`);
  }

  console.log(`Loaded ${govKeys.length} governance keys`);

  // Create signers and verify
  const signers = govKeys.map((key) => {
    const keyHex = key.startsWith("0x") ? key : `0x${key}`;
    return new ethers.Wallet(keyHex, ethers.provider);
  });

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

  // Get mint nonce - use env var or default to timestamp-based unique nonce
  // Old BridgeMultisig versions don't have mintNonce() getter
  let mintNonce: number;
  if (process.env.MINT_NONCE) {
    mintNonce = parseInt(process.env.MINT_NONCE);
  } else {
    // Use timestamp as unique nonce (seconds since epoch)
    mintNonce = Math.floor(Date.now() / 1000);
  }
  console.log(`\nUsing mint nonce: ${mintNonce}`);

  // Build mint payload
  const chainId = (await ethers.provider.getNetwork()).chainId;
  const payload = {
    originChainId: chainId, // Using same chain as origin for admin mint
    token: tokenAddress,
    recipient: mintTo,
    amount: amount,
    nonce: mintNonce,
  };

  // Get digest from contract
  const digest = await multisig.mintDigest(payload);
  console.log(`\nDigest to sign: ${digest}`);

  // Sign with watcher keys (mint uses watcher threshold, not governance)
  // But we're using governance keys - check if they're also watchers
  const watchers = await multisig.getWatchers();
  console.log("\nNote: Mint requires WATCHER signatures (2-of-3), not governance.");
  console.log("Checking if governance keys are also watchers...");

  const watcherSigners: ethers.Wallet[] = [];
  for (const signer of signers) {
    const addr = await signer.getAddress();
    const isWatcher = watchers.map((a: string) => a.toLowerCase()).includes(addr.toLowerCase());
    if (isWatcher) {
      watcherSigners.push(signer);
      console.log(`  ✓ ${addr} is a watcher`);
    }
  }

  if (watcherSigners.length < 2) {
    console.log("\nGovernance keys are not watchers. Using EVM_WATCHER_KEY_* instead...");

    // Try loading watcher keys
    for (let i = 0; i < 3; i++) {
      const key = process.env[`EVM_WATCHER_KEY_${i}`];
      if (key) {
        const keyHex = key.startsWith("0x") ? key : `0x${key}`;
        const signer = new ethers.Wallet(keyHex, ethers.provider);
        const addr = await signer.getAddress();
        const isWatcher = watchers.map((a: string) => a.toLowerCase()).includes(addr.toLowerCase());
        if (isWatcher && !watcherSigners.find(s => s.address.toLowerCase() === addr.toLowerCase())) {
          watcherSigners.push(signer);
          console.log(`  ✓ Loaded watcher ${addr}`);
        }
      }
    }
  }

  if (watcherSigners.length < 2) {
    throw new Error(`Need at least 2 watcher signatures, found ${watcherSigners.length}. Set EVM_WATCHER_KEY_0, EVM_WATCHER_KEY_1`);
  }

  // Collect signatures
  console.log("\nCollecting signatures...");
  const signatures: string[] = [];

  for (let i = 0; i < 2; i++) {
    const signer = watcherSigners[i];
    const addr = await signer.getAddress();
    const keyHex = signer.privateKey;
    const signingKey = new ethers.utils.SigningKey(keyHex);
    const sig = signingKey.signDigest(digest);
    const signature = ethers.utils.joinSignature(sig);
    signatures.push(signature);
    console.log(`  ✓ Signed by ${addr}`);
  }

  // Execute mint
  console.log("\nExecuting mint...");

  const [deployer] = await ethers.getSigners();
  const tx = await multisig.connect(deployer).executeMint(payload, signatures);

  console.log(`Transaction hash: ${tx.hash}`);
  console.log("Waiting for confirmation...");

  const receipt = await tx.wait();
  console.log(`\n✅ Transaction confirmed in block ${receipt.blockNumber}`);

  // Check balance
  const token = await ethers.getContractAt("BridgedSIXR", tokenAddress);
  const balance = await token.balanceOf(mintTo);
  console.log(`\nRecipient balance: ${ethers.utils.formatEther(balance)} SIXRTEST`);

  console.log("\n✅ Mint completed successfully!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
