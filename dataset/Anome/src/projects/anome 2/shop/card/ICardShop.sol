// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ShopTypes} from "../ShopTypes.sol";

import {ICardShopInternal} from "./ICardShopInternal.sol";

interface ICardShop is ICardShopInternal {
    // Write
    function buyCard(uint256 index, uint256 count) external;
    function buyCardTo(uint256 index, uint256 count, address recipient) external;
    function buyCardByBaseToken(
        uint256 index,
        uint256 baseTokenAmount,
        address recipient
    ) external returns (uint256 cardAmount);
    function sellCard(uint256 index, uint256 count) external;

    // View
    function getCardIdByAddress(address card) external view returns (uint256 index);
    function getPoolSize() external view returns (uint256 size);
    function getPool(uint256 index) external view returns (ShopTypes.CardItem memory item);
    function getPrice(uint256 index) external view returns (uint256 price);
    function getPriceByAddress(address cardAddr) external view returns (uint256 price);
    function getAllPools(uint256 page, uint256 size) external view returns (ShopTypes.CardItem[] memory items);
    function getAllPoolsSimple() external view returns (ShopTypes.CardItemSimple[] memory items);
    function getPoolCardSimple(uint256 index) external view returns (address card);
    function getPoolListByLevel(uint256 level) external view returns (ShopTypes.CardItem[] memory items);
    function getPoolUsdaBalance(uint256 index) external view returns (uint256 balance, uint256 adjusted);
    function getCirculationInfo(
        uint256 index
    ) external view returns (uint256 supply, uint256 stock, uint256 destruction, uint256 circulation);
    function getAllSellStartTime() external view returns (uint256[] memory times);
    function getAccountCardInfo(address account) external view returns (uint256 cardCount, uint256 totalValue);
    function getMintBlacklist() external view returns (bool[] memory isBlacklisted);
    function isCardInPool(address card) external view returns (bool);
    function getCardPoolInfo(uint256 id) external view returns (ShopTypes.CardPool memory pool);

    // Admin
    function adminCreatePool(address card, uint256 initialPrice, uint256 sellStartsAt, bool isBlacklisted) external;
    function adminSetPoolHide(uint256 index, bool isHide) external;
    function adminSetPoolUsdaBalance(uint256 index, uint256 balance) external;
    function adminSetUsdaIncreaseVirtualBalance(uint256 index, uint256 adjustedBalance) external;
    function adminSetCardDecreaseVirtualBalance(uint256 index, uint256 adjustedBalance) external;
    function adminSetSellStartTime(uint256 index, uint256 time) external;
    function adminSetCardMintBanned(uint256 index, bool isCardMintBanned) external;
}
