// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity =0.7.4;

import './ERC20.sol';

contract ECO is ERC20 {
    constructor() ERC20('ECO', 'ECO', 18) {
        _mint(msg.sender, 10**9 * 10**18);
    }
}
