# Reopenable Blind Box and Reentrancy Window in openBox Function


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🔴 Critical |
| Triage Verdict | ✅ Valid |
| Project ID | `bc55baa0-c517-11f0-a838-53cc3f14fdf2` |

## Location

- **Local path:** `./source_code/github/CertiKProject/client-upload-projects/d6d5dbf7932a19a1cb71ec3b0a4655b993e055b8/nf9uLcSVXapPUgrNAQJ4ee/ADSMarket.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/bc55baa0-c517-11f0-a838-53cc3f14fdf2/source?file=$/github/CertiKProject/client-upload-projects/d6d5dbf7932a19a1cb71ec3b0a4655b993e055b8/nf9uLcSVXapPUgrNAQJ4ee/ADSMarket.sol
- **Lines:** 480–486

## Description

The ownership check in openBox relies on matching numeric userId values rather than ensuring the caller is a registered user and the actual recorded owner. Code:
```sol
    function openBox(uint256 cardId) external virtual whenNotPaused {
        uint256 userId = getIdByUser[_msgSender()];
        if (cardMap[cardId].userId != userId) revert("not the owner");
        if (!cardMap[cardId].isBox) revert("not a box");
        mining.createMachine(_msgSender(), cardId, cardMap[cardId].lastPrice);
        cardMap[cardId].userId = 0;
    }
```
If a card becomes a box while its cardMap[cardId].userId == 0 (e.g. After a legitimate call, cardMap[cardId].userId is set to 0.), Any caller(unregisterd) whose getIdByUser[...] also returns 0 (unregistered user) will pass the ownership check (cardMap[cardId].userId != userId) because both are 0, allowing unlimited subsequent calls. This allows arbitrary accounts to call openBox and trigger mining.createMachine, effectively claiming an asset.

## Recommendation

Require non-zero ownership: require(card.userId == userId && userId != 0, "not owner");

## Vulnerable Code

```
// 购买卡牌
    function buyCard(uint256 cardId) external virtual whenNotPaused {
        uint256 userId = getIdByUser[_msgSender()];
        if (userId == 0) revert("need bind a leader");
        _buyCardFor(cardId, userId);
    }

    // AI购买卡牌
    function buyCardForUser(uint256 cardId, uint256 userId) external virtual whenNotPaused {
        if (tradeAddress[_msgSender()]) revert("not allowed");
        if (getUserById[userId] == address(0)) revert("user not exist");
        _buyCardFor(cardId, userId);
    }

    // 卡牌变盲盒
    function setCardToBox(uint256[] calldata cardIds) external virtual {
        for (uint256 i; i < cardIds.length; i++) {
            Card storage card = cardMap[cardIds[i]];
            if (card.isBox || card.sellEndTime == 0 || card.sellEndTime > block.timestamp) {
                continue;
            }
            card.isBox = true;
            userCard[card.userId].remove(cardIds[i]);
            emit CardBecomeBox(cardIds[i]);
        }
    }

    // 开盲盒
    function openBox(uint256 cardId) external virtual whenNotPaused {
        uint256 userId = getIdByUser[_msgSender()];
        if (cardMap[cardId].userId != userId) revert("not the owner");
        if (!cardMap[cardId].isBox) revert("not a box");
        mining.createMachine(_msgSender(), cardId, cardMap[cardId].lastPrice);
        cardMap[cardId].userId = 0;
    }

    function teamReward(uint256 userId, uint256 profit) internal virtual returns (uint256) {
        uint256 total;
        uint256 leaderId = getLeaderId[userId];
        uint256 lastLevel; // 上一个level
        uint256 frontLevel; // 上上个level
        uint256 lastRate;
        uint256 lastAmount;
        while (leaderId != 0) {
            if (userCard[leaderId].length() == 0) { // 未持有卡牌
                leaderId = getLeaderId[leaderId];
                continue;
            }
            uint8 level = teamLevel[leaderId];
            uint256 rate = teamRewardRate[level];
            uint256 reward;
            if (level >= lastLevel) {
                if (level == lastLevel && lastLevel != frontLevel) {
                    // 5%平级奖
                    reward = lastAmount / 20;
                } else {
                    reward = (rate - lastRate) * profit / 10000;
                }
            }
            if (reward > 0) {
                total += reward;
                frontLevel = lastLevel;
                lastLevel = level;
                lastRate = rate;
                lastAmount = reward;
```
