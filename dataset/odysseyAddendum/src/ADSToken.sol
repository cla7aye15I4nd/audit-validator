// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ISwapFactory} from "./ISwapFactory.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract ADSToken is ERC20Burnable, Ownable {

    address public pairAddress;
    address public feeAddress;
    uint256 public publicBuyAt;

    mapping(address => bool) public whitelist;

    constructor() ERC20("ADS", "ADS") Ownable(_msgSender()) {
        _mint(_msgSender(), 31e6 ether);
        publicBuyAt = block.timestamp + 180 days;
        address usdtAddress;
        address factoryAddress;
        if (block.chainid == 56) {
            usdtAddress = 0x55d398326f99059fF775485246999027B3197955;
            factoryAddress = 0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73;
        } else {
            usdtAddress = 0x3aACc0a5A92901E2c98856f492f54aa07e849b65;
            factoryAddress = 0x6725F303b657a9451d8BA641348b6761A6CC7a17;
        }
        pairAddress = ISwapFactory(factoryAddress).createPair(usdtAddress, address(this));
    }

    function setFeeAddress(address value) public onlyOwner {
        feeAddress = value;
    }

    function setWhitelist(address[] memory users, bool value) public onlyOwner {
        for (uint256 i = 0; i < users.length; i++) {
            whitelist[users[i]] = value;
        }
    }

    function transfer(address to, uint256 value) public override returns (bool) {
        address from = _msgSender();
        if (to == address(0)) {
            _burn(from, value);
        } else {
            _transfer(from, to, value);
        }
        return true;
    }

    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, value);
        if (to == address(0)) {
            _burn(from, value);
        } else {
            _transfer(from, to, value);
        }
        return true;
    }

    function _update(address from, address to, uint256 amount) internal override {
        if (amount == 0) {
            super._update(from, to, 0);
            return;
        }
        bool isBuy = from == pairAddress;
        bool isSell = to == pairAddress;
        if (whitelist[from] || whitelist[to] || !(isBuy || isSell)) {
            super._update(from, to, amount);
        } else if (isSell) {
            uint256 fee = amount * 5 / 100;
            super._update(from, to, amount - fee);
            super._update(from, feeAddress, fee);
        } else if (isBuy) {
            if (publicBuyAt > block.timestamp) revert("not open");
            super._update(from, to, amount);
        }
    }

}
