//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ShopTypes} from "../../shop/ShopTypes.sol";
import {IERC404Legacy} from "../../../utils/IERC404Legacy.sol";

interface ICard is IERC404Legacy {
    function getUnit() external view returns (uint256);
    function setCardAttributes(ShopTypes.CardAttributes memory cardAttributes_) external;
    function getCardAttributes() external view returns (ShopTypes.CardAttributes memory);
    function setIPReceiver(ShopTypes.Receiver memory receiver) external;
    function getIPReceiver() external view returns (ShopTypes.Receiver memory);
}
