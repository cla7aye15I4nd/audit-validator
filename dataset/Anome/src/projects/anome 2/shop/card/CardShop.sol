// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "../../../lib/openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../../lib/openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {IERC721Receiver} from "../../../lib/openzeppelin/token/ERC721/IERC721Receiver.sol";

import {ShopTypes} from "../ShopTypes.sol";
import {ShopStorage} from "../ShopStorage.sol";

import {ICardShop} from "./ICardShop.sol";
import {CardShopInternal} from "./CardShopInternal.sol";
import {SafeOwnableInternal} from "../../../lib/solidstate/access/ownable/SafeOwnableInternal.sol";

contract CardShop is ICardShop, CardShopInternal, SafeOwnableInternal, IERC721Receiver {
    using SafeERC20 for IERC20;

    // Write
    function buyCard(uint256 index, uint256 count) external override {
        _buyCard(index, count, msg.sender);
    }

    function buyCardTo(uint256 index, uint256 count, address recipient) external override {
        _buyCard(index, count, recipient);
    }

    function buyCardByBaseToken(
        uint256 index,
        uint256 baseTokenAmount,
        address recipient
    ) external pure override returns (uint256 cardAmount) {
        index;
        baseTokenAmount;
        recipient;
        cardAmount = 0;
        revert("not implemented");
        // return _buyCardByBaseToken(index, baseTokenAmount, recipient);
    }

    function sellCard(uint256 index, uint256 count) external override {
        _sellCard(index, count);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    // View
    function getPoolSize() external view override returns (uint256 size) {
        ShopStorage.Layout storage data = ShopStorage.layout();
        return data.pools.length;
    }

    function getPool(uint256 index) external view override returns (ShopTypes.CardItem memory item) {
        return _fillCardItemInfo(index);
    }

    function getAllPools(
        uint256 page,
        uint256 size
    ) external view override returns (ShopTypes.CardItem[] memory items) {
        ShopStorage.Layout storage data = ShopStorage.layout();

        uint256 totalSize = data.pools.length;
        uint256 start = page * size;
        if (start >= totalSize) {
            return new ShopTypes.CardItem[](0);
        }
        uint256 end = (start + size) > totalSize ? totalSize : (start + size);

        // 创建大小为当前页实际数量的数组
        items = new ShopTypes.CardItem[](end - start);

        // 只遍历当前页的范围
        for (uint256 i = 0; i < (end - start); i++) {
            items[i] = _fillCardItemInfo(start + i);
        }
    }

    function getAllPoolsSimple() external view override returns (ShopTypes.CardItemSimple[] memory items) {
        ShopStorage.Layout storage data = ShopStorage.layout();
        items = new ShopTypes.CardItemSimple[](data.pools.length);
        for (uint i = 0; i < data.pools.length; i++) {
            items[i] = ShopTypes.CardItemSimple(i, data.pools[i].card);
        }
    }

    function getPoolCardSimple(uint256 index) external view override returns (address card) {
        ShopStorage.Layout storage data = ShopStorage.layout();
        card = address(data.pools[index].card);
    }

    function getPoolListByLevel(uint256 level) external view override returns (ShopTypes.CardItem[] memory items) {
        ShopStorage.Layout storage data = ShopStorage.layout();
        uint256[] memory ids = data.levelPools[level];
        items = new ShopTypes.CardItem[](ids.length);

        for (uint i = 0; i < ids.length; i++) {
            items[i] = _fillCardItemInfo(ids[i]);
        }
    }

    function getPoolUsdaBalance(uint256 index) external view override returns (uint256 balance, uint256 adjusted) {
        ShopStorage.Layout storage data = ShopStorage.layout();
        return (data.pools[index].usdaBalance, data.pools[index].usdaIncreaseVirtualBalance);
    }

    function getPrice(uint256 index) external view override returns (uint256 price) {
        return _priceOf(index);
    }

    function getPriceByAddress(address cardAddr) external view override returns (uint256 price) {
        ShopStorage.Layout storage data = ShopStorage.layout();
        uint256 index = data.cardsIndex[cardAddr];
        if (address(data.pools[index].card) != cardAddr) {
            return 0;
        }
        return _priceOf(index);
    }

    function getCirculationInfo(
        uint256 index
    ) external view override returns (uint256 supply, uint256 stock, uint256 destruction, uint256 circulation) {
        return _circulationInfoOf(index);
    }

    function getCardIdByAddress(address card) external view override returns (uint256) {
        ShopStorage.Layout storage data = ShopStorage.layout();
        return data.cardsIndex[card];
    }

    function getAllSellStartTime() external view override returns (uint256[] memory times) {
        ShopStorage.Layout storage data = ShopStorage.layout();
        times = new uint256[](data.pools.length);
        for (uint i = 0; i < data.pools.length; i++) {
            times[i] = data.sellStartsAt[i];
        }
    }

    function getAccountCardInfo(
        address account
    ) external view override returns (uint256 cardCount, uint256 totalValue) {
        ShopStorage.Layout storage data = ShopStorage.layout();
        for (uint i = 0; i < data.pools.length; i++) {
            uint256 balance = data.pools[i].card.balanceOf(account);
            if (!data.isPoolHide[i] && balance > 0) {
                cardCount += balance;
                totalValue += (_priceOf(i) * balance) / 1e18;
            }
        }
    }

    function getMintBlacklist() external view override returns (bool[] memory isBlacklisted) {
        ShopStorage.Layout storage data = ShopStorage.layout();
        isBlacklisted = new bool[](data.pools.length);
        for (uint i = 0; i < data.pools.length; i++) {
            isBlacklisted[i] = data.isCardMintBanned[i];
        }
    }

    function isCardInPool(address card) external view override returns (bool) {
        return _isCardInPool(card);
    }

    function getCardPoolInfo(uint256 id) external view override returns (ShopTypes.CardPool memory pool) {
        ShopStorage.Layout storage data = ShopStorage.layout();
        pool = data.pools[id];
    }

    // Admin
    function adminCreatePool(
        address card,
        uint256 initialPrice,
        uint256 sellStartsAt,
        bool isBlacklisted
    ) external override onlyOwner {
        _createPool(card, initialPrice, sellStartsAt, isBlacklisted);
    }

    function adminSetPoolHide(uint256 index, bool isHide) external onlyOwner {
        ShopStorage.Layout storage data = ShopStorage.layout();
        data.isPoolHide[index] = isHide;
    }

    function adminSetPoolUsdaBalance(uint256 index, uint256 balance) external override onlyOwner {
        ShopStorage.Layout storage data = ShopStorage.layout();
        data.pools[index].usdaBalance = balance;
    }

    function adminSetUsdaIncreaseVirtualBalance(
        uint256 index,
        uint256 adjustedBalance
    ) external override onlyOwner {
        ShopStorage.Layout storage data = ShopStorage.layout();
        data.pools[index].usdaIncreaseVirtualBalance = adjustedBalance;
    }

    function adminSetCardDecreaseVirtualBalance(
        uint256 index,
        uint256 adjustedBalance
    ) external override onlyOwner {
        ShopStorage.Layout storage data = ShopStorage.layout();
        data.pools[index].cardDecreaseVirtualBalance = adjustedBalance;
    }

    function adminSetSellStartTime(uint256 index, uint256 time) external override onlyOwner {
        ShopStorage.Layout storage data = ShopStorage.layout();
        data.sellStartsAt[index] = time;
    }

    function adminSetCardMintBanned(uint256 index, bool isCardMintBanned) external override onlyOwner {
        ShopStorage.Layout storage data = ShopStorage.layout();
        data.isCardMintBanned[index] = isCardMintBanned;
    }
}
