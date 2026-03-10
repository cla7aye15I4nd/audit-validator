# Fee Evasion via Multiplication Overflow in Fee Calculation


| Field | Value |
| --- | --- |
| Type | False Positive |
| Severity | low |
| Triage Verdict | ❌ Invalid |
| Triage Reason | Context not considerred |
| Source | scanner.token_scanner |
| Scan Model | o4-mini, gemini-2.5-pro |
| Project ID | `b619bc20-116e-11f0-85f2-afceaa02a7b6` |
| Commit | `54b12f25ff139912cbddcc316c940624a64687cf` |

## Location

- **Local path:** `./source_code/github/GLBank/Web3/54b12f25ff139912cbddcc316c940624a64687cf/GLDB Pulse Contracts/PLT/GLDBToken.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/b619bc20-116e-11f0-85f2-afceaa02a7b6/source?file=$/github/GLBank/Web3/54b12f25ff139912cbddcc316c940624a64687cf/GLDB Pulse Contracts/PLT/GLDBToken.sol
- **Lines:** 1–1

## Description

The `_deflationAmount` and `_taxAmount` functions calculate fees using the formula `(amount * BPS) / MAX_BPS_AMOUNT`. The multiplication `amount * BPS` is performed without using a safe math library. If a user transfers an `amount` large enough, this multiplication can overflow, resulting in a much smaller-than-expected fee. This allows an attacker to avoid the intended deflationary burn and tax, leading to an inconsistency in the total supply reduction.Use a safe math library (e.g., OpenZeppelin's `SafeMath` or Solidity >=0.8.0 checked arithmetic) for fee calculations to prevent overflow. Alternatively, enforce a `maxSupply` limit that ensures `maxSupply * MAX_BPS_AMOUNT` cannot overflow a `uint256`.1. Assume the contract is deployed with a `maxSupply` near `type(uint256).max`.
2. The owner mints a very large number of tokens for an attacker, for example, `(type(uint256).max / 10000) * 2`.
3. The owner sets `deflationBPS` to 5000 (50%).
4. The attacker calls `transfer` with `amount = (type(uint256).max / 10000) * 2`.
5. In `_deflationAmount`, the multiplication `amount * deflationBps` overflows `uint256`, wrapping around to a much smaller value.
6. As a result, the calculated `deflationAmount` is near zero instead of the intended 50% of the transfer amount.
7. The attacker successfully transfers a vast quantity of tokens while bypassing the intended deflationary mechanism, thus keeping the total supply inappropriately high.

## Recommendation

Use a safe math library (e.g., OpenZeppelin's `SafeMath` or Solidity >=0.8.0 checked arithmetic) for fee calculations to prevent overflow. Alternatively, enforce a `maxSupply` limit that ensures `maxSupply * MAX_BPS_AMOUNT` cannot overflow a `uint256`.

## Vulnerable Code

```
function _deflationAmount(TaxStorage memory taxStorage,uint256 amount) internal pure returns (uint256 deflationAmount) {
    uint256 deflationBps = taxStorage.deflationBPS;
    if (deflationBps > 0) {
        return (amount * deflationBps) / MAX_BPS_AMOUNT;
    }
    return 0;
}
```
