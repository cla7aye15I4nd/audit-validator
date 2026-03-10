// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract LpStakePool is Initializable, AccessControlUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.UintSet;
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    uint256 public constant REWARD_INTERVAL = 24 * 3600;
    struct PoolInfo {
        uint256 allocPoint;
        uint256 duration;
        uint256 stakeAmount;
        uint256 shareAmount;
    }
    struct StakeInfo {
        uint256 amount;
        uint256 shareAmount;
        uint256 dueTime;
        uint256 rewardDebt;
        uint256 rewardClaimed;
        uint256 pid;
    }
    mapping(uint256 => StakeInfo) public stakeInfos;
    mapping(uint256 => uint256) public expireAmounts;
    mapping(uint256 => uint256) public accCheckpoints;
    mapping(address => EnumerableSet.UintSet) stakeIds;
    mapping(address => EnumerableSet.UintSet) unstakedIds;
    address public stakeToken;
    address public rewardToken;
    PoolInfo[] public poolInfos;
    uint256 public totalAllocPoint;
    uint256 public totalStakeAmount;
    uint256 public totalShareAmount;
    uint256 public totalRewardAmount;
    uint256 public accRewardPerShare;
    uint256 public nextRewardTime;
    uint256 public rewardPercent;
    uint256 private _stakeId;

    event StakeLog(address indexed user, uint256 indexed stakeId, uint256 pid, uint256 amount, uint256 operation, uint256 timestamp);
    event TotalRewardChanged(uint256 operation, uint256 amount, uint256 total, uint256 timestamp);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    function initialize(address _stakeToken, address _rewardToken) public initializer {
        __UUPSUpgradeable_init();
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);

        require(_stakeToken != address(0), "Invalid stake token address");
        stakeToken = _stakeToken;
        require(_rewardToken != address(0), "Invalid reward token address");
        rewardToken = _rewardToken;
        rewardPercent = 10; // 1%
    }

    function addPool(uint256 allocPoint, uint256 duration) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(duration >= 7 days, "invalid duration");
        require(duration <= 365 days, "invalid duration");
        poolInfos.push(PoolInfo({allocPoint: allocPoint, duration: duration, stakeAmount: 0, shareAmount: 0}));
        totalAllocPoint += allocPoint;
    }

    function updatePool(uint256 pid, uint256 allocPoint) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(pid < poolInfos.length, "pool not exists");
        totalAllocPoint = totalAllocPoint - poolInfos[pid].allocPoint + allocPoint;
        poolInfos[pid].allocPoint = allocPoint;
    }

    function setRewardPercent(uint16 _rewardPercent) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_rewardPercent <= 1000, "invalid percent");
        require(_rewardPercent >= 1, "invalid percent");
        rewardPercent = _rewardPercent;
    }

    function initRewardTime(uint256 _nextRewardTime) external onlyRole(OPERATOR_ROLE) {
        require(nextRewardTime == 0, "duplicate init");
        // require(_nextRewardTime >= block.timestamp, "invalid time");
        nextRewardTime = _nextRewardTime;
    }

    function depositReward(uint256 amount) external onlyRole(OPERATOR_ROLE) {
        require(amount > 0, "invalid amount");
        IERC20(rewardToken).safeTransferFrom(msg.sender, address(this), amount);
        totalRewardAmount += amount;
        emit TotalRewardChanged(1, amount, totalRewardAmount, block.timestamp);
    }

    function processReward() external {
        require(nextRewardTime > 0, "reward time not init");
        // require(block.timestamp > nextRewardTime, "reward time limited");
        uint256 rewardAmount = (totalRewardAmount * rewardPercent) / 1000;
        require(totalRewardAmount >= rewardAmount, "insufficient reward pool");
        if (totalShareAmount > 0) {
            accRewardPerShare += (rewardAmount * 1e18) / totalShareAmount;
            totalRewardAmount -= rewardAmount;
        }
        uint256 interval = nextRewardTime / REWARD_INTERVAL;
        if (expireAmounts[interval] > 0) {
            accCheckpoints[interval] = accRewardPerShare;
            totalShareAmount -= expireAmounts[interval];
        }
        nextRewardTime += REWARD_INTERVAL;
        emit TotalRewardChanged(2, rewardAmount, totalRewardAmount, block.timestamp);
    }

    function stake(uint256 pid, uint256 amount) external {
        require(amount > 0, "invalid amount");
        require(pid < poolInfos.length, "pool not exists");
        require(totalAllocPoint > 0, "no active pools");
        require(poolInfos[pid].allocPoint > 0, "pool disabled");
        IERC20(stakeToken).safeTransferFrom(msg.sender, address(this), amount);
        uint256 stakeId = _stakeId++;
        uint256 shareAmount = (amount * poolInfos[pid].allocPoint) / totalAllocPoint;
        uint256 dueTime = block.timestamp + poolInfos[pid].duration;
        stakeInfos[stakeId] = StakeInfo({
            amount: amount,
            shareAmount: shareAmount,
            dueTime: dueTime,
            rewardDebt: (shareAmount * accRewardPerShare) / 1e18,
            rewardClaimed: 0,
            pid: pid
        });
        poolInfos[pid].stakeAmount += amount;
        poolInfos[pid].shareAmount += shareAmount;
        stakeIds[msg.sender].add(stakeId);
        totalStakeAmount += amount;
        totalShareAmount += shareAmount;
        expireAmounts[getInterval(dueTime)] += shareAmount;
        emit StakeLog(msg.sender, stakeId, pid, amount, 1, block.timestamp);
    }

    function getAccRewardPerShare(uint256 dueTime) internal view returns (uint256) {
        uint256 expireAcc = accCheckpoints[getInterval(dueTime)];
        return expireAcc > 0 ? expireAcc : accRewardPerShare;
    }

    function unstake(uint256 stakeId) external {
        StakeInfo storage data = stakeInfos[stakeId];
        uint256 amount = data.amount;
        uint256 shareAmount = data.shareAmount;
        require(block.timestamp > data.dueTime, "redeem time limited");
        require(stakeIds[msg.sender].remove(stakeId), "stake owner limited");
        unstakedIds[msg.sender].add(stakeId);
        uint256 pid = data.pid;
        totalStakeAmount -= amount;
        uint256 interval = getInterval(data.dueTime);
        uint256 expireAcc = accCheckpoints[interval];
        if (expireAcc == 0) {
            totalShareAmount -= shareAmount;
            expireAmounts[interval] -= shareAmount;
        }
        poolInfos[pid].stakeAmount -= amount;
        poolInfos[pid].shareAmount -= shareAmount;

        uint256 acc = expireAcc > 0 ? expireAcc : accRewardPerShare;
        uint256 rewardAmount = (shareAmount * acc) / 1e18 - data.rewardDebt;
        IERC20(stakeToken).safeTransfer(msg.sender, amount);
        if (rewardAmount > 0) {
            data.rewardDebt += rewardAmount;
            data.rewardClaimed += rewardAmount;
            IERC20(rewardToken).safeTransfer(msg.sender, rewardAmount);
            emit StakeLog(msg.sender, stakeId, pid, rewardAmount, 3, block.timestamp);
        }
        emit StakeLog(msg.sender, stakeId, pid, amount, 2, block.timestamp);
    }

    function pending(uint256[] calldata _stakeIds) external view returns (uint256[] memory rewards) {
        rewards = new uint256[](_stakeIds.length);
        for (uint256 i = 0; i < _stakeIds.length; i++) {
            StakeInfo storage data = stakeInfos[_stakeIds[i]];
            uint256 acc = getAccRewardPerShare(data.dueTime);
            rewards[i] = (data.shareAmount * acc) / 1e18 - data.rewardDebt;
        }
    }

    function harvest(uint256[] calldata _stakeIds) external {
        require(_stakeIds.length > 0 && _stakeIds.length <= 50, "invalid array length");
        uint256 rewardAmount = 0;
        for (uint256 i = 0; i < _stakeIds.length; i++) {
            StakeInfo storage data = stakeInfos[_stakeIds[i]];
            require(stakeIds[msg.sender].contains(_stakeIds[i]), "stake owner limited");
            uint256 acc = getAccRewardPerShare(data.dueTime);
            uint256 rewardWithDebt = (data.shareAmount * acc) / 1e18;
            uint256 _rewardAmount = rewardWithDebt - data.rewardDebt;
            rewardAmount += _rewardAmount;
            data.rewardDebt = rewardWithDebt;
            data.rewardClaimed += _rewardAmount;
            emit StakeLog(msg.sender, _stakeIds[i], data.pid, _rewardAmount, 3, block.timestamp);
        }
        if (rewardAmount > 0) IERC20(rewardToken).safeTransfer(msg.sender, rewardAmount);
    }

    function getInterval(uint256 time) internal pure returns (uint256) {
        return (time + REWARD_INTERVAL - 1) / REWARD_INTERVAL;
    }

    function getPoolInfos() public view returns (PoolInfo[] memory) {
        return poolInfos;
    }

    function getStakeIds(address user) public view returns (uint256[] memory) {
        return stakeIds[user].values();
    }

    function getUnstakedIds(address user) public view returns (uint256[] memory) {
        return unstakedIds[user].values();
    }

    function getStakeInfos(uint256[] calldata _stakeIds) public view returns (StakeInfo[] memory infos) {
        infos = new StakeInfo[](_stakeIds.length);
        for (uint256 i = 0; i < _stakeIds.length; i++) {
            infos[i] = stakeInfos[_stakeIds[i]];
        }
    }
}
