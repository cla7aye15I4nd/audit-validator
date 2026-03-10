// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {GameTypes} from "./GameTypes.sol";
import {IShop} from "../shop/IShop.sol";
import {IConfig} from "../config/IConfig.sol";

library GameStorage {
    ////////// Layout //////////
    bytes32 internal constant STORAGE_SLOT = keccak256("anome.game.contracts.storage.v2");
    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }

    struct Layout {
        IConfig config;
        mapping(GameTypes.RoomType => mapping(uint16 => GameTypes.Room)) rooms;
        mapping(address => GameTypes.PlayerStatistic) playerStatistic;
        GameTypes.Message[] messages;
        mapping(address => uint256[]) userMessages;
        mapping(uint256 => bool) isMessageDeleted;
        mapping(address => bool) isMessageDeleter;
        mapping(GameTypes.RoomType => mapping(uint16 => uint256)) roomStartedAt;
        // 用户托管卡牌余额, player => cardAddress => balance
        mapping(address => mapping(address => uint256)) managedCardBalance;
        // 是否可以领取托管卡牌, 关注FB后, 后台设置可以领取卡牌
        // 已废弃, 因为托管卡牌不再允许提出
        mapping(address => bool) _01;
        // 可以领取托管卡牌的数量, 每对战一局可以领取一张卡牌
        // 已废弃, 已经全部平移到普通场次了
        // 已废弃, 因为托管卡牌不再允许提出
        mapping(address => uint16) _02;
        // 合约托管卡牌余额, 合约中的托管卡牌余额, 比实际余额小, 因为要给销毁预留
        // 已废弃, 因为托管卡牌不再产生实际的销毁
        mapping(address => uint256) _03;
        // 对局唯一ID, 开始游戏时生成, 结束游戏时销毁
        mapping(GameTypes.RoomType => mapping(uint16 => uint256)) battleId;
    }

    ////////// Constants //////////
    uint256 constant DIVIDEND = 10000;
    address constant HOLE = address(0xdead);
    uint8 constant MAX_TURN = 8;
    uint8 constant MAX_X = 3;
    uint8 constant MAX_Y = 3;
    uint256 constant TIMEOUT = 2 minutes;
    uint8 constant PLAYER_CARD_COUNT = 5;
}
