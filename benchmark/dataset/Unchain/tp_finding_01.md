# Incorrect Accounting If Activated/Deactivated Multiple Times


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🟠 Major |
| Triage Verdict | ✅ Valid |
| Project ID | `f72af880-fbcd-11ee-bbd2-ff2e77acf2a4` |
| Commit | `cc2768a918f0b6a245d700d73c1415187926cfaf` |

## Location

- **Local path:** `./source_code/github/UNCHAIN-X-Labs/UNX-V3-Contracts/cc2768a918f0b6a245d700d73c1415187926cfaf/contracts/liquidity-mining/UNXwapV3LmPool.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/f72af880-fbcd-11ee-bbd2-ff2e77acf2a4/source?file=$/github/UNCHAIN-X-Labs/UNX-V3-Contracts/cc2768a918f0b6a245d700d73c1415187926cfaf/contracts/liquidity-mining/UNXwapV3LmPool.sol
- **Lines:** 169–178

## Description

The functions `activate()` and `deactivate()` can be called multiple times via the functions `list()` and `delist()` in the contract `UNXWapV3LmFactory`. However, the logic assumes that if a pool is deactivated, that it will not be activated again.

This is because when `deactivate()` is called, it sets `lastActivedBlock` to be the current block number and `actived` to false. Then the function `accumulateReward()` will treat the `lastActivedBlock` as the `endBlock` as opposed to the end block of the halving protocol. The logic will then only accumulate rewards up until the `lastActivedBlock`, and after it is accumulated to this point the function `accumulateReward()` will simply return without updating the `lastUpdateBlock`. 

Then if `activate()` is called after a pool was deactivated, it will update `actived` to be true, so that it will have the halving end block as the `endBlock`. This will then allow rewards to be accumulated from the `lastUpdateBlock` to the halving end block, which can include time that the pool was deactivated and should not accumulate rewards. 

As this can allocate funds that are not accounted for, it may cause the `HalvingProtocol` to run out of funds, resulting in users being unable to harvest rewards they are entitled to. In addition, it can cause users to be able to claim additional rewards that they should not be entitled to.

## Recommendation

We recommend ensuring that `activate()` and `deactivate()` cannot be called multiple times, or ensure that rewards are accurately accounted for if they are called multiple times.

## Vulnerable Code

```
);
        // Update rewardGrowthInside
        accumulateReward();
        reward = _harvestOperation(tickLower, tickUpper, liquidity, tokenId, nonfungiblePositionManager.ownerOf(tokenId));
    }

    function updateLiquidity(address user, uint256 tokenId) external override onlyNFPManager {
        (, , , , , int24 tickLower, int24 tickUpper, uint128 liquidity, , , , ) = nonfungiblePositionManager.positions(
            tokenId
        );

        // Update rewardGrowthInside
        accumulateReward();
        if(positionRewardInfos[tokenId].flag) {
             _harvestOperation(tickLower, tickUpper, liquidity, tokenId, address(0));
        } else {
            positionRewardInfos[tokenId].flag = true;
        }

        int128 liquidityDelta = int128(liquidity) - int128(positionRewardInfos[tokenId].liquidity);
        positionRewardInfos[tokenId].liquidity = liquidity;

        if(liquidityDelta != 0) {
            _updatePosition(tickLower, tickUpper, liquidityDelta);
            // Update latest rewardGrowthInside
            positionRewardInfos[tokenId].rewardGrowthInside = getRewardGrowthInside(tickLower, tickUpper);
            emit UpdateLiquidity(user, tokenId, liquidityDelta, tickLower, tickUpper);
        }
    }

    function activate() external override onlyLmFactory {
        require(!actived, "lmPool is already actived");
        actived = true;
    }

    function deactivate() external override onlyLmFactory whenActived {
        actived = false;
        lastActivedBlock = block.number;
    }

    function setAllocation(uint256 alloc) external override onlyLmFactory {
        accumulateReward();
        allocation = alloc;
    }

    function getRewardGrowthInside(int24 tickLower, int24 tickUpper) public view override returns (uint256 rewardGrowthInsideX128) {
        (, int24 tick, , , , ,) = v3Pool.slot0();
        return lmTicks.getRewardGrowthInside(tickLower, tickUpper, tick, rewardGrowthGlobalX128);
    }

    function currentRewardPerBlock() public view returns (uint256 reward) {
        reward = halvingProtocol.currentRewardPerBlock() * allocation / 10000;
    }

    function rewardPerBlockOf(uint256 halvingNum) public view returns (uint256 reward) {
        reward = halvingProtocol.rewardPerBlockOf(halvingNum) * allocation / 10000;
    }

    function _calculateReward(uint256 rewardGrowthInside, uint128 liquidity, uint256 tokenId) internal view returns (uint256 reward) {
        uint256 rewardGrowthInsideDelta;
        rewardGrowthInsideDelta = rewardGrowthInside - positionRewardInfos[tokenId].rewardGrowthInside;
        reward = FullMath.mulDiv(rewardGrowthInsideDelta, liquidity, FixedPoint128.Q128) * REWARD_PRECISION;
        reward += positionRewardInfos[tokenId].reward;
    }

    function _harvestOperation(int24 tickLower, int24 tickUpper, uint128 liquidity, uint256 tokenId, address to) internal returns (uint256 reward) {
        uint256 rewardGrowthInside = getRewardGrowthInside(tickLower, tickUpper);
        reward = _calculateReward(rewardGrowthInside, liquidity, tokenId);
        positionRewardInfos[tokenId].rewardGrowthInside = rewardGrowthInside;
```
