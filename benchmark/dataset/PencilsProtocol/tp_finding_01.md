# Incorrect Refund Calculation in `reverse`


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🟠 Major |
| Triage Verdict | ✅ Valid |
| Project ID | `1fed1c20-02af-11ef-b6bc-1de73d127368` |
| Commit | `85a34006d9445412fb5e9a315a6ad90ab43ad74d` |

## Location

- **Local path:** `./source_code/github/PencilsProtocol/audit-pencils-protocol/a751770f1b38a7c7a82f1486ffcae7450fa59580/src/launchpad/PenPadFixedSwapNFT.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/1fed1c20-02af-11ef-b6bc-1de73d127368/source?file=$/github/PencilsProtocol/audit-pencils-protocol/a751770f1b38a7c7a82f1486ffcae7450fa59580/src/launchpad/PenPadFixedSwapNFT.sol
- **Lines:** 389–391

## Description

The `amount1` variable in the `PenPadFixedSwapNFT.reverse` function represents the amount of `token1` to refund if `token0` is returned. The pointed lines refer to the calculation in the case of an ERC721 pool, and should calculate the refund amount proportionally to the returned NFTs.

However, the current code constantly sets `amount1` to `myAmountSwapped1[msg.sender][index]` because `amount0OrTokenIds.getSetBitCount(pool.amountTotal0)` and `_amount0` contain the same value at that point. So, if a user returns $k$ NFTs out of $n$ they bought, a full refund is always issued.

Thanks to this mechanism, any whitelisted user can take all the available NFTs but 1 for free by buying all of them and return 1 but obtaining a full refund.

## Recommendation

We recommend computing the exact refund amount. Specifically, the refund should be calculated, as done in the ERC1155 logic, proportionally to the bought `token0` units, most likely replacing the `amount0` denominator with `myAmountSwapped0[msg.sender][index].getSetBitCount(pool.amountTotal0)`

## Vulnerable Code

```
require(enableReverses[index], "Reverse is disabled");

        uint256 amount1 = 0;
        Pool memory pool = pools[index];
        // send token0 to this contract
        if (pool.isERC721) {
            amount0OrTokenIds = amount0OrTokenIds.normalize(pool.amountTotal0);
            require(
                (amount0OrTokenIds != 0)
                    && (amount0OrTokenIds & myAmountSwapped0[msg.sender][index] == amount0OrTokenIds),
                "invalid amount0OrTokenIds"
            );

            uint256 _amount0 = amount0OrTokenIds.getSetBitCount(pool.amountTotal0);
            amount1 =
                (amount0OrTokenIds.getSetBitCount(pool.amountTotal0) * myAmountSwapped1[msg.sender][index]) / _amount0;
            myAmountSwapped0[msg.sender][index] = myAmountSwapped0[msg.sender][index] & (~amount0OrTokenIds);
            amountSwap0[index] = amountSwap0[index] & (~amount0OrTokenIds);

            if (pool.claimAt == 0) {
                uint256[] memory positions = amount0OrTokenIds.getSetBitPositions(pool.amountTotal0);
                for (uint256 i = 0; i < positions.length; i++) {
                    uint256 tokenId = pool.tokenIds[positions[i]];
                    IERC721Upgradeable(pool.token0).safeTransferFrom(msg.sender, address(this), tokenId);
                }
            }
        } else {
            require(amount0OrTokenIds <= myAmountSwapped0[msg.sender][index], "invalid amount0OrTokenIds");
            amount1 = (amount0OrTokenIds * myAmountSwapped1[msg.sender][index]) / myAmountSwapped0[msg.sender][index];
            myAmountSwapped0[msg.sender][index] = myAmountSwapped0[msg.sender][index] - amount0OrTokenIds;
            amountSwap0[index] = amountSwap0[index] - amount0OrTokenIds;

            if (pool.claimAt == 0) {
                IERC1155Upgradeable(pool.token0).safeTransferFrom(
                    msg.sender, address(this), pool.tokenIds[0], amount0OrTokenIds, ""
                );
            }
        }

        myAmountSwapped1[msg.sender][index] = myAmountSwapped1[msg.sender][index] - amount1;
        amountSwap1[index] = amountSwap1[index] - amount1;

        // transfer token1 to sender
        tokenTransfer(pool.token1, msg.sender, amount1);

        emit Reversed(index, msg.sender, amount0OrTokenIds, amount1);
    }

    function getTokenIdsByIndex(uint256 index) external view returns (uint256[] memory) {
        return pools[index].tokenIds;
    }

    function getTokenIdsByBitmap(uint256 index, uint256 bitmap) external view returns (uint256[] memory) {
        Pool memory pool = pools[index];
        bitmap = bitmap.normalize(pool.amountTotal0);
        uint256[] memory positions = bitmap.getSetBitPositions(pool.amountTotal0);
        uint256[] memory tokenIds = new uint256[](positions.length);
        for (uint256 i = 0; i < positions.length; i++) {
            tokenIds[i] = pool.tokenIds[positions[i]];
        }
        return tokenIds;
    }
```
