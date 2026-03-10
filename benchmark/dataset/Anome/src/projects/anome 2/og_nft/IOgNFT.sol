// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IOg721} from "./erc721/IOg721.sol";
import {IGameGuild} from "./guild/IGameGuild.sol";
import {IOgMigrate} from "./migrate/IOgMigrate.sol";
import {ISolidStateERC721} from "../../lib/solidstate/token/ERC721/ISolidStateERC721.sol";

interface IOgNFT is IOg721, ISolidStateERC721, IGameGuild, IOgMigrate {}
