// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IADSMarket} from "./IADSMarket.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISwapRouter} from "./ISwapRouter.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract Mining is UUPSUpgradeable, OwnableUpgradeable {

    using SafeERC20 for IERC20;

    address public usdtAddress;
    address public adsAddress;
    ISwapRouter public swapRouter;
    IADSMarket public market;

    mapping(address user => Machine[] machines) public userMachine; // 用户矿机

    struct Machine {
        uint256 price;
        uint256 remainder;
        uint256 lastTake;
    }

    event NewMachine(address indexed user, uint256 cardId, uint256 price, uint256 timestamp);
    event TakeMachineReward(address indexed user, uint256 usdtAmount, uint256 adsAmount);

    constructor() {
        _disableInitializers();
    }

    function initialize(address marketAddress) public initializer {
        __Ownable_init(_msgSender());
        __UUPSUpgradeable_init();
        market = IADSMarket(marketAddress);
        usdtAddress = market.usdtAddress();
        adsAddress = market.adsAddress();
        swapRouter = ISwapRouter(market.swapRouter());
    }

    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}

    function _getADSAmountsOut(uint256 usdtIn) internal view virtual returns (uint256) {
        if (usdtIn == 0) return 0;
        address[] memory swapPath = new address[](2);
        swapPath[0] = usdtAddress;
        swapPath[1] = adsAddress;
        return swapRouter.getAmountsOut(usdtIn, swapPath)[1];
    }

    function getMachineReward() public view virtual returns (uint256) {
        Machine[] memory list = userMachine[_msgSender()];
        uint256 totalUsdt;
        for (uint256 i; i < list.length; i++) {
            Machine memory machine = list[i];
            if (machine.remainder > 0) {
                uint256 dayNum = (block.timestamp - machine.lastTake) / 86400;
                if (dayNum > 0) {
                    uint256 amount = machine.price * dayNum * 12 / 1000;
                    if (amount > machine.remainder) {
                        amount = machine.remainder;
                    }
                    totalUsdt += amount;
                }
            }
        }
        return _getADSAmountsOut(totalUsdt);
    }

    // 提矿机收益
    function takeMachineReward() external virtual {
        if (market.getUserHoldNum(_msgSender()) == 0) revert("hold no card");
        Machine[] storage list = userMachine[_msgSender()];
        uint256 total;
        for (uint256 i; i < list.length; i++) {
            Machine storage machine = list[i];
            if (machine.remainder > 0) {
                uint256 dayNum = (block.timestamp - machine.lastTake) / 86400;
                if (dayNum > 0) {
                    uint256 usdtNum = machine.price * dayNum * 12 / 1000;
                    if (usdtNum > machine.remainder) {
                        usdtNum = machine.remainder;
                    }
                    total += usdtNum;
                    machine.remainder -= usdtNum;
                    machine.lastTake += dayNum * 86400;
                }
            }
        }
        if (total == 0) revert("no reward to take");
        uint256 amount = _getADSAmountsOut(total);
        IERC20(adsAddress).safeTransfer(_msgSender(), amount);
        emit TakeMachineReward(_msgSender(), total, amount);
    }

    function createMachine(address user, uint256 cardId, uint256 price) external virtual {
        require(_msgSender() == address(market), "not market");
        userMachine[user].push(Machine(price, price, block.timestamp));
        emit NewMachine(user, cardId, price, block.timestamp);
    }

}
