# safeTransferFrom Bypasses Whitelist/Blacklist Enforcement


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | — |
| Triage Verdict | ✅ Valid |
| Source | scanner.smart_audit |
| Scan Model | o4-mini |
| Project ID | `b619bc20-116e-11f0-85f2-afceaa02a7b6` |
| Commit | `54b12f25ff139912cbddcc316c940624a64687cf` |

## Location

- **Local path:** `./src/GLDB Pulse Contracts/ENT&Swap/NFT.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/b619bc20-116e-11f0-85f2-afceaa02a7b6/source?file=$/github/GLBank/Web3/54b12f25ff139912cbddcc316c940624a64687cf/GLDB Pulse Contracts/ENT&Swap/NFT.sol
- **Lines:** 1–1

## Description

Vulnerability: The override of safeTransferFrom completely omits the contract’s whitelist/blacklist checks (the checkTransfer modifier used in createNFTsFromTokens). As a result, once an NFT is in the CREATED state, partyA can transfer it to any address—even if that address is blacklisted or not whitelisted.

Exploit Steps:
1. Deploy the NFT contract and initialize it with a whitelisting and blacklisting implementation.
2. Let A call createNFTsFromTokens(...) so that partyA receives NFT id = N (status CREATED).
3. Using the blacklist controller, add address X to the blacklist.
4. From partyA’s EOA, invoke safeTransferFrom(partyA, X, N, value, "").
   - The function skips any calls to checkWhiteBlacklist, so it passes the from/to and timing checks.
   - It updates the transfer history and ledger, then calls super.safeTransferFrom, which succeeds.
5. Confirm the transfer by calling balanceOf(X, N) and getHistoryLength(N):
   - balanceOf(X, N) == value
   - getHistoryLength(N) increased by 1

Impact: A blacklisted or non-whitelisted address X can receive and later realize (redeem) NFTs despite being explicitly disallowed by the blacklist policy, completely bypassing the intended access control.

## Vulnerable Code

```
function safeTransferFrom(address from, address to, uint256 id, uint256 value, bytes memory data)
        public
        virtual
        override
    {
        address operator = _msgSender();
        NFTMetadata storage mt = _getNFTStorage().nfts[id];
        address nftPartyA = mt.partyA;
        if (nftPartyA != from || to == nftPartyA) {
            revert TransferNotAllowed();
        }
        uint40 nowTime = uint40(block.timestamp);
        // Only before the execution date can it be transferred.
        if (mt.status != NFTStatus.CREATED || nowTime > mt.executionDate.startTime) {
            revert TransferNotAllowed();
        }
        if (_getNFTStorage().nftTransferHistory[id].length > MAX_TRANSFER_HISTORY_LENGTH) {
            revert MaxTransferExceed(id);
        }
        _updateTotalHold(id, to, value, true);
        _updateTotalHold(id, from, value, false);
        _getNFTStorage().nftTransferHistory[id].push(to);
        super.safeTransferFrom(from, to, id, value, data);
        emit NFTTransferred(operator, from, to, id, value);
    }
```

## Related Context

```
_msgSender ->     function _msgSender() internal view virtual override(Context, ContextUpgradeable) returns (address) {
        return ContextUpgradeable._msgSender();
    }

_getNFTStorage ->     function _getNFTStorage() internal pure returns (NFTStorage storage $) {
        assembly {
            $.slot := NFT_STORAGE_LOCATION
        }
    }

_updateTotalHold ->     function _updateTotalHold(uint256 nftId, address account, uint256 amount, bool increase) internal {
        mapping(NFTStatisticsType => uint256) storage r = _getNFTStorage().nftActivityLedger[nftId][account];
        if (increase) {
            r[NFTStatisticsType.TOTAL_HOLD] += amount;
        } else {
            r[NFTStatisticsType.TOTAL_HOLD] -= amount;
        }
    }
```
