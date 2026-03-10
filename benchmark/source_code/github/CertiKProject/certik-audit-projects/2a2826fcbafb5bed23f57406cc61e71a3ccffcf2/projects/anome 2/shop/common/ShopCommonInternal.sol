// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IShopCommonInternal} from "./IShopCommonInternal.sol";
import {ShopStorage} from "../ShopStorage.sol";
import {ShopTypes} from "../ShopTypes.sol";

contract ShopCommonInternal is IShopCommonInternal {
    modifier commonCheck() {
        if (ShopStorage.layout().isAccountBanned[msg.sender]) {
            revert AccountBanned();
        }

        if (ShopStorage.layout().isAccountBanned[tx.origin]) {
            revert AccountBanned();
        }

        if (ShopStorage.layout().isShopPaused) {
            revert ShopPaused();
        }

        _;
    }

    modifier onlyGame() {
        ShopStorage.Layout storage data = ShopStorage.layout();

        if (msg.sender != data.config.game()) {
            revert OnlyGame();
        }

        _;
    }

    modifier noContractCall() {
        if (msg.sender != tx.origin && !ShopStorage.layout().isNoContractWhitelist[msg.sender]) {
            revert NoContractCall();
        }

        _;
    }

    function checkCardAndId(address card, uint256 cardId) internal {
        if (!_isCardInPool(card)) {
            revert InvalidCardAddress();
        }

        if (!_isCardIdValid(card, cardId)) {
            revert InvalidCardId();
        }
    }

    function _isCardInPool(address card) internal view returns (bool) {
        ShopStorage.Layout storage data = ShopStorage.layout();
        uint256 poolIndex = data.cardsIndex[card];
        ShopTypes.CardPool storage pool = data.pools[poolIndex];

        if (card == address(0)) {
            return false;
        }

        if (card != address(pool.card)) {
            return false;
        }

        return true;
    }

    function _isCardIdValid(address card, uint256 cardId) internal returns (bool) {
        ShopStorage.Layout storage data = ShopStorage.layout();
        uint256 poolIndex = data.cardsIndex[card];
        ShopTypes.CardPool storage pool = data.pools[poolIndex];

        if (cardId > pool.card.minted()) {
            return false;
        }

        return true;
    }
}
