// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ShopTypes} from "../ShopTypes.sol";
import {ShopStorage} from "../ShopStorage.sol";

import {IBnomeStake} from "./IBnomeStake.sol";
import {BnomeStakeInternal} from "./BnomeStakeInternal.sol";
import {SafeOwnableInternal} from "../../../lib/solidstate/access/ownable/SafeOwnableInternal.sol";

contract BnomeStake is IBnomeStake, BnomeStakeInternal, SafeOwnableInternal {
    function stakeBnome(uint256 amount) external {
        _stakeBnome(amount);
    }

    function unstakeBnome(uint256 index) external {
        _unstakeBnome(index);
    }

    function getBnomeStakeOrders(
        uint256 page,
        uint256 count
    ) external view returns (BnomeStakeOrderParams[] memory result) {
        ShopStorage.Layout storage l = ShopStorage.layout();
        uint256 totalOrders = l.bnomeStakeOrders[msg.sender].length;
        
        uint256 start = page * count;
        if (start >= totalOrders) {
            return new BnomeStakeOrderParams[](0);
        }
        
        uint256 end = start + count;
        if (end > totalOrders) {
            end = totalOrders;
        }
        
        uint256 resultSize = end - start;
        result = new BnomeStakeOrderParams[](resultSize);
        
        for (uint256 i = 0; i < resultSize; i++) {
            uint256 orderIndex = start + i;
            result[i] = BnomeStakeOrderParams({
                index: l.bnomeStakeOrders[msg.sender][orderIndex].index,
                createdAt: l.bnomeStakeOrders[msg.sender][orderIndex].createdAt,
                bnomeAmount: l.bnomeStakeOrders[msg.sender][orderIndex].bnomeAmount,
                unstakedAmount: l.bnomeStakeOrders[msg.sender][orderIndex].unstakedAmount,
                anchorCard: l.bnomeStakeOrders[msg.sender][orderIndex].anchorCard,
                anchorCardInitialDestruction: l.bnomeStakeOrders[msg.sender][orderIndex].anchorCardInitialDestruction,
                unlocked: _getUnlockedBnome(l.bnomeStakeOrders[msg.sender][orderIndex].index)
            });
        }
    }

    function getBnomeStakeStatistic() external view returns (BnomeStakeStatistic memory) {
        ShopStorage.Layout storage l = ShopStorage.layout();
        return BnomeStakeStatistic({
            totalStaked: l.bnomeTotalStaked,
            totalUnstaked: l.bnomeTotalUnstaked
        });
    }

    function getBnomeStakeAccountStatistic(
        address account
    ) external view returns (BnomeStakeAccountStatistic memory) {
        ShopStorage.Layout storage l = ShopStorage.layout();
        return BnomeStakeAccountStatistic({
            highBorrowLTVLimit: l.highBorrowLTVLimit[account],
            totalHighBorrowLTVLimit: l.bnomeAccountTotalHighBorrowLTVLimit[account],
            bnomeStaked: l.bnomeAccountTotalStaked[account],
            bnomeTotalUnstaked: l.bnomeAccountTotalUnstaked[account],
            orderCount: l.bnomeStakeOrders[account].length
        });
    }

    function adminSetHighBorrowLTVLimit(address account, uint256 limit) external onlyOwner {
        ShopStorage.Layout storage l = ShopStorage.layout();
        l.highBorrowLTVLimit[account] = limit;
    }
}
