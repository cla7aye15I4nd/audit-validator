// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IGameAdmin} from "./admin/IGameAdmin.sol";
import {IGameRoom} from "./room/IGameRoom.sol";
import {IGameRules} from "./rules/IGameRules.sol";
import {IGameChat} from "./chat/IGameChat.sol";
import {IGameSettlerInternal} from "./settle/IGameSettlerInternal.sol";
import {IGameManagedCard} from "./managed_card/IGameManagedCard.sol";
import {IGameMatcher} from "./matcher/IGameMatcher.sol";
import {IGameFacet} from "./facet/IGameFacet.sol";
import {IGameMigrate} from "./migrate/IGameMigrate.sol";

interface IGame is
    IGameAdmin,
    IGameRoom,
    IGameRules,
    IGameChat,
    IGameSettlerInternal,
    IGameManagedCard,
    IGameMatcher,
    IGameFacet,
    IGameMigrate
{}
