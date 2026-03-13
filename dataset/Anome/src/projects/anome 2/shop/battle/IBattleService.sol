// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ShopTypes} from "../ShopTypes.sol";

import {IBattleServiceInternal} from "./IBattleServiceInternal.sol";

interface IBattleService is IBattleServiceInternal {
    function onBattled(
        address winner,
        address loser,
        uint256 amount,
        uint256 winnerCardCost,
        uint256 loserCardCost,
        uint256 destroyValue
    )
        external
        returns (
            uint256 winnerVnomeAmount,
            uint256 loserVnomeAmount,
            uint256 winnerSuperiorVnomeAmount,
            uint256 loserSuperiorVnomeAmount,
            uint256 wkAmount
        );

    function destroyCard(
        address account,
        address cardAddr,
        address winner,
        address loser
    ) external returns (uint256 xnomeAmount);

    function getAccountBattleLevel(address account) external view returns (uint256);

    function getAccountBattleExp(address account) external view returns (uint256);

    function getAccountBattleRewardInfo(address account) external view returns (ShopTypes.BattleRewardInfo memory);

    function getAccountBattleRecordLength(address account) external view returns (uint256);

    function getAccountBattleRecords(
        address account,
        uint256 page,
        uint256 size
    ) external view returns (ShopTypes.BattleRewardRecord[] memory);
}
