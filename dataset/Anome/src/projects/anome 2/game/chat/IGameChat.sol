// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {GameTypes} from "../GameTypes.sol";

interface IGameChat {
    event MessageSent(address indexed sender, string content, uint256 timestamp);

    struct MessageWithIndex {
        uint256 index;
        address sender;
        string content;
        uint256 timestamp;
    }

    function sendMessage(string memory message) external;

    function getMessages(uint256 page, uint256 limit) external view returns (MessageWithIndex[] memory);

    function setDeleter(address deleter) external;

    function deleteMessage(uint256[] memory indexes) external;
}
