// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IBnomeStakeInternal {
    struct BnomeStakeOrderParams {
        uint256 index;
        uint256 createdAt;
        uint256 bnomeAmount;
        uint256 unstakedAmount;
        uint256 anchorCard;
        uint256 anchorCardInitialDestruction;
        uint256 unlocked;
    }

    struct BnomeStakeStatistic {
        uint256 totalStaked;
        uint256 totalUnstaked;
    }

    struct BnomeStakeAccountStatistic {
        uint256 highBorrowLTVLimit;
        uint256 totalHighBorrowLTVLimit;
        uint256 bnomeStaked;
        uint256 bnomeTotalUnstaked;
        uint256 orderCount;
    }

    error AlreadyUnstaked();
}
