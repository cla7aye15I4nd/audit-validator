// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import "forge-std/console.sol";
import "../test/TEVA.sol";
import "../test/TBTC.sol";

/// @title DeployLocalHostScript - Script to deploy OrderBookFactory, MyTokenA, and MyTokenB contracts
/// @notice This script deploys the OrderBookFactory, MyTokenA, and MyTokenB contracts, sets up order books, and adds trading pairs to the factory
/// @dev Uses Foundry's `Script` library for deployment automation, loading private keys from environment variables
contract DeployLocalHostScript is Script {

    /// @notice Runs the deployment process, including OrderBookFactory, MyTokenA, and MyTokenB
    /// @dev Loads private keys and fees from environment variables, deploys contracts, and sets up trading pairs
    function run() external {

        // TOKEN A DEPLOYMENT
        // @dev Loads the deployer's private key for MyTokenA from `PRIVATE_KEY_TOKEN_A` environment variable
        uint256 deployerTokenAPrivateKey = vm.envUint("PRIVATE_KEY_MAINNET");

        // @dev Starts broadcasting transactions for MyTokenA deployment
        vm.startBroadcast(deployerTokenAPrivateKey);

        // @dev Deploys the MyTokenA contract with max initial supply and assigns to `myTokenA`
        TBTC myTokenA = new TBTC(type(uint256).max);

        // @dev Stops broadcasting transactions after MyTokenA deployment
        vm.stopBroadcast();

        // @notice Logs the deployed MyTokenA contract address
        console.log("Deployed TBTC contract at address:", address(myTokenA));

        // TOKEN B DEPLOYMENT
        // @dev Loads the deployer's private key for MyTokenB from `PRIVATE_KEY_TOKEN_B` environment variable
        uint256 deployerTokenBPrivateKey = vm.envUint("PRIVATE_KEY_MAINNET");

        // @dev Starts broadcasting transactions for MyTokenB deployment
        vm.startBroadcast(deployerTokenBPrivateKey);

        // @dev Deploys the MyTokenB contract with max initial supply and assigns to `myTokenB`
        TEVA myTokenB = new TEVA();

        // @dev Stops broadcasting transactions after MyTokenB deployment
        vm.stopBroadcast();

        // @notice Logs the deployed MyTokenB contract address
        console.log("Deployed TEVA contract at address:", address(myTokenB));
    }
}
