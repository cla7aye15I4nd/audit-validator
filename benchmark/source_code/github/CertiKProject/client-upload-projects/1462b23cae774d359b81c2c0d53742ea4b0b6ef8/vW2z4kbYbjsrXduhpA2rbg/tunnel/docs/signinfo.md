# Sign Info

## Sign Spec

### Sign
- select * from db to struct
- get json of struct
- sha256 hash of json
- call kms sign, with message-type of DIGEST

### verify
- select * from db to struct
- pop signature
- get json of new struct
- sha256 hash
- call kms verify with DIGEST

### sign_info definition

```go
type SignInfo struct {
    Signatures [][]byte `json:"signatures"`
}
type History struct {
	// ...
	SignInfo  *SignInfo `db:"sign_info" json:"sign_info"`
}
```

- sign_info
  - signatures
    - use empty when signatures is null

> {"variable":"Ethereum-1-LatestBlockHeight","value":"21701257","created_at":"0000-01-01T00:00:00Z","updated_at":"2025-01-29T14:54:58Z","sign_info":{"signatures":[]}}

or 

> {"variable":"Ethereum-1-WithdrawMainAddress","value":"0xe7a3aF7f5f46C0e9b0e7324E94D96fAE59Fbd6D4","created_at":"2025-01-29T15:07:24Z","updated_at":"2025-01-30T12:04:47Z","sign_info":{"signatures":["pv3/6SJGcY1fgRgLLgDJ8HtYWNL9SF7P7lgOugwjyeg=","HHA3V7NleX9kZ1aO/C1z6J0tny1EN0ePSB1h0+5yVbc="]}}




## Accounts of Chain
- no need to sign/verify


## AWS KMS Key ID

### Chains

Each chain has the following Key ID:

| KeyId                 | Desc                               |
|-----------------------|------------------------------------|
| ChainKeyId            | Encrypt/Decrypt Keystore           |
| ChainAPISignKeyId     | chain api                          |
| ChainTaskSignKeyId    | chain tasks                        |
| ChainManagerSignKeyId | chain manager run, for merge asset |
| MonitorSignKeyId      | monitor, used for Deposit          |

the `config.newton.mainnet.toml` is as follows:

```
[[Tunnel.Blockchain]]
    ChainAPIHost = "127.0.0.1:8301" # the grpc api host
    Slug = "newton"
    Network = "Newton"
    ChainId = "1012"
    BaseChain = "NewChain"
    ChainKeyId: "arn:aws:kms:ap-northeast-1:281906612721:key/efd90ce7-eb4b-495c-8450-c87bef885398" 
    ChainAPISignKeyId = "alias/NewFiTestNetBridgeSignKey"
    ChainTaskSignKeyId = "alias/NewFiTestNetBridgeSignKey"
    ChainManagerSignKeyId = "alias/NewFiTestNetBridgeSignKey"
    MonitorSignKeyId = "alias/NewFiTestNetBridgeSignKey"
```

### Core/API

For system:

| KeyId               | Desc                                       |
|---------------------|--------------------------------------------|
| APISignKeyId        | tunnel api                                 |
| ManagerAPISignKeyId | tunnel api --manager                       |
| CoreSignKeyId       | tunnel cre                                 |
| ToolsSignKeyId      | some tools, for manager pairs, approve txs |

part of `config.toml`:

```
APISignKeyId = "alias/NewFiTestNetBridgeSignKey"
ManagerAPISignKeyId = "alias/NewFiTestNetBridgeSignKey"
CoreSignKeyId = "alias/NewFiTestNetBridgeSignKey"
ToolsSignKeyId = "alias/NewFiTestNetBridgeSignKey"
```







