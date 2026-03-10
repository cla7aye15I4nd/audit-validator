# Locked Funds If Taker Creates Buy Order With Price Above Market Price


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🟠 Major |
| Triage Verdict | ✅ Valid |
| Project ID | `f03adfd0-ab7c-11f0-96ab-8b123d6a0fc2` |
| Commit | `0c7c8686c79ba951fedb3173822077b159b3829b` |

## Location

- **Local path:** `./source_code/github/devervalue/orderbook/0c7c8686c79ba951fedb3173822077b159b3829b/src/PairLib.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/f03adfd0-ab7c-11f0-96ab-8b123d6a0fc2/source?file=$/github/devervalue/orderbook/0c7c8686c79ba951fedb3173822077b159b3829b/src/PairLib.sol
- **Lines:** 567–567

## Description

When a user submits a buy order for base tokens, the contract currently requires the buyer to deposit `_quantity * _price / PRECISION` amount of quote tokens, where `_quantity` is the desired amount to purchase and `_price` is the maximum price the buyer is willing to pay per unit. This calculation assumes that no immediate matching occurs and the order is added as an unfilled maker order. However, if the submitted buy order is matched, fully or partially, with existing sell orders at a lower price, the buyer should pay only the matched quantity multiplied by the actual (lower) maker order price. In the audited implementation, the buyer is charged according to their input price, not the matched price, which results in depositing more quote tokens than needed for the executed trade. The surplus quote tokens remain in the contract and are not refunded or allocated, resulting in user funds being unintentionally locked.

## Recommendation

We recommend that the order matching logic is updated so that, when a new buy order is created and matched (either partially or fully) with existing sell orders at lower prices, the protocol calculates the exact required amount of quote tokens based on the actual matched prices and amounts

## Vulnerable Code

```
while (newOrder.quantity > 0 && orderCount < MAX_NUMBER_ORDERS_FILLED) {
            // If there are no more orders to match against, exit the loop
            if (currentPricePoint == 0) {
                break;
            }

            // Determine if the new order should be matched at the current price point
            bool shouldMatch = isBuy ? newOrder.price >= currentPricePoint : newOrder.price <= currentPricePoint;

            if (shouldMatch) {
                // Match the order and update remaining quantity
                (newOrder.quantity, orderCount, takerAmountReceive) = matchOrder(pair, orderCount, newOrder,takerAmountReceive);
                //newOrder.quantity = _quantity;
                // Update the current price point for the next iteration
                currentPricePoint = isBuy ? pair.sellOrders.getLowestPrice() : pair.buyOrders.getHighestPrice();
            } else {
                // If the current price is not favorable, stop matching
                break;
            }
        }

        // If there's remaining quantity after matching, add the order to the book
        if (newOrder.quantity > 0) {
            addOrder(pair, newOrder);
        }

        //Send Transfer Amount
        if (newOrder.isBuy) {
            // If it's a buy order, update the quote token balance of the new order (creator order)
            IERC20(pair.quoteToken).safeTransferFrom(msg.sender, address(this), _quantity * _price / PRECISION);
            //Taker receive base token
            if(takerAmountReceive != 0){
                // Calculate fee (on the buy token amount, which is what the taker receives)
                /// @dev The fee is calculated in basis points (1/100 of a percent)
                uint256 fee = (takerAmountReceive * pair.fee) / 10000;
                pair.baseFeeBalance += fee;
                uint256 takerReceiveAmountAfterFee = takerAmountReceive - fee;
                IERC20(pair.baseToken).safeTransfer(msg.sender,takerReceiveAmountAfterFee);
            }
        } else {
            IERC20(pair.baseToken).safeTransferFrom(msg.sender, address(this), _quantity);
            if(takerAmountReceive != 0){
                // Calculate fee (on the buy token amount, which is what the taker receives)
                /// @dev The fee is calculated in basis points (1/100 of a percent)
                uint256 fee = (takerAmountReceive * pair.fee) / 10000;
                pair.quoteFeeBalance += fee;
                uint256 takerReceiveAmountAfterFee = takerAmountReceive - fee;
            if(takerReceiveAmountAfterFee / PRECISION == 0){
                    //Acumulation quote token
                    pair.traderBalances[msg.sender].quoteTokenBalance += takerReceiveAmountAfterFee;
                }else{
                    //Taker receive quote token
                    IERC20(pair.quoteToken).safeTransfer(msg.sender,takerReceiveAmountAfterFee / PRECISION);
                }
            }
        }
    }

    /// @notice Retrieves the balance of a trader for a specific trading pair
    /// @dev This function returns the current balance of base and quote tokens for a given trader
```
