/**
 * @file submit-payload.ts
 * @notice Example script showing how to submit a payload to the Bridge Aggregator
 *
 * This demonstrates how watchers should interact with the aggregator API.
 */

import 'dotenv/config';
import { ethers } from 'ethers';
import { buildPayload, buildDomain, signPayload } from '../../shared/payload';

/**
 * Example: Submit a payload to the Bridge Aggregator
 */
async function main() {
  // Configuration
  const aggregatorUrl = process.env.BRIDGE_AGGREGATOR_URL || 'http://localhost:3000';
  const watcherPrivateKey = process.env.WATCHER_PRIVKEY_1;
  const multisigAddress = process.env.MULTISIG_ADDRESS;
  const tokenDecimals = parseInt(process.env.TOKEN_DECIMALS || '18', 10);
  const chainId = parseInt(process.env.BASE_CHAIN_ID || '8453', 10);

  if (!watcherPrivateKey) {
    throw new Error('WATCHER_PRIVKEY_1 environment variable is required');
  }

  if (!multisigAddress) {
    throw new Error('MULTISIG_ADDRESS environment variable is required');
  }

  // Create watcher wallet
  const wallet = new ethers.Wallet(watcherPrivateKey);

  console.log('Watcher Payload Submission Example');
  console.log('===================================\n');
  console.log(`Aggregator URL: ${aggregatorUrl}`);
  console.log(`Watcher:        ${wallet.address}\n`);

  // Example payload data (from TON burn)
  const payloadData = {
    originChainId: 0, // TON
    token: process.env.OFT_CONTRACT_ADDRESS!,
    recipient: '0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb0', // Example recipient
    amountRaw9: '1000000000', // 1 token in 9 decimals
    nonce: Date.now(), // Use timestamp as nonce for example
    tonTxId: 'example-tx-id-' + Date.now(),
  };

  console.log('Payload Data:');
  console.log(`  Origin Chain ID:  ${payloadData.originChainId}`);
  console.log(`  Token:            ${payloadData.token}`);
  console.log(`  Recipient:        ${payloadData.recipient}`);
  console.log(`  Amount (raw9):    ${payloadData.amountRaw9}`);
  console.log(`  Nonce:            ${payloadData.nonce}`);
  console.log(`  TON TX ID:        ${payloadData.tonTxId}\n`);

  // Build canonical payload
  console.log('Building canonical payload...');
  const payload = buildPayload(
    payloadData.originChainId,
    payloadData.token,
    payloadData.recipient,
    payloadData.amountRaw9,
    payloadData.nonce,
    tokenDecimals
  );

  console.log(`  Scaled Amount:    ${payload.amount}\n`);

  // Build domain
  const domain = buildDomain(chainId, multisigAddress);

  // Sign payload
  console.log('Signing payload...');
  const signature = await signPayload(wallet, payload, domain);
  console.log(`  Signature:        ${signature}\n`);

  // Submit to aggregator
  console.log('Submitting to aggregator...');

  const response = await fetch(`${aggregatorUrl}/payloads`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      originChainId: payloadData.originChainId,
      token: payloadData.token,
      recipient: payloadData.recipient,
      amountRaw9: payloadData.amountRaw9,
      nonce: payloadData.nonce,
      watcher: wallet.address,
      signature,
      tonTxId: payloadData.tonTxId,
    }),
  });

  if (!response.ok) {
    const error = await response.json();
    console.error('Submission failed:');
    console.error(JSON.stringify(error, null, 2));
    process.exit(1);
  }

  const result = await response.json();

  console.log('Submission successful!\n');
  console.log('Result:');
  console.log(JSON.stringify(result, null, 2));

  console.log('\nPayload Status:');
  console.log(`  Hash:             ${result.payload.hash}`);
  console.log(`  Status:           ${result.payload.status}`);
  console.log(`  Signature Count:  ${result.payload.signatures.length}`);

  if (result.payload.status === 'ready') {
    console.log('\n✓ Quorum reached! Payload will be submitted to Base shortly.');
  } else {
    console.log('\n⏳ Waiting for more signatures...');
  }
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error('\nError:', err.message);
    process.exit(1);
  });
