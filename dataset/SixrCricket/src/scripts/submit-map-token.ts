/**
 * Submit MAP_TOKEN governance action with CORRECT signatures
 *
 * This script reads TON jetton root and EVM token address from environment variables or CLI args.
 *
 * Required env vars:
 *   - TON_JETTON_ROOT (or TON_MULTISIG_JETTON_ROOT)
 *   - OFT_CONTRACT_ADDRESS (EVM token address, can be overridden by CLI arg)
 *   - TON_MULTISIG_ADDRESS
 *   - TON_GOVERNANCE_KEY_0..3
 *
 * Usage:
 *   # Use env var OFT_CONTRACT_ADDRESS
 *   DOTENV_CONFIG_PATH=runs/1-bridge-base-to-ton/.env npx ts-node scripts/submit-map-token.ts
 *
 *   # Override with CLI argument (BSC example)
 *   DOTENV_CONFIG_PATH=runs/2-bridge-bsc-to-ton/.env npx ts-node scripts/submit-map-token.ts 0x8b1502290C5db3A3995558484DEF2E36Fb081732
 */

import 'dotenv/config';
import { TonClient, WalletContractV5R1, internal, SendMode, Address, toNano } from '@ton/ton';
import { mnemonicToPrivateKey } from '@ton/crypto';
import { hashGovernanceAction, buildMapTokenPayload, buildExecuteGovernanceMessage, GovernanceActionType } from '../apps/shared/ton-multisig/payload';
import { signPayload } from '../apps/shared/ton-multisig/signatures';
import { keypairFromSecretKeyHex } from '../apps/shared/ton-multisig/signatures';
import { createBridgeMultisig } from '../apps/shared/ton-multisig/contract';

/**
 * Get TON jetton root address from environment
 * Checks TON_JETTON_ROOT first, then falls back to TON_MULTISIG_JETTON_ROOT
 */
function getEnvJettonRoot(): string {
  const jettonRoot = process.env.TON_JETTON_ROOT ?? process.env.TON_MULTISIG_JETTON_ROOT;

  if (!jettonRoot) {
    throw new Error(
      'TON_JETTON_ROOT not set in environment.\n' +
      'Please set TON_JETTON_ROOT or TON_MULTISIG_JETTON_ROOT in your .env file.'
    );
  }

  // Validate address format
  try {
    Address.parse(jettonRoot);
  } catch (e) {
    throw new Error(
      `Invalid TON jetton root address: ${jettonRoot}\n` +
      'Address must be a valid TON address (e.g., EQxxx...)'
    );
  }

  return jettonRoot;
}

/**
 * Get EVM token address from CLI argument or environment
 */
function getEvmToken(): string {
  // CLI argument takes precedence
  const cliToken = process.argv[2];
  const evmToken = cliToken || process.env.OFT_CONTRACT_ADDRESS || process.env.OFT_CONTRACT_ADDRESS_BSC;

  if (!evmToken) {
    throw new Error(
      'EVM token address not provided.\n' +
      'Usage:\n' +
      '  1. Pass as CLI argument: npx ts-node script.ts 0x...\n' +
      '  2. Set OFT_CONTRACT_ADDRESS in .env\n' +
      '  3. Set OFT_CONTRACT_ADDRESS_BSC in .env'
    );
  }

  // Validate EVM address format (0x + 40 hex chars)
  const cleaned = evmToken.toLowerCase().startsWith('0x') ? evmToken.slice(2) : evmToken;
  if (cleaned.length !== 40 || !/^[0-9a-f]+$/i.test(cleaned)) {
    throw new Error(
      `Invalid EVM token address: ${evmToken}\n` +
      'Address must be a valid EVM address (0x + 40 hex characters)'
    );
  }

  return evmToken;
}

async function main() {
  console.log('=== SUBMITTING MAP_TOKEN WITH CORRECT SIGNATURES ===\n');

  // Get configuration from environment or CLI args
  const multisigAddr = process.env.TON_MULTISIG_ADDRESS;
  if (!multisigAddr) {
    throw new Error('TON_MULTISIG_ADDRESS not set in environment');
  }

  const evmToken = getEvmToken(); // Now supports CLI arg or env
  const tonJettonRoot = getEnvJettonRoot();

  console.log('Configuration:');
  console.log(`  EVM Token (OFT_CONTRACT_ADDRESS): ${evmToken}`);
  console.log(`  TON Jetton Root (TON_JETTON_ROOT): ${tonJettonRoot}`);
  console.log(`  Multisig Address: ${multisigAddr}`);
  console.log('');

  // Connect to contract to get current governance nonce
  const endpointBase = process.env.TON_MULTISIG_SUBMITTER_TONCENTER_BASE || process.env.TONCENTER_BASE || 'https://toncenter.com/api/v2';
  const endpoint = endpointBase.endsWith('/jsonRPC') ? endpointBase : `${endpointBase.replace(/\/?$/, '')}/jsonRPC`;
  const apiKey = process.env.TON_MULTISIG_SUBMITTER_TONCENTER_API_KEY || process.env.TONCENTER_API_KEY;
  const client = new TonClient({ endpoint, apiKey });

  const contract = createBridgeMultisig({
    contractAddress: multisigAddr,
    chain: 'mainnet',
  });

  const provider = client.provider(contract.address);
  const currentGovernanceNonce = await contract.getGovernanceNonce(provider);
  const currentGovernanceEpoch = await contract.getGovernanceEpoch(provider);

  console.log(`Current governance_nonce: ${currentGovernanceNonce.toString()}`);
  console.log(`Current governance_epoch: ${currentGovernanceEpoch.toString()}`);
  console.log(`Next governance_nonce: ${(currentGovernanceNonce + 1n).toString()}\n`);

  // Build MAP_TOKEN payload
  const mapTokenPayload = buildMapTokenPayload({
    evmToken,
    tonJettonRoot,
  });

  const action = {
    actionType: GovernanceActionType.MAP_TOKEN,
    nonce: currentGovernanceNonce + 1n,
    epoch: currentGovernanceEpoch,
    payload: mapTokenPayload,
  };

  // Compute CORRECT hash
  const hash = hashGovernanceAction(action);
  console.log('Governance action hash:');
  console.log('  0x' + hash.toString('hex'));
  console.log('');
  console.log(`Mapping token: ${evmToken} -> ${tonJettonRoot}`);
  console.log('');

  // Load governance keys from environment
  console.log('Loading governance keys...');

  if (!process.env.TON_GOVERNANCE_KEY_0) throw new Error('TON_GOVERNANCE_KEY_0 not set');
  if (!process.env.TON_GOVERNANCE_KEY_1) throw new Error('TON_GOVERNANCE_KEY_1 not set');
  if (!process.env.TON_GOVERNANCE_KEY_2) throw new Error('TON_GOVERNANCE_KEY_2 not set');
  if (!process.env.TON_GOVERNANCE_KEY_3) throw new Error('TON_GOVERNANCE_KEY_3 not set');

  const gov0 = keypairFromSecretKeyHex(process.env.TON_GOVERNANCE_KEY_0);
  const gov1 = keypairFromSecretKeyHex(process.env.TON_GOVERNANCE_KEY_1);
  const gov2 = keypairFromSecretKeyHex(process.env.TON_GOVERNANCE_KEY_2);
  const gov3 = keypairFromSecretKeyHex(process.env.TON_GOVERNANCE_KEY_3);

  console.log('Generating signatures...');

  const sig0 = signPayload(hash, gov0);
  const sig1 = signPayload(hash, gov1);
  const sig2 = signPayload(hash, gov2);
  const sig3 = signPayload(hash, gov3);

  console.log('✅ Generated 4 signatures');
  console.log('  Gov 0:', '0x' + sig0.publicKey.toString('hex').slice(0, 16) + '...');
  console.log('  Gov 1:', '0x' + sig1.publicKey.toString('hex').slice(0, 16) + '...');
  console.log('  Gov 2:', '0x' + sig2.publicKey.toString('hex').slice(0, 16) + '...');
  console.log('  Gov 3:', '0x' + sig3.publicKey.toString('hex').slice(0, 16) + '...');
  console.log('');

  // Build message
  const message = buildExecuteGovernanceMessage(action, [sig0, sig1, sig2, sig3]);

  // Load wallet
  const mnemonic = process.env.TON_MULTISIG_SUBMITTER_MNEMONIC || process.env.TON_MNEMONIC;
  if (!mnemonic) throw new Error('Mnemonic not set (TON_MULTISIG_SUBMITTER_MNEMONIC or TON_MNEMONIC)');

  const keyPair = await mnemonicToPrivateKey(mnemonic.split(' '));
  const wallet = WalletContractV5R1.create({
    workchain: 0,
    publicKey: keyPair.publicKey,
  });
  const openedWallet = client.open(wallet);

  console.log('Submitting to contract...');
  console.log('Wallet:', wallet.address.toString());
  console.log('');

  const valueTon = process.env.TON_GOVERNANCE_CALL_VALUE || '0.05';

  try {
    await openedWallet.sendTransfer({
      seqno: await openedWallet.getSeqno(),
      secretKey: keyPair.secretKey,
      sendMode: SendMode.PAY_GAS_SEPARATELY,
      messages: [
        internal({
          to: Address.parse(multisigAddr),
          value: toNano(valueTon),
          body: message,
        }),
      ],
    });

    console.log('✅ Transaction sent successfully!');
    console.log('');
    console.log('Check Tonviewer for confirmation:');
    console.log(`  https://tonviewer.com/${multisigAddr}`);
    console.log('');
    console.log('Verify that exit code is 0 (success).');
    console.log(`After confirmation, the mapping ${evmToken} -> ${tonJettonRoot} is active.`);
  } catch (e: any) {
    console.error('❌ Failed to send transaction:', e.message);
    process.exit(1);
  }
}

main().catch((err) => {
  console.error('Script failed:', err);
  process.exit(1);
});
