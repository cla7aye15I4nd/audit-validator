// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IConfig} from "../../config/IConfig.sol";
import {GameGuildStorage} from "../guild/GameGuildStorage.sol";

import {IOgMigrate} from "./IOgMigrate.sol";
import {SafeOwnableInternal} from "../../../lib/solidstate/access/ownable/SafeOwnableInternal.sol";

contract OgMigrate is IOgMigrate, SafeOwnableInternal {
    function migrate01(address config, address shop) external override onlyOwner {
        GameGuildStorage.Layout storage lg = GameGuildStorage.layout();
        lg.config = IConfig(config);
        lg.shop = shop;
    }
}
