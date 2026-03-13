/**
 * Mint jettons on TON via bridge multisig
 *
 * Usage:
 *   MINT_TO=UQAJxIRZIiqzd80MkMgA-PVlsy_bm0BhI8OoluoyL-12ErlP MINT_AMOUNT=100 npx ts-node scripts/ton/mint.ts
 *
 * Environment variables (from .env):
 *   TON_MULTISIG_ADDRESS - Bridge multisig address
 *   JETTON_ROOT_ADDRESS  - Jetton root address
 *   TON_GOVERNANCE_KEY_* - Governance keys (need 3 of 5)
 *   TON_SENDER_MNEMONIC  - Sender wallet mnemonic for gas
 *
 * CLI arguments:
 *   MINT_TO     - Recipient TON address
 *   MINT_AMOUNT - Amount in whole tokens (e.g. 100)
 */

import 'dotenv/config';
import { Address, toNano, internal, TonClient } from '@ton/ton';
import { mnemonicToPrivateKey, sign } from '@ton/crypto';
import { WalletContractV4 } from '@ton/ton';
import {
  TonMintPayload,
  TonSignature,
  hashMintPayload,
  buildExecuteMintMessage,
  hexToBuffer,
} from '../../apps/shared/ton-multisig/payload';

// Decimals: jetton uses 9 decimals
const DECIMALS = 9;

async function main() {
  console.log('=== TON MINT JETTONS ===\n');

  // Get recipient
  const mintTo = process.env.MINT_TO;
  if (!mintTo) {
    throw new Error('MINT_TO environment variable is required');
  }

  // Get amount
  const amountStr = process.env.MINT_AMOUNT;
  if (!amountStr) {
    throw new Error('MINT_AMOUNT environment variable is required');
  }
  const amountRaw = BigInt(Math.floor(parseFloat(amountStr) * 10 ** DECIMALS));

  // Get multisig address
  const multisigAddress = process.env.TON_MULTISIG_ADDRESS;
  if (!multisigAddress) {
    throw new Error('TON_MULTISIG_ADDRESS environment variable is required');
  }

  // Get EVM token address (for payload - use Base token as default)
  const evmToken = process.env.EVM_TOKEN_ADDRESS || '0x985c9C7eE0288A21254EEd52F11C0ea8AB10b260';
  const originChainId = parseInt(process.env.ORIGIN_CHAIN_ID || '8453'); // Base mainnet

  console.log(`Multisig: ${multisigAddress}`);
  console.log(`Recipient: ${mintTo}`);
  console.log(`Amount: ${amountStr} (${amountRaw} raw)`);
  console.log(`EVM Token: ${evmToken}`);
  console.log(`Origin Chain: ${originChainId}\n`);

  // Load governance keys (full 64-byte format: secret(32) + public(32))
  const watcherKeys: { publicKey: Buffer; secretKey: Buffer }[] = [];

  for (let i = 0; i < 5; i++) {
    const fullKeyHex = process.env[`TON_GOVERNANCE_KEY_${i}`];

    if (fullKeyHex) {
      const fullKey = hexToBuffer(fullKeyHex);
      // Full key is 64 bytes: first 32 = secret seed, last 32 = public key
      const secretKey = fullKey; // sign() expects full 64-byte key
      const publicKey = fullKey.subarray(32, 64);
      watcherKeys.push({
        publicKey,
        secretKey,
      });
      console.log(`Loaded governance key ${i}: ${fullKeyHex.slice(64, 80)}... (pubkey)`);
    }
  }

  if (watcherKeys.length < 3) {
    throw new Error(`Need at least 3 watcher keys, found ${watcherKeys.length}`);
  }

  // Get mint nonce from env or use timestamp
  const mintNonce = process.env.MINT_NONCE
    ? BigInt(process.env.MINT_NONCE)
    : BigInt(Math.floor(Date.now() / 1000));

  console.log(`\nUsing mint nonce: ${mintNonce}`);

  // Build payload
  const payload: TonMintPayload = {
    originChainId,
    token: evmToken,
    tonRecipient: mintTo,
    amount: amountRaw,
    nonce: mintNonce,
  };

  // Hash payload
  const payloadHash = hashMintPayload(payload);
  console.log(`Payload hash: 0x${payloadHash.toString('hex')}`);

  // Sign with 3 watchers
  const signatures: TonSignature[] = [];
  for (let i = 0; i < 3; i++) {
    const watcher = watcherKeys[i];
    const signature = sign(payloadHash, watcher.secretKey);
    signatures.push({
      publicKey: watcher.publicKey,
      signature,
    });
    console.log(`Signed by watcher ${i}`);
  }

  // Build message
  const messageBody = buildExecuteMintMessage(payload, signatures);
  console.log(`\nMessage built successfully`);

  // Connect to TON
  const toncenterBase = process.env.TON_MULTISIG_SUBMITTER_TONCENTER_BASE || process.env.TONCENTER_BASE || 'https://toncenter.com/api/v2';
  const endpoint = `${toncenterBase}/jsonRPC`;
  const apiKey = process.env.TON_MULTISIG_SUBMITTER_TONCENTER_API_KEY || process.env.TONCENTER_API_KEY;

  const client = new TonClient({
    endpoint,
    apiKey,
  });

  // Load sender wallet (use multisig submitter mnemonic or TON_MNEMONIC)
  const mnemonic = process.env.TON_MULTISIG_SUBMITTER_MNEMONIC || process.env.TON_MNEMONIC;
  if (!mnemonic) {
    throw new Error('TON_MULTISIG_SUBMITTER_MNEMONIC or TON_MNEMONIC required for gas');
  }

  const keyPair = await mnemonicToPrivateKey(mnemonic.split(' '));
  const wallet = WalletContractV4.create({
    workchain: 0,
    publicKey: keyPair.publicKey,
  });

  const walletContract = client.open(wallet);
  const senderAddress = wallet.address.toString();
  console.log(`\nSender wallet: ${senderAddress}`);

  // Check balance
  const balance = await walletContract.getBalance();
  console.log(`Sender balance: ${Number(balance) / 1e9} TON`);

  if (balance < toNano('0.1')) {
    throw new Error('Insufficient balance for gas (need at least 0.1 TON)');
  }

  // Send transaction
  console.log('\nSending transaction...');

  const seqno = await walletContract.getSeqno();

  await walletContract.sendTransfer({
    secretKey: keyPair.secretKey,
    seqno,
    messages: [
      internal({
        to: Address.parse(multisigAddress),
        value: toNano('0.3'), // Gas for mint operation (needs enough for multisig -> jetton root -> jetton wallet)
        body: messageBody,
      }),
    ],
  });

  console.log(`Transaction sent! Seqno: ${seqno}`);
  console.log('\nWaiting for confirmation...');

  // Wait for seqno to increment
  let attempts = 0;
  while (attempts < 30) {
    await new Promise((r) => setTimeout(r, 2000));
    const newSeqno = await walletContract.getSeqno();
    if (newSeqno > seqno) {
      console.log(`\n✅ Transaction confirmed!`);
      break;
    }
    attempts++;
    process.stdout.write('.');
  }

  if (attempts >= 30) {
    console.log('\n⚠️  Transaction may still be pending. Check explorer.');
  }

  console.log(`\nMint of ${amountStr} SIXRTEST to ${mintTo} completed!`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
