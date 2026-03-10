/**
 * @file deploy-ton-multisig.ts
 * @notice Deployment script for TON Bridge Multisig contract
 *
 * This script deploys the bridge multisig contract to TON mainnet/testnet
 * with proper configuration, verification, and deployment metadata saving.
 *
 * Environment Variables:
 * - TON_CHAIN: mainnet | testnet
 * - TONCENTER_API_KEY: API key for TonCenter
 * - TON_DEPLOYER_MNEMONIC: Deployer wallet mnemonic (v5r1)
 * - TON_DEPLOYER_PUBLIC_KEY_HEX: Alternative to mnemonic (64 hex chars)
 * - TON_DEPLOYER_SECRET_KEY_HEX: Alternative to mnemonic (64 hex chars)
 * - DEPLOYER_WALLET_VERSION: v5r1 (default)
 * - TON_MULTISIG_WATCHERS: Comma-separated watcher public keys (5)
 * - TON_MULTISIG_GOVERNANCE: Comma-separated governance public keys (5)
 * - TON_JETTON_ROOT: Primary jetton root address
 * - TON_MULTISIG_ALLOW_LIST: Comma-separated additional jetton addresses
 * - TON_MULTISIG_INIT_BALANCE: Initial balance in TON (default: 1.5)
 * - TON_MULTISIG_INIT_MINT_NONCE: Optional initial mint_nonce (uint64, for redeployment sync)
 * - TON_MULTISIG_INIT_GOVERNANCE_NONCE: Optional initial governance_nonce (uint64, for redeployment sync)
 * - TON_DEPLOYMENT_CONFIG: Path to JSON config file (alternative to ENV vars)
 * - TON_MULTISIG_CODE_BOC: Path to precompiled BOC file
 *
 * Usage:
 *   ts-node scripts/deploy-ton-multisig.ts [--network mainnet|testnet] [--save output.json] [--dry-run]
 */

import 'dotenv/config';
import { Address, Cell, StateInit, beginCell, storeStateInit, toNano, internal, SendMode } from '@ton/core';
import { TonClient, WalletContractV5R1 } from '@ton/ton';
import { mnemonicToPrivateKey } from '@ton/crypto';
import {
  buildInitialStorage,
  DeployParams,
  BridgeMultisig,
  parsePublicKey,
} from '../apps/shared/ton-multisig';
import * as fs from 'fs';
import * as path from 'path';

/**
 * Configuration for deployment
 */
interface DeploymentConfig {
  // Network configuration
  network: 'mainnet' | 'testnet';
  endpoint: string;
  apiKey?: string;

  // Watcher configuration (5 keys, 3-of-5 threshold)
  watcherPublicKeys: string[]; // Hex-encoded Ed25519 public keys

  // Governance configuration (5 keys, 3-of-5 threshold)
  governancePublicKeys: string[]; // Hex-encoded Ed25519 public keys

  // Initial jetton whitelist
  allowedJettons: string[]; // TON addresses

  // Deployment wallet
  deployerMnemonic?: string;
  deployerPublicKeyHex?: string;
  deployerSecretKeyHex?: string;
  deployerWalletVersion: string; // 'v5r1', 'v4', etc.

  // Deployment parameters
  initBalance: string; // In TON (e.g., '1.5')

  // Optional precompiled code
  codeBocPath?: string;

  // Optional initial nonce values (for redeployment sync)
  initialMintNonce?: string; // Uint64 as string
  initialGovernanceNonce?: string; // Uint64 as string
}

/**
 * Deployment result metadata
 */
interface DeploymentResult {
  network: 'mainnet' | 'testnet';
  contractAddress: string;
  deployerAddress: string;
  txHash?: string;
  lt?: string;
  deployedAt: string;
  watchers: string[];
  governance: string[];
  allowedJettons: string[];
  initBalance: string;
  verified: boolean;
}

/**
 * Load configuration from environment variables
 */
function loadConfigFromEnv(): DeploymentConfig {
  const network = (process.env.TON_CHAIN as 'mainnet' | 'testnet') || 'testnet';

  // Determine endpoint
  let endpoint: string;
  if (network === 'mainnet') {
    endpoint = 'https://toncenter.com/api/v2/jsonRPC';
  } else {
    endpoint = 'https://testnet.toncenter.com/api/v2/jsonRPC';
  }

  const apiKey = process.env.TONCENTER_API_KEY;

  // Parse watcher keys
  const watchersEnv = process.env.TON_MULTISIG_WATCHERS;
  if (!watchersEnv) {
    throw new Error('TON_MULTISIG_WATCHERS environment variable is required');
  }
  const watcherPublicKeys = watchersEnv.split(',').map(k => k.trim()).filter(k => k.length > 0);

  // Parse governance keys
  const governanceEnv = process.env.TON_MULTISIG_GOVERNANCE;
  if (!governanceEnv) {
    throw new Error('TON_MULTISIG_GOVERNANCE environment variable is required');
  }
  const governancePublicKeys = governanceEnv.split(',').map(k => k.trim()).filter(k => k.length > 0);

  // Parse jetton addresses
  const allowedJettons: string[] = [];

  // Add primary jetton root
  const jettonRoot = process.env.TON_JETTON_ROOT;
  if (jettonRoot && jettonRoot.trim()) {
    allowedJettons.push(jettonRoot.trim());
  }

  // Add additional jettons from allow list
  const allowListEnv = process.env.TON_MULTISIG_ALLOW_LIST;
  if (allowListEnv && allowListEnv.trim()) {
    const additionalJettons = allowListEnv.split(',').map(j => j.trim()).filter(j => j.length > 0);
    allowedJettons.push(...additionalJettons);
  }

  // Get deployer wallet credentials
  const deployerMnemonic = process.env.TON_DEPLOYER_MNEMONIC;
  const deployerPublicKeyHex = process.env.TON_DEPLOYER_PUBLIC_KEY_HEX;
  const deployerSecretKeyHex = process.env.TON_DEPLOYER_SECRET_KEY_HEX;

  if (!deployerMnemonic && (!deployerPublicKeyHex || !deployerSecretKeyHex)) {
    throw new Error('Either TON_DEPLOYER_MNEMONIC or both TON_DEPLOYER_PUBLIC_KEY_HEX and TON_DEPLOYER_SECRET_KEY_HEX must be provided');
  }

  const deployerWalletVersion = process.env.DEPLOYER_WALLET_VERSION || 'v5r1';
  const initBalance = process.env.TON_MULTISIG_INIT_BALANCE || '0.3';
  const codeBocPath = process.env.TON_MULTISIG_CODE_BOC;

  // Optional initial nonce values for redeployment
  const initialMintNonce = process.env.TON_MULTISIG_INIT_MINT_NONCE;
  const initialGovernanceNonce = process.env.TON_MULTISIG_INIT_GOVERNANCE_NONCE;

  return {
    network,
    endpoint,
    apiKey,
    watcherPublicKeys,
    governancePublicKeys,
    allowedJettons,
    deployerMnemonic,
    deployerPublicKeyHex,
    deployerSecretKeyHex,
    deployerWalletVersion,
    initBalance,
    codeBocPath,
    initialMintNonce,
    initialGovernanceNonce,
  };
}

/**
 * Load configuration from JSON file
 */
function loadConfigFromFile(filePath: string): DeploymentConfig {
  const rawData = fs.readFileSync(filePath, 'utf-8');
  const config = JSON.parse(rawData);

  // Validate required fields
  if (!config.network || !config.watcherPublicKeys || !config.governancePublicKeys) {
    throw new Error('Invalid configuration file: missing required fields');
  }

  // Set defaults
  config.endpoint = config.endpoint || (config.network === 'mainnet'
    ? 'https://toncenter.com/api/v2/jsonRPC'
    : 'https://testnet.toncenter.com/api/v2/jsonRPC');
  config.deployerWalletVersion = config.deployerWalletVersion || 'v5r1';
  config.initBalance = config.initBalance || '1.5';
  config.allowedJettons = config.allowedJettons || [];

  return config;
}

/**
 * Validate deployment configuration
 */
function validateConfig(config: DeploymentConfig): void {
  // Validate watchers (5 keys for 3-of-5 threshold)
  if (config.watcherPublicKeys.length !== 5) {
    throw new Error(`Expected 5 watcher keys, got ${config.watcherPublicKeys.length}`);
  }

  // Validate governance (5 keys for 3-of-5 threshold)
  if (config.governancePublicKeys.length !== 5) {
    throw new Error(`Expected 5 governance keys, got ${config.governancePublicKeys.length}`);
  }

  // Validate jettons
  if (config.allowedJettons.length === 0) {
    console.warn('Warning: No jettons in whitelist. Contract will not allow any mints until updated via governance.');
  }

  // Validate public keys format
  for (const key of [...config.watcherPublicKeys, ...config.governancePublicKeys]) {
    try {
      parsePublicKey(key);
    } catch (e) {
      throw new Error(`Invalid public key format: ${key}`);
    }
  }

  // Validate jetton addresses
  for (const jetton of config.allowedJettons) {
    try {
      Address.parse(jetton);
    } catch (e) {
      throw new Error(`Invalid jetton address: ${jetton}`);
    }
  }
}

/**
 * Get deployer wallet keys from configuration
 */
async function getDeployerKeys(config: DeploymentConfig): Promise<{ publicKey: Buffer; secretKey: Buffer }> {
  if (config.deployerMnemonic) {
    const words = config.deployerMnemonic.trim().split(/\s+/);
    const keypair = await mnemonicToPrivateKey(words);
    // mnemonicToPrivateKey returns { publicKey: Uint8Array, secretKey: Uint8Array }
    return {
      publicKey: Buffer.from(new Uint8Array(keypair.publicKey as any)),
      secretKey: Buffer.from(new Uint8Array(keypair.secretKey as any)),
    };
  } else if (config.deployerPublicKeyHex && config.deployerSecretKeyHex) {
    const publicKey = parsePublicKey(config.deployerPublicKeyHex);
    const secretKeyHex = config.deployerSecretKeyHex.startsWith('0x')
      ? config.deployerSecretKeyHex.slice(2)
      : config.deployerSecretKeyHex;
    if (secretKeyHex.length !== 128) {
      throw new Error('Secret key must be 128 hex characters (64 bytes)');
    }
    const secretKey = Buffer.from(secretKeyHex, 'hex');
    return { publicKey, secretKey };
  } else {
    throw new Error('No deployer credentials provided');
  }
}

/**
 * Load or compile contract code
 */
function loadContractCode(config: DeploymentConfig): Cell {
  if (config.codeBocPath) {
    console.log(`Loading precompiled code from: ${config.codeBocPath}`);
    if (!fs.existsSync(config.codeBocPath)) {
      throw new Error(`Code BOC file not found: ${config.codeBocPath}`);
    }
    const bocData = fs.readFileSync(config.codeBocPath);
    return Cell.fromBoc(bocData)[0];
  } else {
    // Try to load from default build location
    const defaultBocPath = path.join(__dirname, '../build/bridge-multisig.boc');
    if (fs.existsSync(defaultBocPath)) {
      console.log(`Loading code from default location: ${defaultBocPath}`);
      const bocData = fs.readFileSync(defaultBocPath);
      return Cell.fromBoc(bocData)[0];
    } else {
      throw new Error(
        `No contract code found. Please either:\n` +
        `1. Provide TON_MULTISIG_CODE_BOC environment variable\n` +
        `2. Place compiled code at: ${defaultBocPath}\n` +
        `3. Compile using: func -o build/bridge-multisig.boc contracts/ton/bridge-multisig.fc`
      );
    }
  }
}

/**
 * Build StateInit for contract deployment
 */
function buildStateInit(code: Cell, data: Cell): StateInit {
  return {
    code,
    data,
  };
}

/**
 * Calculate contract address from StateInit
 */
function contractAddress(stateInit: StateInit, workchain: number = 0): Address {
  const stateInitCell = beginCell()
    .store(storeStateInit(stateInit))
    .endCell();
  const hash = stateInitCell.hash();
  return new Address(workchain, hash);
}

/**
 * Wait for transaction confirmation
 */
async function waitForTransaction(
  client: TonClient,
  address: Address,
  startLt: string,
  timeout: number = 60000
): Promise<{ hash: string; lt: string } | null> {
  const startTime = Date.now();
  let currentLt = BigInt(startLt);

  while (Date.now() - startTime < timeout) {
    try {
      const txs = await client.getTransactions(address, { limit: 10 });
      for (const tx of txs) {
        if (BigInt(tx.lt) > currentLt) {
          return {
            hash: tx.hash().toString('hex'),
            lt: tx.lt.toString(),
          };
        }
      }
    } catch (e) {
      // Ignore errors during polling
    }
    await new Promise(resolve => setTimeout(resolve, 2000));
  }

  return null;
}

/**
 * Deploy the bridge multisig contract
 */
async function deployBridgeMultisig(
  config: DeploymentConfig,
  dryRun: boolean = false
): Promise<{ address: Address; txHash?: string; lt?: string; deployerAddress: string }> {
  console.log('🚀 Starting TON Bridge Multisig deployment...');
  console.log(`Network: ${config.network}`);
  console.log(`Endpoint: ${config.endpoint}`);
  console.log(`Dry run: ${dryRun ? 'YES' : 'NO'}\n`);

  // Validate configuration
  validateConfig(config);
  console.log('✓ Configuration validated');

  // Initialize TON client
  const client = new TonClient({
    endpoint: config.endpoint,
    apiKey: config.apiKey,
  });
  console.log('✓ TON client initialized');

  // Get deployer keys
  const deployerKeys = await getDeployerKeys(config);
  console.log('✓ Deployer keys loaded');

  // Only v5r1 is supported for now
  if (config.deployerWalletVersion !== 'v5r1') {
    throw new Error(`Unsupported wallet version: ${config.deployerWalletVersion}. Only v5r1 is supported.`);
  }

  const deployerWallet = WalletContractV5R1.create({
    workchain: 0,
    publicKey: deployerKeys.publicKey,
  });
  const deployerAddress = deployerWallet.address;

  console.log(`✓ Deployer wallet: ${deployerAddress.toString()}`);

  // Check deployer wallet state and balance
  const deployerState = await client.getContractState(deployerAddress);
  if (deployerState.state !== 'active') {
    throw new Error(
      `Deployer wallet is not active (state: ${deployerState.state}). ` +
      `Please deploy the wallet first by sending TON to: ${deployerAddress.toString()}`
    );
  }

  const openedWallet = client.open(deployerWallet);
  const balance = await openedWallet.getBalance();
  const balanceTON = Number(balance) / 1e9;
  const requiredBalance = parseFloat(config.initBalance) + 0.2; // init balance + gas

  console.log(`✓ Deployer balance: ${balanceTON.toFixed(4)} TON`);

  if (balanceTON < requiredBalance) {
    throw new Error(
      `Insufficient deployer balance. Required: ${requiredBalance.toFixed(2)} TON, Available: ${balanceTON.toFixed(4)} TON`
    );
  }

  // Load contract code
  const code = loadContractCode(config);
  console.log('✓ Contract code loaded');

  // Parse configuration
  const deployParams: DeployParams = {
    watchers: config.watcherPublicKeys.map(parsePublicKey),
    governance: config.governancePublicKeys.map(parsePublicKey),
    allowedJettons: config.allowedJettons,
    initialMintNonce: config.initialMintNonce ? BigInt(config.initialMintNonce) : undefined,
    initialGovernanceNonce: config.initialGovernanceNonce ? BigInt(config.initialGovernanceNonce) : undefined,
  };

  // Build initial storage
  const data = buildInitialStorage(deployParams);
  console.log('✓ Initial storage built');
  if (deployParams.initialMintNonce !== undefined) {
    console.log(`  Initial mint_nonce: ${deployParams.initialMintNonce.toString()}`);
  }
  if (deployParams.initialGovernanceNonce !== undefined) {
    console.log(`  Initial governance_nonce: ${deployParams.initialGovernanceNonce.toString()}`);
  }

  // Build StateInit
  const stateInit = buildStateInit(code, data);
  const multisigAddress = contractAddress(stateInit);

  console.log('\n' + '='.repeat(80));
  console.log('DEPLOYMENT CONFIGURATION');
  console.log('='.repeat(80));
  console.log(`\nContract Address: ${multisigAddress.toString()}`);
  console.log(`Explorer: https://tonviewer.com/${multisigAddress.toString()}`);

  console.log('\nWatchers (3-of-5 threshold):');
  config.watcherPublicKeys.forEach((key, i) => {
    console.log(`  [${i}] ${key}`);
  });

  console.log('\nGovernance (3-of-5 threshold):');
  config.governancePublicKeys.forEach((key, i) => {
    console.log(`  [${i}] ${key}`);
  });

  console.log('\nAllowed Jettons:');
  if (config.allowedJettons.length === 0) {
    console.log('  (none - must be added via governance)');
  } else {
    config.allowedJettons.forEach((addr, i) => {
      console.log(`  [${i}] ${addr}`);
    });
  }

  console.log(`\nInitial Balance: ${config.initBalance} TON`);
  console.log('='.repeat(80) + '\n');

  if (dryRun) {
    console.log('✓ Dry run complete - no transaction sent');
    return { address: multisigAddress, deployerAddress: deployerAddress.toString() };
  }

  // Get current seqno
  const seqno = await openedWallet.getSeqno();
  console.log(`Current seqno: ${seqno}`);

  // Prepare deployment message
  const deployMessage = internal({
    to: multisigAddress,
    value: toNano(config.initBalance),
    bounce: false,
    init: stateInit,
    body: new Cell(), // Empty body for deployment
  });

  console.log('\nSending deployment transaction...');

  // Send deployment transaction
  await openedWallet.sendTransfer({
    seqno,
    secretKey: deployerKeys.secretKey,
    sendMode: SendMode.PAY_GAS_SEPARATELY + SendMode.IGNORE_ERRORS,
    messages: [deployMessage],
  });

  console.log('✓ Transaction sent');

  // Wait for seqno to increment (confirms transaction was processed)
  console.log('Waiting for transaction confirmation...');
  const confirmTimeout = 120000; // 2 minutes
  const startTime = Date.now();
  let confirmed = false;

  while (Date.now() - startTime < confirmTimeout) {
    try {
      const newSeqno = await openedWallet.getSeqno();
      if (newSeqno > seqno) {
        confirmed = true;
        console.log('✓ Transaction confirmed (seqno incremented)');
        break;
      }
    } catch (e) {
      // Ignore errors during polling
    }
    await new Promise(resolve => setTimeout(resolve, 3000));
  }

  if (!confirmed) {
    console.warn('Warning: Transaction confirmation timeout. Contract may still deploy.');
  }

  // Try to get transaction details
  let txHash: string | undefined;
  let lt: string | undefined;

  try {
    console.log('Fetching transaction details...');
    const txs = await client.getTransactions(deployerAddress, { limit: 5 });
    const deployTx = txs.find(tx => tx.inMessage?.info.type === 'internal');
    if (deployTx) {
      txHash = deployTx.hash().toString('hex');
      lt = deployTx.lt.toString();
      console.log(`✓ Transaction hash: ${txHash}`);
      console.log(`✓ Logical time: ${lt}`);
    }
  } catch (e: any) {
    console.warn(`Warning: Could not fetch transaction details: ${e.message}`);
  }

  // Wait a bit more and check if contract is deployed
  console.log('\nChecking contract deployment...');
  await new Promise(resolve => setTimeout(resolve, 5000));

  const contractState = await client.getContractState(multisigAddress);
  if (contractState.state === 'active') {
    console.log('✓ Contract is deployed and active');
  } else {
    console.warn(`Warning: Contract state is: ${contractState.state}`);
  }

  // Wait additional time for state to fully propagate
  console.log('Waiting for state propagation (10 seconds)...');
  await new Promise(resolve => setTimeout(resolve, 10000));

  return {
    address: multisigAddress,
    txHash,
    lt,
    deployerAddress: deployerAddress.toString(),
  };
}

/**
 * Verify deployed contract
 */
async function verifyDeployment(
  client: TonClient,
  contractAddress: Address,
  expectedConfig: DeployParams
): Promise<boolean> {
  console.log('\n' + '='.repeat(80));
  console.log('DEPLOYMENT VERIFICATION');
  console.log('='.repeat(80) + '\n');

  console.log(`Contract: ${contractAddress.toString()}`);

  let allChecksPass = true;

  try {
    // Check contract is active
    const state = await client.getContractState(contractAddress);
    if (state.state !== 'active') {
      console.log(`❌ Contract is not active (state: ${state.state})`);
      return false;
    }
    console.log('✓ Contract is active');

    // Open contract for get method calls
    const contract = client.open(BridgeMultisig.createFromAddress(contractAddress));

    // Verify watchers (5 watchers)
    console.log('\nVerifying watchers...');
    for (let i = 0; i < 5; i++) {
      try {
        const onChainWatcher = await contract.getWatcher(i);
        const expectedWatcher = BigInt('0x' + expectedConfig.watchers[i].toString('hex'));

        if (onChainWatcher === expectedWatcher) {
          console.log(`  ✓ Watcher[${i}]: ${expectedConfig.watchers[i].toString('hex')}`);
        } else {
          console.log(`  ❌ Watcher[${i}] mismatch!`);
          console.log(`     Expected: ${expectedWatcher.toString(16)}`);
          console.log(`     Got:      ${onChainWatcher.toString(16)}`);
          allChecksPass = false;
        }
      } catch (e: any) {
        console.log(`  ⚠️  Could not verify watcher[${i}]: ${e.message}`);
        if (e.message.includes('exit_code: 9')) {
          console.log(`     ⚠️  CRITICAL: Storage layout mismatch - contract code doesn't match deployed data!`);
        }
        allChecksPass = false;
      }
    }

    // Verify governance
    console.log('\nVerifying governance members...');
    for (let i = 0; i < 5; i++) {
      try {
        const onChainGov = await contract.getGovernanceMember(i);
        const expectedGov = BigInt('0x' + expectedConfig.governance[i].toString('hex'));

        if (onChainGov === expectedGov) {
          console.log(`  ✓ Governance[${i}]: ${expectedConfig.governance[i].toString('hex')}`);
        } else {
          console.log(`  ❌ Governance[${i}] mismatch!`);
          console.log(`     Expected: ${expectedGov.toString(16)}`);
          console.log(`     Got:      ${onChainGov.toString(16)}`);
          allChecksPass = false;
        }
      } catch (e: any) {
        console.log(`  ⚠️  Could not verify governance[${i}]: ${e.message}`);
        if (e.message.includes('exit_code: 9')) {
          console.log(`     ⚠️  CRITICAL: Storage layout mismatch - contract code doesn't match deployed data!`);
        }
        allChecksPass = false;
      }
    }

    // Verify nonces
    console.log('\nVerifying nonces...');
    try {
      const mintNonce = await contract.getMintNonce();
      const expectedMintNonce = expectedConfig.initialMintNonce ?? 0n;
      if (mintNonce === expectedMintNonce) {
        console.log(`  ✓ Mint nonce: ${mintNonce}`);
      } else {
        console.log(`  ❌ Mint nonce should be ${expectedMintNonce}, got: ${mintNonce}`);
        allChecksPass = false;
      }
    } catch (e: any) {
      console.log(`  ❌ Failed to get mint nonce: ${e.message}`);
      allChecksPass = false;
    }

    try {
      const govNonce = await contract.getGovernanceNonce();
      const expectedGovNonce = expectedConfig.initialGovernanceNonce ?? 0n;
      if (govNonce === expectedGovNonce) {
        console.log(`  ✓ Governance nonce: ${govNonce}`);
      } else {
        console.log(`  ❌ Governance nonce should be ${expectedGovNonce}, got: ${govNonce}`);
        allChecksPass = false;
      }
    } catch (e: any) {
      console.log(`  ❌ Failed to get governance nonce: ${e.message}`);
      allChecksPass = false;
    }

    // Verify allowed jettons
    console.log('\nVerifying allowed jettons...');
    if (expectedConfig.allowedJettons.length === 0) {
      console.log('  (no jettons to verify)');
    } else {
      for (const jettonAddr of expectedConfig.allowedJettons) {
        try {
          const addr = Address.parse(jettonAddr);
          const isAllowed = await contract.isJettonAllowed(addr);

          if (isAllowed) {
            console.log(`  ✓ Jetton allowed: ${jettonAddr}`);
          } else {
            console.log(`  ❌ Jetton not allowed: ${jettonAddr}`);
            allChecksPass = false;
          }
        } catch (e: any) {
          console.log(`  ⚠️  Could not verify jetton ${jettonAddr}: ${e.message}`);
          if (e.message.includes('exit_code: 9')) {
            console.log(`     ⚠️  CRITICAL: Storage layout mismatch - contract code doesn't match deployed data!`);
          }
          allChecksPass = false;
        }
      }
    }

    console.log('\n' + '='.repeat(80));
    if (allChecksPass) {
      console.log('✓ ALL VERIFICATION CHECKS PASSED');
    } else {
      console.log('❌ SOME VERIFICATION CHECKS FAILED');
    }
    console.log('='.repeat(80) + '\n');

    return allChecksPass;
  } catch (e: any) {
    console.log(`\n❌ Verification failed with error: ${e.message}`);
    console.log('='.repeat(80) + '\n');
    return false;
  }
}

/**
 * Save deployment result to JSON file
 */
function saveDeploymentResult(result: DeploymentResult, outputPath: string): void {
  const dir = path.dirname(outputPath);
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }

  fs.writeFileSync(outputPath, JSON.stringify(result, null, 2), 'utf-8');
  console.log(`\n✓ Deployment metadata saved to: ${outputPath}`);
}

/**
 * Parse command-line arguments
 */
function parseArgs(): {
  network?: 'mainnet' | 'testnet';
  configPath?: string;
  saveOutput?: string;
  dryRun: boolean;
  verify: boolean;
} {
  const args = process.argv.slice(2);
  const result: {
    network?: 'mainnet' | 'testnet';
    configPath?: string;
    saveOutput?: string;
    dryRun: boolean;
    verify: boolean;
  } = {
    dryRun: false,
    verify: true,
  };

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];

    if (arg === '--network' && i + 1 < args.length) {
      const networkValue = args[i + 1] as 'mainnet' | 'testnet';
      if (networkValue !== 'mainnet' && networkValue !== 'testnet') {
        throw new Error('--network must be either "mainnet" or "testnet"');
      }
      result.network = networkValue;
      i++;
    } else if (arg === '--config' && i + 1 < args.length) {
      result.configPath = args[i + 1];
      i++;
    } else if (arg === '--save' && i + 1 < args.length) {
      result.saveOutput = args[i + 1];
      i++;
    } else if (arg === '--dry-run') {
      result.dryRun = true;
    } else if (arg === '--no-verify') {
      result.verify = false;
    } else if (arg === '--help' || arg === '-h') {
      console.log(`
TON Bridge Multisig Deployment Script

Usage:
  ts-node scripts/deploy-ton-multisig.ts [options]

Options:
  --network <mainnet|testnet>    Network to deploy to (default: from env TON_CHAIN)
  --config <path>                Path to JSON configuration file
  --save <path>                  Save deployment metadata to JSON file
  --dry-run                      Simulate deployment without sending transaction
  --no-verify                    Skip post-deployment verification
  --help, -h                     Show this help message

Environment Variables:
  TON_CHAIN                      Network: mainnet or testnet
  TONCENTER_API_KEY              API key for TonCenter
  TON_DEPLOYER_MNEMONIC          Deployer wallet mnemonic (v5r1)
  TON_DEPLOYER_PUBLIC_KEY_HEX    Alternative to mnemonic (64 hex chars)
  TON_DEPLOYER_SECRET_KEY_HEX    Alternative to mnemonic (64 hex chars)
  TON_MULTISIG_WATCHERS          Comma-separated watcher public keys (5)
  TON_MULTISIG_GOVERNANCE        Comma-separated governance public keys (5)
  TON_JETTON_ROOT                Primary jetton root address
  TON_MULTISIG_ALLOW_LIST        Comma-separated additional jetton addresses
  TON_MULTISIG_INIT_BALANCE      Initial balance in TON (default: 1.5)
  TON_MULTISIG_CODE_BOC          Path to precompiled BOC file

Examples:
  # Deploy to testnet using environment variables
  ts-node scripts/deploy-ton-multisig.ts

  # Deploy to mainnet with custom config and save result
  ts-node scripts/deploy-ton-multisig.ts --network mainnet --config config.json --save deployment.json

  # Dry run (no actual deployment)
  ts-node scripts/deploy-ton-multisig.ts --dry-run
`);
      process.exit(0);
    }
  }

  return result;
}

/**
 * Main execution
 */
async function main() {
  console.log('TON Bridge Multisig Deployment Script\n');

  const cliArgs = parseArgs();

  // Load configuration
  let config: DeploymentConfig;

  if (cliArgs.configPath) {
    console.log(`Loading configuration from: ${cliArgs.configPath}\n`);
    config = loadConfigFromFile(cliArgs.configPath);
  } else {
    console.log('Loading configuration from environment variables\n');
    config = loadConfigFromEnv();
  }

  // Override network if specified on command line
  if (cliArgs.network) {
    config.network = cliArgs.network;
    config.endpoint = config.network === 'mainnet'
      ? 'https://toncenter.com/api/v2/jsonRPC'
      : 'https://testnet.toncenter.com/api/v2/jsonRPC';
  }

  // Mainnet safety check
  if (config.network === 'mainnet' && !cliArgs.dryRun) {
    console.log('⚠️  WARNING: MAINNET DEPLOYMENT');
    console.log('='.repeat(80));
    console.log('Please ensure:');
    console.log('  1. Contract has been audited by reputable security firms');
    console.log('  2. All keys are from hardware wallets or secure key management');
    console.log('  3. Configuration has been triple-checked by multiple team members');
    console.log('  4. Emergency procedures and incident response plan are documented');
    console.log('  5. Team is ready for 24/7 monitoring post-deployment');
    console.log('  6. You have tested this exact configuration on testnet');
    console.log('='.repeat(80));
    console.log('\nPress Ctrl+C to cancel, or wait 10 seconds to continue...\n');
    await new Promise((resolve) => setTimeout(resolve, 10000));
  }

  // Deploy
  const deployResult = await deployBridgeMultisig(config, cliArgs.dryRun);

  if (cliArgs.dryRun) {
    console.log('\n✓ Dry run completed successfully');
    return;
  }

  // Initialize client for verification
  const client = new TonClient({
    endpoint: config.endpoint,
    apiKey: config.apiKey,
  });

  // Verify deployment
  let verified = false;
  if (cliArgs.verify) {
    const deployParams: DeployParams = {
      watchers: config.watcherPublicKeys.map(parsePublicKey),
      governance: config.governancePublicKeys.map(parsePublicKey),
      allowedJettons: config.allowedJettons,
    };

    verified = await verifyDeployment(client, deployResult.address, deployParams);
  } else {
    console.log('\n⚠️  Verification skipped (--no-verify flag)');
  }

  // Prepare result metadata
  const result: DeploymentResult = {
    network: config.network,
    contractAddress: deployResult.address.toString(),
    deployerAddress: deployResult.deployerAddress,
    txHash: deployResult.txHash,
    lt: deployResult.lt,
    deployedAt: new Date().toISOString(),
    watchers: config.watcherPublicKeys,
    governance: config.governancePublicKeys,
    allowedJettons: config.allowedJettons,
    initBalance: config.initBalance,
    verified,
  };

  // Save deployment metadata if requested
  if (cliArgs.saveOutput) {
    saveDeploymentResult(result, cliArgs.saveOutput);
  }

  // Final summary
  console.log('\n' + '='.repeat(80));
  console.log('DEPLOYMENT COMPLETE');
  console.log('='.repeat(80));
  console.log(`\nContract Address: ${result.contractAddress}`);
  console.log(`Network: ${config.network}`);
  console.log(`Explorer: https://tonviewer.com/${result.contractAddress}`);
  if (result.txHash) {
    console.log(`Transaction: ${result.txHash}`);
  }
  console.log(`Verification: ${verified ? 'PASSED' : 'FAILED'}`);
  console.log('\n' + '='.repeat(80));

  if (!verified && cliArgs.verify) {
    console.log('\n⚠️  WARNING: Verification failed! Please check the contract manually.');
    process.exit(1);
  }

  console.log('\n✓ Deployment successful!');
}

// Run if called directly
if (require.main === module) {
  main().catch((error) => {
    console.error('\n❌ Deployment failed:', error.message);
    if (error.stack) {
      console.error('\nStack trace:');
      console.error(error.stack);
    }
    process.exit(1);
  });
}

export {
  deployBridgeMultisig,
  verifyDeployment,
  loadConfigFromEnv,
  loadConfigFromFile,
  DeploymentConfig,
  DeploymentResult,
};
