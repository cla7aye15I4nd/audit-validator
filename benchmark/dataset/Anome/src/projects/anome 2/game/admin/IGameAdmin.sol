// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IGameAdmin {
    error NotAllowed();

    function callerSetManagedCardBalance(address account, address[] memory cards, uint256 balance) external;

    function callerSetPlayerStatistic(address account, uint16 wins, uint16 losses) external;

    function callerClearPlayerStatisticRooms(address account) external;
}
