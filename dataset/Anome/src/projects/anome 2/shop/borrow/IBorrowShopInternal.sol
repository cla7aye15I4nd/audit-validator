// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ShopTypes} from "../ShopTypes.sol";

interface IBorrowShopInternal {
    error PageError();
    error AlreadyRepaid();

    event Borrowed(address indexed account, ShopTypes.BorrowOrder order);
    event Repaid(address indexed account, ShopTypes.BorrowOrder order);
}
