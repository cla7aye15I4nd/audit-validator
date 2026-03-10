# Exploitable Re-Entrancy Issue Allows High-Priced Orders to Be Settled at Lower Cost


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🔴 Critical |
| Triage Verdict | ✅ Valid |
| Project ID | `ac8b6780-bcbe-11ef-b2a6-53871e3ecd80` |
| Commit | `08fa763d77799f16bd9054b15488a1c0e1f59429` |

## Location

- **Local path:** `./src/x/dex/keeper/keeper_matching_result.go`
- **ACC link:** https://acc.audit.certikpowered.info/project/ac8b6780-bcbe-11ef-b2a6-53871e3ecd80/source?file=$/github/CoreumFoundation/coreum/188736cb7d7e3de92f6286201ea4fb2494ae9daf/x/dex/keeper/keeper_matching_result.go
- **Lines:** 193–216

## Description

Repository:
- `Coreum DEX`

Commit hash:
- [`188736cb7d7e3de92f6286201ea4fb2494ae9daf`](https://github.com/CoreumFoundation/coreum/tree/188736cb7d7e3de92f6286201ea4fb2494ae9daf)

Files:
- `x/dex/keeper/keeper_matching.go`

The `ft` module of Coreum allows for an additional extension option to be specified when defining a token. This extension is essentially a Cosmos WASM contract address. When a user places an order or conducts a transfer, if the involved token has the extension feature, the corresponding extension contract address will be invoked during the process.

There are two similar hooks, `placeorder` and `transfer`.

**`x/asset/ft/keeper/before_send.go`**
```go=178
func (k Keeper) invokeAssetExtensionExtensionTransferMethod(
	ctx sdk.Context,
	sender sdk.AccAddress,
	recipient sdk.AccAddress,
	def types.Definition,
	sendAmount sdk.Coin,
	commissionAmount sdkmath.Int,
	burnAmount sdkmath.Int,
) error {
	extensionContract, err := sdk.AccAddressFromBech32(def.ExtensionCWAddress)
	...

	contractMsg := map[string]interface{}{
		ExtensionTransferMethod: sudoExtensionTransferMsg{
			Sender:           sender.String(),
			Recipient:        recipient.String(),
			TransferAmount:   sendAmount.Amount,
			BurnAmount:       burnAmount,
			CommissionAmount: commissionAmount,
			Context: sudoExtensionTransferContext{
				SenderIsSmartContract:    senderIsSmartContract,
				RecipientIsSmartContract: recipientIsSmartContract,
				IBCPurpose:               ibcPurposeToExtensionString(ctx),
			},
		},
	}
	contractMsgBytes, err := json.Marshal(contractMsg)
	if err != nil {
		return errors.Wrapf(err, "failed to marshal contract msg")
	}

	_, err = k.wasmPermissionedKeeper.Sudo(
		ctx,
		extensionContract,
		contractMsgBytes,
	)
	if err != nil {
		return types.ErrExtensionCallFailed.Wrapf("wasm error: %s", err)
	}
	return nil
}
```

**`x/asset/ft/keeper/keeper_dex.go`**
```go=465
func (k Keeper) invokeAssetExtensionPlaceOrderMethod(
	ctx sdk.Context,
	extensionContract sdk.AccAddress,
	order types.DEXOrder,
	expectedToSpend, expectedToReceive sdk.Coin,
) error {
	contractMsg := map[string]interface{}{
		ExtensionPlaceOrderMethod: sudoExtensionPlaceOrderMsg{
			Order:             order,
			ExpectedToSpend:   expectedToSpend,
			ExpectedToReceive: expectedToReceive,
		},
	}
	contractMsgBytes, err := json.Marshal(contractMsg)
	if err != nil {
		return errors.Wrapf(err, "failed to marshal contract msg")
	}

	_, err = k.wasmPermissionedKeeper.Sudo(
		ctx,
		extensionContract,
		contractMsgBytes,
	)
	if err != nil {
		return types.ErrExtensionCallFailed.Wrapf("wasm error: %s", err)
	}

	return nil
}
```
When a user places an order, Coreum initially searches the order book for any maker orders that can fulfill the user's taker order based on the type of order placed. It evaluates the matching results and decides whether to proceed with transfers and state update operations depending on the match outcomes and order type.

**`x/dex/keeper/keeper_matching.go`**
```go=73
switch takerOrder.Type {
	case types.ORDER_TYPE_LIMIT:
		switch takerOrder.TimeInForce {
		case types.TIME_IN_FORCE_GTC:
			// If taker order is filled fully or not executable as maker we just apply matching result and return.
			if takerIsFilled || !isOrderRecordExecutableAsMaker(&takerRecord) {
				return k.applyMatchingResult(ctx, mr)
			}
        ...
        }
	}
```


If the taker order is fulfilled, Coreum will call the `applyMatchingResult` function. This function handles the final steps in the order matching process, including aggregating final transfers, updating the status of orders, and adjusting user balances. 

**`x/dex/keeper/keeper_matching_result.go`**
```go=193
func (k Keeper) applyMatchingResult(ctx sdk.Context, mr *MatchingResult) error {
	// if matched passed but no changes are applied return
	if mr.FTActions.CreatorExpectedToSpend.IsNil() {
		return nil
	}

	if err := k.assetFTKeeper.DEXExecuteActions(ctx, mr.FTActions); err != nil {
		return err
	}

	for _, item := range mr.RecordsToRemove {
		if err := k.removeOrderByRecord(ctx, item.Address, *item.Record); err != nil {
			return err
		}
	}

	if mr.RecordToUpdate != nil {
		if err := k.saveOrderBookRecord(ctx, *mr.RecordToUpdate); err != nil {
			return err
		}
	}

	return k.publishMatchingEvents(ctx, mr)
}
```

Within `applyMatchingResult`, the first function called is `k.assetFTKeeper.DEXExecuteActions`, which executes actions such as transferring funds and updating user balances. Subsequently, the logic modifies the storage state within the DEX module.


**`x/asset/ft/keeper/keeper_dex.go`**
```go=36
func (k Keeper) DEXExecuteActions(ctx sdk.Context, actions types.DEXActions) error {
	if err := k.DEXCheckOrderAmounts(
		ctx,
		actions.Order,
		actions.CreatorExpectedToSpend,
		actions.CreatorExpectedToReceive,
	); err != nil {
		return err
	}

	...
	for _, send := range actions.Send {
		k.logger(ctx).Debug(
			"DEX sending coin",
			"from", send.FromAddress.String(),
			"to", send.ToAddress.String(),
			"coin", send.Coin.String(),
		)
		if err := k.bankKeeper.SendCoins(ctx, send.FromAddress, send.ToAddress, sdk.NewCoins(send.Coin)); err != nil {
			return sdkerrors.Wrap(err, "failed to DEX send coins")
		}
	}

	return nil
}
```

The `DEXExecuteActions` function processes the DEX-related actions generated from order match results. When the `DEXCheckOrderAmounts` function is called within it, the extension contract associated with the token involved in the order is ultimately invoked.

**`x/asset/ft/keeper/keeper_dex.go`**
```go=101
func (k Keeper) DEXCheckOrderAmounts(
	ctx sdk.Context,
	order types.DEXOrder,
	expectedToSpend, expectedToReceive sdk.Coin,
) error {
	if err := k.dexCheckExpectedToSpend(ctx, order, expectedToSpend, expectedToReceive); err != nil {
		return err
	}

	return k.dexCheckExpectedToReceive(ctx, order, expectedToSpend, expectedToReceive)
}
```

**`x/asset/ft/keeper/keeper_dex.go`**
```go=391
func (k Keeper) dexCheckExpectedToSpend(
	ctx sdk.Context,
	order types.DEXOrder,
	expectedToSpend, expectedToReceive sdk.Coin,
) error {
	...

	if spendDef.IsFeatureEnabled(types.Feature_extension) {
		extensionContract, err := sdk.AccAddressFromBech32(spendDef.ExtensionCWAddress)
		if err != nil {
			return err
		}
		return k.invokeAssetExtensionPlaceOrderMethod(
			ctx, extensionContract, order, expectedToSpend, expectedToReceive,
		)
	}

	return nil
}

```

**`x/asset/ft/keeper/keeper_dex.go`**
```go=431
func (k Keeper) dexCheckExpectedToReceive(
	ctx sdk.Context,
	order types.DEXOrder,
	expectedToSpend, expectedToReceive sdk.Coin,
) error {
	...
	if receiveDef.IsFeatureEnabled(types.Feature_extension) {
		extensionContract, err := sdk.AccAddressFromBech32(receiveDef.ExtensionCWAddress)
		if err != nil {
			return err
		}
		return k.invokeAssetExtensionPlaceOrderMethod(
			ctx, extensionContract, order, expectedToSpend, expectedToReceive,
		)
	}

	return nil
}
```

At the end of `DEXExecuteActions`, `k.bankKeeper.SendCoins` also invokes the token's extension contract. The relevant call sequence for this process begins with `SendCoins` in the `BaseKeeperWrapper`, which leads to `k.ftProvider.BeforeSendCoins`. This method, in turn, calls `k.applyFeatures`, where if the extension feature is enabled, `k.invokeAssetExtensionExtensionTransferMethod` is invoked.

**`x/wbank/keeper/keeper.go`**
```go=103
func (k BaseKeeperWrapper) SendCoins(goCtx context.Context, fromAddr, toAddr sdk.AccAddress, amt sdk.Coins) error {
	...
	return k.ftProvider.BeforeSendCoins(ctx, fromAddr, toAddr, amt)
}
```

**`x/asset/ft/keeper/before_send.go`**
```go=50
func (k Keeper) BeforeSendCoins(ctx sdk.Context, fromAddress, toAddress sdk.AccAddress, coins sdk.Coins) error {
	return k.applyFeatures(
		ctx,
		banktypes.Input{Address: fromAddress.String(), Coins: coins},
		[]banktypes.Output{{Address: toAddress.String(), Coins: coins}},
	)
}
```

**`x/asset/ft/keeper/before_send.go`**
```go=63
func (k Keeper) applyFeatures(ctx sdk.Context, input banktypes.Input, outputs []banktypes.Output) error {
	...
			if def.IsFeatureEnabled(types.Feature_extension) {
				if err := k.invokeAssetExtensionExtensionTransferMethod(
					ctx, sender, recipient, *def, coin, commissionAmount, burnAmount,
				); err != nil {
					return err
				}
				continue
			}

			...
}
```

Since the `applyMatchingResult` function removes related records and updates records only after invoking the external contract, there potentially exists a reentrancy issue.
In the `applyMatchingResult` function, `RecordsToRemove` and `saveOrderBookRecord` essentially perform writes to the KVStore. Since external calls occur before this step, recursively invoking `placeorder` or other functions that make state change such as cancel order could lead to potential asset loss.

## Recommendation

Recommend to disable extension for dex token or move `DEXExecuteActions` at the end of `applyMatchingResult` function after state changed.

## Vulnerable Code

```
makerAddr sdk.AccAddress,
	makerOrderID string,
	makerOrderSequence uint64,
	coin sdk.Coin,
) {
	mr.TakerOrderReducedEvent.SentCoin = mr.TakerOrderReducedEvent.SentCoin.Add(coin)
	mr.MakerOrderReducedEvents = append(mr.MakerOrderReducedEvents, types.EventOrderReduced{
		Creator:      makerAddr.String(),
		ID:           makerOrderID,
		Sequence:     makerOrderSequence,
		ReceivedCoin: coin,
	})
}

func (mr *MatchingResult) updateMakerSendEvents(
	makerAddr sdk.AccAddress,
	makerOrderID string,
	coin sdk.Coin,
) {
	mr.TakerOrderReducedEvent.ReceivedCoin = mr.TakerOrderReducedEvent.ReceivedCoin.Add(coin)
	for i := range mr.MakerOrderReducedEvents {
		// find corresponding event created by `updateTakerSendEvents`
		if mr.MakerOrderReducedEvents[i].Creator == makerAddr.String() && mr.MakerOrderReducedEvents[i].ID == makerOrderID {
			mr.MakerOrderReducedEvents[i].SentCoin = coin
			break
		}
	}
}

func (k Keeper) applyMatchingResult(ctx sdk.Context, mr *MatchingResult) error {
	// if matched passed but no changes are applied return
	if mr.FTActions.CreatorExpectedToSpend.IsNil() {
		return nil
	}

	if err := k.assetFTKeeper.DEXExecuteActions(ctx, mr.FTActions); err != nil {
		return err
	}

	for _, item := range mr.RecordsToRemove {
		if err := k.removeOrderByRecord(ctx, item.Address, *item.Record); err != nil {
			return err
		}
	}

	if mr.RecordToUpdate != nil {
		if err := k.saveOrderBookRecord(ctx, *mr.RecordToUpdate); err != nil {
			return err
		}
	}

	return k.publishMatchingEvents(ctx, mr)
}

func (k Keeper) publishMatchingEvents(
	ctx sdk.Context,
	mr *MatchingResult,
) error {
	events := mr.MakerOrderReducedEvents
	if !mr.TakerOrderReducedEvent.SentCoin.IsZero() {
		events = append(events, mr.TakerOrderReducedEvent)
	}

	for _, evt := range events {
		if err := ctx.EventManager().EmitTypedEvent(&evt); err != nil {
			return sdkerrors.Wrapf(types.ErrInvalidInput, "failed to emit event EventOrderReduced: %s", err)
		}
	}

	return nil
}
```
