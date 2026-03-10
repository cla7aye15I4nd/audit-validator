/**
 * @file deploy-bridge-vault.ts
 * @notice Deployment script for TON Bridge Vault contract
 *
 * This script deploys the bridge vault contract to TON mainnet/testnet.
 * The vault automatically processes jetton deposits by taking 1% fee and burning 99%.
 *
 * Environment Variables:
 * - TON_CHAIN: mainnet | testnet
 * - TONCENTER_API_KEY: API key for TonCenter
 * - TON_DEPLOYER_MNEMONIC: Deployer wallet mnemonic
 * - TON_DEPLOYER_PUBLIC_KEY_HEX: Alternative to mnemonic (64 hex chars)
 * - TON_DEPLOYER_SECRET_KEY_HEX: Alternative to mnemonic (128 hex chars)
 * - VAULT_ADMIN_ADDRESS: Admin address for governance
 * - VAULT_FEE_WALLET: Wallet to receive 1% fees
 * - VAULT_ALLOWED_JETTON: Whitelisted jetton root address
 * - VAULT_INIT_BALANCE: Initial balance in TON (default: 0.1)
 * - VAULT_CODE_BOC: Path to precompiled BOC file (optional)
 *
 * Usage:
 *   DOTENV_CONFIG_PATH=runs/3-bridge-ton-to-base/.env npx ts-node scripts/deploy-bridge-vault.ts
 */

import 'dotenv/config';
import { Address, Cell, StateInit, beginCell, storeStateInit, toNano, internal, SendMode } from '@ton/core';
import { TonClient, WalletContractV5R1 } from '@ton/ton';
import { mnemonicToPrivateKey, KeyPair } from '@ton/crypto';
import * as fs from 'fs';
import * as path from 'path';

/**
 * Configuration for deployment
 */
interface DeploymentConfig {
  network: 'mainnet' | 'testnet';
  endpoint: string;
  apiKey?: string;

  // Vault configuration
  adminAddress: string;
  feeWalletAddress: string;
  allowedJettonAddress: string;

  // Deployment wallet
  deployerMnemonic?: string;
  deployerPublicKeyHex?: string;
  deployerSecretKeyHex?: string;

  // Deployment parameters
  initBalance: string; // In TON (e.g., '0.1')

  // Optional precompiled code
  codeBocPath?: string;
}

/**
 * Deployment result metadata
 */
interface DeploymentResult {
  network: 'mainnet' | 'testnet';
  contractAddress: string;
  deployerAddress: string;
  txHash?: string;
  deployedAt: string;
  adminAddress: string;
  feeWalletAddress: string;
  allowedJettonAddress: string;
  initBalance: string;
  explorerUrl: string;
}

/**
 * Load configuration from environment variables
 */
function loadConfigFromEnv(): DeploymentConfig {
  const network = (process.env.TON_CHAIN as 'mainnet' | 'testnet') || 'testnet';

  // Determine endpoint
  const endpoint =
    network === 'testnet'
      ? 'https://testnet.toncenter.com/api/v2/jsonRPC'
      : 'https://toncenter.com/api/v2/jsonRPC';

  // Load vault configuration
  const adminAddress = process.env.VAULT_ADMIN_ADDRESS;
  const feeWalletAddress = process.env.VAULT_FEE_WALLET;
  const allowedJettonAddress = process.env.VAULT_ALLOWED_JETTON;

  if (!adminAddress || !feeWalletAddress || !allowedJettonAddress) {
    throw new Error(
      'Missing required environment variables: VAULT_ADMIN_ADDRESS, VAULT_FEE_WALLET, VAULT_ALLOWED_JETTON'
    );
  }

  return {
    network,
    endpoint,
    apiKey: process.env.TONCENTER_API_KEY,
    adminAddress,
    feeWalletAddress,
    allowedJettonAddress,
    deployerMnemonic: process.env.TON_DEPLOYER_MNEMONIC,
    deployerPublicKeyHex: process.env.TON_DEPLOYER_PUBLIC_KEY_HEX,
    deployerSecretKeyHex: process.env.TON_DEPLOYER_SECRET_KEY_HEX,
    initBalance: process.env.VAULT_INIT_BALANCE || '0.1',
    codeBocPath: process.env.VAULT_CODE_BOC,
  };
}

/**
 * Build initial storage cell for vault contract
 *
 * Storage structure:
 * Main cell:
 *   - admin (MsgAddress)
 *   - fee_wallet (MsgAddress)
 *   - allowed_jetton (MsgAddress)
 *   - stats_ref (reference to stats cell)
 *
 * Stats cell:
 *   - total_burned (uint128)
 *   - total_fees (uint128)
 *
 * NOTE: The contract address is deterministic based on code + data.
 * If you need a new address for the same code/config, you cannot use this function.
 * Instead, temporarily change one of the addresses in your .env, deploy, then update via governance.
 */
function buildInitialStorage(
  adminAddress: string,
  feeWalletAddress: string,
  allowedJettonAddress: string
): Cell {
  const admin = Address.parse(adminAddress);
  const feeWallet = Address.parse(feeWalletAddress);
  const allowedJetton = Address.parse(allowedJettonAddress);

  // Build stats cell
  const statsCell = beginCell()
    .storeUint(0, 128) // total_burned = 0
    .storeUint(0, 128) // total_fees = 0
    .endCell();

  // Build main storage cell
  return beginCell()
    .storeAddress(admin)
    .storeAddress(feeWallet)
    .storeAddress(allowedJetton)
    .storeRef(statsCell)
    .endCell();
}

/**
 * Load contract code from BOC file
 */
function loadContractCode(bocPath: string): Cell {
  const bocBuffer = fs.readFileSync(bocPath);
  return Cell.fromBoc(bocBuffer)[0];
}

/**
 * Deploy vault contract
 */
async function deployVault(config: DeploymentConfig): Promise<DeploymentResult> {
  console.log('\n========================================');
  console.log('TON Bridge Vault Deployment');
  console.log('========================================\n');

  console.log('Network:', config.network);
  console.log('Endpoint:', config.endpoint);
  console.log('Admin Address:', config.adminAddress);
  console.log('Fee Wallet:', config.feeWalletAddress);
  console.log('Allowed Jetton:', config.allowedJettonAddress);
  console.log('Init Balance:', config.initBalance, 'TON\n');

  // Initialize TON client
  const client = new TonClient({
    endpoint: config.endpoint,
    apiKey: config.apiKey,
  });

  // Initialize deployer wallet
  let keyPair: KeyPair;
  if (config.deployerMnemonic) {
    keyPair = await mnemonicToPrivateKey(config.deployerMnemonic.split(' '));
    console.log('Deployer: Using mnemonic');
  } else if (config.deployerPublicKeyHex && config.deployerSecretKeyHex) {
    // Remove 0x prefix if present
    const publicKey = config.deployerPublicKeyHex.replace(/^0x/, '');
    const secretKey = config.deployerSecretKeyHex.replace(/^0x/, '');

    keyPair = {
      publicKey: Buffer.from(publicKey, 'hex'),
      secretKey: Buffer.from(secretKey, 'hex'),
    };
    console.log('Deployer: Using hex keys');
  } else {
    throw new Error(
      'Must provide either TON_DEPLOYER_MNEMONIC or (TON_DEPLOYER_PUBLIC_KEY_HEX + TON_DEPLOYER_SECRET_KEY_HEX)'
    );
  }

  // Use V5R1 wallet
  const deployerWallet = client.open(
    WalletContractV5R1.create({
      workchain: 0,
      publicKey: keyPair.publicKey,
    })
  );

  const deployerAddress = deployerWallet.address;
  console.log('Deployer Address:', deployerAddress.toString());

  // Check deployer balance
  const balance = await client.getBalance(deployerAddress);
  console.log('Deployer Balance:', Number(balance) / 1e9, 'TON');

  if (balance < toNano(config.initBalance)) {
    throw new Error(`Insufficient balance. Need at least ${config.initBalance} TON`);
  }

  // Load or compile contract code
  let contractCode: Cell;
  if (config.codeBocPath) {
    console.log('\nLoading precompiled code from:', config.codeBocPath);
    contractCode = loadContractCode(config.codeBocPath);
  } else {
    console.log('\nERROR: Contract code BOC file not specified.');
    console.log('Please compile bridge-vault.fc first and set VAULT_CODE_BOC environment variable.');
    console.log('\nTo compile:');
    console.log('  npx ts-node scripts/build-ton-vault.ts');
    throw new Error('Contract code not provided');
  }

  // Build initial storage
  console.log('\nBuilding initial storage...');
  const contractData = buildInitialStorage(
    config.adminAddress,
    config.feeWalletAddress,
    config.allowedJettonAddress
  );

  // Create StateInit
  const stateInit: StateInit = {
    code: contractCode,
    data: contractData,
  };

  // Calculate contract address
  const stateInitCell = beginCell().store(storeStateInit(stateInit)).endCell();
  const contractAddress = new Address(0, stateInitCell.hash());

  console.log('Vault Contract Address:', contractAddress.toString());
  console.log('Vault Contract Address (raw):', contractAddress.toRawString());

  // Check if contract already exists
  const isDeployed = await client.isContractDeployed(contractAddress);
  if (isDeployed) {
    console.log('\n⚠️  Contract already deployed at this address!');
    console.log('Skipping deployment.');

    return {
      network: config.network,
      contractAddress: contractAddress.toString(),
      deployerAddress: deployerAddress.toString(),
      deployedAt: new Date().toISOString(),
      adminAddress: config.adminAddress,
      feeWalletAddress: config.feeWalletAddress,
      allowedJettonAddress: config.allowedJettonAddress,
      initBalance: config.initBalance,
      explorerUrl:
        config.network === 'testnet'
          ? `https://testnet.tonviewer.com/${contractAddress.toString()}`
          : `https://tonviewer.com/${contractAddress.toString()}`,
    };
  }

  // Deploy contract
  console.log('\n📤 Deploying vault contract...');

  const seqno = await deployerWallet.getSeqno();
  console.log('Current seqno:', seqno);

  await deployerWallet.sendTransfer({
    seqno,
    secretKey: keyPair.secretKey,
    messages: [
      internal({
        to: contractAddress,
        value: toNano(config.initBalance),
        bounce: false,
        init: stateInit,
        body: beginCell().endCell(), // Empty body for deployment
      }),
    ],
    sendMode: SendMode.PAY_GAS_SEPARATELY + SendMode.IGNORE_ERRORS,
  });

  console.log('✅ Deployment transaction sent!');
  console.log('Waiting for confirmation...');

  // Wait for deployment (check seqno change)
  let currentSeqno = seqno;
  let attempts = 0;
  while (currentSeqno === seqno && attempts < 30) {
    await new Promise((resolve) => setTimeout(resolve, 2000));
    currentSeqno = await deployerWallet.getSeqno();
    attempts++;
  }

  if (currentSeqno === seqno) {
    throw new Error('Deployment timeout - transaction may have failed');
  }

  console.log('✅ Deployment confirmed!');

  // Verify deployment
  const deployed = await client.isContractDeployed(contractAddress);
  if (!deployed) {
    throw new Error('Contract deployment verification failed');
  }

  console.log('✅ Contract verified on-chain');

  const explorerUrl =
    config.network === 'testnet'
      ? `https://testnet.tonviewer.com/${contractAddress.toString()}`
      : `https://tonviewer.com/${contractAddress.toString()}`;

  console.log('\n========================================');
  console.log('Deployment Successful!');
  console.log('========================================');
  console.log('Contract Address:', contractAddress.toString());
  console.log('Explorer:', explorerUrl);
  console.log('========================================\n');

  return {
    network: config.network,
    contractAddress: contractAddress.toString(),
    deployerAddress: deployerAddress.toString(),
    deployedAt: new Date().toISOString(),
    adminAddress: config.adminAddress,
    feeWalletAddress: config.feeWalletAddress,
    allowedJettonAddress: config.allowedJettonAddress,
    initBalance: config.initBalance,
    explorerUrl,
  };
}

/**
 * Main execution
 */
async function main() {
  try {
    // Load configuration
    const config = loadConfigFromEnv();

    // Deploy vault
    const result = await deployVault(config);

    // Save deployment metadata
    const outputPath = path.join(__dirname, '..', 'deployments', 'vault-deployment.json');
    fs.mkdirSync(path.dirname(outputPath), { recursive: true });
    fs.writeFileSync(outputPath, JSON.stringify(result, null, 2));

    console.log('Deployment metadata saved to:', outputPath);
  } catch (error) {
    console.error('\n❌ Deployment failed:');
    console.error(error);
    process.exit(1);
  }
}

// Run if executed directly
if (require.main === module) {
  main();
}

export { deployVault, loadConfigFromEnv };
