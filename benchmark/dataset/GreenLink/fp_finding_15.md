# Max Balance Limit Can Be Bypassed for the Tax Recipient Address


| Field | Value |
| --- | --- |
| Type | False Positive |
| Severity | — |
| Triage Verdict | ❌ Invalid |
| Triage Reason | Intended design |
| Source | scanner.smart_audit |
| Scan Model | gemini-2.5-pro |
| Project ID | `b619bc20-116e-11f0-85f2-afceaa02a7b6` |
| Commit | `54b12f25ff139912cbddcc316c940624a64687cf` |

## Location

- **Local path:** `./source_code/github/GLBank/Web3/54b12f25ff139912cbddcc316c940624a64687cf/GLDB Pulse Contracts/PLT/GLDBToken.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/b619bc20-116e-11f0-85f2-afceaa02a7b6/source?file=$/github/GLBank/Web3/54b12f25ff139912cbddcc316c940624a64687cf/GLDB Pulse Contracts/PLT/GLDBToken.sol
- **Lines:** 1–1

## Description

The function `_checkMaxAmountPerAddress` is intended to enforce a maximum token balance per address. This check is applied to the recipient of a transfer (`to`) but is not applied to the `taxAddress` when it receives funds from transfer fees. The `_payFeeWhenTransfer` function, called by `transfer`, first checks the main recipient's potential new balance, and only then does it proceed to transfer the tax fee. This creates a logical flaw where the tax fee transfer itself can cause the `taxAddress` to exceed its `maxTokenAmountPerAddress` without any validation, thus breaking a core tokenomics rule. The `batchTransfer` function can be used to repeatedly trigger this vulnerability in a single transaction, making it easier to accumulate a large amount in the `taxAddress`.

**Exploit Demonstration:**

1. **Prerequisites:**
   - The contract is initialized with `isMaxAmountPerAddressSet` as `true` and `maxTokenAmountPerAddress` set to a specific limit (e.g., 1,000 tokens).
   - The contract is initialized with `isTaxable` as `true`, a valid `taxAddress`, and a non-zero `taxBPS` (e.g., 1000, representing a 10% tax).
   - The `taxAddress` holds a balance close to the limit, for instance, 950 tokens. An attacker can achieve this state by performing legitimate transfers that generate tax fees.
   - The attacker is a regular token holder with a sufficient balance to perform the transfer (e.g., more than 600 tokens).

2. **Exploitation Step:**
   - The attacker calls the `batchTransfer` function to send tokens to any valid address other than the `taxAddress`. A single-recipient transfer is sufficient to demonstrate the flaw.
   - `batchTransfer(toList=[0xRecipient...], amountList=[600])`

3. **Execution Analysis:**
   - The `batchTransfer` function calls `transfer(0xRecipient..., 600)`.
   - The `transfer` function calls `_payFeeWhenTransfer`. A tax of 60 tokens (10% of 600) is calculated.
   - `_checkMaxAmountPerAddress` is called for the recipient `0xRecipient...` with the net transfer amount of 540 tokens. Assuming the recipient's balance is low, this check passes.
   - The `_payFeeWhenTransfer` function then proceeds to execute `super._transfer(from, taxAddress, 60)`, transferring the 60 tax tokens. No balance check is performed for the `taxAddress`.
   - The `taxAddress` balance, which was 950, is now incremented by 60, resulting in a new balance of 1,010 tokens.
   - The transaction completes successfully.

4. **Result:**
   - The `taxAddress` now holds 1,010 tokens, exceeding the configured `maxTokenAmountPerAddress` of 1,000. This demonstrates that the control mechanism to limit holdings per address has been successfully bypassed for the `taxAddress`.

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
