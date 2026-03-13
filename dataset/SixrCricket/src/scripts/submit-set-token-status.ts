/**
 * Submit SET_TOKEN_STATUS governance action
 *
 * This script submits a governance action to whitelist/blacklist a jetton
 * in the multisig contract. Required after every contract redeployment.
 *
 * Usage:
 *   DOTENV_CONFIG_PATH=runs/bridge-base-to-ton/.env npx ts-node scripts/submit-set-token-status.ts <jetton_root> <status>
 *
 * Example:
 *   DOTENV_CONFIG_PATH=runs/bridge-base-to-ton/.env npx ts-node scripts/submit-set-token-status.ts EQD63rjusgzC91ugSr_cTZN3gYWbXj5u1jGXKXmxvOVMXyy0 1
 *
 * Arguments:
 *   jetton_root - TON jetton root address
 *   status      - 1 to whitelist (allow), 0 to blacklist (disallow)
 */

import 'dotenv/config';
import { TonClient, WalletContractV5R1, internal, SendMode, Address, toNano } from '@ton/ton';
import { mnemonicToPrivateKey } from '@ton/crypto';
import { hashGovernanceAction, buildSetTokenStatusPayload, buildExecuteGovernanceMessage, GovernanceActionType } from '../apps/shared/ton-multisig/payload';
import { signPayload } from '../apps/shared/ton-multisig/signatures';
import { keypairFromSecretKeyHex } from '../apps/shared/ton-multisig/signatures';
import { createBridgeMultisig } from '../apps/shared/ton-multisig/contract';

async function main() {
  console.log('=== SET TOKEN STATUS GOVERNANCE ACTION ===\n');

  // Parse arguments
  const jettonRootArg = process.argv[2];
  const statusArg = process.argv[3];

  if (!jettonRootArg || !statusArg) {
    console.error('Error: Missing arguments');
    console.error('Usage: npx ts-node scripts/submit-set-token-status.ts <jetton_root> <status>');
    console.error('Example: npx ts-node scripts/submit-set-token-status.ts EQD63rjusgzC91ugSr_cTZN3gYWbXj5u1jGXKXmxvOVMXyy0 1');
    console.error('');
    console.error('Arguments:');
    console.error('  jetton_root - TON jetton root address');
    console.error('  status      - 1 to whitelist (allow), 0 to blacklist (disallow)');
    process.exit(1);
  }

  // Validate jetton_root address
  let jettonAddress: Address;
  try {
    jettonAddress = Address.parse(jettonRootArg);
  } catch (e) {
    console.error('❌ Invalid jetton_root address:', jettonRootArg);
    process.exit(1);
  }

  // Validate status
  const statusInt = parseInt(statusArg);
  if (statusInt !== 0 && statusInt !== 1) {
    console.error('❌ Invalid status. Must be 0 or 1');
    process.exit(1);
  }

  const status = statusInt === 1;

  console.log(`Jetton root: ${jettonAddress.toString()}`);
  console.log(`Status: ${status ? 'ALLOWED (1)' : 'NOT ALLOWED (0)'}\n`);

  // Get current nonce from contract
  const multisigAddr = process.env.TON_MULTISIG_ADDRESS;
  if (!multisigAddr) {
    throw new Error('TON_MULTISIG_ADDRESS not set in environment');
  }

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

  // Build SET_TOKEN_STATUS payload
  const setTokenStatusPayload = buildSetTokenStatusPayload({
    jettonRoot: jettonAddress.toString(),
    status,
  });

  const action = {
    actionType: GovernanceActionType.SET_TOKEN_STATUS,
    nonce: currentGovernanceNonce + 1n,
    epoch: currentGovernanceEpoch,
    payload: setTokenStatusPayload,
  };

  // Compute hash
  const hash = hashGovernanceAction(action);
  console.log('Governance action hash:');
  console.log('  0x' + hash.toString('hex'));
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
  console.log('Multisig:', multisigAddr);
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
    console.log('After confirmation, the jetton should be ' + (status ? 'ALLOWED' : 'NOT ALLOWED'));
  } catch (e: any) {
    console.error('❌ Failed to send transaction:', e.message);
    process.exit(1);
  }
}

main().catch((err) => {
  console.error('Script failed:', err);
  process.exit(1);
});
