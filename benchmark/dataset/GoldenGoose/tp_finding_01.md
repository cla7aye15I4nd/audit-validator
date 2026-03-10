# Incorrect Order of `share` and `assetAmount` in `RedeemLock` Struct


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🟠 Major |
| Triage Verdict | ✅ Valid |
| Project ID | `6d39eb30-786f-11ef-b8f3-35e3732ff258` |
| Commit | `0749dc0878a90a2cfe53cb823986465f3e823d35` |

## Location

- **Local path:** `./source_code/github/RollNA/x-project-contract/be44567375e8b18b82bc651a27d52d3d7b56fc5b/contracts/USDVault.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/6d39eb30-786f-11ef-b8f3-35e3732ff258/source?file=$/github/RollNA/x-project-contract/be44567375e8b18b82bc651a27d52d3d7b56fc5b/contracts/USDVault.sol
- **Lines:** 147–147

## Description

In the `_redeem()` function, the `RedeemLock` struct is intended to store information about a redemption, including the `share` (LP token amount) and `assetAmount` (corresponding asset amount). However, the values for `share` and `assetAmount` are incorrectly reversed when generating the `RedeemLock`. This mistake could lead to various issues, such as failed redemptions or users receiving fewer tokens than expected.

## Recommendation

Swap the `share` and `assetAmount` values when creating the `RedeemLock` struct in the `_redeem()` function to correctly assign them to their respective fields.

## Vulnerable Code

```
emit Withdraw(setEventId(),redeemLock.account,redeemLock.assetAmount,redeemLock.share,redeemLock.price,lpToken.totalSupply(),block.timestamp);
        emit UnLockRedeem(id,redeemLock.account,redeemLock.share,block.timestamp);

        balanceMap[redeemLock.account] -= redeemLock.share;
        redeemLock.share = 0;
        redeemLock.assetAmount = 0;
        redeemMap[id] = redeemLock;
    }

    function redeemAndUnLockDeposit(uint256 amount,uint256 minAssetAmount,uint256[] memory ids) external {
        unLockDeposit(ids);
        _redeem(msg.sender,amount,minAssetAmount);
    }

    function redeem(uint256 share,uint256 minAssetAmount) external {
        _redeem(msg.sender,share,minAssetAmount);
    }

    function _redeem(address account,uint256 share,uint256 minAssetAmount) internal nonReentrant{
        require(availableShare[account] >= share,"Available balance not enough");

        uint256 assetAmount = lpToken.convertToAssets(share);
        require(assetAmount >= minAssetAmount,"Asset amount error");

        availableShare[account] -= share;
        lpToken.burn(share,0);
        emit Redeem(setEventId(),account,assetAmount,share,lpToken.price(),getRedeemLockLength(),dataStorage.redeemLockTime(),lpToken.totalSupply(),block.timestamp);

        redeemMap[setRedeemLockId()] = RedeemLock(account,assetAmount,share,lpToken.price(),block.timestamp);
    }

    function setDepositLockId() internal returns(uint256) {
        return depositLockId++;
    }

    function setRedeemLockId() internal returns (uint256) {
        return redeemLockId++;
    }

    function getDepositLockInfo(uint256[] memory ids) public view returns(DepositLock[] memory) {
        DepositLock[] memory list = new DepositLock[](ids.length);
        for(uint256 i; i<ids.length; i++){
            list[i] = depositMap[ids[i]];
        }
        return list;
    }

    function getDepositLockLength() public view returns(uint256) {
        return depositLockId;
    }

    function getRedeemLockInfo(uint256[] memory ids) public view returns(RedeemLock[] memory) {
        RedeemLock[] memory list = new RedeemLock[](ids.length);
        for(uint256 i; i<ids.length; i++){
            list[i] = redeemMap[ids[i]];
        }
        return list;
    }
```
