## Deploy for AB Core and AB IoT

- AB@ABCore <=> AB@ABIoT

### build from source

for AB-Core and ethereum, `make` and use `tunnel`,

for AB-IoT, `make newton` and use `tunnel-newton`

### database

Use `tunnel.sql` to create a shared `tunnel` database, and use `accounts_kms.sql` to create a separate accounts database for each blockchain.

### config.toml

- cp `config.default.toml` as `config.toml` and update it for `tunnel`
- cp `config.blockchain.default.toml` as `config.abiot.toml` and `config.abcore.toml`

### Add New Blockchain

```bash
# tunnel bc add <network> <chainId> <BaseChain>
# mainnet
./tunnel -c config.toml bc add ABIoT 1012 NewChain
./tunnel -c config.toml bc add ABCore 26988 Ethereum
./tunnel -c config.toml bc add Ethereum 1 Ethereum
```

### Run Blockchain API

```bash
# Chain API, use tunnel-newton for newton 
./tunnel-newton -c config.abiot.toml chain api
./tunnel -c config.abcore.toml chain api

# Chain main address init
./tunnel-newton -c config.abiot.toml chain init
./tunnel -c config.abcore.toml chain init
```



### add asset

```bash
# tunnel asset add <BlockchainId:AssetTickOrTokenAddress:Slug:Symbol:Decimals:attribute:AssetType>
# add native coin
./tunnel asset add 1::AB:AB:18:transfer:Coin
./tunnel asset add 2::AB:AB:18:transfer:Coin
./tunnel asset add 3::Ethereum:ETH:18:transfer:Coin


# add USDT and NUSDT
./tunnel asset add 3:0xdac17f958d2ee523a2206206994597c13d831ec7::::transfer:ERC20
./tunnel asset add 2:0x27893305289c3B149ad3c245a6feFB549e875BBb::::mint:ERC20
```


### add pair

get `assetId` from `./tunnel asset list`.

```bash
# tunnel pair add <AssetIdA:minDepositAmountInDecimals:withdrawFeePercent:withdrawFeeMinInDecimals:AutoDepositConfirmAmountInDecimals> <AssetIdB:attribute:minDepositAmountInDecimals:withdrawFeePercent:withdrawFeeMinInDecimals:AutoDepositConfirmAmountInDecimals>
# MUST AssetIdA < AssetIdB
# ABIoT-AB to ABCore-AB, fee is 0 NEW
./tunnel pair add 1:0:0:0:100000000 3:0:0:0:100000000
# Ethereum-USDT to NewtonFi-NUSDT, fee is 10 USDT/NUSDT
./tunnel pair add 4:0:0:5:100000000 6:0:0:5:100000000
```

### run chain tasks

```bash

# Chain tasks
./tunnel-newton -c config.abiot.toml chain tasks
./tunnel -c config.abcore.toml chain tasks

# monitor detected
./tunnel-newton -c config.abiot.toml monitor --detected
./tunnel -c config.abcore.toml monitor --detected

# monitor
./tunnel-newton -c config.abiot.toml monitor
./tunnel -c config.abcore.toml monitor

# manager
./tunnel-newton -c config.abiot.toml chain manager run
./tunnel -c config.abcore.toml chain manager run
```

### Run tunnel

```bash
# run exchange core
./tunnel -c config.toml core
# run api
./tunnel -c config.toml api
# run api http
./tunnel -c config.toml api --http
```

for manager:

```
# run manager api
./tunnel -c config.toml api --manager
# run manager api http
./tunnel -c config.toml api --manager --http
```
