// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IGameChat} from "./IGameChat.sol";
import {GameTypes} from "../GameTypes.sol";
import {GameStorage} from "../GameStorage.sol";

import {SafeOwnableInternal} from "../../../lib/solidstate/access/ownable/SafeOwnableInternal.sol";

contract GameChat is IGameChat, SafeOwnableInternal {
    function sendMessage(string memory message) external override {
        GameStorage.Layout storage l = GameStorage.layout();

        // 创建新消息
        GameTypes.Message memory newMessage = GameTypes.Message({
            sender: msg.sender,
            content: message,
            timestamp: block.timestamp
        });

        // 将消息添加到全局消息数组
        l.messages.push(newMessage);

        // 将消息索引添加到用户的消息列表中
        l.userMessages[msg.sender].push(l.messages.length - 1);

        // 触发消息发送事件
        emit MessageSent(msg.sender, message, block.timestamp);
    }

    function getMessages(uint256 page, uint256 limit) external view override returns (MessageWithIndex[] memory) {
        GameStorage.Layout storage l = GameStorage.layout();

        uint256 totalMessages = l.messages.length;
        if (totalMessages == 0) {
            return new MessageWithIndex[](0);
        }

        uint256 skip = page * limit;
        if (skip >= totalMessages) {
            return new MessageWithIndex[](0);
        }

        uint256 startIndex = totalMessages - skip;
        uint256 endIndex = startIndex > limit ? startIndex - limit : 0;
        uint256 currentPageSize = startIndex - endIndex;

        MessageWithIndex[] memory messages = new MessageWithIndex[](currentPageSize);
        for (uint256 i = 0; i < currentPageSize; i++) {
            uint256 index = startIndex - 1 - i;
            if (l.isMessageDeleted[index]) {
                continue;
            }
            messages[i] = MessageWithIndex({
                index: index,
                sender: l.messages[index].sender,
                content: l.messages[index].content,
                timestamp: l.messages[index].timestamp
            });
        }

        return messages;
    }

    function setDeleter(address deleter) external override onlyOwner {
        GameStorage.Layout storage l = GameStorage.layout();
        l.isMessageDeleter[deleter] = true;
    }

    function deleteMessage(uint256[] memory indexes) external override {
        GameStorage.Layout storage l = GameStorage.layout();

        if (!l.isMessageDeleter[msg.sender]) {
            revert("Not deleter");
        }

        for (uint256 i = 0; i < indexes.length; i++) {
            l.isMessageDeleted[indexes[i]] = true;
        }
    }
}
