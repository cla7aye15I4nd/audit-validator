import 'dotenv/config';
import { TonClient, WalletContractV5R1, Address, toNano, beginCell, Dictionary } from '@ton/ton';
import { mnemonicToPrivateKey, sha256_sync } from '@ton/crypto';
import { JettonMinter } from '@ton-community/assets-sdk';

/**
 * Deploy a new jetton with ON-CHAIN metadata (like minter.ton.org)
 * Metadata is stored directly on blockchain, not via external URL
 * 
 * Example:
 * DOTENV_CONFIG_PATH=runs/1-bridge-base-to-ton/.env \
 * npx ts-node scripts/deploy-jetton-onchain-metadata.ts \
 * EQAAGb1X1GBu47ZovfzVJih_a_8gkvfQoiU63dbjlRpAh2fm
 * 
 */
async function main() {
  const mnemonic = process.env.TON_MNEMONIC;
  const multisigAddress = process.argv[2] || 'EQAtNKcm7A91RosL6EJ0hiiwnDB7xH-OQQEEsGNHuum3m0-N';

  if (!mnemonic) {
    console.error('TON_MNEMONIC not found in .env');
    process.exit(1);
  }

  const kp = await mnemonicToPrivateKey(mnemonic.split(' '));
  const deployerWallet = WalletContractV5R1.create({ workchain: 0, publicKey: kp.publicKey });

  const endpointBase = process.env.TONCENTER_BASE || 'https://toncenter.com/api/v2';
  const endpoint = endpointBase.endsWith('/jsonRPC')
    ? endpointBase
    : `${endpointBase}/jsonRPC`;

  const client = new TonClient({ endpoint, apiKey: process.env.TONCENTER_API_KEY });
  const opened = client.open(deployerWallet);

  console.log('Deployer wallet:', deployerWallet.address.toString());
  console.log('Multisig address (will be jetton admin):', multisigAddress);

  // Create ON-CHAIN metadata (stored directly in contract)
  const metadata = {
    name: 'SIXR Test Token',
    description: 'Test token for SIXR cross-chain bridge',
    symbol: 'SIXRTEST',
    decimals: '9',
    image: 'https://ton.org/download/ton_symbol.png',
  };

  console.log('\nJetton Metadata (on-chain):');
  console.log(JSON.stringify(metadata, null, 2));

  // Build on-chain content cell (TEP-64 standard)
  const contentDict = Dictionary.empty(Dictionary.Keys.Buffer(32), Dictionary.Values.Cell());

  // Helper to create metadata entry
  const makeSnakeCell = (data: string): any => {
    const bytes = Buffer.from(data, 'utf-8');
    return beginCell()
      .storeUint(0, 8) // snake format prefix
      .storeBuffer(bytes)
      .endCell();
  };

  // Add metadata entries
  contentDict.set(sha256_sync('name'), makeSnakeCell(metadata.name));
  contentDict.set(sha256_sync('description'), makeSnakeCell(metadata.description));
  contentDict.set(sha256_sync('symbol'), makeSnakeCell(metadata.symbol));
  contentDict.set(sha256_sync('decimals'), makeSnakeCell(metadata.decimals));
  contentDict.set(sha256_sync('image'), makeSnakeCell(metadata.image));

  const jettonContent = beginCell()
    .storeUint(0x00, 8) // IMPORTANT: Use 0x00 (off-chain marker) even for dictionary metadata!
    .storeDict(contentDict)
    .endCell();

  // Create JettonMinter with multisig as admin
  const jettonMinter = client.open(
    JettonMinter.createFromConfig({
      admin: Address.parse(multisigAddress),
      content: jettonContent,
    })
  );

  console.log('\nNew Jetton Root Address:', jettonMinter.address.toString());
  console.log('Jetton Admin (Multisig):', multisigAddress);

  // Deploy the jetton minter
  console.log('\nDeploying jetton minter with on-chain metadata...');

  await jettonMinter.sendDeploy(opened.sender(kp.secretKey), toNano('0.5'));

  console.log('✅ Jetton deployment transaction sent!');
  console.log('\nWait ~30 seconds, then verify:');
  console.log(`  https://tonviewer.com/${jettonMinter.address.toString()}`);
  console.log(`  https://tonscan.org/jetton/${jettonMinter.address.toString()}`);
  console.log('\nUpdate your .env with:');
  console.log(`  TON_JETTON_ROOT=${jettonMinter.address.toString()}`);
}

main().catch((err) => {
  console.error('Error:', err);
  process.exit(1);
});
