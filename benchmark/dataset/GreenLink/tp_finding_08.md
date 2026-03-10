# Enabling `authorisedSenderEnabled` Freezes All Non-Authorized User Tokens


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | high |
| Triage Verdict | ✅ Valid |
| Triage Reason | Centralization Related Risk |
| Source | scanner.token_scanner |
| Scan Model | o4-mini, gemini-2.5-pro |
| Project ID | `b619bc20-116e-11f0-85f2-afceaa02a7b6` |
| Commit | `54b12f25ff139912cbddcc316c940624a64687cf` |

## Location

- **Local path:** `./source_code/github/GLBank/Web3/54b12f25ff139912cbddcc316c940624a64687cf/GLDB Pulse Contracts/PLT/GLDBToken.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/b619bc20-116e-11f0-85f2-afceaa02a7b6/source?file=$/github/GLBank/Web3/54b12f25ff139912cbddcc316c940624a64687cf/GLDB Pulse Contracts/PLT/GLDBToken.sol
- **Lines:** 1–1

## Description

The `_update` function, which is executed on every token transfer, mint, or burn, contains a check that can enable a restrictive operational mode. If `authorisedSenderEnabled` is set to `true`, only addresses marked as 'authorized senders' can trigger actions that call `_update`. Regular token holders are not authorized by default. If this feature is enabled, it effectively freezes the assets of all non-authorized users, as they cannot call `transfer` or `approve`, leading to a permanent Denial of Service for those users.The `authorisedSenderEnabled` feature should be used with extreme caution and its implications must be clearly communicated. It should not be enabled for a token intended for public trading or general use. If it must be used, there should be a transparent and accessible process for users to request authorization, or it should be controlled by a decentralized governance mechanism rather than a single owner.1. The contract is deployed with the `authorisedSenderEnabled` parameter set to `true` during initialization. By default, only the `tokenOwner` is an authorized sender.
2. The owner transfers 1000 tokens to a regular user, Alice.
3. Alice now owns 1000 tokens but is not in the `authorisedSender` mapping.
4. Alice attempts to transfer 500 tokens to Bob by calling `transfer(Bob, 500)`.
5. The `transfer` function calls `_update(Alice, Bob, 500)`.
6. Inside `_update`, the condition `authStorage.authorisedSenderEnabled && !authStorage.authorisedSender[msg.sender]` evaluates to `true && !false`, which is `true`.
7. The transaction reverts with the `UnAuthorisedSender` error.
8. Alice is unable to transfer her tokens, approve another account to spend them, or perform any action that relies on the `_update` function. Her funds are effectively frozen.

## Recommendation

The `authorisedSenderEnabled` feature should be used with extreme caution and its implications must be clearly communicated. It should not be enabled for a token intended for public trading or general use. If it must be used, there should be a transparent and accessible process for users to request authorization, or it should be controlled by a decentralized governance mechanism rather than a single owner.

## Vulnerable Code

```
function _update(address from, address to, uint256 value)
    internal
    virtual
    override(ERC20Upgradeable, ERC20PausableUpgradeable, ERC20CappedUpgradeable)
{
    AuthStorage storage authStorage = _getAuthStorage();
    if (authStorage.authorisedSenderEnabled && !authStorage.authorisedSender[msg.sender]) {
        revert UnAuthorisedSender();
    }
    super._update(from, to, value);
}
```
