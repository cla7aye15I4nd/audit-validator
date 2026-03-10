// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library GameTypes {
    enum RoomType {
        STANDARD,
        BATTLE_ROYALE,
        NEWBIE
    }

    enum EndType {
        TIMEOUT,
        NORMAL
    }

    struct Room {
        RoomType roomType;
        uint16 roomId;
        States state;
        address player1;
        address player2;
        // 从0开始, 0-8
        uint8 turn;
        uint256 turnStartedAt;
        address currentPlayer;
        Card[] allCards;
        mapping(uint8 => mapping(uint8 => uint8)) board;
        mapping(address => uint8[]) handCards;
    }

    enum States {
        EMPTY,
        WAITING,
        GAMING
    }

    struct Card {
        uint8 index;
        address card;
        CardTransferType cardTransferType;
        uint8 level;
        uint8 top;
        uint8 right;
        uint8 bottom;
        uint8 left;
        address originalOwner;
        address currentHolder;
        bool isPlaced;
        uint8 x;
        uint8 y;
    }

    struct BoardCard {
        uint8 x;
        uint8 y;
        Card cardInfo;
    }

    struct PlayerStatistic {
        uint16 wins;
        uint16 losses;
        PlayerRoom[] rooms;
    }

    struct PlayerRoom {
        uint16 roomId;
        RoomType roomType;
    }

    struct Message {
        address sender;
        string content;
        uint256 timestamp;
    }

    enum CardTransferType {
        USER,
        MANAGED
    }

    struct JoinCard {
        address card;
        CardTransferType transferType;
    }

    struct ManagedCard {
        address card;
        uint256 balance;
    }
}
