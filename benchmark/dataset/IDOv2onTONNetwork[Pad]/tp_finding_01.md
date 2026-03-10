# Missing Consistency Check Between `buyCurr` and `buyCurrAddr`


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🔴 Critical |
| Triage Verdict | ✅ Valid |
| Project ID | `e91d2cd0-ccf2-11ef-b7b3-991e621d882a` |
| Commit | `cb9e917ee7191cc63f3095a5ebe160674a9ffd6c` |

## Location

- **Local path:** `./src/contracts/i_d_o/i_d_o_pool.fc`
- **ACC link:** https://acc.audit.certikpowered.info/project/e91d2cd0-ccf2-11ef-b7b3-991e621d882a/source?file=$/github/ChainGPT-org/ton_IDO_contracts/cb9e917ee7191cc63f3095a5ebe160674a9ffd6c/contracts/i_d_o/i_d_o_pool.fc
- **Lines:** 850–850

## Description

At line 858, the value for `buyCurr` is provided by the user, which may differ from the `buyCurrAddr`. However, there is no validation to ensure that these two values are consistent with each other. While line 491 checks if `buyCurr` is set, this does not account for the possibility of the contract owner mistakenly setting the `buyCurr` value. If `buyCurr` is set incorrectly, it can result in an incorrect `buyCurrRate`, leading to an unintended sell amount. The mismatch between the `buyCurr` and `buyCurrAddr` can cause discrepancies that affect the expected outcome of the transaction, potentially resulting in financial loss or incorrect calculations for users.

## Recommendation

Add a validation check to ensure that the `buyCurr` value matches the `buyCurrAddr` value before proceeding with the transaction. This will prevent unexpected changes to the `buyCurrRate` and ensure the correct sell amount is calculated.

## Vulnerable Code

```
;; send excess ton back
        int payBack = calc_money_to_pay_back(myBalance, msgValue, COMPUTE_COST);
        if (payBack > 0) {
            send_empty_message(payBack, g_owner, NORMAL);
        }

        return ();

    }
    if (op == op::transferNotification) {

        (int jettonAmount, slice fromUser) = (inMsgBody~load_coins(), inMsgBody~load_msg_addr());

        ;; logic to maintain token account balances in contract
        (int found, slice buyCurrAddr) = add_token_balance(senderAddr, jettonAmount);
        throw_unless(error::POOL::CURRENCY_NOT_SUPPORTED, found); ;; check that notification is from a relevant contract
        if (equal_slices(buyCurrAddr, g_sellTokenMint)) { ;; no further processing needed if sell token was sent
            send_empty_message(msgValue - COMPUTE_COST, fromUser, NORMAL); ;; send remaining gas back
            return ();
        }

        ;; try catch block is used so the balance change does not get discarded
        try {

            throw_unless(error::GENERAL::INSUFFICIENT_TON_FOR_GAS, msgValue >= TON_TO_NANO); ;; atleast 1 TON is needed

            ;; swap by token data read
            slice refDs = inMsgBody~load_ref().begin_parse();
            slice buyCurr = refDs~load_msg_addr();
            int maxAmount = refDs~load_coins();
            int minAmount = refDs~load_coins();
            slice signature = refDs~load_ref().begin_parse();

            try {

                buy_token_by_token_with_permission(
                    buyCurr,
                    jettonAmount,
                    fromUser,
                    maxAmount,
                    minAmount,
                    signature
                );

            } catch (x, n) {
                ;; refund tokens
                var body = create_simple_transfer_body(0, 0, jettonAmount, fromUser);
                send_simple_message(TON_TO_NANO / 10, senderAddr, body.end_cell(), PAID_EXTERNALLY);

                (
                    int buyCurrRaised,
                    int buyCurrRefundedTotal,
                    int buyCurrRefundedLeft,
                    slice buyCurrAddr,
                    int buyCurrDecimal,
                    int buyCurrRate,
                    int buyCurrBalance,
                    slice buyCurrTokenAccountAddr
                ) = load_per_buy_curr(buyCurrAddr);
```
