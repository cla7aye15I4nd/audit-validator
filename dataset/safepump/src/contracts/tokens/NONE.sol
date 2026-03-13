// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity =0.7.4;

import './ERC25.sol';

contract NONE is ERC25 {
    constructor(
        address equivalent,
        uint256 price,
        uint8 taxRate
    ) ERC25('NONE', 'NONE', 18, equivalent, price, taxRate) {
        _mint(msg.sender, 1000 * 10**8 * 10**18);
        initCost(msg.sender);
    }
}
