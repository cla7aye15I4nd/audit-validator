// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity =0.7.4;

import './ERC25.sol';

contract MeVerse is ERC25 {
    constructor(
        address equivalent,
        uint256 price,
        uint8 taxRate
    ) ERC25('Treasure', 'TR', 18, equivalent, price, taxRate) {
        _mint(msg.sender, 500 * 10**4 * 10**18);
        initCost(msg.sender);
    }
}
