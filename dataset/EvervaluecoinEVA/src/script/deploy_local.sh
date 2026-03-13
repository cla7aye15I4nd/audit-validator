#!/bin/sh

# Deploy OrderbookFactory Local
echo "Deploy LocalHost"
source .env && forge script script/DeployLocalHostScript.s.sol --rpc-url $RPC_LOCAL_URL --broadcast --private-key $PRIVATE_KEY_LOCAL