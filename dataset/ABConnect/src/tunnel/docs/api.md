## Tunnel API

- Endpoint: https://api.end.point.to.be.replaced

------------------------------------------------------------------------------------------

### Struct

<details>
 <summary><code><b>Blockchain</b></code></summary>

####

> | name         | value                                                    | desc                                                                        |
> |--------------|----------------------------------------------------------|-----------------------------------------------------------------------------|
> | `network`    | `Ethereum`, `Bitcoin`, `Newton`, `Dogelayer`, `Dogecoin` | blockchain network name                                                     |
> | `chain_id`   | `1`, `1012` or `main`, `test`                            | get from rpc, `eth_chainId` for ethereum or `getblockchaininfo` for bitcoin |
> | `base_chain` | `Ethereum`, `NewChain`, `Bitcoin`, `Dogecoin`            | Base chain                                                                  |
> | `slug`       | uuid                                                     | uid string                                                                  |

##### Example

> | network   | chain_id | base_chain | slug              |
> |-----------|----------|------------|-------------------|
> | Newton    | 1012     | NewChain   | newton            |
> | Ethereum  | 1        | Ethereum   | ethereum          |
> | Bitcoin   | main     | Bitcoin    | bitcoin           |
> | Dogecoin  | main     | Dogecoin   | dogecoin          |
> | Dogelayer | 9888     | Ethereum   | dogelayer         |
> | Newton    | 1007     | NewChain   | newton-testnet    |
> | Ethereum  | 11155111 | Ethereum   | ethereum-sepolia  |
> | Bitcoin   | test     | Bitcoin    | bitcoin-test      |
> | Dogecoin  | test     | Dogecoin   | dogecoin-test     |
> | Dogelayer | 16888    | Ethereum   | dogelayer-testnet |

</details>


<details>
 <summary><code><b>Asset</b></code></summary>

####

> | name       | desc                                       |
> |------------|--------------------------------------------|
> | asset      | empty for native coin or address for token | 
> | name       | name                                       |
> | symbol     | symbol                                     |
> | decimals   | 0-18                                       |
> | asset_type | `Coin`, `ERC-20`, `NRC-6`, `BRC-20`        |
> | network    | Blockchain.network                         |
> | chain_id   | Blockchain.chain_id                        |
> | base_chain | Blockchain.base_chain                      |
> | Slug       | Blockchain.slug                            |

##### Example

> | asset                                      | name       | symbol | decimal | asset_type | network  | chain_id | base_chain | slug     | desc                     |
> |--------------------------------------------|------------|--------|---------|------------|----------|----------|------------|----------|--------------------------|
> |                                            | Newton     | NEW    | 18      | Coin       | Newton   | 1012     | NewChain   | newton   | newton native asset      |
> |                                            | Ethereum   | ETH    | 18      | Coin       | Ethereum | 1        | Ethereum   | ethereum | ethereum native asset    |
> |                                            | Bitcoin    | BTC    | 8       | Coin       | Bitcoin  | main     | Bitcoin    | bitcoin  | bitcoin natvie asset     |
> | 0xdAC17F958D2ee523a2206206994597C13D831ec7 | Tether USD | USDT   | 6       | ERC-20     | Ethereum | 1        | Ethereum   | ethereum | USDT on Ethereum mainnet |

</details>

------------------------------------------------------------------------------------------

### API

<details>
 <summary><code>GET</code> <code><b>/v1/tunnel/networks</b></code> <code>(get networks)</code></summary>

#### Parameters

> None

#### Responses

array of `Blockchain`

#### Example cURL

> ```javascript
>  curl http://localhost:9399/v1/tunnel/networks
> ```

```json
{
  "networks": [
    {
      "network": "Newton",
      "chain_id": "1012",
      "base_chain": "NewChain",
      "slug": "newton"
    },
    {
      "network": "Ethereum",
      "chain_id": "11155111",
      "base_chain": "Ethereum",
      "slug": "ethereum"
    },
    {
      "network": "Dogelayer",
      "chain_id": "16888",
      "base_chain": "Ethereum",
      "slug": "dogelayer"
    },
    {
      "network": "Dogecoin",
      "chain_id": "test",
      "base_chain": "Dogecoin",
      "slug": "dogecoin"
    }
  ]
}
```

</details>

<details>
 <summary><code>GET</code> <code><b>/v1/tunnel/pairs</b></code> <code>(get pairs)</code></summary>

#### Parameters

> None

#### Responses

> | name                     | value                | desc                                |
> |--------------------------|----------------------|-------------------------------------|
> | `asset_a`                | `Asset`              | asset_a                             |
> | `asset_b`                | `Asset`              | asset_b                             |
> | `a2b_min_deposit_amount` | big int              | min deposit amount for asset a to b |
> | `b2a_min_deposit_amount` | big int              | min deposit amount for asset b to a |
> | `a2b_fee_percent`        | float, base on 10000 | fee percent for asset a to b        |
> | `b2a_fee_percent`        | float, base on 10000 | fee percent for asset b to a        |
> | `a2b_fee_min_amount`     | big int              | min fee for asset a to b            |
> | `b2a_fee_min_amount`     | big int              | min fee for asset b to a            |
> | `bridge_pair`            | string               | merge of blockchain slug for a-b    |


#### Example cURL

> ```javascript
>  curl http://localhost:9399/v1/tunnel/pairs
> ```

```json
{
  "pairs": [
    {
      "asset_a": {
        "asset": "0x9Fc54AAAd8ED0085CAE87e1c94F2b19eE10a1653",
        "name": "Tether USD",
        "symbol": "USDT",
        "decimals": 6,
        "asset_type": "ERC20",
        "network": "Ethereum",
        "chain_id": "11155111",
        "base_chain": "Ethereum",
        "slug": "ethereum"
      },
      "asset_b": {
        "asset": "0x95bD0804D9ddFe616316f6769E282510E1b8644f",
        "name": "Tether USD",
        "symbol": "USDT",
        "decimals": 6,
        "asset_type": "ERC20",
        "network": "Dogelayer",
        "chain_id": "16888",
        "base_chain": "Ethereum",
        "slug": "dogelayer"
      },
      "a2b_min_deposit_amount": "0",
      "b2a_min_deposit_amount": "0",
      "a2b_fee_percent": "0.000000",
      "b2a_fee_percent": "0.000000",
      "a2b_fee_min_amount": "0",
      "b2a_fee_min_amount": "0",
      "bridge_pair": "ethereum-dogelayer"
    }
  ]
}
```

</details>

<details>
 <summary><code>GET</code> <code><b>/v1/tunnel/account</b></code> <code>(get account's deposit address)</code></summary>

#### Parameters

> | name                   | value     | desc                                                                       |
> |------------------------|-----------|----------------------------------------------------------------------------|
> | `recipient_address`    | `address` | recipient address on recipient blockchain, user's address to receive asset |
> | `recipient_blockchain` | `slug`    | slug of recipient blockchain                                               | 
> | `deposit_blockchain`   | `slug`    | slug of deposit blockchain                                                 |

#### Responses

> | name                   | value     | desc                                                                       |
> |------------------------|-----------|----------------------------------------------------------------------------|
> | `recipient_address`    | `address` | recipient address on recipient blockchain, user's address to receive asset |
> | `recipient_blockchain` | `slug`    | slug of recipient blockchain                                               | 
> | `deposit_blockchain`   | `slug`    | slug of deposit blockchain                                                 |
> | `deposit_address`      | `address` | deposit address on deposit blockchain, which used for use to send asset to |


#### Example cURL

> ```javascript
>  curl http://127.0.0.1:9399/v1/tunnel/account?recipient_address=0xD7bfFc191f5a9F70002E6b887Ea9e0146c6c8d3C&&recipient_blockchain=dogelayer&deposit_blockchain=ethereum
> ```

```json
{
  "recipient_address": "0xD7bfFc191f5a9F70002E6b887Ea9e0146c6c8d3C",
  "recipient_blockchain": "dogelayer",
  "deposit_address": "0x1E01e9CA1AB80F66Fba09905076F9Ba7071B8853",
  "deposit_blockchain": "ethereum"
}
```

</details>

<details>
 <summary><code>GET</code> <code><b>/v1/tunnel/history</b></code> <code>(get all history or account's history)</code></summary>

#### Parameters

> | name         | value                     | desc                              |
> |--------------|---------------------------|-----------------------------------|
> | `page_id`    | uint64                    | `Optional`, page id, default 0    |
> | `page_size`  | 50                        | `Optional`, page size, default 50 |
> | `address`    | `address` on `blockchain` | Base chain                        |
> | `blockchain` | `slug` of `blockchain`    | slug of blockchain                |

if `address` and `blockchain` is empty, return all history 

#### Responses


> | name     | value     | desc           |
> |----------|-----------|----------------|
> | `status` | `Deposit` | current status |

##### Example cURL

> ```javascript
>  curl http://localhost:9399/v1/tunnel/history
> ```

```json
{
  "page_id": "1",
  "page_size": "1",
  "total_page": "22",
  "total_history": "21",
  "list": [
    {
      "source_slug": "dogelayer",
      "source_network": "Dogelayer",
      "source_chain_id": "16888",
      "source_base_chain": "Ethereum",
      "destination_slug": "ethereum",
      "destination_network": "Ethereum",
      "destination_chain_id": "11155111",
      "destination_base_chain": "Ethereum",
      "source_address": "0x7Ba73d7930Ae5Ac28A042ca911b2592c49310C55",
      "destination_address": "0xD7bfFc191f5a9F70002E6b887Ea9e0146c6c8d3C",
      "source_tx_hash": "0x1d1d7acf2bba37495c297835e4e15f8f727bb81013804ff187bec5b1f6f9be3f",
      "destination_tx_hash": "0xc8a82fd58d3387903a945535e79cc0aa07a500cb0bc3cfec590658d69c678b8c",
      "source_asset_id": "20",
      "source_asset_address": "0x4DB3A8Ec8fa794ED03025f2aF8E4Ed929c40e1B7",
      "source_asset_name": "Newton",
      "source_asset_symbol": "NEW",
      "source_asset_decimals": 18,
      "source_asset_type": "ERC20",
      "destination_asset_id": "21",
      "destination_asset_address": "0x13439AD092d2D54ED958b1C0E65620721aB0aB2a",
      "destination_asset_name": "Newton",
      "destination_asset_symbol": "NEW",
      "destination_asset_decimals": 18,
      "destination_asset_type": "ERC20",
      "source_amount": "1000",
      "destination_amount": "950",
      "fee": "50",
      "status": "Confirmed",
      "statusMessage": "Confirmed"
    }
  ],
  "address": "",
  "blockchain": ""
}
```

</details>


------------------------------------------------------------------------------------------
