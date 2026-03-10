## Deploy for AB Core and AB IoT

require:
- [depoly-AB](./depoly-AB.md)
- [Depoly NewUSDT@ABCore](./depoly-usda.md)

- USDT@TronNile <=> NUSDT@ABCore

### build from source

for AB-Core and ethereum, `make` and use `tunnel`,

for Tron,

```bash
git clone git@gitlab.weinvent.org:yangchenzhong/tunnel-tron.git
cd tunnel-tron
GOPRIVATE=gitlab.weinvent.org go get gitlab.weinvent.org/yangchenzhong/tunnel@latest
make
```

`make` and use `tunnel-tron`

### database

use `accounts_kms.sql` to create a separate accounts database for `tron`.

### config.toml

- cp `config.blockchain.default.toml` as `config.tron.toml`
- update `config.toml` add `tron` blockchain

### Add New Blockchain

```bash
# tunnel bc add <network> <chainId> <BaseChain>
# mainnet
./tunnel -c config.toml bc add Tron niletestnet Tron
```

### Run Blockchain API

```bash
# Chain API, use tunnel-newton for newton 
./tunnel-tron -c config.tron.toml chain api

# Chain main address init
./tunnel-tron -c config.tron.toml chain init
```



### add asset

```bash
# tunnel asset add <BlockchainId:AssetTickOrTokenAddress:Slug:Symbol:Decimals:attribute:AssetType>


# add USDT and NUSDT
./tunnel asset add 8:0xdf72F39AB271ae7b13618468f4801Bb679e6b595::::mint:ERC20
./tunnel asset add 10:TXYZopYRdj2D9XRtbG411XZZ3kM5VkAeBf::::transfer:TRC20
```


### add pair

get `assetId` from `./tunnel asset list`.

```bash
# tunnel pair add <AssetIdA:minDepositAmountInDecimals:withdrawFeePercent:withdrawFeeMinInDecimals:AutoDepositConfirmAmountInDecimals> <AssetIdB:attribute:minDepositAmountInDecimals:withdrawFeePercent:withdrawFeeMinInDecimals:AutoDepositConfirmAmountInDecimals>
# MUST AssetIdA < AssetIdB
# ABCore-NUSDT to Tron-USDT, fee is 2 USDT/NUSDT
./tunnel pair add 12:3:0:2:100000000 13:3:0:2:100000000
```

### run chain tasks

```bash

# Chain tasks
./tunnel-tron -c config.tron.toml chain tasks

# monitor detected
./tunnel-tron -c config.tron.toml monitor --detected

# monitor
./tunnel-tron -c config.tron.toml monitor

# manager
./tunnel-newton -c config.tron.toml chain manager run
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

```bash
# run manager api
./tunnel -c config.toml api --manager
# run manager api http
./tunnel -c config.toml api --manager --http
```
