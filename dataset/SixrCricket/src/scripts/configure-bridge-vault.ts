/**
 * @file configure-bridge-vault.ts
 * @notice Configuration script for TON Bridge Vault contract
 *
 * This script sends governance messages to the vault contract to configure:
 * - Fee wallet address (OP_SET_FEE_WALLET = 0x46454557)
 * - Allowed jetton address (OP_SET_ALLOWED_JETTON = 0x414c4c57)
 * - Admin address (OP_SET_ADMIN = 0x41444d4e)
 * - Withdraw TON funds (OP_WITHDRAW_TON = 0x57495448)
 *
 * Environment Variables:
 * - TON_CHAIN: mainnet | testnet
 * - TONCENTER_API_KEY: API key for TonCenter
 * - TON_ADMIN_MNEMONIC: Admin wallet mnemonic (must match VAULT_ADMIN_ADDRESS)
 * - TON_DEPLOYER_PUBLIC_KEY_HEX: Alternative to mnemonic (64 hex chars)
 * - TON_DEPLOYER_SECRET_KEY_HEX: Alternative to mnemonic (128 hex chars)
 * - VAULT_CONTRACT_ADDRESS: Deployed vault contract address
 * - VAULT_FEE_WALLET: Wallet to receive 1% fees (optional, if setting fee wallet)
 * - VAULT_ALLOWED_JETTON: Whitelisted jetton root address (optional, if setting allowed jetton)
 * - NEW_ADMIN_ADDRESS: New admin address (optional, if changing admin)
 * - WITHDRAW_DESTINATION: Destination address for TON withdrawal (optional, if withdrawing)
 * - WITHDRAW_AMOUNT: Amount in TON to withdraw (optional, if withdrawing, e.g., "0.5")
 *
 * Usage:
 *   # Set fee wallet
 *   DOTENV_CONFIG_PATH=runs/3-bridge-ton-to-base/.env npx ts-node scripts/configure-bridge-vault.ts --set-fee-wallet
 *
 *   # Set allowed jetton
 *   DOTENV_CONFIG_PATH=runs/3-bridge-ton-to-base/.env npx ts-node scripts/configure-bridge-vault.ts --set-allowed-jetton
 *
 *   # Set both
 *   DOTENV_CONFIG_PATH=runs/3-bridge-ton-to-base/.env npx ts-node scripts/configure-bridge-vault.ts --set-fee-wallet --set-allowed-jetton
 *
 *   # Change admin
 *   DOTENV_CONFIG_PATH=runs/3-bridge-ton-to-base/.env npx ts-node scripts/configure-bridge-vault.ts --set-admin
 *
 *   # Initialize fee wallet jetton wallet (fixes exit 709 bounce on fee transfers)
 *   DOTENV_CONFIG_PATH=runs/3-bridge-ton-to-base/.env npx ts-node scripts/configure-bridge-vault.ts --initialize-fee-wallet
 *
 *   # Withdraw TON
 *   WITHDRAW_DESTINATION=EQxxx... WITHDRAW_AMOUNT=0.5 DOTENV_CONFIG_PATH=runs/3-bridge-ton-to-base/.env npx ts-node scripts/configure-bridge-vault.ts --withdraw-ton
 *
 *   # Query vault state
 *   DOTENV_CONFIG_PATH=runs/3-bridge-ton-to-base/.env npx ts-node scripts/configure-bridge-vault.ts --query
 */

import 'dotenv/config';
import { Address, Cell, beginCell, toNano, internal, SendMode } from '@ton/core';
import { TonClient, WalletContractV5R1 } from '@ton/ton';
import { mnemonicToPrivateKey, KeyPair } from '@ton/crypto';

// Fetch polyfill for Node.js environments
const fetch = (global as any).fetch ?? require('node-fetch');

/**
 * Vault operation codes
 */
const OP_SET_FEE_WALLET = 0x46454557; // "FEEW"
const OP_SET_ADMIN = 0x41444d4e; // "ADMN"
const OP_SET_ALLOWED_JETTON = 0x414c4c57; // "ALLW"
const OP_WITHDRAW_TON = 0x57495448; // "WITH"

/**
 * Configuration for vault operations
 */
interface VaultConfig {
  network: 'mainnet' | 'testnet';
  endpoint: string;
  apiKey?: string;

  // Vault contract
  vaultAddress: string;

  // Admin wallet (must be current admin)
  adminMnemonic?: string;
  adminPublicKeyHex?: string;
  adminSecretKeyHex?: string;

  // Configuration values
  feeWalletAddress?: string;
  allowedJettonAddress?: string;
  newAdminAddress?: string;

  // Withdraw values
  withdrawDestination?: string;
  withdrawAmount?: string;
}

/**
 * Load configuration from environment variables
 */
function loadConfigFromEnv(): VaultConfig {
  const network = (process.env.TON_CHAIN as 'mainnet' | 'testnet') || 'testnet';

  // Determine endpoint
  const endpoint =
    network === 'testnet'
      ? 'https://testnet.toncenter.com/api/v2/jsonRPC'
      : 'https://toncenter.com/api/v2/jsonRPC';

  // Load vault contract address
  const vaultAddress = process.env.VAULT_CONTRACT_ADDRESS || process.env.TON_VAULT_CONTRACT;
  if (!vaultAddress) {
    throw new Error('Missing required environment variable: VAULT_CONTRACT_ADDRESS or TON_VAULT_CONTRACT');
  }

  return {
    network,
    endpoint,
    apiKey: process.env.TONCENTER_API_KEY,
    vaultAddress,
    adminMnemonic: process.env.TON_ADMIN_MNEMONIC,
    adminPublicKeyHex: process.env.TON_DEPLOYER_PUBLIC_KEY_HEX,
    adminSecretKeyHex: process.env.TON_DEPLOYER_SECRET_KEY_HEX,
    feeWalletAddress: process.env.VAULT_FEE_WALLET,
    allowedJettonAddress: process.env.VAULT_ALLOWED_JETTON,
    newAdminAddress: process.env.NEW_ADMIN_ADDRESS,
    withdrawDestination: process.env.WITHDRAW_DESTINATION,
    withdrawAmount: process.env.WITHDRAW_AMOUNT,
  };
}

/**
 * Parse command line arguments
 */
interface CliArgs {
  setFeeWallet: boolean;
  setAllowedJetton: boolean;
  setAdmin: boolean;
  withdrawTon: boolean;
  initializeFeeWallet: boolean;
  queryState: boolean;
}

function parseArgs(): CliArgs {
  const args = process.argv.slice(2);

  return {
    setFeeWallet: args.includes('--set-fee-wallet'),
    setAllowedJetton: args.includes('--set-allowed-jetton'),
    setAdmin: args.includes('--set-admin'),
    withdrawTon: args.includes('--withdraw-ton'),
    initializeFeeWallet: args.includes('--initialize-fee-wallet'),
    queryState: args.includes('--query') || args.includes('--state'),
  };
}

/**
 * Query current vault state
 */
async function queryVaultState(client: TonClient, vaultAddress: Address) {
  console.log('\n========================================');
  console.log('Vault Current State');
  console.log('========================================\n');

  try {
    // Call get methods
    const adminResult = await client.runMethod(vaultAddress, 'get_admin');
    const feeWalletResult = await client.runMethod(vaultAddress, 'get_fee_wallet');
    const allowedJettonResult = await client.runMethod(vaultAddress, 'get_allowed_jetton');
    const totalBurnedResult = await client.runMethod(vaultAddress, 'get_total_burned');
    const totalFeesResult = await client.runMethod(vaultAddress, 'get_total_fees');
    const feeBpsResult = await client.runMethod(vaultAddress, 'get_fee_basis_points');

    // Parse addresses
    const adminSlice = adminResult.stack.readCell().beginParse();
    const feeWalletSlice = feeWalletResult.stack.readCell().beginParse();
    const allowedJettonSlice = allowedJettonResult.stack.readCell().beginParse();

    // Try to parse addresses (may be addr_none)
    let adminAddr = 'Not set (addr_none)';
    let feeWalletAddr = 'Not set (addr_none)';
    let allowedJettonAddr = 'Not set (addr_none)';

    try {
      const admin = adminSlice.loadAddress();
      adminAddr = admin.toString();
    } catch (e) {
      // addr_none
    }

    try {
      const feeWallet = feeWalletSlice.loadAddress();
      feeWalletAddr = feeWallet.toString();
    } catch (e) {
      // addr_none
    }

    try {
      const allowedJetton = allowedJettonSlice.loadAddress();
      allowedJettonAddr = allowedJetton.toString();
    } catch (e) {
      // addr_none
    }

    const totalBurned = totalBurnedResult.stack.readBigNumber();
    const totalFees = totalFeesResult.stack.readBigNumber();
    const feeBps = feeBpsResult.stack.readNumber();

    // Get balance information
    const contractBalanceResult = await client.runMethod(vaultAddress, 'get_contract_balance');
    const availableBalanceResult = await client.runMethod(vaultAddress, 'get_available_balance');
    const minReserveResult = await client.runMethod(vaultAddress, 'get_min_ton_reserve');

    const contractBalance = contractBalanceResult.stack.readBigNumber();
    const availableBalance = availableBalanceResult.stack.readBigNumber();
    const minReserve = minReserveResult.stack.readBigNumber();

    console.log('Admin Address:', adminAddr);
    console.log('Fee Wallet:', feeWalletAddr);
    console.log('Allowed Jetton:', allowedJettonAddr);
    console.log('Total Burned:', totalBurned.toString());
    console.log('Total Fees:', totalFees.toString());
    console.log('Fee Basis Points:', feeBps, `(${feeBps / 100}%)`);
    console.log('\n--- TON Balance ---');
    console.log('Contract Balance:', Number(contractBalance) / 1e9, 'TON');
    console.log('Available Balance:', Number(availableBalance) / 1e9, 'TON (withdrawable)');
    console.log('Minimum Reserve:', Number(minReserve) / 1e9, 'TON');
    console.log('\n========================================\n');
  } catch (error) {
    console.error('Error querying vault state:', error);
    throw error;
  }
}

/**
 * Send governance message to vault
 */
async function sendGovernanceMessage(
  client: TonClient,
  adminWallet: any,
  adminKeyPair: KeyPair,
  vaultAddress: Address,
  op: number,
  addressToSet: Address,
  opName: string
) {
  console.log(`\n📤 Sending ${opName} governance message...`);
  console.log('Vault Address:', vaultAddress.toString());
  console.log('New Address:', addressToSet.toString());

  // Build message body
  const messageBody = beginCell().storeUint(op, 32).storeAddress(addressToSet).endCell();

  // Get current seqno
  const seqno = await adminWallet.getSeqno();
  console.log('Current seqno:', seqno);

  // Send transaction
  await adminWallet.sendTransfer({
    seqno,
    secretKey: adminKeyPair.secretKey,
    messages: [
      internal({
        to: vaultAddress,
        value: toNano('0.05'), // 0.05 TON for gas
        bounce: true,
        body: messageBody,
      }),
    ],
    sendMode: SendMode.PAY_GAS_SEPARATELY + SendMode.IGNORE_ERRORS,
  });

  console.log('✅ Transaction sent!');
  console.log('Waiting for confirmation...');

  // Wait for confirmation (check seqno change)
  let currentSeqno = seqno;
  let attempts = 0;
  while (currentSeqno === seqno && attempts < 30) {
    await new Promise((resolve) => setTimeout(resolve, 2000));
    currentSeqno = await adminWallet.getSeqno();
    attempts++;
  }

  if (currentSeqno === seqno) {
    throw new Error('Transaction timeout - may have failed');
  }

  console.log('✅ Transaction confirmed!');
}

/**
 * Send withdraw TON message to vault
 */
async function sendWithdrawTonMessage(
  client: TonClient,
  adminWallet: any,
  adminKeyPair: KeyPair,
  vaultAddress: Address,
  destination: Address,
  amount: bigint
) {
  console.log('\n📤 Sending WITHDRAW_TON message...');
  console.log('Vault Address:', vaultAddress.toString());
  console.log('Destination:', destination.toString());
  console.log('Amount:', Number(amount) / 1e9, 'TON');

  // Build message body: op (32 bits) + destination (address) + amount (coins)
  const messageBody = beginCell()
    .storeUint(OP_WITHDRAW_TON, 32)
    .storeAddress(destination)
    .storeCoins(amount)
    .endCell();

  // Get current seqno
  const seqno = await adminWallet.getSeqno();
  console.log('Current seqno:', seqno);

  // Send transaction
  await adminWallet.sendTransfer({
    seqno,
    secretKey: adminKeyPair.secretKey,
    messages: [
      internal({
        to: vaultAddress,
        value: toNano('0.1'), // 0.1 TON for gas + withdrawal
        bounce: true,
        body: messageBody,
      }),
    ],
    sendMode: SendMode.PAY_GAS_SEPARATELY + SendMode.IGNORE_ERRORS,
  });

  console.log('✅ Transaction sent!');
  console.log('Waiting for confirmation...');

  // Wait for confirmation (check seqno change)
  let currentSeqno = seqno;
  let attempts = 0;
  while (currentSeqno === seqno && attempts < 30) {
    await new Promise((resolve) => setTimeout(resolve, 2000));
    currentSeqno = await adminWallet.getSeqno();
    attempts++;
  }

  if (currentSeqno === seqno) {
    throw new Error('Transaction timeout - may have failed');
  }

  console.log('✅ Withdrawal transaction confirmed!');
}

/**
 * Fetch jetton wallet address for an owner
 */
async function fetchJettonWallet(
  network: 'mainnet' | 'testnet',
  ownerAddress: string,
  jettonMasterAddress: string
): Promise<string> {
  const TON_BASE = network === 'testnet' ? 'https://testnet.tonapi.io' : 'https://tonapi.io';
  const url = `${TON_BASE}/v2/accounts/${ownerAddress}/jettons`;

  const jettonMasterRaw = Address.parse(jettonMasterAddress).toRawString();

  for (let attempt = 0; attempt < 5; attempt++) {
    try {
      const response = await fetch(url, { headers: { Accept: 'application/json' } });

      if (response.status === 429) {
        const waitMs = 1000 * Math.pow(2, attempt);
        console.log(`  Rate limited (429), waiting ${waitMs}ms before retry ${attempt + 1}/5`);
        await new Promise((resolve) => setTimeout(resolve, waitMs));
        continue;
      }

      if (!response.ok) {
        throw new Error(`TonAPI error: ${response.status} ${response.statusText}`);
      }

      const data = await response.json();
      const balances = data?.balances ?? [];

      const hit = balances.find((x: any) => {
        const a = x?.jetton?.address as string | undefined;
        if (!a) return false;
        try {
          const rawAddr = Address.parse(a).toRawString();
          return rawAddr === jettonMasterRaw;
        } catch {
          return false;
        }
      });

      let walletAddr = hit?.wallet_address || hit?.wallet?.address;

      if (typeof walletAddr === 'object' && walletAddr !== null) {
        walletAddr = (walletAddr as any).address || String(walletAddr);
      }

      if (!walletAddr || typeof walletAddr !== 'string') {
        throw new Error(`Jetton wallet not found for owner ${ownerAddress}`);
      }

      return walletAddr;
    } catch (e: any) {
      if (attempt === 4 || (e.message && !e.message.includes('429'))) {
        throw e;
      }
      console.log(`  Attempt ${attempt + 1}/5 failed: ${e.message}`);
    }
  }

  throw new Error('Failed to fetch jetton wallet after 5 attempts');
}

/**
 * Initialize fee wallet jetton wallet by sending minimal jetton transfer
 */
async function initializeFeeWalletJettonWallet(
  client: TonClient,
  network: 'mainnet' | 'testnet',
  adminWallet: any,
  adminKeyPair: KeyPair,
  adminAddress: Address,
  feeWalletAddress: Address,
  jettonMasterAddress: Address
) {
  console.log('\n📤 Initializing fee wallet jetton wallet...');
  console.log('Admin Address:', adminAddress.toString());
  console.log('Fee Wallet:', feeWalletAddress.toString());
  console.log('Jetton Master:', jettonMasterAddress.toString());

  // Fetch admin's jetton wallet address
  console.log('\n🔍 Fetching admin jetton wallet address...');
  let adminJettonWallet: string;
  try {
    adminJettonWallet = await fetchJettonWallet(
      network,
      adminAddress.toString(),
      jettonMasterAddress.toString()
    );
    console.log('✅ Admin jetton wallet:', adminJettonWallet);
  } catch (error: any) {
    console.error('❌ Failed to fetch admin jetton wallet:', error.message);
    console.error(
      '\nAdmin must have a jetton wallet for this jetton master first. Please send some jettons to admin address.'
    );
    throw error;
  }

  // Build jetton transfer message body
  // OP_JETTON_TRANSFER = 0xf8a7ea5
  const transferAmount = 1n; // Transfer 1 unit (smallest denomination) to initialize wallet
  const forwardTonAmount = toNano('0.01'); // Forward 0.01 TON for notification

  const transferBody = beginCell()
    .storeUint(0xf8a7ea5, 32) // op = transfer
    .storeUint(0, 64) // query_id
    .storeCoins(transferAmount) // amount (1 unit)
    .storeAddress(feeWalletAddress) // destination
    .storeAddress(adminAddress) // response_destination
    .storeUint(0, 1) // custom_payload (null)
    .storeCoins(forwardTonAmount) // forward_ton_amount
    .storeUint(0, 1) // forward_payload (null)
    .endCell();

  // Get current seqno
  const seqno = await adminWallet.getSeqno();
  console.log('\n📨 Sending jetton transfer to initialize fee wallet...');
  console.log('Current seqno:', seqno);
  console.log('Transfer amount:', transferAmount.toString(), 'units (minimal)');

  // Send transaction
  await adminWallet.sendTransfer({
    seqno,
    secretKey: adminKeyPair.secretKey,
    messages: [
      internal({
        to: Address.parse(adminJettonWallet),
        value: toNano('0.15'), // 0.15 TON for gas + wallet initialization
        bounce: true,
        body: transferBody,
      }),
    ],
    sendMode: SendMode.PAY_GAS_SEPARATELY + SendMode.IGNORE_ERRORS,
  });

  console.log('✅ Transaction sent!');
  console.log('Waiting for confirmation...');

  // Wait for confirmation (check seqno change)
  let currentSeqno = seqno;
  let attempts = 0;
  while (currentSeqno === seqno && attempts < 30) {
    await new Promise((resolve) => setTimeout(resolve, 2000));
    currentSeqno = await adminWallet.getSeqno();
    attempts++;
  }

  if (currentSeqno === seqno) {
    throw new Error('Transaction timeout - may have failed');
  }

  console.log('✅ Transaction confirmed!');
  console.log(
    '\n💡 Fee wallet jetton wallet should now be initialized. Wait a few seconds for blockchain propagation.'
  );
  console.log(
    '   You can verify by checking fee wallet jetton balance on explorer or wait ~10 seconds before using vault.'
  );
}

/**
 * Main execution
 */
async function main() {
  try {
    console.log('\n========================================');
    console.log('TON Bridge Vault Configuration');
    console.log('========================================\n');

    // Parse CLI arguments
    const cliArgs = parseArgs();

    // Load configuration
    const config = loadConfigFromEnv();

    console.log('Network:', config.network);
    console.log('Endpoint:', config.endpoint);
    console.log('Vault Contract:', config.vaultAddress);

    // Initialize TON client
    const client = new TonClient({
      endpoint: config.endpoint,
      apiKey: config.apiKey,
    });

    const vaultAddress = Address.parse(config.vaultAddress);

    // Check if contract exists
    const isDeployed = await client.isContractDeployed(vaultAddress);
    if (!isDeployed) {
      throw new Error('Vault contract not found at specified address');
    }

    // Query state if requested
    if (cliArgs.queryState) {
      await queryVaultState(client, vaultAddress);
      return;
    }

    // Check if any operation is requested
    if (
      !cliArgs.setFeeWallet &&
      !cliArgs.setAllowedJetton &&
      !cliArgs.setAdmin &&
      !cliArgs.withdrawTon &&
      !cliArgs.initializeFeeWallet
    ) {
      console.log('\nNo operation specified. Use one of:');
      console.log('  --set-fee-wallet          Set fee wallet address');
      console.log('  --set-allowed-jetton      Set allowed jetton address');
      console.log('  --set-admin               Set new admin address');
      console.log('  --withdraw-ton            Withdraw TON from vault');
      console.log('  --initialize-fee-wallet   Initialize fee wallet jetton wallet (fixes exit 709)');
      console.log('  --query                   Query current vault state');
      console.log('\nExample:');
      console.log('  npx ts-node scripts/configure-bridge-vault.ts --set-fee-wallet --set-allowed-jetton');
      console.log('  npx ts-node scripts/configure-bridge-vault.ts --initialize-fee-wallet');
      console.log('  npx ts-node scripts/configure-bridge-vault.ts --withdraw-ton');
      process.exit(0);
    }

    // Initialize admin wallet
    let keyPair: KeyPair;
    if (config.adminMnemonic) {
      keyPair = await mnemonicToPrivateKey(config.adminMnemonic.split(' '));
      console.log('Admin: Using mnemonic');
    } else if (config.adminPublicKeyHex && config.adminSecretKeyHex) {
      const publicKey = config.adminPublicKeyHex.replace(/^0x/, '');
      const secretKey = config.adminSecretKeyHex.replace(/^0x/, '');

      keyPair = {
        publicKey: Buffer.from(publicKey, 'hex'),
        secretKey: Buffer.from(secretKey, 'hex'),
      };
      console.log('Admin: Using hex keys');
    } else {
      throw new Error(
        'Must provide either TON_ADMIN_MNEMONIC or (TON_DEPLOYER_PUBLIC_KEY_HEX + TON_DEPLOYER_SECRET_KEY_HEX)'
      );
    }

    const adminWallet = client.open(
      WalletContractV5R1.create({
        workchain: 0,
        publicKey: keyPair.publicKey,
      })
    );

    const adminAddress = adminWallet.address;
    console.log('Admin Address:', adminAddress.toString());

    // Check admin balance
    const balance = await client.getBalance(adminAddress);
    console.log('Admin Balance:', Number(balance) / 1e9, 'TON');

    if (balance < toNano('0.1')) {
      throw new Error('Insufficient admin balance. Need at least 0.1 TON for transactions');
    }

    // Execute operations
    if (cliArgs.setFeeWallet) {
      if (!config.feeWalletAddress) {
        throw new Error('VAULT_FEE_WALLET environment variable is required for --set-fee-wallet');
      }

      const feeWalletAddress = Address.parse(config.feeWalletAddress);
      await sendGovernanceMessage(
        client,
        adminWallet,
        keyPair,
        vaultAddress,
        OP_SET_FEE_WALLET,
        feeWalletAddress,
        'SET_FEE_WALLET'
      );
    }

    if (cliArgs.setAllowedJetton) {
      if (!config.allowedJettonAddress) {
        throw new Error('VAULT_ALLOWED_JETTON environment variable is required for --set-allowed-jetton');
      }

      const allowedJettonAddress = Address.parse(config.allowedJettonAddress);
      await sendGovernanceMessage(
        client,
        adminWallet,
        keyPair,
        vaultAddress,
        OP_SET_ALLOWED_JETTON,
        allowedJettonAddress,
        'SET_ALLOWED_JETTON'
      );
    }

    if (cliArgs.setAdmin) {
      if (!config.newAdminAddress) {
        throw new Error('NEW_ADMIN_ADDRESS environment variable is required for --set-admin');
      }

      const newAdminAddress = Address.parse(config.newAdminAddress);
      await sendGovernanceMessage(
        client,
        adminWallet,
        keyPair,
        vaultAddress,
        OP_SET_ADMIN,
        newAdminAddress,
        'SET_ADMIN'
      );
    }

    if (cliArgs.withdrawTon) {
      if (!config.withdrawDestination) {
        throw new Error('WITHDRAW_DESTINATION environment variable is required for --withdraw-ton');
      }

      if (!config.withdrawAmount) {
        throw new Error('WITHDRAW_AMOUNT environment variable is required for --withdraw-ton');
      }

      const withdrawDestination = Address.parse(config.withdrawDestination);
      const withdrawAmount = toNano(config.withdrawAmount);

      await sendWithdrawTonMessage(
        client,
        adminWallet,
        keyPair,
        vaultAddress,
        withdrawDestination,
        withdrawAmount
      );
    }

    if (cliArgs.initializeFeeWallet) {
      if (!config.feeWalletAddress) {
        throw new Error('VAULT_FEE_WALLET environment variable is required for --initialize-fee-wallet');
      }

      if (!config.allowedJettonAddress) {
        throw new Error(
          'VAULT_ALLOWED_JETTON environment variable is required for --initialize-fee-wallet'
        );
      }

      const feeWalletAddress = Address.parse(config.feeWalletAddress);
      const jettonMasterAddress = Address.parse(config.allowedJettonAddress);

      await initializeFeeWalletJettonWallet(
        client,
        config.network,
        adminWallet,
        keyPair,
        adminAddress,
        feeWalletAddress,
        jettonMasterAddress
      );
    }

    console.log('\n========================================');
    console.log('Configuration Successful!');
    console.log('========================================');

    // Query final state
    await queryVaultState(client, vaultAddress);
  } catch (error) {
    console.error('\n❌ Configuration failed:');
    console.error(error);
    process.exit(1);
  }
}

// Run if executed directly
if (require.main === module) {
  main();
}

export { loadConfigFromEnv, queryVaultState };
