import 'dotenv/config';
import {
  buildExecuteGovernanceMessage,
  buildTransferTokenOwnerPayload,
  GovernanceActionType,
  hashGovernanceAction,
} from '../apps/shared/ton-multisig/payload';
import { keypairFromSecretKeyHex, signPayload } from '../apps/shared/ton-multisig/signatures';
import { TonClient, WalletContractV5R1, internal, SendMode, Address, toNano } from '@ton/ton';
import { createBridgeMultisig } from '../apps/shared/ton-multisig/contract';
import { mnemonicToPrivateKey } from '@ton/crypto';

async function main() {
  // Read from environment variables
  const oldMultisigAddr = process.env.OLD_TON_MULTISIG_ADDRESS;
  const newMultisigAddr = process.env.TON_MULTISIG_ADDRESS;
  const jettonRoot = process.env.TON_MULTISIG_JETTON_ROOT;

  if (!oldMultisigAddr) {
    throw new Error('OLD_TON_MULTISIG_ADDRESS not set in .env');
  }
  if (!newMultisigAddr) {
    throw new Error('TON_MULTISIG_ADDRESS not set in .env');
  }
  if (!jettonRoot) {
    throw new Error('TON_MULTISIG_JETTON_ROOT not set in .env');
  }

  console.log('═══════════════════════════════════════════════════════════');
  console.log('  TON Bridge - Transfer Jetton Ownership');
  console.log('═══════════════════════════════════════════════════════════\n');
  console.log('Configuration:');
  console.log('  Old Multisig (Current Owner):', oldMultisigAddr);
  console.log('  New Multisig (New Owner):     ', newMultisigAddr);
  console.log('  Jetton Root:                  ', jettonRoot);
  console.log();

  const endpointBase =
    process.env.TON_MULTISIG_SUBMITTER_TONCENTER_BASE ||
    process.env.TONCENTER_BASE ||
    'https://toncenter.com/api/v2';
  const endpoint = endpointBase.endsWith('/jsonRPC')
    ? endpointBase
    : `${endpointBase.replace(/\/?$/, '')}/jsonRPC`;
  const apiKey =
    process.env.TON_MULTISIG_SUBMITTER_TONCENTER_API_KEY ||
    process.env.TONCENTER_API_KEY;

  const client = new TonClient({ endpoint, apiKey });
  const contract = createBridgeMultisig({
    contractAddress: oldMultisigAddr,
    chain: (process.env.TON_CHAIN as 'mainnet' | 'testnet') || 'mainnet',
  });
  const provider = client.provider(contract.address);

  const currentNonce = await contract.getGovernanceNonce(provider);
  const currentEpoch = await contract.getGovernanceEpoch(provider);
  console.log(`Current governance_nonce: ${currentNonce.toString()}`);
  console.log(`Current governance_epoch: ${currentEpoch.toString()}`);

  const payload = buildTransferTokenOwnerPayload({
    jettonRoot,
    newOwner: newMultisigAddr,
  });

  const action = {
    actionType: GovernanceActionType.TRANSFER_TOKEN_OWNER,
    nonce: currentNonce + 1n,
    epoch: currentEpoch,
    payload,
  };

  const hash = hashGovernanceAction(action);
  console.log(`Action hash: 0x${hash.toString('hex')}`);

  const keys = [
    process.env.TON_GOVERNANCE_KEY_0,
    process.env.TON_GOVERNANCE_KEY_1,
    process.env.TON_GOVERNANCE_KEY_2,
    process.env.TON_GOVERNANCE_KEY_3,
  ];
  if (keys.some((k) => !k)) {
    throw new Error('TON_GOVERNANCE_KEY_0-3 must be set');
  }

  const signatures = keys.map((hex, idx) => {
    const kp = keypairFromSecretKeyHex(hex!);
    const sig = signPayload(hash, kp);
    console.log(`Governance ${idx} signed (pubkey ${sig.publicKey.toString('hex').slice(0, 16)}…)`);
    return sig;
  });

  const message = buildExecuteGovernanceMessage(action, signatures);

  const mnemonic = process.env.TON_MULTISIG_SUBMITTER_MNEMONIC || process.env.TON_MNEMONIC;
  if (!mnemonic) throw new Error('Submitter mnemonic not set');

  const keyPair = await mnemonicToPrivateKey(mnemonic.split(' '));
  const wallet = WalletContractV5R1.create({ workchain: 0, publicKey: keyPair.publicKey });
  const opened = client.open(wallet);

  console.log('Submitting transfer_token_owner governance action…');
  await opened.sendTransfer({
    seqno: await opened.getSeqno(),
    secretKey: keyPair.secretKey,
    sendMode: SendMode.PAY_GAS_SEPARATELY,
    messages: [
      internal({
        to: Address.parse(oldMultisigAddr),
        value: toNano('0.02'),
        body: message,
      }),
    ],
  });

  console.log('✅ Transaction sent. Check Tonviewer for confirmation.');
}

main().catch((err) => {
  console.error('Error:', err);
  process.exit(1);
});
