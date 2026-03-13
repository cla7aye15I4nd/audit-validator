#!/bin/sh

# Deploy OrderbookFactory Mainnet
echo "Deploy Tokens Mainnet"
source .env && forge script script/DeployTestTokens.s.sol --rpc-url $RPC_MAINNET_URL --broadcast --private-key $PRIVATE_KEY_MAINNET