// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IShopCommonInternal {
    error InvalidCardAddress();
    error InvalidCardId();
    error AccountBanned();
    error OnlyGame();
    error NoContractCall();
    error ShopPaused();
}