// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {EnumerableSet} from "../../../lib/openzeppelin/utils/structs/EnumerableSet.sol";
import {ISolidStateERC721} from "../../../lib/solidstate/token/ERC721/ISolidStateERC721.sol";

import {ICard} from "../../token/card/ICard.sol";
import {OgNftDepositStorage} from "./OgNftDepositStorage.sol";
import {IERC721Receiver} from "../../../lib/openzeppelin/token/ERC721/IERC721Receiver.sol";

import {IOgNftDeposit} from "./IOgNftDeposit.sol";

contract OgNftDeposit is IOgNftDeposit, IERC721Receiver {
    using EnumerableSet for EnumerableSet.UintSet;

    function depositNft(uint256 id) external {
        OgNftDepositStorage.Layout storage l = OgNftDepositStorage.layout();
        ISolidStateERC721 nft = ISolidStateERC721(address(this));

        nft.safeTransferFrom(msg.sender, address(this), id);
        l.depositedIds[msg.sender].add(id);
    }

    function requestClaimNft(uint256 id) external {
        OgNftDepositStorage.Layout storage l = OgNftDepositStorage.layout();
        if (!l.depositedIds[msg.sender].contains(id)) {
            revert NotDeposited();
        }

        if (l.claimRequestTime[id] > 0) {
            revert AlreadyClaimed();
        }

        l.claimRequestTime[id] = block.timestamp;
    }

    function claimNft(uint256 id) external {
        OgNftDepositStorage.Layout storage l = OgNftDepositStorage.layout();

        if (!l.depositedIds[msg.sender].contains(id)) {
            revert NotDeposited();
        }

        if (l.claimRequestTime[id] == 0) {
            revert NotClaimable();
        }

        if (block.timestamp < l.claimRequestTime[id] + 3 days) {
            revert NotClaimableYet();
        }

        ISolidStateERC721 nft = ISolidStateERC721(address(this));
        nft.safeTransferFrom(address(this), msg.sender, id);

        l.claimRequestTime[id] = 0;
        l.depositedIds[msg.sender].remove(id);
    }

    function claimCards(uint256 id) external {
        OgNftDepositStorage.Layout storage l = OgNftDepositStorage.layout();
        if (!l.depositedIds[msg.sender].contains(id)) {
            revert NotDeposited();
        }

        if (l.isClaimedCards[id]) {
            revert AlreadyClaimed();
        }

        l.isClaimedCards[id] = true;

        _transferClaimedCards(0x2e57d55f228d71fD94047acDAB75750CbF895648, msg.sender);
        _transferClaimedCards(0x820a5cd16Eb60A95F57fA6be1584e4682cb19f82, msg.sender);
        _transferClaimedCards(0x737A3f71d7bd99514C89CF7a6CDee21AC3D1E787, msg.sender);
        _transferClaimedCards(0xE9783bC65ea883Da3e5C64D24Cf884486d8D8D00, msg.sender);
        _transferClaimedCards(0x2712d28f18B0Accf78A0d3cdf5350924216D9C4b, msg.sender);
        _transferClaimedCards(0x6984fBC5fe442DcA359EA0f609Ba8F30A897BFA4, msg.sender);
        _transferClaimedCards(0xdF1eeaB402c5EC502dF5A61633eCb9871285FA41, msg.sender);
        _transferClaimedCards(0xa9cc58c0991F931761a8073b1e4Bd1096bD91570, msg.sender);
        _transferClaimedCards(0xfFB9D8DFC7f230F870fC8d92038a1068593f7f2B, msg.sender);
        _transferClaimedCards(0xA1269452B740b5743D37540a5DFb91D6A9675971, msg.sender);
        _transferClaimedCards(0xDa0cD1557fcF47d0FbbbD83a34b9be01d5eAf984, msg.sender);
    }

    function _transferClaimedCards(address card, address to) internal {
        ICard cardContract = ICard(card);
        uint256 balance = cardContract.balanceOf(address(this));
        uint256 amount = 30 * cardContract.getUnit();
        if (balance < amount) {
            revert CardBalanceNotEnough(card, balance, amount);
        }
        cardContract.transfer(to, amount);
    }

    function getDepositedNft(address account) external view returns (uint256[] memory) {
        OgNftDepositStorage.Layout storage l = OgNftDepositStorage.layout();
        return l.depositedIds[account].values();
    }

    function getNftClaimRequestTime(uint256 id) external view returns (uint256) {
        OgNftDepositStorage.Layout storage l = OgNftDepositStorage.layout();
        return l.claimRequestTime[id];
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
