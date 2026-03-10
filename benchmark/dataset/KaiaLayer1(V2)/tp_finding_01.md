# The Tx Pool Can Accept `TxTypeEthereumSetCode` Transaction  Before The Prague Activated Could Enable Attackers To DoS It


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🟠 Major |
| Triage Verdict | ✅ Valid |
| Project ID | `9abd0390-085b-11f0-a65b-e3b852450e7f` |
| Commit | `3c8ad8536c9b9108df9b175ef6fe817c17d4b744` |

## Location

- **Local path:** `./src/blockchain/tx_pool.go`
- **ACC link:** https://acc.audit.certikpowered.info/project/9abd0390-085b-11f0-a65b-e3b852450e7f/source?file=$/github/kaiachain/kaia/3c8ad8536c9b9108df9b175ef6fe817c17d4b744/blockchain/tx_pool.go
- **Lines:** 704–915

## Description

Repository:
- `Kaia Chain`

Commits:
- [`3c8ad8536c9b9108df9b175ef6fe817c17d4b744`](https://github.com/kaiachain/kaia/tree/3c8ad8536c9b9108df9b175ef6fe817c17d4b744)

Files:
- `blockchain/tx_pool.go`
- `blockchain/blockchain.go`
- `blockchain/types/transaction.go`

The `validateTx` function in the transaction pool (`TxPool`) fails to enforce the `Prague` hardfork activation check before processing `SetCode` (introduced by `EIP-7702`). This oversight could allow `SetCode` transactions to be accepted before the Prague upgrade is activated. These `SetCode` transactions will not pass the validations in execution layer and will not be charged gas. As a result, attackers can flood the transaction pool with invalid `SetCode` transactions at minimal cost.


The current validation logic checks whether EIP-1559 is active for dynamic fee transactions (`TxTypeEthereumDynamicFee`) but does not verify if the Prague hardfork is active before allowing `TxTypeEthereumSetCode` transactions.

**`blockchain/tx_pool.go`**
```go=709
   // Reject dynamic fee transactions until EIP-1559 activates.
	if !pool.rules.IsEthTxType && (tx.Type() == types.TxTypeEthereumDynamicFee || tx.Type() == types.TxTypeEthereumSetCode) {
		return ErrTxTypeNotSupported
	}
```

This check only considers `IsEthTxType` (EIP-1559 activation) but does not enforce `IsPrague` for `SetCode` transactions.

Later in the function, `SetCode` transactions are validated for required fields (e.g., AuthList), but no check ensures the Prague upgrade is active:

**`blockchain/tx_pool.go`**
```go=895
if tx.Type() == types.TxTypeEthereumSetCode {
		if len(tx.AuthList()) == 0 {
			return errors.New("set code tx must have at least one authorization tuple")
		}
	}
```
This means the `SetCode` transaction could pass initial checks even before Prague is live.

When `SetCode` transactions are executed in `ApplyTransaction()` function, it will try to validate sender in `AsMessageWithAccountKeyPicker` function:

**`blockchain/blockchain.go`**
```go=2740
func (bc *BlockChain) ApplyTransaction(chainConfig *params.ChainConfig, author *common.Address, statedb *state.StateDB, header *types.Header, tx *types.Transaction, usedGas *uint64, vmConfig *vm.Config) (*types.Receipt, *vm.InternalTxTrace, error) {
	// TODO-Kaia We reject transactions with unexpected gasPrice and do not put the transaction into TxPool.
	//         And we run transactions regardless of gasPrice if we push transactions in the TxPool.
	/*
		// istanbul BFT
		if tx.GasPrice() != nil && tx.GasPrice().Cmp(common.Big0) > 0 {
			return nil, uint64(0), ErrInvalidGasPrice
		}
	*/

	blockNumber := header.Number.Uint64()

	// validation for each transaction before execution
	if err := tx.Validate(statedb, blockNumber); err != nil {
		return nil, nil, err
	}

	msg, err := tx.AsMessageWithAccountKeyPicker(types.MakeSigner(chainConfig, header.Number), statedb, blockNumber)
    ...
    ...
```

**`blockchain/types/transaction.go`**
```go=619
func (tx *Transaction) AsMessageWithAccountKeyPicker(s Signer, picker AccountKeyPicker, currentBlockNumber uint64) (*Transaction, error) {
	intrinsicGas, err := tx.IntrinsicGas(currentBlockNumber)
	if err != nil {
		return nil, err
	}

	gasFrom, err := tx.ValidateSender(s, picker, currentBlockNumber)
    ...
    ...
```
Since the Prague hardfork is not active, the code `types.MakeSigner(chainConfig, header.Number)` will change the signer to a `londonSigner`:

**`blockchain/types/transaction_signing.go`**
```go=58
// MakeSigner returns a Signer based on the given chain config and block number.
func MakeSigner(config *params.ChainConfig, blockNumber *big.Int) Signer {
	var signer Signer

	if config.IsPragueForkEnabled(blockNumber) {
		signer = NewPragueSigner(config.ChainID)
	} else if config.IsEthTxTypeForkEnabled(blockNumber) {
		signer = NewLondonSigner(config.ChainID)
	} else {
		signer = NewEIP155Signer(config.ChainID)
	}

	return signer
}
```
Here the `signer` is changed from a `pragueSigner` to a `londonSigner`.

In `AsMessageWithAccountKeyPicker` function, it calls `tx.ValidateSender` and the `tx.ValidateSender` will call `Sender(signer, tx)`:

**`blockchain/tx_pool.go`**
```go=704
// ValidateSender finds a sender from both legacy and new types of transactions.
// It returns the senders address and gas used for the tx validation.
func (tx *Transaction) ValidateSender(signer Signer, p AccountKeyPicker, currentBlockNumber uint64) (uint64, error) {
	if tx.IsEthereumTransaction() {
		addr, err := Sender(signer, tx)
		// Legacy transaction cannot be executed unless the account has a legacy key.
		if p.GetKey(addr).Type().IsLegacyAccountKey() == false {
			return 0, kerrors.ErrLegacyTransactionMustBeWithLegacyKey
		}
```
The `Sender(signer, tx)` will call `SenderFrom(signer, tx)`:

**`blockchain/types/transaction_signing.go`**
```go=137
func Sender(signer Signer, tx *Transaction) (common.Address, error) {
	if tx.IsEthereumTransaction() {
		return SenderFrom(signer, tx)
	}

	return tx.From()
}
```
The `SenderFrom(signer, tx)` will call `signer.Sender(tx)`:

**`blockchain/types/transaction_signing.go`**
```go=190
func SenderFrom(signer Signer, tx *Transaction) (common.Address, error) {
	if sc := tx.from.Load(); sc != nil {
		sigCache := sc.(sigCache)
		// If the signer used to derive from in a previous
		// call is not the same as used current, invalidate
		// the cache.
		if sigCache.signer.Equal(signer) {
			return sigCache.from, nil
		}
	}

	addr, err := signer.Sender(tx)
```


When calling `signer.Sender(tx)`, the `pragueSigner` supports the `TxTypeEthereumSetCode` type:

**`blockchain/types/transaction_signing.go`**
```go=280
func (s pragueSigner) Sender(tx *Transaction) (common.Address, error) {
	if tx.Type() != TxTypeEthereumSetCode {
		return s.londonSigner.Sender(tx)
	}
    if tx.ChainId().Cmp(s.chainId) != 0 {
		return common.Address{}, ErrInvalidChainId
	}

	return tx.data.RecoverAddress(s.Hash(tx), true, func(v *big.Int) *big.Int {
		// AL txs are defined to use 0 and 1 as their recovery
		// id, add 27 to become equivalent to unprotected Homestead signatures.
		V := new(big.Int).Add(v, big.NewInt(27))
		return V
	})
}
```
However, the `londonSigner` does not support the `TxTypeEthereumSetCode` type:

**`blockchain/types/transaction_signing.go`**
```go=388
// SenderPubkey returns the public key derived from tx signature and txhash.
func (s londonSigner) SenderPubkey(tx *Transaction) ([]*ecdsa.PublicKey, error) {
	if tx.Type() != TxTypeEthereumDynamicFee {
		return s.eip2930Signer.SenderPubkey(tx)
	}

	if tx.ChainId().Cmp(s.chainId) != 0 {
		return nil, ErrInvalidChainId
	}

	return tx.data.RecoverPubkey(s.Hash(tx), true, func(v *big.Int) *big.Int {
		// AL txs are defined to use 0 and 1 as their recovery
		// id, add 27 to become equivalent to unprotected Homestead signatures.
		V := new(big.Int).Add(v, big.NewInt(27))
		return V
	})
}
```
As a result, the `ValidateSender` will fail and return error with `invalid sender: transaction type not supported`.

Since the `SetCode` transactions will fail before calling the `ApplyMessage(vmenv, msg)`, no gas will be charged. So attackers can send numerous `SetCode` transactions to tx pools and DoS other's normal transactions with a very low cost.

## Recommendation

Recommend adding following checks in `validateTx` function in `tx_pool.go`:
```go
if !pool.rules.IsPrague && tx.Type() == types.TxTypeEthereumSetCode {
		return ErrTxTypeNotSupported
}
```

## Vulnerable Code

```
}

		if len(pendingPerAccount) >= txPerAddr {
			if txPerAddr > 1 {
				txPerAddr = txPerAddr / 2
			}
		}
	}
	return pending
}

// local retrieves all currently known local transactions, groupped by origin
// account and sorted by nonce. The returned transaction set is a copy and can be
// freely modified by calling code.
func (pool *TxPool) local() map[common.Address]types.Transactions {
	txs := make(map[common.Address]types.Transactions)
	for addr := range pool.locals.accounts {
		if pending := pool.pending[addr]; pending != nil {
			txs[addr] = append(txs[addr], pending.Flatten()...)
		}
		if queued := pool.queue[addr]; queued != nil {
			txs[addr] = append(txs[addr], queued.Flatten()...)
		}
	}
	return txs
}

// validateTx checks whether a transaction is valid according to the consensus
// rules and adheres to some heuristic limits of the local node (price and size).
func (pool *TxPool) validateTx(tx *types.Transaction) error {
	// Accept only legacy transactions until EIP-2718/2930 activates.
	if !pool.rules.IsEthTxType && tx.IsEthTypedTransaction() {
		return ErrTxTypeNotSupported
	}
	// Reject dynamic fee transactions until EIP-1559 activates.
	if !pool.rules.IsEthTxType && (tx.Type() == types.TxTypeEthereumDynamicFee || tx.Type() == types.TxTypeEthereumSetCode) {
		return ErrTxTypeNotSupported
	}

	// Check whether the init code size has been exceeded
	if pool.rules.IsShanghai && tx.To() == nil && len(tx.Data()) > params.MaxInitCodeSize {
		return fmt.Errorf("%w: code size %v, limit %v", ErrMaxInitCodeSizeExceeded, len(tx.Data()), params.MaxInitCodeSize)
	}

	// Check chain Id first.
	if tx.Protected() && tx.ChainId().Cmp(pool.chainconfig.ChainID) != 0 {
		return ErrInvalidChainId
	}

	// NOTE-Kaia Drop transactions with unexpected gasPrice
	// If the transaction type is DynamicFee tx, Compare transaction's GasFeeCap(MaxFeePerGas) and GasTipCap with tx pool's gasPrice to check to have same value.
	if tx.Type() == types.TxTypeEthereumDynamicFee || tx.Type() == types.TxTypeEthereumSetCode {
		// Sanity check for extremely large numbers
		if tx.GasTipCap().BitLen() > 256 {
			return ErrTipVeryHigh
		}

		if tx.GasFeeCap().BitLen() > 256 {
			return ErrFeeCapVeryHigh
		}

		// Ensure gasFeeCap is greater than or equal to gasTipCap.
		if tx.GasFeeCap().Cmp(tx.GasTipCap()) < 0 {
			return ErrTipAboveFeeCap
		}

		if pool.rules.IsMagma {
			// Ensure transaction's gasFeeCap is greater than or equal to transaction pool's gasPrice(baseFee).
			if pool.gasPrice.Cmp(tx.GasFeeCap()) > 0 {
				logger.Trace("fail to validate maxFeePerGas", "pool.gasPrice", pool.gasPrice, "maxFeePerGas", tx.GasFeeCap())
				return ErrFeeCapBelowBaseFee
			}
		} else {

			if pool.gasPrice.Cmp(tx.GasTipCap()) != 0 {
				logger.Trace("fail to validate maxPriorityFeePerGas", "unitprice", pool.gasPrice, "maxPriorityFeePerGas", tx.GasFeeCap())
				return ErrInvalidGasTipCap
			}

			if pool.gasPrice.Cmp(tx.GasFeeCap()) != 0 {
				logger.Trace("fail to validate maxFeePerGas", "unitprice", pool.gasPrice, "maxFeePerGas", tx.GasTipCap())
				return ErrInvalidGasFeeCap
			}
		}

	} else {
		if pool.rules.IsMagma {
			if pool.gasPrice.Cmp(tx.GasPrice()) > 0 {
				// Ensure transaction's gasPrice is greater than or equal to transaction pool's gasPrice(baseFee).
				logger.Trace("fail to validate gasprice", "pool.gasPrice", pool.gasPrice, "tx.gasPrice", tx.GasPrice())
				return ErrGasPriceBelowBaseFee
			}
		} else {
			// Unitprice policy before magma hardfork
			if pool.gasPrice.Cmp(tx.GasPrice()) != 0 {
				logger.Trace("fail to validate unitprice", "unitPrice", pool.gasPrice, "txUnitPrice", tx.GasPrice())
				return ErrInvalidUnitPrice
			}
		}
	}

	// Reject transactions over MaxTxDataSize to prevent DOS attacks
	if uint64(tx.Size()) > MaxTxDataSize {
		return ErrOversizedData
	}

	// Transactions can't be negative. This may never happen using RLP decoded
	// transactions but may occur if you create a transaction using the RPC.
	if tx.Value().Sign() < 0 {
		return ErrNegativeValue
	}

	// Make sure the transaction is signed properly
	gasFrom, err := tx.ValidateSender(pool.signer, pool.currentState, pool.currentBlockNumber)
	if err != nil {
		return types.ErrSender(err)
	}

	var (
		from          = tx.ValidatedSender()
		senderBalance = pool.getBalance(from)
		gasFeePayer   = uint64(0)
	)
	// Ensure the transaction adheres to nonce ordering
	if pool.getNonce(from) > tx.Nonce() {
		return ErrNonceTooLow
	}

	// If module recognizes the tx, run an alternative balance check and then skip the default balance check later.
	shouldSkipBalanceCheck := false
	for _, module := range pool.modules {
		if module.IsModuleTx(tx) {
			if checkBalance := module.GetCheckBalance(); checkBalance != nil {
				shouldSkipBalanceCheck = true
				err := checkBalance(tx)
				if err != nil {
					logger.Trace("[tx_pool] invalid funds of module transaction sender", "from", from, "txhash", tx.Hash().Hex())
					return err
				}
			}
			break
		}
	}

	// Transactor should have enough funds to cover the costs
	// cost == V + GP * GL
	if tx.IsFeeDelegatedTransaction() {
		// balance check for fee-delegated tx
		gasFeePayer, err = tx.ValidateFeePayer(pool.signer, pool.currentState, pool.currentBlockNumber)
		if err != nil {
			return types.ErrFeePayer(err)
		}

		var (
			feePayer            = tx.ValidatedFeePayer()
			feePayerBalance     = pool.getBalance(feePayer)
			feeRatio, isRatioTx = tx.FeeRatio()
		)
		if isRatioTx {
			// Check fee ratio range
			if !feeRatio.IsValid() {
				return kerrors.ErrFeeRatioOutOfRange
			}

			feeByFeePayer, feeBySender := types.CalcFeeWithRatio(feeRatio, tx.Fee())

			if senderBalance.Cmp(new(big.Int).Add(tx.Value(), feeBySender)) < 0 {
				logger.Trace("[tx_pool] insufficient funds for feeBySender", "from", from, "balance", senderBalance, "feeBySender", feeBySender)
				return ErrInsufficientFundsFrom
			}

			if feePayerBalance.Cmp(feeByFeePayer) < 0 {
				logger.Trace("[tx_pool] insufficient funds for feeByFeePayer", "feePayer", feePayer, "balance", feePayerBalance, "feeByFeePayer", feeByFeePayer)
				return ErrInsufficientFundsFeePayer
			}
		} else {
			if senderBalance.Cmp(tx.Value()) < 0 {
				logger.Trace("[tx_pool] insufficient funds for cost(value)", "from", from, "balance", senderBalance, "value", tx.Value())
				return ErrInsufficientFundsFrom
			}

			if feePayerBalance.Cmp(tx.Fee()) < 0 {
				logger.Trace("[tx_pool] insufficient funds for cost(gas * price)", "feePayer", feePayer, "balance", feePayerBalance, "fee", tx.Fee())
				return ErrInsufficientFundsFeePayer
			}
		}
		// additional balance check in case of sender = feepayer
		// since a single account has to bear the both cost(feepayer_cost + sender_cost),
		// it is necessary to check whether the balance is equal to the sum of the cost.
		if from == feePayer && senderBalance.Cmp(tx.Cost()) < 0 {
			logger.Trace("[tx_pool] insufficient funds for cost(gas * price + value)", "from", from, "balance", senderBalance, "cost", tx.Cost())
			return ErrInsufficientFundsFrom
		}
	} else if !shouldSkipBalanceCheck {
		// balance check for non-fee-delegated tx
		if senderBalance.Cmp(tx.Cost()) < 0 {
			logger.Trace("[tx_pool] insufficient funds for cost(gas * price + value)", "from", from, "balance", senderBalance, "cost", tx.Cost())
			return ErrInsufficientFundsFrom
		}
	}

	intrGas, err := tx.IntrinsicGas(pool.currentBlockNumber)
	sigValGas := gasFrom + gasFeePayer
	if err != nil {
		return err
	}
	if tx.Gas() < intrGas+sigValGas {
		return ErrIntrinsicGas
	}
	// Ensure the transaction can cover floor data gas.
	if pool.rules.IsPrague {
		floorDataGas, err := FloorDataGas(tx.Type(), tx.Data(), sigValGas)
		if err != nil {
			return err
		}
		if tx.Gas() < floorDataGas {
			return fmt.Errorf("%w: gas %v, minimum needed %v", ErrFloorDataGas, tx.Gas(), floorDataGas)
		}
	}

	if tx.Type() == types.TxTypeEthereumSetCode {
		if len(tx.AuthList()) == 0 {
			return errors.New("set code tx must have at least one authorization tuple")
		}
	}

	if err := pool.validateAuth(tx); err != nil {
		return err
	}

	// "tx.Validate()" conducts additional validation for each new txType.
	// Validate humanReadable address when this tx has "true" in the humanReadable field.
	// Validate accountKey when the this create or update an account
	// Validate the existence of the address which will be created though this Tx
	// Validate a contract account whether it is executable
	if err := tx.Validate(pool.currentState, pool.currentBlockNumber); err != nil {
		return err
	}

	return nil
}

// validateAuth verifies that the transaction complies with code authorization
// restrictions brought by SetCode transaction type.
func (pool *TxPool) validateAuth(tx *types.Transaction) error {
	from, _ := types.Sender(pool.signer, tx) // validated

	// Allow at most one in-flight tx for delegated accounts or those with a
	// pending authorization.
	if pool.currentState.GetCodeHash(from) != types.EmptyCodeHash || len(pool.all.auths[from]) != 0 {
		var (
			count  int
			exists bool
		)
		pending := pool.pending[from]
		if pending != nil {
			count += pending.Len()
			exists = pending.Contains(tx.Nonce())
		}
		queue := pool.queue[from]
		if queue != nil {
			count += queue.Len()
			exists = exists || queue.Contains(tx.Nonce())
		}
		// Replace the existing in-flight transaction for delegated accounts
		// are still supported
		if count >= 1 && !exists {
			return ErrInflightTxLimitReached
		}
	}
	// Authorities cannot conflict with any pending or queued transactions.
```
