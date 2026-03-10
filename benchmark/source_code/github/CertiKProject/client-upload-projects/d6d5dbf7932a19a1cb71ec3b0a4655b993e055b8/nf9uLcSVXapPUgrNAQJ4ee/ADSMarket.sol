// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IMining} from "./IMining.sol";
import {INodeNFT} from "./INodeNFT.sol";
import {ISwapFactory} from "./ISwapFactory.sol";
import {ISwapRouter} from "./ISwapRouter.sol";
import {IPancakePair} from "./IPancakePair.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract ADSMarket is UUPSUpgradeable, OwnableUpgradeable, ERC721Holder, PausableUpgradeable {

    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableMap for EnumerableMap.UintToUintMap;

    uint256 public initialCardNum; // 初始卡牌数量
    uint256 public lockTime; // 卡牌交易锁定时间
    uint256 public saleTime; // 卡牌最多挂卖时间
    address public usdtAddress;
    address public adsAddress;
    ISwapRouter public swapRouter;
    INodeNFT public nodeNft;
    IMining public mining;
    address public devAddress1;
    address public devAddress2;
    mapping(uint8 level => uint256 price) public levelPrice; // NFT价格
    mapping(uint8 level => uint256 rate) public teamRewardRate; // 团队收益比例
    mapping(uint8 nodeLevel => uint8 teamLevel) public nodeTeamLevel; // 节点赠送等级

    uint256 public userIdCounter; // 用户id
    uint256 public cardIdCounter; // 卡牌id
    mapping(uint256 id => address user) public getUserById;
    mapping(address user => uint256 id) public getIdByUser;
    mapping(uint256 userId => uint256 leaderId) public getLeaderId; // 层级关系
    mapping(uint256 userId => EnumerableSet.UintSet inviteList) private directUsers; // 直推用户
    mapping(uint256 userId => EnumerableSet.UintSet teamList) private teamUsers; // 团队用户
    mapping(uint256 cardId => Card card) public cardMap; // 卡牌
    mapping(uint256 userId => EnumerableSet.UintSet cardIds) private userCard; // 用户卡牌
    mapping(uint256 userId => uint256 profit) public userProfitMap; // 用户静态利润

    uint256 public nodeTotalPrice; // 节点价格总和
    uint256 public nodeRewardAmount; // 节点待分红总数量
    mapping(uint256 userId => uint8 level) public teamLevel; // 用户团队等级
    mapping(uint256 userId => uint256 teamPerformance) public teamPerformanceMap; // 用户团队业绩
    mapping(uint256 userId => uint8 level) public teamHighestLevel; // 团队最高等级
    mapping(uint256 userId => mapping(uint8 level => uint256 count)) public teamLevelCount; // 团队内各等级数量
    EnumerableMap.UintToUintMap private nodeUserMap; // 节点用户==>tokenId
    mapping(uint256 tokenId => Node node) public nodeMap; // tokenId==>节点
    mapping(uint8 level => uint256[] tokenIds) public onSaleNft; // 在售NFT
    mapping(address => bool) public tradeAddress; // AI交易地址

    struct Card {
        uint256 userId;
        uint256 lastPrice;
        uint256 currentPrice;
        uint256 lastTradeAt;
        uint256 sellStartTime;
        uint256 sellEndTime;
        bool isBox;
    }

    struct Node {
        uint8 level;
        uint256 price;
        uint256 remainder;
        uint256 renewalEndAt;
    }

    struct User {
        uint256 userId;
        address addr;
        uint256 teamPerformance;
    }

    event AddRelation(address indexed user, uint256 userId, uint256 leaderId);
    event TransferTeam(uint256 userId, address newAddress);
    event CardTransfer(uint256 toUserId, uint256 cardId, uint256 price, uint256 lastTradeAt, uint256 sellStartTime, uint256 sellEndTime);
    event CardBecomeBox(uint256 cardId);
    event TeamLevelChanged(uint256 userId, uint8 level);
    event DirectReward(uint256 userId, uint256 fromId, uint256 amount);
    event TeamReward(uint256 userId, uint256 fromId, uint256 amount);
    event ActiveNode(uint256 userId, uint256 tokenId, uint8 tokenLevel);
    event TransferNode(uint256 userId, uint256 toUserId, uint256 tokenId);
    event NodeReward(uint256 userId, uint256 amount);
    event NodeDividendEnd(uint256 userId);
    event DeprecateNode(uint256 tokenId);

    constructor() {
        _disableInitializers();
    }

    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}

    function initialize(address _usdtAddress, address _adsAddress, address _nftAddress, address _swapRouter) public initializer {
        __Ownable_init(_msgSender());
        teamRewardRate[1] = 500;
        teamRewardRate[2] = 1000;
        teamRewardRate[3] = 1500;
        teamRewardRate[4] = 2000;
        teamRewardRate[5] = 2500;
        teamRewardRate[6] = 3000;
        teamRewardRate[7] = 3500;
        nodeTeamLevel[1] = 3;
        nodeTeamLevel[2] = 4;
        nodeTeamLevel[3] = 5;
        levelPrice[1] = 500 ether;
        levelPrice[2] = 2000 ether;
        levelPrice[3] = 5000 ether;
        usdtAddress = _usdtAddress;
        adsAddress = _adsAddress;
        nodeNft = INodeNFT(_nftAddress);
        swapRouter = ISwapRouter(_swapRouter);
        userIdCounter = 1000;
        _registerUser(_msgSender(), 0);
        cardIdCounter = 1;
        initialCardNum = 1000;
        IERC20(usdtAddress).forceApprove(address(swapRouter), type(uint256).max);
        IERC20(adsAddress).forceApprove(address(swapRouter), type(uint256).max);
        _pause();
    }

    function _registerUser(address account, uint256 leaderId) internal virtual {
        userIdCounter += _randomInt();
        uint256 id = userIdCounter;
        getUserById[id] = account;
        getIdByUser[account] = id;
        getLeaderId[id] = leaderId;
        emit AddRelation(account, id, leaderId);
        if (leaderId != 0) {
            directUsers[leaderId].add(id);
        }
        while (leaderId != 0) {
            teamUsers[leaderId].add(id);
            leaderId = getLeaderId[leaderId];
        }
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function initContract(uint256 _lockTime, uint256 _saleTime, address dev1, address dev2, address _miningAddress) external onlyOwner {
        lockTime = _lockTime;
        saleTime = _saleTime;
        devAddress1 = dev1;
        devAddress2 = dev2;
        mining = IMining(_miningAddress);
    }

    function setTradeAddress(address account, bool value) external onlyOwner {
        tradeAddress[account] = value;
    }

    function _randomInt() internal virtual returns (uint256 value) {
        uint256 randomNum = uint256(keccak256(abi.encodePacked(block.prevrandao, block.timestamp, userIdCounter)));
        value = randomNum % 20;
        if (value == 0) {
            value = 6;
        }
    }

    function _getAmountBOptimal(uint256 amountA, address tokenA, address tokenB) internal virtual returns (uint256) {
        address pairAddress = ISwapFactory(swapRouter.factory()).getPair(tokenA, tokenB);
        (uint256 reserve0, uint256 reserve1, ) = IPancakePair(pairAddress).getReserves();
        (uint256 reserveA, uint256 reserveB) = tokenA < tokenB ? (reserve0, reserve1) : (reserve1, reserve0);
        return amountA * reserveB / reserveA;
    }

    function _swapAndAddLiquidity(uint256 usdtIn) internal virtual {
        uint256 halfUsdt = usdtIn / 2;
        address[] memory swapPath = new address[](2);
        swapPath[0] = usdtAddress;
        swapPath[1] = adsAddress;
        uint256 adsIn = swapRouter.swapExactTokensForTokens(
            halfUsdt,
            0,
            swapPath,
            address(this),
            block.timestamp
        )[1];
        swapRouter.addLiquidity(usdtAddress, adsAddress, halfUsdt, adsIn, 0, 0, address(0), block.timestamp);
        uint256 remainAds = IERC20(adsAddress).balanceOf(address(this));
        if (remainAds > 0) {
            IERC20(adsAddress).safeTransfer(address(mining), remainAds);
        }
    }

    function _getADSAmountsOut(uint256 usdtIn) internal view virtual returns (uint256) {
        if (usdtIn == 0) return 0;
        address[] memory swapPath = new address[](2);
        swapPath[0] = usdtAddress;
        swapPath[1] = adsAddress;
        return swapRouter.getAmountsOut(usdtIn, swapPath)[1];
    }

    function _updateTeamLevel(uint256 userId) internal virtual {
        uint256 teamPerformance = teamPerformanceMap[userId];
        uint8 newLevel;
        if (teamPerformance >= 100000 ether) newLevel = 1;
        if (teamLevelCount[userId][1] >= 2 && teamPerformance >= 500000 ether) newLevel = 2;
        if (teamLevelCount[userId][2] >= 2 && teamPerformance >= 3000000 ether) newLevel = 3;
        if (teamLevelCount[userId][3] >= 2 && teamPerformance >= 10000000 ether) newLevel = 4;
        if (teamLevelCount[userId][4] >= 2 && teamPerformance >= 20000000 ether) newLevel = 5;
        if (teamLevelCount[userId][5] >= 2 && teamPerformance >= 50000000 ether) newLevel = 6;
        if (teamLevelCount[userId][6] >= 2 && teamPerformance >= 80000000 ether) newLevel = 7;
        if (newLevel > teamLevel[userId]) {
            teamLevel[userId] = newLevel;
            emit TeamLevelChanged(userId, newLevel);
            _onTeamLevelUp(userId, newLevel);
        }
    }

    function _onTeamLevelUp(uint256 userId, uint8 newLevel) internal virtual {
        while (userId != 0) {
            if (newLevel > teamHighestLevel[userId]) {
                teamHighestLevel[userId] = newLevel;
                _onTeamHighestLevelUp(userId, newLevel);
            }
            userId = getLeaderId[userId];
        }
    }

    function _onTeamHighestLevelUp(uint256 userId, uint8 newLevel) internal virtual {
        uint256 leaderId = getLeaderId[userId];
        if (leaderId == 0) {
            return;
        }
        teamLevelCount[leaderId][newLevel] += 1;
    }

    // 设置领导人
    function addRelation(uint256 _id) external virtual whenNotPaused {
        if (getIdByUser[_msgSender()] != 0) revert("repeat bind");
        if (getUserById[_id] == address(0)) revert("user not exist");
        _registerUser(_msgSender(), _id);
    }

    // 转出团队
    function transferTeam(address to) external virtual whenNotPaused {
        uint256 userId = getIdByUser[_msgSender()];
        if (userId == 0) revert("need bind a leader");
        if (getIdByUser[to] != 0) revert("already bind leader");
        getUserById[userId] = to;
        getIdByUser[to] = userId;
        delete getIdByUser[_msgSender()];
        emit TransferTeam(userId, to);
    }

    // NFT上架
    function publishNft(uint256[] calldata tokenIds) external virtual whenNotPaused {
        for (uint256 i; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            nodeNft.safeTransferFrom(_msgSender(), address(this), tokenId);
            onSaleNft[nodeNft.tokenLevel(tokenId)].push(tokenId);
        }
    }

    // 购买节点
    function buyNode(uint8 level) external virtual whenNotPaused {
        uint256 len = onSaleNft[level].length;
        if (len == 0) revert("nodes not enough");
        uint256 price = levelPrice[level];
        if (price == 0) revert("parameter error: level");
        IERC20(usdtAddress).safeTransferFrom(_msgSender(), address(this), price);
        uint256 tokenId = onSaleNft[level][len - 1];
        onSaleNft[level].pop();
        nodeNft.safeTransferFrom(address(this), _msgSender(), tokenId);
        _swapAndAddLiquidity(price);
    }

    // 激活节点
    function activeNode(uint256 tokenId) external virtual whenNotPaused {
        takeNodeReward();
        uint256 userId = getIdByUser[_msgSender()];
        if (userId == 0) revert("need bind a leader");
        if (nodeUserMap.contains(userId)) revert("already a node");
        nodeNft.safeTransferFrom(_msgSender(), address(this), tokenId);
        nodeUserMap.set(userId, tokenId);
        uint8 tokenLevel = nodeNft.tokenLevel(tokenId);
        uint256 price = levelPrice[tokenLevel];
        nodeMap[tokenId] = Node(tokenLevel, price, price * 3, 0);
        uint8 oldLevel = teamLevel[userId];
        uint8 level = nodeTeamLevel[tokenLevel];
        if (level <= oldLevel) revert("invalid node");
        teamLevel[userId] = level;
        emit TeamLevelChanged(userId, level);
        for (uint8 i = oldLevel + 1; i <= level; i++) {
            _onTeamLevelUp(userId, i);
        }
        emit ActiveNode(userId, tokenId, tokenLevel);
        nodeTotalPrice += price;
    }

    // 转出节点
    function transferNode(uint256 to) external virtual {
        if (getUserById[to] == address(0)) revert("user not exist");
        if (nodeUserMap.contains(to)) revert("already a node");
        uint256 userId = getIdByUser[_msgSender()];
        if (!nodeUserMap.contains(userId)) revert("not a node");
        nodeUserMap.set(to, nodeUserMap.get(userId));
        nodeUserMap.remove(userId);
        emit TransferNode(userId, to, nodeUserMap.get(to));
    }

    // 提取节点分红奖励
    function takeNodeReward() public virtual whenNotPaused {
        uint256 reward = nodeRewardAmount;
        if (reward <= 0) return;
        uint256[] memory list = nodeUserMap.keys();
        uint256 size = list.length;
        if (size == 0) return;
        uint256 total;
        for (uint256 i; i < size; i++) {
            Node storage node = nodeMap[nodeUserMap.get(list[i])];
            uint256 remain = node.remainder;
            if (userCard[list[i]].length() > 0 && remain > 0) {
                // 分红数量=待分红总数*节点价格/节点价格总和
                uint256 value = reward * node.price / nodeTotalPrice;
                uint256 amount = remain > value ? value : remain;
                node.remainder = remain - amount;
                if (node.remainder == 0) {
                    node.renewalEndAt = block.timestamp + 2 days;
                    emit NodeDividendEnd(list[i]);
                }
                IERC20(usdtAddress).safeTransfer(getUserById[list[i]], amount);
                emit NodeReward(list[i], amount);
                total += amount;
            }
        }
        nodeRewardAmount -= total;
    }

    // 节点续费
    function renewalNode() external virtual {
        uint256 userId = getIdByUser[_msgSender()];
        if (!nodeUserMap.contains(userId)) revert("not a node");
        Node storage node = nodeMap[nodeUserMap.get(userId)];
        if (node.remainder != 0) revert("dividend not end");
        if (node.renewalEndAt != 0 && node.renewalEndAt < block.timestamp) revert("node renewal ended");
        uint256 amount = _getADSAmountsOut(node.price);
        IERC20(adsAddress).safeTransferFrom(_msgSender(), address(0), amount);
        node.remainder = node.price * 3;
        node.renewalEndAt = 0;
    }

    // 节点废除
    function deprecateNode(uint256 userId) external virtual {
        if (!nodeUserMap.contains(userId)) revert("not a node");
        uint256 tokenId = nodeUserMap.get(userId);
        Node memory node = nodeMap[tokenId];
        if (node.remainder != 0) revert("dividend not end");
        if (node.renewalEndAt == 0 || node.renewalEndAt > block.timestamp) revert("node renewal not ended");
        nodeUserMap.remove(userId);
        nodeTotalPrice -= node.price;
        // 重新上架NFT
        onSaleNft[node.level].push(tokenId);
        emit DeprecateNode(tokenId);
    }

    // 发新的卡牌
    function mintCard(uint256 num) external virtual whenNotPaused {
        uint256 currentId = cardIdCounter - 1;
        uint256 maxNum = 1;
        if (currentId < initialCardNum) {
            maxNum = initialCardNum - currentId;
        } else if (cardMap[currentId].userId == 0 && cardMap[currentId].lastPrice == 0) {
            maxNum = 0;
        } else if (cardMap[currentId].lastTradeAt > block.timestamp - 30 minutes) {
            maxNum = 0;
        }
        if (num > maxNum) revert("exceed maximum card number");
        for (uint256 i; i < num; i++) {
            uint256 id = cardIdCounter++;
            cardMap[id] = Card(0, 0, 100 ether, block.timestamp, block.timestamp, block.timestamp + 100 days, false);
            emit CardTransfer(0, id, 100 ether, 0, 0, block.timestamp + 100 days);
        }
    }

    function _buyCardFor(uint256 cardId, uint256 userId) internal virtual {
        if (cardMap[cardId].currentPrice == 0) revert("card not exist");
        if (cardMap[cardId].userId == userId) revert("your own card");
        if (cardMap[cardId].sellStartTime > block.timestamp) revert("not release");
        if (cardMap[cardId].isBox || cardMap[cardId].sellEndTime < block.timestamp) revert("not a card");
        uint256 canHold = getUserCanHold(userId);
        if (canHold <= userCard[userId].length()) revert("exceed maximum hold");
        Card storage card = cardMap[cardId];
        uint256 seller = card.userId;
        uint256 price = card.currentPrice;
        uint256 lastPrice = card.lastPrice;
        IERC20(usdtAddress).safeTransferFrom(getUserById[userId], address(this), price);
        if (seller == 0) { // 首发卡
            // 添加流动性
            _swapAndAddLiquidity(price);
        } else {
            // 卖家本金
            IERC20(usdtAddress).safeTransfer(getUserById[seller], lastPrice);
            uint256 profit = price - lastPrice;
            // 卖家30%盈利
            userProfitMap[seller] += profit * 30 / 100;
            // 15%添加流动性
            _swapAndAddLiquidity(profit * 15 / 100);
            IERC20(usdtAddress).safeTransfer(devAddress1, profit * 2 / 100);
            uint256 directAmount;
            if (getLeaderId[userId] > 0) {
                // 8%直推奖励
                directAmount = profit * 8 / 100;
                IERC20(usdtAddress).safeTransfer(getUserById[getLeaderId[userId]], directAmount);
                emit DirectReward(getLeaderId[userId], userId, directAmount);
            }
            // 35%团队奖励+5%平级奖
            uint256 teamAmount = teamReward(userId, profit);
            IERC20(usdtAddress).safeTransfer(devAddress2, profit * 48 / 100 - directAmount - teamAmount);
            // 5%节点分红
            nodeRewardAmount += (profit * 5 / 100);
        }
        card.userId = userId;
        card.lastPrice = price;
        card.currentPrice = price * 11 / 10;
        card.lastTradeAt = block.timestamp;
        card.sellStartTime = card.lastTradeAt + lockTime;
        card.sellEndTime = card.sellStartTime + saleTime;
        // 买家领取上一次交易的利润
        uint256 userProfit = userProfitMap[userId];
        if (userProfit > 0) {
            IERC20(usdtAddress).safeTransfer(getUserById[userId], userProfit);
            userProfitMap[userId] = 0;
        }
        emit CardTransfer(userId, cardId, card.currentPrice, card.lastTradeAt, card.sellStartTime, card.sellEndTime);
        userCard[seller].remove(cardId);
        userCard[userId].add(cardId);
        while (userId != 0) {
            unchecked {
                teamPerformanceMap[userId] += price;
            }
            _updateTeamLevel(userId);
            userId = getLeaderId[userId];
        }
    }

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
                IERC20(usdtAddress).safeTransfer(getUserById[leaderId], reward);
                emit TeamReward(leaderId, userId, reward);
            }
            leaderId = getLeaderId[leaderId];
        }
        return total;
    }

    function getUserCanHold(uint256 userId) public view virtual returns (uint256 value) {
        value = 5;
        EnumerableSet.UintSet storage list = directUsers[userId];
        for (uint256 i; i < list.length(); i++) {
            if (userCard[list.at(i)].length() > 0) {
                value += 3;
            }
        }
    }

    function getInviteList(uint256 userId) public view virtual returns (User[] memory list) {
        uint256 len = directUsers[userId].length();
        list = new User[](len);
        for (uint256 i; i < len; i++) {
            uint256 id = directUsers[userId].at(i);
            list[i] = User(id, getUserById[id], teamPerformanceMap[id]);
        }
    }

    function getNodeNumber(uint8 level) public view virtual returns (uint256 value) {
        value = onSaleNft[level].length;
    }

    function isNode(uint256 userId) public view virtual returns (bool value) {
        value = nodeUserMap.contains(userId);
    }

    function getUserHoldNum(address user) external view returns (uint256) {
        return userCard[getIdByUser[user]].length();
    }

}
