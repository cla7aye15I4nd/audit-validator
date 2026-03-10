// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.20;

import {ERC20} from "../../../lib/openzeppelin/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "../../../lib/openzeppelin/token/ERC20/extensions/ERC20Burnable.sol";

import {DefaultAccessControl} from "../../../utils/DefaultAccessControl.sol";
import {IUSDA} from "./IUSDA.sol";

contract USDA is DefaultAccessControl, ERC20, ERC20Burnable, IUSDA {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    constructor() ERC20("Anome USD", "USDA") {
        _setupRoles(msg.sender, msg.sender);
    }

    function mint(address to, uint256 amount) public override onlyCaller {
        _mint(to, amount);
    }

    function burn(uint256 value) public override(ERC20Burnable, IUSDA) {
        super.burn(value);
    }

    function burnFrom(address account, uint256 value) public override(ERC20Burnable, IUSDA) {
        super.burnFrom(account, value);
    }
}
