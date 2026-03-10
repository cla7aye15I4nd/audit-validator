// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20} from "../../lib/openzeppelin/token/ERC20/ERC20.sol";

library UtilsLib {
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    /**
     * @dev 获取代币精度
     * @param token 代币地址
     * @return 代币精度
     */
    function getDecimals(address token) internal view returns (uint8) {
        try ERC20(token).decimals() returns (uint8 decimals) {
            return decimals;
        } catch {
            return 18; // 默认返回18位精度
        }
    }

    /**
     * @dev 代币精度转换函数
     * @param amount 原始金额
     * @param from 原始代币地址
     * @param to 目标代币地址
     * @return 转换后的金额
     */
    function convertDecimals(uint256 amount, address from, address to) internal view returns (uint256) {
        uint8 fromDecimals = getDecimals(from);
        uint8 toDecimals = getDecimals(to);

        if (fromDecimals == toDecimals) {
            return amount;
        }

        if (fromDecimals < toDecimals) {
            return amount * (10 ** (toDecimals - fromDecimals));
        }

        return amount / (10 ** (fromDecimals - toDecimals));
    }

    // 生成随机数, min最小, max最大
    function genRandomUint(uint256 minUint, uint256 maxUint) internal view returns (uint256) {
        uint256 random = uint256(
            keccak256(
                abi.encodePacked(
                    block.prevrandao,
                    blockhash(block.number - 1),
                    blockhash(block.number - 2),
                    blockhash(block.number - 3),
                    blockhash(block.number - 4),
                    blockhash(block.number - 5),
                    blockhash(block.number - 6),
                    blockhash(block.number - 7),
                    blockhash(block.number - 8),
                    block.timestamp,
                    msg.sender,
                    gasleft()
                )
            )
        );
        return (random % (maxUint - minUint + 1)) + minUint;
    }
}
