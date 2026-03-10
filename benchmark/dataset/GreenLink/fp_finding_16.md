# A Single Failing Transfer Reverts the Entire Batch


| Field | Value |
| --- | --- |
| Type | False Positive |
| Severity | low |
| Triage Verdict | ❌ Invalid |
| Triage Reason | not important enough |
| Source | scanner.token_scanner |
| Scan Model | o4-mini, gemini-2.5-pro |
| Project ID | `b619bc20-116e-11f0-85f2-afceaa02a7b6` |
| Commit | `54b12f25ff139912cbddcc316c940624a64687cf` |

## Location

- **Local path:** `./source_code/github/GLBank/Web3/54b12f25ff139912cbddcc316c940624a64687cf/GLDB Pulse Contracts/PLT/GLDBToken.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/b619bc20-116e-11f0-85f2-afceaa02a7b6/source?file=$/github/GLBank/Web3/54b12f25ff139912cbddcc316c940624a64687cf/GLDB Pulse Contracts/PLT/GLDBToken.sol
- **Lines:** 1–1

## Description

The `batchTransfer` function iterates through a list of recipients and executes a `transfer` for each one within a single transaction. If any of the individual `transfer` calls fail for any reason (e.g., the recipient is on a blacklist, a transfer exceeds the maximum allowed balance for a user, etc.), the entire loop is aborted, and the parent `batchTransfer` transaction reverts. This means a single invalid recipient can prevent all other valid transfers in the batch from succeeding, causing a Denial of Service for the batch operation.The `transfer` call inside the `batchTransfer` loop should be wrapped in a `try/catch` block. This would allow the function to handle a failing transfer (e.g., by emitting an event indicating the failure) without reverting the entire transaction. The successful transfers in the batch could then be completed.1. The contract has `isBlacklistEnabled` set to `true`.
2. A user, Alice, wants to airdrop tokens to 10 recipients. She calls `batchTransfer` with two arrays of 10 elements each.
3. The 5th address in her `toList` array, `0xbadactor...`, has been blacklisted by the owner. The other 9 addresses are valid.
4. The `for` loop begins execution. The first four transfers succeed internally.
5. When `i = 4`, the function calls `transfer(0xbadactor..., amount)`.
6. This `transfer` call invokes the `checkTransfer` modifier, which finds that the recipient is blacklisted and reverts the transaction.
7. Because the `transfer` call reverted, the entire `batchTransfer` transaction fails. None of the 10 recipients, including the 9 legitimate ones, receive their tokens. Any attempt by Alice to complete this batch will fail as long as the blacklisted address is included.

## Recommendation

The `transfer` call inside the `batchTransfer` loop should be wrapped in a `try/catch` block. This would allow the function to handle a failing transfer (e.g., by emitting an event indicating the failure) without reverting the entire transaction. The successful transfers in the batch could then be completed.

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
