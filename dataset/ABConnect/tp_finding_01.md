# Ineffective Wallet Clearing in execDogecoinTaskBatch


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🟠 Major |
| Triage Verdict | ✅ Valid |
| Project ID | `c30ae600-5a45-11f0-9989-739d017e346c` |
| Commit | `1462b23cae774d359b81c2c0d53742ea4b0b6ef8` |

## Location

- **Local path:** `./src/tunnel/chain/tasks_dogecoin.go`
- **ACC link:** https://acc.audit.certikpowered.info/project/c30ae600-5a45-11f0-9989-739d017e346c/source?file=$/github/CertiKProject/client-upload-projects/1462b23cae774d359b81c2c0d53742ea4b0b6ef8/vW2z4kbYbjsrXduhpA2rbg/tunnel/chain/tasks_dogecoin.go
- **Lines:** 327–334

## Description

Repository:
- `AB-Connect`

A private repo:
- Shasum256 value of `tunnel.zip`: `f3e429b0f77e51b372d1ad6d16859ce2077c86c9075882663f6783fd59e305cb`

Files:
- tunnel/chain/tasks_dogecoin.go

The function execDogecoinTaskBatch is responsible for loading private keys from disk and storing them in a map called wallets. A deferred function attempts to clear these keys to prevent memory disclosure. However, the current implementation does not populate the wallets map correctly, leaving it empty and rendering the clearing mechanism ineffective. The relevant code snippets are as follows:
```go=327
	wallets := make(map[string]*dogecoinWallet)
	defer func() {
		for _, w := range wallets {
			if w != nil && w.privateKey != nil {
				w.privateKey.Zero()
			}
		}
	}()
```
The issue arises because the wallets map is not populated when retrieving wallets using x.getWallet:
```go
				if wallets[address.String()] == nil {
					w, err = x.getWallet(address)
					if err != nil {
						log.Errorln("getWallet error: ", err)
						return
					}
				}

				if wallets[feeAddress.String()] == nil {
					feeWallet, err = x.getWallet(feeAddress)
					if err != nil {
						log.Errorln("getWallet error: ", err)
						return
					}
				}
```
Due to this oversight, the wallets map remains empty, and no private keys are cleared, leading to a potential Memory Disclosure Attack where private keys could be exposed in memory or paged to disk. Development tools and active attacks can look for it in memory.

## Recommendation

Ensure that the wallets map is correctly populated with the wallets retrieved by x.getWallet.

## Vulnerable Code

```
}

func (x *Chain) execDogecoinTaskBatch(taskBatch map[dbtcutil.Address]map[string]TaskTransactions,
	feeAddress dbtcutil.Address) {
	nodeClientConnConfig := drpcclient.ConnConfig{
		Host:         x.DogecoinConfig.RpcURL,
		Endpoint:     "ws",
		User:         x.DogecoinConfig.Username,
		Pass:         x.DogecoinConfig.Password,
		HTTPPostMode: true, // Bitcoin core only supports HTTP POST mode
		DisableTLS:   true, // Bitcoin core does not provide TLS by default
	}
	rpcClient, err := drpcclient.New(&nodeClientConnConfig, nil)
	if err != nil {
		log.Errorln(Error(err))
		return
	}

	indexerClient := NewDRC20Client(x.DogecoinConfig.IndexerURL)

	// blockbookClient := NewBlockBookClient(x.DogecoinConfig.BlockbookURL)

	sdbTasks, err := database.OpenDatabase(x.DB.Adapter, x.DB.ConnectionURL)
	if err != nil {
		log.Errorln(err)
		return
	}
	defer sdbTasks.Close()

	wallets := make(map[string]*dogecoinWallet)
	defer func() {
		for _, w := range wallets {
			if w != nil && w.privateKey != nil {
				w.privateKey.Zero()
			}
		}
	}()

	for address, txsBatch := range taskBatch {

		for tick, txs := range txsBatch {

			func() {
				fmt.Println(address, tick, len(txs))

				// ctx := context.Background()

				drc20Balance, err := indexerClient.Balance(tick, address)
				if err != nil {
					log.Errorln(Error(err))
					return
				}
				log.WithFields(logrus.Fields{
					"address": address.String(),
					"tick":    tick,
					"balance": drc20Balance.String(),
				}).Warnln("balance show")

				totalAmount := big.NewInt(0)

				sendTxList := make(TaskTransactions, 0)
				for _, tx := range txs {
					totalAmount.Add(totalAmount, tx.Value)

					sendTxList = append(sendTxList, tx)
				}
				if totalAmount.Cmp(drc20Balance) > 0 {
```
