// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library NumberEncoderLib {
    string internal constant BASE26 = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";

    // 编码数字为动态长度字符串，无数量限制
    // 前缀长度固定为4位伪随机字符，后面跟数字的26进制编码（数字部分至少2位）
    function encode(uint256 num) internal pure returns (string memory) {
        // 计算数字需要多少位26进制表示
        uint256 numLength = getBase26Length(num);
        
        // 确保数字部分至少2位，总长度至少6位
        if (numLength < 2) {
            numLength = 2;
        }
        
        // 总长度 = 4位前缀 + 数字长度
        uint256 totalLength = 4 + numLength;
        bytes memory result = new bytes(totalLength);

        // 前4位伪随机填充，基于num生成确定性字符
        for (uint256 i = 0; i < 4; i++) {
            uint256 seed = num + i * 7919; // 使用质数增加随机性
            result[i] = convertToFixedChar(seed);
        }

        // 后面放数字的26进制编码
        bytes memory base26Num = toBase26(num, numLength);
        for (uint256 i = 0; i < numLength; i++) {
            result[4 + i] = base26Num[i];
        }

        return string(result);
    }

    // 固定字符生成, 基于输入num确定字符
    function convertToFixedChar(uint256 num) internal pure returns (bytes1) {
        uint256 rand = uint256(keccak256(abi.encodePacked(num))) % 26;
        return bytes(BASE26)[rand];
    }

    // 解码字符串，返回数字（无限制）
    // 前4位是前缀，从第5位开始是数字的26进制编码（数字部分至少2位）
    function decode(string memory str) internal pure returns (uint256) {
        bytes memory b = bytes(str);
        require(b.length >= 6, "Invalid length, minimum 6 characters");
        
        uint256 num = 0;
        // 从第5位开始解码数字部分
        for (uint256 i = 4; i < b.length; i++) {
            num = num * 26 + charToValue(b[i]);
        }
        return num;
    }

    // 计算数字需要多少位26进制表示
    function getBase26Length(uint256 num) internal pure returns (uint256) {
        if (num == 0) return 1;
        uint256 length = 0;
        uint256 temp = num;
        while (temp > 0) {
            temp /= 26;
            length++;
        }
        return length;
    }

    // 将数字转换为指定长度的26进制字符串
    function toBase26(uint256 num, uint256 length)
        internal
        pure
        returns (bytes memory)
    {
        bytes memory s = new bytes(length);
        for (uint256 i = length; i > 0; i--) {
            s[i - 1] = bytes(BASE26)[num % 26];
            num /= 26;
        }
        return s;
    }

    // 字符转数字
    function charToValue(bytes1 char) internal pure returns (uint256) {
        bytes memory b = bytes(BASE26);
        for (uint256 i = 0; i < 26; i++) {
            if (b[i] == char) {
                return i;
            }
        }
        revert("Invalid character");
    }
}