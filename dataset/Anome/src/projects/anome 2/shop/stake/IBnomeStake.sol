// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ShopTypes} from "../ShopTypes.sol";
import {IBnomeStakeInternal} from "./IBnomeStakeInternal.sol";

interface IBnomeStake is IBnomeStakeInternal {
    function stakeBnome(uint256 amount) external;

    function unstakeBnome(uint256 index) external;

    function getBnomeStakeOrders(
        uint256 page,
        uint256 count
    ) external view returns (BnomeStakeOrderParams[] memory);

    function getBnomeStakeStatistic() external view returns (BnomeStakeStatistic memory);

    function getBnomeStakeAccountStatistic(
        address account
    ) external view returns (BnomeStakeAccountStatistic memory);
}
