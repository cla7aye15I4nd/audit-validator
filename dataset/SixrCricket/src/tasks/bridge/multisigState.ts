import { task, types } from 'hardhat/config';
import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { Contract } from 'ethers';

interface MultisigStateArgs {
  address?: string;
}

task('bridge:multisig:state', 'Query and display BridgeMultisig contract state')
  .addOptionalParam(
    'address',
    'Contract address (defaults to deployment artifact)',
    undefined,
    types.string
  )
  .setAction(async (args: MultisigStateArgs, hre: HardhatRuntimeEnvironment) => {
    const { ethers, deployments, network } = hre;

    let contractAddress: string;
    let contract: Contract;

    // Resolve contract address
    if (args.address) {
      contractAddress = args.address;
      console.log(`Using provided contract address: ${contractAddress}`);
    } else {
      // Try to get from deployment artifact
      try {
        const deployment = await deployments.get('BridgeMultisig');
        contractAddress = deployment.address;
        console.log(`Using deployment artifact address: ${contractAddress}`);
      } catch (error) {
        console.error(`\nError: BridgeMultisig deployment artifact not found on network '${network.name}'`);
        console.error(`Please deploy the contract first or provide --address argument`);
        process.exit(1);
      }
    }

    // Validate address format
    if (!ethers.utils.isAddress(contractAddress)) {
      console.error(`\nError: Invalid contract address: ${contractAddress}`);
      process.exit(1);
    }

    // Get contract instance
    try {
      const BridgeMultisig = await ethers.getContractFactory('BridgeMultisig');
      contract = BridgeMultisig.attach(contractAddress);
    } catch (error) {
      console.error(`\nError: Failed to attach to BridgeMultisig contract at ${contractAddress}`);
      console.error(`Make sure the contract is deployed and the ABI is available`);
      console.error(`Error: ${error}`);
      process.exit(1);
    }

    // Verify contract exists at address
    try {
      const code = await ethers.provider.getCode(contractAddress);
      if (code === '0x' || code === '0x0') {
        console.error(`\nError: No contract found at address ${contractAddress}`);
        console.error(`The address may be incorrect or the contract may not be deployed`);
        process.exit(1);
      }
    } catch (error) {
      console.error(`\nError: Failed to verify contract at ${contractAddress}`);
      console.error(`Error: ${error}`);
      process.exit(1);
    }

    console.log(`\n========================================`);
    console.log(`BridgeMultisig State Query`);
    console.log(`========================================`);
    console.log(`Network:  ${network.name}`);
    console.log(`Address:  ${contractAddress}`);
    console.log(`========================================\n`);

    try {
      // Query watcher addresses
      console.log(`Fetching watcher addresses...`);
      const watchers = await contract.getWatchers();
      console.log(`\nWatchers (${watchers.length} addresses, 2-of-3 threshold):`);
      watchers.forEach((addr: string, i: number) => {
        console.log(`  [${i}] ${addr}`);
      });

      // Query governance addresses
      console.log(`\nFetching governance addresses...`);
      const governance = await contract.getGovernance();
      console.log(`\nGovernance (${governance.length} addresses, 3-of-5 threshold):`);
      governance.forEach((addr: string, i: number) => {
        console.log(`  [${i}] ${addr}`);
      });

      // Query governance nonce
      console.log(`\nFetching governance nonce...`);
      const governanceNonce = await contract.governanceNonce();
      console.log(`\nGovernance Nonce: ${governanceNonce.toString()}`);

      // Query allowed token statuses
      // Get allowed tokens from environment variable
      const tokensEnv = process.env.MULTISIG_ALLOWED_TOKENS;
      if (tokensEnv) {
        const tokenAddresses = tokensEnv.split(',').map((addr: string) => addr.trim());
        console.log(`\nAllowed Token Status (${tokenAddresses.length} tokens from MULTISIG_ALLOWED_TOKENS):`);

        for (const tokenAddr of tokenAddresses) {
          if (ethers.utils.isAddress(tokenAddr)) {
            try {
              const isAllowed = await contract.allowedTokens(tokenAddr);
              const status = isAllowed ? 'ALLOWED' : 'NOT ALLOWED';
              console.log(`  ${tokenAddr}: ${status}`);
            } catch (error) {
              console.log(`  ${tokenAddr}: ERROR (${error})`);
            }
          } else {
            console.log(`  ${tokenAddr}: INVALID ADDRESS`);
          }
        }
      } else {
        console.log(`\nAllowed Token Status: Not available (MULTISIG_ALLOWED_TOKENS not set)`);
        console.log(`To check token statuses, set MULTISIG_ALLOWED_TOKENS environment variable`);
      }

      console.log(`\n========================================`);
      console.log(`Query completed successfully`);
      console.log(`========================================\n`);

    } catch (error) {
      console.error(`\nError: Failed to query contract state`);
      console.error(`Make sure the contract is properly deployed and accessible`);
      console.error(`Error details: ${error}`);
      process.exit(1);
    }
  });
