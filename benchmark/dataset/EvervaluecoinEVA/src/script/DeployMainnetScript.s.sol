// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {OrderBookFactory} from "../src/OrderBookFactory.sol";
import "forge-std/console.sol";
import "../src/interface/IOrderBookFactory.sol";

/// @title DeployMainnetScript - Script to deploy OrderBookFactory on the mainnet and set up order books
/// @notice This script deploys the OrderBookFactory contract and sets up an order book for trading pairs
/// @dev Uses Foundry's `Script` library for deployment automation, loading private keys from environment variables
contract DeployMainnetScript is Script {
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

    /// @notice Runs the deployment process for the OrderBookFactory and sets up order books
    /// @dev Loads private keys from environment variables, deploys contracts, and configures trading pairs
    function run() external {
        // ORDERBOOKFACTORY DEPLOYMENT
        // @dev Loads the deployer's private key for the OrderBookFactory contract from the `PRIVATE_KEY_MAINNET` environment variable
        uint256 deployerOrderBookFactoryPrivateKey = vm.envUint("PRIVATE_KEY_MAINNET");

        // @dev Starts broadcasting transactions for the OrderBookFactory deployment
        vm.startBroadcast(deployerOrderBookFactoryPrivateKey);

        // @dev Deploys the OrderBookFactory contract and assigns it to `orderBookFactory`
        OrderBookFactory orderBookFactoryInstance = new OrderBookFactory();

        // @dev Stops broadcasting transactions after OrderBookFactory deployment
        vm.stopBroadcast();

        // @notice Logs the deployed OrderBookFactory contract address
        console.log("Deployed OrderBookFactory contract at address:", address(orderBookFactoryInstance));

        // CREATE ORDER BOOK AND SETUP TRADING PAIR
        // @dev Converts orderBookFactoryInstance to the IOrderBookFactory interface
        orderBookFactory = IOrderBookFactory(address(orderBookFactoryInstance));

        // @dev Creates a new OrderBook struct with specified token addresses and fee details
        OrderBook memory newOrderBook = OrderBook({
            tokenA: vm.envAddress("ADDRESS_WBTC"), // WBTC
            tokenB: vm.envAddress("ADDRESS_EVA"), // EVA
            fee: vm.envUint("FEE_MAINNET"),
            feeAddress: vm.envAddress("FEE_ADDRESS_MAINNET")
        });

        // @dev Adds the new OrderBook instance to the orderBooks array
        orderBooks.push(newOrderBook);

        // ADDING PAIRS TO ORDERBOOKFACTORY
        // @dev Loads the deployer's private key to add pairs to the OrderBookFactory
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_MAINNET");
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
