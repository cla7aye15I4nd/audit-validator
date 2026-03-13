// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {OrderBookFactory} from "../src/OrderBookFactory.sol";
import "forge-std/console.sol";
import "../test/MyTokenA.sol";
import "../test/MyTokenB.sol";
import "../src/interface/IOrderBookFactory.sol";

/// @title DeployLocalHostScript - Script to deploy OrderBookFactory, MyTokenA, and MyTokenB contracts
/// @notice This script deploys the OrderBookFactory, MyTokenA, and MyTokenB contracts, sets up order books, and adds trading pairs to the factory
/// @dev Uses Foundry's `Script` library for deployment automation, loading private keys from environment variables
contract DeployLocalHostScript is Script {
    IOrderBookFactory public orderBookFactory;

    /// @notice Struct to store details of each OrderBook pair
    struct OrderBook {
        address tokenA;
        address tokenB;
        uint256 fee;
        address feeAddress;
    }

    /// @dev Array of order books to set up multiple trading pairs
    OrderBook[] public orderBooks;

    /// @notice Runs the deployment process, including OrderBookFactory, MyTokenA, and MyTokenB
    /// @dev Loads private keys and fees from environment variables, deploys contracts, and sets up trading pairs
    function run() external {
        // ORDERBOOKFACTORY DEPLOYMENT
        // @dev Loads the deployer's private key for the OrderBookFactory contract from the `PRIVATE_KEY` environment variable
        uint256 deployerOrderBookFactoryPrivateKey = vm.envUint("PRIVATE_KEY_LOCAL");

        // @dev Starts broadcasting transactions for the OrderBookFactory deployment
        vm.startBroadcast(deployerOrderBookFactoryPrivateKey);

        // @dev Deploys the OrderBookFactory contract and assigns it to `orderBookFactory`
        OrderBookFactory orderBookFactoryInstance = new OrderBookFactory();

        // @dev Stops broadcasting transactions after OrderBookFactory deployment
        vm.stopBroadcast();

        // @notice Logs the deployed OrderBookFactory contract address
        console.log("Deployed OrderBookFactory contract at address:", address(orderBookFactoryInstance));

        // TOKEN A DEPLOYMENT
        // @dev Loads the deployer's private key for MyTokenA from `PRIVATE_KEY_TOKEN_A` environment variable
        uint256 deployerTokenAPrivateKey = vm.envUint("PRIVATE_KEY_TOKEN_A");

        // @dev Starts broadcasting transactions for MyTokenA deployment
        vm.startBroadcast(deployerTokenAPrivateKey);

        // @dev Deploys the MyTokenA contract with max initial supply and assigns to `myTokenA`
        MyTokenA myTokenA = new MyTokenA(type(uint256).max);

        // @dev Stops broadcasting transactions after MyTokenA deployment
        vm.stopBroadcast();

        // @notice Logs the deployed MyTokenA contract address
        console.log("Deployed MyTokenA contract at address:", address(myTokenA));

        // TOKEN B DEPLOYMENT
        // @dev Loads the deployer's private key for MyTokenB from `PRIVATE_KEY_TOKEN_B` environment variable
        uint256 deployerTokenBPrivateKey = vm.envUint("PRIVATE_KEY_TOKEN_B");

        // @dev Starts broadcasting transactions for MyTokenB deployment
        vm.startBroadcast(deployerTokenBPrivateKey);

        // @dev Deploys the MyTokenB contract with max initial supply and assigns to `myTokenB`
        MyTokenB myTokenB = new MyTokenB(type(uint256).max);

        // @dev Stops broadcasting transactions after MyTokenB deployment
        vm.stopBroadcast();

        // @notice Logs the deployed MyTokenB contract address
        console.log("Deployed MyTokenB contract at address:", address(myTokenB));

        // CREATE ORDER BOOK AND SETUP TRADING PAIR
        // @dev Converts orderBookFactoryInstance to the IOrderBookFactory interface
        orderBookFactory = IOrderBookFactory(address(orderBookFactoryInstance));

        // @dev Creates a new OrderBook struct and adds it to the `orderBooks` array
        OrderBook memory newOrderBook = OrderBook({
            tokenA: address(myTokenA),
            tokenB: address(myTokenB),
            fee: vm.envUint("FEE_LOCAL"),
            feeAddress: vm.envAddress("FEE_ADDRESS_LOCAL")
        });

        // @dev Adds the new OrderBook instance to the orderBooks array
        orderBooks.push(newOrderBook);

        // ADDING PAIRS TO ORDERBOOKFACTORY
        // @dev Loads the deployer's private key to add pairs to the OrderBookFactory
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_LOCAL");
        vm.startBroadcast(deployerPrivateKey);

        // @dev Loops through the `orderBooks` array to add each pair to the OrderBookFactory
        for (uint256 i = 0; i < orderBooks.length; i++) {
            orderBookFactory.addPair(
                orderBooks[i].tokenA, orderBooks[i].tokenB, orderBooks[i].fee, orderBooks[i].feeAddress
            );
        }

        // @dev Stops broadcasting transactions after adding pairs
        vm.stopBroadcast();
    }
}
