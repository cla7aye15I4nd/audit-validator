/**
 * Check if a jetton is allowed/mapped on TON bridge multisig
 *
 * Usage:
 *   JETTON_ADDRESS=EQxxxx npx ts-node scripts/ton/check-token-mapping.ts
 *
 * Environment variables:
 *   TON_MULTISIG_ADDRESS - Bridge multisig address
 *   TONCENTER_BASE       - Toncenter API base URL
 *   TONCENTER_API_KEY    - Toncenter API key
 *
 * CLI arguments:
 *   JETTON_ADDRESS - Jetton root address to check
 */

import 'dotenv/config';
import { Address, TonClient } from '@ton/ton';
import { beginCell } from '@ton/core';

async function main() {
  console.log('=== CHECK TON JETTON MAPPING ===\n');

  // Get multisig address
  const multisigAddress = process.env.TON_MULTISIG_ADDRESS;
  if (!multisigAddress) {
    throw new Error('TON_MULTISIG_ADDRESS environment variable is required');
  }

  // Get jetton address to check
  const jettonAddress = process.env.JETTON_ADDRESS;
  if (!jettonAddress) {
    throw new Error('JETTON_ADDRESS environment variable is required');
  }

  console.log(`Multisig: ${multisigAddress}`);
  console.log(`Jetton:   ${jettonAddress}\n`);

  // Connect to TON
  const toncenterBase = process.env.TONCENTER_BASE || 'https://toncenter.com/api/v2';
  const endpoint = `${toncenterBase}/jsonRPC`;
  const apiKey = process.env.TONCENTER_API_KEY;

  const client = new TonClient({
    endpoint,
    apiKey,
  });

  const multisigAddr = Address.parse(multisigAddress);
  const jettonAddr = Address.parse(jettonAddress);

  // Check if jetton is allowed using is_jetton_allowed_query
  console.log('Checking if jetton is allowed...');

  try {
    const result = await client.runMethod(multisigAddr, 'is_jetton_allowed_query', [
      { type: 'slice', cell: beginCell().storeAddress(jettonAddr).endCell() },
    ]);

    const isAllowed = result.stack.readNumber();

    if (isAllowed === -1) {
      console.log(`\n✅ Jetton IS ALLOWED (mapped)`);
    } else {
      console.log(`\n❌ Jetton IS NOT ALLOWED (not mapped)`);
      console.log(`   Result: ${isAllowed}`);
      console.log(`\n   To map this token, use scripts/submit-map-token.ts`);
    }
  } catch (error) {
    console.error(`\n❌ Error checking jetton status:`, error);
  }

  // Also show other useful multisig info
  console.log('\n--- Multisig State ---');

  try {
    const mintNonce = await client.runMethod(multisigAddr, 'get_mint_nonce');
    console.log(`Mint Nonce: ${mintNonce.stack.readNumber()}`);
  } catch (e) {
    console.log(`Mint Nonce: Error reading`);
  }

  try {
    const govNonce = await client.runMethod(multisigAddr, 'get_governance_nonce');
    console.log(`Governance Nonce: ${govNonce.stack.readNumber()}`);
  } catch (e) {
    console.log(`Governance Nonce: Error reading`);
  }

  try {
    const epoch = await client.runMethod(multisigAddr, 'get_governance_epoch');
    console.log(`Governance Epoch: ${epoch.stack.readNumber()}`);
  } catch (e) {
    console.log(`Governance Epoch: Error reading`);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
