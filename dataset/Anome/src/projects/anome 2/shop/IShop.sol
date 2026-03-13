// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ICardShop} from "./card/ICardShop.sol";
import {IBorrowShop} from "./borrow/IBorrowShop.sol";
import {IBattleService} from "./battle/IBattleService.sol";
import {IShopReferral} from "./referral/IShopReferral.sol";
import {IShopUser} from "./user/IShopUser.sol";
import {IShopMigrate} from "./migrate/IShopMigrate.sol";
import {IBattleMining} from "./mining/IBattleMining.sol";
import {IBnomeStake} from "./stake/IBnomeStake.sol";
import {IShopAdmin} from "./admin/IShopAdmin.sol";

interface IShop is
    ICardShop,
    IBorrowShop,
    IBattleService,
    IShopReferral,
    IShopUser,
    IShopMigrate,
    IBattleMining,
    IBnomeStake,
    IShopAdmin
{}
