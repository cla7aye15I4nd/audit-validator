// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {GameTypes} from "../GameTypes.sol";

interface IGameSettlerInternal {
    error RoomStatusError(GameTypes.States current);
    error AbnormalState();
    error NotInRoom(address account);
    error NoSettlementPermission(GameTypes.States state, address account);

    event GameEnded(
        GameTypes.RoomType roomType,
        uint16 roomId,
        GameTypes.EndType endType,
        address caller,
        address winner,
        address loser,
        address destroyCard,
        address[] winnerCards,
        address[] loserCards,
        uint256 battleId
    );

    event GameStarted(
        GameTypes.RoomType roomType,
        uint16 roomId,
        address player1,
        address player2,
        address currentPlayer,
        uint256 battleId
    );
}
