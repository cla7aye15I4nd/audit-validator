// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {GameStorage} from "../GameStorage.sol";
import {IConfig} from "../../config/IConfig.sol";
import {ICard} from "../../token/card/ICard.sol";

import {SafeOwnable} from "../../../lib/solidstate/access/ownable/SafeOwnable.sol";
import {IGameAdmin} from "./IGameAdmin.sol";

contract GameAdmin is SafeOwnable, IGameAdmin {
    // 设置用户的托管卡牌余额
    function callerSetManagedCardBalance(
        address account,
        address[] memory cards,
        uint256 balance
    ) external override {
        GameStorage.Layout storage data = GameStorage.layout();
        if (msg.sender != data.config.caller()) {
            revert NotAllowed();
        }
        for (uint256 i = 0; i < cards.length; i++) {
            data.managedCardBalance[account][cards[i]] = balance;
        }
    }

    function callerSetPlayerStatistic(address account, uint16 wins, uint16 losses) external override {
        GameStorage.Layout storage data = GameStorage.layout();
        if (msg.sender != data.config.caller()) revert NotAllowed();
        data.playerStatistic[account].wins = wins;
        data.playerStatistic[account].losses = losses;
    }

    function callerClearPlayerStatisticRooms(address account) external override {
        GameStorage.Layout storage data = GameStorage.layout();
        if (msg.sender != data.config.caller()) revert NotAllowed();
        delete data.playerStatistic[account].rooms;
    }
}
