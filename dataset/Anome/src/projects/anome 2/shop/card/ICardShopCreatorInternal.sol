// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ICardShopCreatorInternal {
    error InvalidCardCreatePrice();
    error AlreadyExists();

    event CardPoolCreated(uint256 indexed index, address indexed card, uint256 initialPrice, uint256 sellStartsAt, bool isCardMintBanned);
}