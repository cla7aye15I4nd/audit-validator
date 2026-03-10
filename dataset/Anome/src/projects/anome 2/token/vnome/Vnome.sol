// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20} from "../../../lib/openzeppelin/token/ERC20/ERC20.sol";
import {DefaultAccessControl} from "../../../utils/DefaultAccessControl.sol";
import {IVnome} from "../vnome/IVnome.sol";

contract Vnome is ERC20, DefaultAccessControl, IVnome {
    error TransferDisabled();

    constructor() ERC20("Vnome", "Vnome") {
        _setupRoles(msg.sender, msg.sender);
    }

    function mint(address account, uint256 amount) external override onlyCaller {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external override onlyCaller {
        _burn(account, amount);
    }

    function _update(address from, address to, uint256 value) internal virtual override {
        value;

        if (from != address(0) && to != address(0)) {
            revert TransferDisabled();
        }

        super._update(from, to, value);
    }
}
