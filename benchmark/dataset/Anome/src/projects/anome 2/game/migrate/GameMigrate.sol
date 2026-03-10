// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IConfig} from "../../config/IConfig.sol";
import {GameStorage} from "../GameStorage.sol";

import {IGameMigrate} from "./IGameMigrate.sol";
import {SafeOwnableInternal} from "../../../lib/solidstate/access/ownable/SafeOwnableInternal.sol";

contract GameMigrate is IGameMigrate, SafeOwnableInternal {
    function migrate01(address config) external override onlyOwner {
        GameStorage.Layout storage data = GameStorage.layout();
        data.config = IConfig(config);
    }
}