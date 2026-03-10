# Rounding‐Based Fee Evasion via batchTransfer


| Field | Value |
| --- | --- |
| Type | False Positive |
| Severity | — |
| Triage Verdict | ❌ Invalid |
| Triage Reason | Fees are calculated seperately |
| Source | scanner.smart_audit |
| Scan Model | o4-mini |
| Project ID | `b619bc20-116e-11f0-85f2-afceaa02a7b6` |
| Commit | `54b12f25ff139912cbddcc316c940624a64687cf` |

## Location

- **Local path:** `./source_code/github/GLBank/Web3/54b12f25ff139912cbddcc316c940624a64687cf/GLDB Pulse Contracts/PLT/GLDBToken.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/b619bc20-116e-11f0-85f2-afceaa02a7b6/source?file=$/github/GLBank/Web3/54b12f25ff139912cbddcc316c940624a64687cf/GLDB Pulse Contracts/PLT/GLDBToken.sol
- **Lines:** 1–1

## Description

The batchTransfer function simply invokes transfer() on each recipient in a loop, and transfer() applies tax and burn fees independently to each send. Because those fees are computed with integer division (floored), splitting a large transfer into many small transfers can drive each individual fee to zero – effectively evading the fee altogether.

Exploit Steps:
1. Assume taxBPS is 100 (1%) and deflationBPS is 0.  
2. Normally, transferring 100 tokens via a single transfer() call would levy a fee of (100 × 100)/10 000 = 1 token, so the recipient gets 99 tokens and 1 token is collected as tax.
3. Instead, the attacker calls batchTransfer with toList = [Bob, Bob, …, Bob] (100 entries) and amountList = [1, 1, …, 1] (100 entries).
4. For each of the 100 micro-transfers:  
   • taxAmount = (1 × 100)/10 000 = 0  
   • deflationAmount = 0  
   • net amountToTransfer = 1 − 0 = 1
5. After the loop completes Bob’s balance has increased by 100 tokens, and the protocol collected 0 tokens in fees instead of the expected 1 token.

Because batchTransfer does not aggregate amounts before computing a single fee, an attacker can reduce or entirely avoid fees simply by slicing one large transfer into many small ones.

## Vulnerable Code

```
function batchTransfer(address[] memory toList, uint256[] memory amountList) external whenNotPaused {
        uint256 len = toList.length;
        if (len != amountList.length) {
            revert InvalidRecipientAndAmount();
        }
        for (uint256 i = 0; i < len;) {
            transfer(toList[i], amountList[i]);
            unchecked {
                i++;
            }
        }
    }
```
