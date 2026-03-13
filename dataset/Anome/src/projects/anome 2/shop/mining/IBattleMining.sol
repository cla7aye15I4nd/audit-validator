// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ShopTypes} from "../ShopTypes.sol";
import {IBattleMiningInternal} from "./IBattleMiningInternal.sol";

interface IBattleMining is IBattleMiningInternal {
    function claimXnome(address to) external;

    function getUnlockedXnome(address account) external view returns (uint256);

    function getUnlockedXnomeByDayRange(
        address account,
        uint256 startDay,
        uint256 endDay
    ) external view returns (uint256);

    function claimLossCompensation(address to) external;

    function getLossCompensation(address account) external view returns (uint256);

    function getMiningParams(address account) external view returns (BattleMiningAccountParams memory);

    function getDailyCompensationParams(
        address account
    ) external view returns (uint256 dailyCompensation, uint256 dailyMaxCompensation, bool isCompensationClaimed);

    function getCompensationClaimRecords(
        address account
    ) external view returns (ShopTypes.CompensationClaimRecord[] memory);

    function getCurrentDay() external view returns (uint256);

    function setLatestClaimDay(address account, uint256 day) external;

    function getCurrentXnomeDistributionAmount(uint256 destroyValueUsda) external view returns (uint256);
}
