# OrderBook Smart Contract

## Overview

The OrderBook Smart Contract is an on-chain decentralized exchange (DEX) implementation that aims to provide a fully transparent and efficient trading platform for ERC20 tokens on the Ethereum blockchain. Unlike traditional Automated Market Maker (AMM) based DEXes, this system implements a limit order book model, similar to those used in centralized exchanges.

Key features of this implementation include:

1. **On-Chain Order Book**: All orders are stored and matched directly on the Arbitrum blockchain, ensuring full transparency and eliminating the need for trusted intermediaries.

2. **Limit Orders**: Users can place buy or sell orders at specific prices, allowing for more sophisticated trading strategies compared to AMM-based DEXes.

3. **Efficient Matching**: The contract uses a Red-Black Tree data structure for efficient order storage and matching, optimizing gas costs for trading operations.

4. **Multiple Trading Pairs**: The system supports multiple trading pairs, allowing users to trade various ERC20 tokens against each other.

5. **Factory Pattern**: An OrderBookFactory contract is used to deploy and manage multiple order books, making it easy to add new trading pairs.

The smart contract system is designed to balance efficiency, security, and decentralization, providing traders with a robust platform for on-chain limit order trading.

## Contract Architecture

The OrderBook system consists of several interconnected contracts and libraries, each serving a specific purpose:

1. **OrderBookFactory.sol**:
    - Main entry point for creating and managing order books
    - Deploys new order book contracts for different trading pairs
    - Maintains a registry of all deployed order books

2. **OrderBookLib.sol**:
    - Core logic for the order book functionality
    - Handles order placement, cancellation, and matching
    - Interacts with PairLib and RedBlackTreeLib for order management

3. **PairLib.sol**:
    - Manages trading pair information
    - Handles token transfers and balance tracking for each pair

4. **QueueLib.sol**:
    - Implements a queue data structure
    - Used for managing the order of limit orders at the same price point

5. **RedBlackTreeLib.sol**:
    - Implements a Red-Black Tree data structure
    - Provides efficient order storage and retrieval based on price

6. **Interface Directory**:
    - Contains interface definitions for the main contracts
    - Ensures proper interaction between different components of the system

This modular architecture allows for easy maintenance, upgrades, and testing of individual components while maintaining a cohesive overall system.

For detailed information on the contract architecture please refer our [documentation](./docs/src/SUMMARY.md)

## Functional Requirements

### Roles

1. **Trader**: Any user who can place, cancel, or execute orders.
2. **Admin**: The entity responsible for managing the OrderBookFactory and deploying new order books.

### Features and Use Cases

1. **Order Management**
    - Place a limit order (buy or sell)
    - Cancel an existing order
    - Modify an existing order (cancel and replace)

2. **Order Execution**
    - Execute a market order against existing limit orders
    - Partial filling of orders
    - Automatic matching of compatible orders

3. **Token Pair Management**
    - Add new trading pairs through the OrderBookFactory
    - View available trading pairs

4. **Order Book Queries**
    - View the current state of the order book (bid/ask spreads)
    - Retrieve best bid and ask prices
    - Get order details by order ID

5. **User Account Operations**
    - View user's open orders

6. **Admin Functions**
    - Deploy new order books for token pairs
    - Pause/unpause trading (emergency function)
   
7. **Market Data**
    - Access real-time pricing data

8. **Fee Management**
    - Set and adjust fee rates
    - Distribute fees to designated recipients

### Installation

1. Clone the repository:
    ```bash
    git clone https://github.com/devervalue/orderbook.git
    ```
2. Install dependencies:
    ```bash 
    forge install
    ```
### Running Tests
To run the full test suite:
```bash
forge test
 ```
To run a specific test file:
```bash
forge test --match-path test/QueueLibTest.sol
 ```

### Test Coverage
To generate a test coverage report:
```bash
forge coverage
 ```

### Deployment
To deploy the contracts to a local network, first set up your environment variables:
```bash
export PRIVATE_KEY_LOCAL=your_private_key
export RPC_LOCAL_URL=your_rpc_url
export PRIVATE_KEY_TOKEN_A=token_A_deployer_private_key
export PRIVATE_KEY_TOKEN_B=token_B_deployer_private_key
export FEE_LOCAL=100 (amount in basis points - 100 is 1%)
export FEE_ADDRESS_LOCAL=address_that_will_be_receiving_the_pair_fees
 ```
Then run de local deployment script:
```bash
./script/deploy_local.sh
 ```
To deploy to a testnet or mainnet, first set up your environment variables:
```bash
export PRIVATE_KEY_MAINNET=your_private_key
export RPC_MAINNET_URL=your_rpc_url
export ADDRESS_WBTC=WBTC_TOKEN_ADDRESS
export ADDRESS_EVA=EVA_TOKEN_ADDRESS
export FEE_MAINNET=100 (amount in basis points - 100 is 1%)
export FEE_ADDRESS_MAINNET=address_that_will_be_receiving_the_pair_fees
 ```
Then run the deployment script:
```bash
./script/deploy_mainnet.sh
 ```

For more detailed information on using Foundry, please refer to the [Foundry Book](https://book.getfoundry.sh/).