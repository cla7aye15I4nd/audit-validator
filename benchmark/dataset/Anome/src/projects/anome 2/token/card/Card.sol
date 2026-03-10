//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ShopTypes} from "../../shop/ShopTypes.sol";
import {ICard} from "./ICard.sol";
import {ERC404Legacy} from "../../../utils/ERC404Legacy.sol";
import {IERC404Legacy} from "../../../utils/IERC404Legacy.sol";

contract Card is ICard, ERC404Legacy {
    string private fixedUri;
    ShopTypes.CardAttributes private cardAttributes;
    ShopTypes.Receiver private ipReceiver;

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint256 supply_,
        address receiver,
        string memory tokenUri_,
        ShopTypes.CardAttributes memory cardAttributes_,
        ShopTypes.Receiver memory ipReceiver_
    ) ERC404Legacy(name_, symbol_, decimals_, supply_, msg.sender) {
        fixedUri = tokenUri_;
        whitelist[msg.sender] = true;
        whitelist[receiver] = true;
        whitelist[0x000000000000000000000000000000000000dEaD] = true;
        balanceOf[receiver] = supply_ * 10 ** decimals_;
        cardAttributes = cardAttributes_;
        ipReceiver = ipReceiver_;
    }

    function tokenURI(uint256 id) public view override(ERC404Legacy, IERC404Legacy) returns (string memory) {
        id;
        return fixedUri;
    }

    function getUnit() external view override returns (uint256) {
        return _getUnit();
    }

    function setCardAttributes(ShopTypes.CardAttributes memory cardAttributes_) external override onlyOwner {
        cardAttributes = cardAttributes_;
    }

    function getCardAttributes() external view override returns (ShopTypes.CardAttributes memory) {
        return cardAttributes;
    }

    function setIPReceiver(ShopTypes.Receiver memory receiver) external override onlyOwner {
        ipReceiver = receiver;
    }

    function getIPReceiver() external view override returns (ShopTypes.Receiver memory) {
        return ipReceiver;
    }
}
