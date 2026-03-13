## Tunnel Manager API

- Endpoint: https://api.end.point.to.be.replaced
- Base on [Tunnel API](./api.md)

------------------------------------------------------------------------------------------

### Struct

<details>
 <summary><code><b>AssetBalance</b></code></summary>

####

> | name                      | value             | desc                                                 |
> |---------------------------|-------------------|------------------------------------------------------|
> | `asset`                   | [Asset](./api.md) | Asset                                                |
> | `total_deposit`           | uint256           | total user's deposit from database                   |
> | `total_withdraw`          | uint256           | total user's withdraw or mint from database          |
> | `total_deposit_last_day`  | uint256           | total user's deposit from database   last day        |
> | `total_withdraw_last_day` | uint256           | total user's withdraw or mint from database last day |

</details>

------------------------------------------------------------------------------------------

### API

<details>
 <summary><code>GET</code> <code><b>/v1/tunnel/info</b></code> <code>(get system info)</code></summary>

#### Parameters

> | name                 | value                   | desc               |
> |----------------------|-------------------------|--------------------|
> | `only_system_config` | bool, `true` or `false` | only system config |

#### Responses

> | name    | value                 | desc          |
> |---------|-----------------------|---------------|
> | `key`   | `SC_AutoConfirm_`     | system config |
> | `value` | `enable` or `disable` |               |

#### Example cURL

> ```shell
>  curl http://localhost:9393/v1/tunnel/info?only_system_config=true
> ```

```json
{
  "status": "ok",
  "configs": [
    {
      "key": "SC_AutoConfirm",
      "value": "enable"
    }
  ]
}
```

</details>

<details>
 <summary><code>POST</code> <code><b>/v1/tunnel/config</b></code> <code>(set system config)</code></summary>

#### Parameters

> | name    | value                 | desc               |
> |---------|-----------------------|--------------------|
> | `key`   | `SC_AutoConfirm`      | only system config |
> | `value` | `enable` or `disable` |                    |                 |               

#### Responses

> | name     | value                  | desc               |
> |----------|------------------------|--------------------|
> | `key`    | `SC_AutoConfirm`       | only system config |
> | `value`  | `enable` or `disable`  |
> | `status` | `SUCCESS` or `FAILURE` |

#### Example cURL

> ```shell
>  curl -XPOST http://127.0.0.1:9393/v1/tunnel/config -d'{"key": "SC_Config", "value": "disable"}'
> ```

```json
{
  "key": "SC_Config",
  "value": "disable",
  "status": "SUCCESS"
}
```

</details>


<details>
 <summary><code>POST</code> <code><b>/v1/tunnel/pair/update</b></code> <code>(update pair info)</code></summary>

#### Parameters

> | name                              | value   | desc                                                              |
> |-----------------------------------|---------|-------------------------------------------------------------------|
> | `pair_id`                         | uint256 | the pair id, get from `/v1/tunnel/pairs`, it's also for the below |
> | `asset_a_id`                      | uint256 | asset A id                                                        |
> | `asset_b_id`                      | uint256 | asset B id                                                        |
> | `a2b_min_deposit_amount`          | string  | asset A min deposit amount                                        |
> | `b2a_min_deposit_amount`          | string  | asset B min deposit amount                                        |
> | `a2b_fee_percent`                 | string  | asset A to B fee percent                                          |
> | `a2b_fee_min_amount`              | string  | min fee amount                                                    |
> | `b2a_fee_min_amount`              | string  | min fee amount                                                    |
> | `a2b_auto_confirm_deposit_amount` | string  | asset A auto confirm deposit amount                               |
> | `b2a_auto_confirm_deposit_amount` | string  | asset B auto confirm deposit amount                               |
           

#### Responses

> | name         | value                  | desc                                                              |
> |--------------|------------------------|-------------------------------------------------------------------|
> | `pair_id`    | uint256                | the pair id, get from `/v1/tunnel/pairs`, it's also for the below |
> | `asset_a_id` | uint256                | asset A id                                                        |
> | `asset_b_id` | uint256                | asset B id                                                        |
> | `status`     | `SUCCESS` or `FAILURE` |

#### Example cURL

> ```shell
>  curl  -d '{"pair_id":1,"asset_a_id":1,"asset_b_id":3,"a2b_fee_min_amount":"11.55","b2a_fee_min_amount":"11.55"}' "http://127.0.0.1:9393/v1/tunnel/pair/update"
> ```

```json
{
  "pairId": "1",
  "asset_a_id": "1",
  "asset_b_id": "3",
  "status": "SUCCESS"
}
```

</details>

<details>
 <summary><code>POST</code> <code><b>/v1/tunnel/approve</b></code> <code>(set system config)</code></summary>

#### Parameters

> | name    | value                 | desc               |
> |---------|-----------------------|--------------------|
> | `key`   | `SC_AutoConfirm_`     | only system config |
> | `value` | `enable` or `disable` |                    |               

#### Responses

> | name             | value   | desc           |
> |------------------|---------|----------------|
> | `history_id`     | uint256 |                |
> | `source_tx_hash` | hex     | source tx hash |

#### Example cURL

> ```shell
>  curl -XPOST http://127.0.0.1:9393/v1/tunnel/approve -d'{"history_id":13,"source_tx_hash":"0x9a18eb36789cfbb59891b17b24fdbf2876324b6dddb53407fe2d818860cbbdf6"}'
> ```

```json
{
  "history_id": "13",
  "status": "SUCCESS"
}
```

</details>



<details>
 <summary><code>GET</code> <code><b>/v1/tunnel/balance</b></code> <code>(get system balance)</code></summary>

#### Parameters

>              

#### Responses

> | name       | value          | desc |
> |------------|----------------|------|
> | `balances` | `AssetBalance` |      |

#### Example cURL

> ```shell
>  curl http://127.0.0.1:9393/v1/tunnel/balance
> ```

```json
{
  "blockchains": [
    {
      "blockchain_id": "1",
      "blockchain": {
        "network": "Newton",
        "chain_id": "1012",
        "base_chain": "NewChain",
        "slug": "newton"
      },
      "balances": [
        {
          "asset": {
            "id": "1",
            "asset": "",
            "name": "Newton",
            "symbol": "NEW",
            "decimals": 18,
            "asset_type": "Coin",
            "network": "Newton",
            "chain_id": "1012",
            "base_chain": "NewChain",
            "slug": "newton"
          },
          "total_deposit": "1346000000000000000000",
          "total_withdraw": "828400000000000000000",
          "total_deposit_last_day": "200000000000000000000",
          "total_withdraw_last_day": "176900000000000000000"
        }
      ]
    },
    {
      "blockchain_id": "3",
      "blockchain": {
        "network": "NewtonFi",
        "chain_id": "26988",
        "base_chain": "Ethereum",
        "slug": "newtonfi"
      },
      "balances": [
        {
          "asset": {
            "id": "3",
            "asset": "",
            "name": "Newton",
            "symbol": "NEW",
            "decimals": 18,
            "asset_type": "Coin",
            "network": "NewtonFi",
            "chain_id": "26988",
            "base_chain": "Ethereum",
            "slug": "newtonfi"
          },
          "total_deposit": "904000000000000000000",
          "total_withdraw": "1301900000000000000000",
          "total_deposit_last_day": "200000000000000000000",
          "total_withdraw_last_day": "176900000000000000000"
        },
        {
          "asset": {
            "id": "6",
            "asset": "0x27893305289c3B149ad3c245a6feFB549e875BBb",
            "name": "NewUSDT",
            "symbol": "NUSDT",
            "decimals": 6,
            "asset_type": "ERC20",
            "network": "NewtonFi",
            "chain_id": "26988",
            "base_chain": "Ethereum",
            "slug": "newtonfi"
          },
          "total_deposit": "10000000",
          "total_withdraw": "97000000",
          "total_deposit_last_day": "0",
          "total_withdraw_last_day": "0"
        }
      ]
    },
    {
      "blockchain_id": "2",
      "blockchain": {
        "network": "Ethereum",
        "chain_id": "1",
        "base_chain": "Ethereum",
        "slug": "ethereum"
      },
      "balances": [
        {
          "asset": {
            "id": "4",
            "asset": "0xdAC17F958D2ee523a2206206994597C13D831ec7",
            "name": "Tether USD",
            "symbol": "USDT",
            "decimals": 6,
            "asset_type": "ERC20",
            "network": "Ethereum",
            "chain_id": "1",
            "base_chain": "Ethereum",
            "slug": "ethereum"
          },
          "total_deposit": "100000000",
          "total_withdraw": "7000000",
          "total_deposit_last_day": "0",
          "total_withdraw_last_day": "0"
        }
      ]
    }
  ]
}
```

</details>

------------------------------------------------------------------------------------------
