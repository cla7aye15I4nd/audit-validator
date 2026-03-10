/**
 * Emergency withdrawal tool for TON Bridge multisig
 *
 * Usage:
 *   DOTENV_CONFIG_PATH=... \
 *     npx ts-node scripts/withdraw-with-3-keys.ts \
 *       <multisig_address> <destination_address> <amount_ton> [reference_id]
 * 
 * Example:
 *   DOTENV_CONFIG_PATH=runs/1-bridge-base-to-ton/.env npx ts-node scripts/withdraw-with-3-keys.ts EQD9yULWoMag9RzXyoyQRhdmsYy5TiZ-DegPca3i-XzRna9v UQBrWmXcEKUi1oTVDMGNukS2W0CHCfGhKZpaCVYF7_nCD-2a 0.52 1728585909
 *
 * Arguments are optional if environment variables are provided:
 *   WITHDRAW_MULTISIG_ADDRESS   (defaults to TON_MULTISIG_ADDRESS)
 *   WITHDRAW_DESTINATION        (fallback to DEST argument)
 *   WITHDRAW_AMOUNT_TON         (fallback to AMOUNT argument)
 *   WITHDRAW_REFERENCE_ID       (fallback to generated reference)
 *   WITHDRAW_GOV_KEY_INDEXES    (comma-separated governance key indices, default: 0,1,2)
 *   WITHDRAW_GAS_TON            (default: 0.03 TON)
 *
 * Requires at least 3 governance private keys in env:
 *   TON_GOVERNANCE_KEY_0 ... TON_GOVERNANCE_KEY_4
 */

import 'dotenv/config';
import { Address, toNano, internal, SendMode } from '@ton/core';
import { TonClient, WalletContractV5R1 } from '@ton/ton';
import { mnemonicToPrivateKey } from '@ton/crypto';
import {
  buildWithdrawMessage,
  generateReference,
  getWithdrawPayloadHash,
  signWithdrawPayload,
  WithdrawTonFundsParams,
  GovernanceSignature,
  Constants,
} from '../contracts/ton/helpers/withdraw-ton-funds';
import { keypairFromSecretKeyHex } from '../apps/shared/ton-multisig/signatures';

const args = process.argv.slice(2);

function readArgOrEnv(
  argIndex: number,
  envKeys: string[],
  description: string
): string {
  if (args[argIndex]) {
    return args[argIndex];
  }
  for (const key of envKeys) {
    const value = process.env[key];
    if (value && value.trim().length > 0) {
      return value.trim();
    }
  }
  throw new Error(`Missing ${description}. Provide argument or set one of: ${envKeys.join(', ')}`);
}

async function main() {
  const multisigAddressRaw = readArgOrEnv(0, ['WITHDRAW_MULTISIG_ADDRESS', 'TON_MULTISIG_ADDRESS'], 'multisig address');
  const destinationRaw = readArgOrEnv(1, ['WITHDRAW_DESTINATION'], 'destination address');
  const amountTonStr = readArgOrEnv(2, ['WITHDRAW_AMOUNT_TON'], 'amount (TON)');

  const referenceInput = args[3] ?? process.env.WITHDRAW_REFERENCE_ID;
  const reference = referenceInput ? BigInt(referenceInput) : generateReference();

  const amountNano = toNano(amountTonStr);
  const multisigAddress = Address.parse(multisigAddressRaw);
  const destinationAddress = Address.parse(destinationRaw);

  const keyIndexString = process.env.WITHDRAW_GOV_KEY_INDEXES ?? '0,1,2';
  const keyIndices = keyIndexString
    .split(',')
    .map((v) => parseInt(v.trim(), 10))
    .filter((idx) => !Number.isNaN(idx));

  if (keyIndices.length < Constants.GOVERNANCE_THRESHOLD_RELAXED) {
    throw new Error(
      `WITHDRAW_GOV_KEY_INDEXES must provide at least ${Constants.GOVERNANCE_THRESHOLD_RELAXED} indices`
    );
  }

  const governanceKeypairs = keyIndices.map((idx) => {
    const envKey = `TON_GOVERNANCE_KEY_${idx}`;
    const secretHex = process.env[envKey];
    if (!secretHex) {
      throw new Error(`Missing ${envKey} in environment`);
    }
    return keypairFromSecretKeyHex(secretHex);
  });

  const params: WithdrawTonFundsParams = {
    destination: destinationAddress,
    amount: amountNano,
    reference,
  };

  const endpointBase =
    process.env.TON_MULTISIG_SUBMITTER_TONCENTER_BASE ||
    process.env.TONCENTER_BASE ||
    'https://toncenter.com/api/v2';
  const endpoint = endpointBase.endsWith('/jsonRPC')
    ? endpointBase
    : `${endpointBase.replace(/\/?$/, '')}/jsonRPC`;
  const apiKey =
    process.env.TON_MULTISIG_SUBMITTER_TONCENTER_API_KEY || process.env.TONCENTER_API_KEY;

  const client = new TonClient({ endpoint, apiKey });

  const state = await client.getContractState(multisigAddress);
  const balanceNano = state.balance ?? 0n;

  console.log('═══════════════════════════════════════');
  console.log('💰 TON Multisig Emergency Withdrawal');
  console.log('═══════════════════════════════════════');
  console.log(`Multisig:      ${multisigAddress.toString()}`);
  console.log(`Destination:   ${destinationAddress.toString()}`);
  console.log(`Amount (TON):  ${amountTonStr}`);
  console.log(`Reference ID:  ${reference.toString()}`);
  console.log(`Balance (TON): ${(Number(balanceNano) / 1e9).toFixed(4)}`);
  console.log('');

  if (balanceNano <= amountNano) {
    console.warn(
      `⚠️  Warning: requested amount (${amountTonStr} TON) is greater than or equal to contract balance ${(Number(
        balanceNano
      ) / 1e9).toFixed(4)} TON. The on-chain contract may still reject the withdrawal if INTERNAL reserve checks fail.`
    );
  }

  const payloadHash = getWithdrawPayloadHash(params);
  console.log('Payload hash:  0x' + payloadHash.toString('hex'));

  const governanceSignatures: GovernanceSignature[] = [];
  for (const kp of governanceKeypairs) {
    const signature = await signWithdrawPayload(params, kp.secretKey);
    governanceSignatures.push({
      publicKey: kp.publicKey,
      signature,
    });
    console.log(`  ✓ Signed with gov key ${kp.publicKey.toString('hex').slice(0, 16)}…`);
  }

  const messageBody = buildWithdrawMessage(params, governanceSignatures);

  const mnemonicSource =
    process.env.TON_MULTISIG_SUBMITTER_MNEMONIC || process.env.TON_MNEMONIC;
  if (!mnemonicSource) {
    throw new Error('TON_MULTISIG_SUBMITTER_MNEMONIC (or TON_MNEMONIC) is required to send tx');
  }
  const mnemonic = mnemonicSource.replace(/"/g, '').trim().split(/\s+/);
  const submitterKeys = await mnemonicToPrivateKey(mnemonic);

  const submitterWallet = WalletContractV5R1.create({
    workchain: 0,
    publicKey: Buffer.from(submitterKeys.publicKey as any),
  });

  const openedWallet = client.open(submitterWallet);
  const seqno = await openedWallet.getSeqno();

  const gasValue = process.env.WITHDRAW_GAS_TON ?? '0.015';

  console.log('');
  console.log('📤 Sending withdrawal transaction…');
  console.log(`  Submitter wallet: ${submitterWallet.address.toString()}`);
  console.log(`  Seqno:            ${seqno}`);
  console.log(`  Gas (TON):        ${gasValue}`);

  await openedWallet.sendTransfer({
    seqno,
    secretKey: Buffer.from(submitterKeys.secretKey as any),
    sendMode: SendMode.PAY_GAS_SEPARATELY + SendMode.IGNORE_ERRORS,
    messages: [
      internal({
        to: multisigAddress,
        value: toNano(gasValue),
        body: messageBody,
      }),
    ],
  });

  console.log('  ✓ Transaction submitted!');
  console.log('');
  console.log('Next steps:');
  console.log('  • Wait for inclusion on Tonviewer: https://tonviewer.com/' + multisigAddressRaw);
  console.log('  • Confirm destination wallet balance: https://tonviewer.com/' + destinationRaw);
  console.log('  • Reference ID helps avoid replay; do not reuse it.');
  console.log('');
  console.log('═══════════════════════════════════════');
}

main().catch((error) => {
  console.error('\n❌ Error:', error.message);
  if (error.stack) {
    console.error('\nStack trace:');
    console.error(error.stack);
  }
  process.exit(1);
});
