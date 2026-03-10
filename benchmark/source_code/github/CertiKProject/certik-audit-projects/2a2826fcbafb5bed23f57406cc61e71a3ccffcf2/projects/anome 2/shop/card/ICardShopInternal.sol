// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ICardShopPriceInternal} from "./ICardShopPriceInternal.sol";

interface ICardShopInternal is ICardShopPriceInternal {
    error InvalidShopAmount();
    error SoldOut();
    error CardRefundNotStarted();
    error CardMintBanned();

    event CardBought(address indexed account, address indexed card, uint256 cardAmount, uint256 baseTokenAmount);
    event CardSell(address indexed account, address indexed card, uint256 cardAmount, uint256 usdaAmount);
}
