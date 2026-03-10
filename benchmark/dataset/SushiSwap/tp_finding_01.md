# Improper Validation on Initial Liquidity Allows Permanent Unusable Pair


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🟡 Medium |
| Triage Verdict | ✅ Valid |
| Project ID | `953e5590-47ad-11f0-8fe7-f5f1ab22f4b9` |
| Commit | `3a40dfc61e13f56f0683b1e971a39490a4ab7142` |

## Location

- **Local path:** `./source_code/github/solidity-io/kadena-amm-contracts/d5a54f7c7a18222374b305bc4fcdc074c623312f/contracts/modules/sushi-exchange.pact`
- **ACC link:** https://acc.audit.certikpowered.info/project/953e5590-47ad-11f0-8fe7-f5f1ab22f4b9/source?file=$/github/solidity-io/kadena-amm-contracts/d5a54f7c7a18222374b305bc4fcdc074c623312f/contracts/modules/sushi-exchange.pact
- **Lines:** 248–248

## Description

The `add-liquidity` function in the `sushi-exchange` module fails to validate that `amountADesired`, `amountBDesired`, `amountAMin`, `amountBMin` are strictly positive. This issue exists during the initial liquidity addition. When both `reserveA` and `reserveB` are `0.0`, the function will bypass the `quote()` logic, which enforces `amountA` to be larger than 0.
```lisp=342
    (enforce (> amountA 0.0) "quote: insufficient amount")
```

This allows a malicious actor to input negative values for both `amountADesired` and `amountBDesired`, which leads to the following consequences:

If a malicious actor submits negative values for `amountADesired` and/or `amountBDesired`, the following consequences arise:

- The `token::transfer` calls execute with negative values, resulting in a transfer from the pair contract to the attacker, instead of a deposit to the pool. 
- LP tokens are minted using `sqrt(amountA * amountB)`. Since both values are negative, their product remains positive, allowing the attacker to mint fake LP tokens without making a valid deposit.
- The pool enters an invalid state with negative reserves and incorrect total supply, causing all future calls to `add-liquidity` to fail slippage checks inside `quote()`.


Because the protocol enforces unique `(tokenA, tokenB)` pair through the `get-pair-key` mechanism, this vulnerability leads to a permanent lock-out of that pair. There is no way to recreate or reset the pair using existing protocol methods.

## Recommendation

We recommend the team to add zero validation to parameters `amountADesired`, `amountBDesired`, `amountAMin`, and `amountBMin`.

## Vulnerable Code

```
tokenB:module{fungible-v2}
    )
    (read pairs (get-pair-key tokenA tokenB)))

  (defun pair-exists:bool
    ( tokenA:module{fungible-v2}
      tokenB:module{fungible-v2}
    )
    (with-default-read pairs
      (get-pair-key tokenA tokenB)
      { 'account: "" }
      { 'account := a }
      (> (length a) 0))
  )

  (defun update-reserves
    ( p:object{pair}
      pair-key:string
      reserve0:decimal
      reserve1:decimal
    )
    (require-capability (UPDATE pair-key reserve0 reserve1))
    (update pairs pair-key
      { 'leg0: { 'token: (at 'token (at 'leg0 p))
               , 'reserve: reserve0 }
      , 'leg1: { 'token: (at 'token (at 'leg1 p))
               , 'reserve: reserve1 }})
  )

  (defun add-liquidity:object
    ( tokenA:module{fungible-v2}
      tokenB:module{fungible-v2}
      amountADesired:decimal
      amountBDesired:decimal
      amountAMin:decimal
      amountBMin:decimal
      sender:string
      to:string
      to-guard:guard
    )
    (enforce (try false (tokenA::enforce-unit amountADesired)) "amountADesired precision mismatch")
    (enforce (try false (tokenB::enforce-unit amountBDesired)) "amountBDesired precision mismatch")
    (with-capability (MUTEX) ;; obtain the mutex lock
      (obtain-pair-mutex-lock (get-pair-key tokenA tokenB)))
    (let*
      ( (p (get-pair tokenA tokenB))
        (reserveA (reserve-for p tokenA))
        (reserveB (reserve-for p tokenB))
        (amounts
          (if (and (= reserveA 0.0) (= reserveB 0.0))
            [amountADesired amountBDesired]
            (let ((amountBOptimal (quote amountADesired reserveA reserveB)))
              (if (<= amountBOptimal amountBDesired)
                (let ((x (enforce (>= amountBOptimal amountBMin)
                           "add-liquidity: insufficient B amount")))
                  [amountADesired amountBOptimal])
                (let ((amountAOptimal (quote amountBDesired reserveB reserveA)))
                  (enforce (<= amountAOptimal amountADesired)
                    "add-liquidity: optimal A less than desired")
                  (enforce (>= amountAOptimal amountAMin)
```
