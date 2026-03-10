## Deploy

### Add New Blockchain

1. add blockchain

```bash
# tunnel bc add <network> <chainId> <BaseChain>
# mainnet
./tunnel add Newton 1012 NewChain
./tunnel add Ethereum 1 Ethereum
./tunnel add Bitcoin main Bitcoin
./tunnel add Dogecoin main Dogecoin

# testnet
./tunnel add Newton 1007 NewChain
./tunnel add Ethereum 11155111 Ethereum
./tunnel add Bitcoin test Bitcoin
./tunnel add Dogecoin test Dogecoin

# dogelayer
./tunnel add Dogelayer 9888 Ethereum
./tunnel add Dogelayer 16888 Ethereum
```

2. add asset

```bash
# tunnel asset add <BlockchainId:AssetTickOrTokenAddress:Slug:Symbol:Decimals:attribute:AssetType>
# add native coin
./tunnel asset add 1::Newton:NEW:18:transfer:Coin
# add token
./tunnel asset add "6:0x9Fc54AAAd8ED0085CAE87e1c94F2b19eE10a1653:Tether USD:USDT:6:transfer:ERC20"
```

3. add pair

get `assetId` from `./tunnel asset list`.

```bash
# tunnel pair add <AssetIdA:minDepositAmountInDecimals:withdrawFeePercent:withdrawFeeMinInDecimals:AutoDepositConfirmAmountInDecimals> <AssetIdB:attribute:minDepositAmountInDecimals:withdrawFeePercent:withdrawFeeMinInDecimals:AutoDepositConfirmAmountInDecimals>
# AssetIdA < AssetIdB
./tunnel pair add 1:0:0.003:1:10 2:1000:0.003:1:10
```

### Run Blockchain

1. monitor
   - run node for WalletRPC 
   - run `./tunnel monitor` for WalletKMS
2. chain api (both WalletRPC and WalletKMS)
    - RPC: proxy of node wallet rpc
3. chain tasks
    - RPC: proxy of node wallet sendTx
4. chain manager merge (optional, only for WalletKMS)

### Run tunnel

1. tunnel core
2. tunnel api
3. tunnel api http

## TODO
- restart all monitor of WalletKMS after new pair added