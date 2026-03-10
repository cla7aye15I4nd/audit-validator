// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {GameTypes} from "../GameTypes.sol";

interface IGameManagedCard {
    function getManagedCard(address account) external view returns (GameTypes.ManagedCard[] memory);
}
