// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract MWXStaking is UUPSUpgradeable, AccessControlUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20Metadata;

    // Constants
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    uint256 private constant SECONDS_PER_YEAR = 31536000; // 365 * 24 * 60 * 60
    uint256 private constant PRECISION_FACTOR = 1e18;

    // Tokens
    IERC20Metadata public stakingToken;
    IERC20Metadata public rewardToken;

    address public rewardVault;
    
    // Core staking variables
    /// @notice Divider for the reward pool
    uint8 public forYear;
    /// @notice Annual reward pool in 1e18 precision
    uint256 private annualRewardPool;
    /// @notice Emission rate per second in 1e18 precision
    uint256 private emissionPerSecond;
    /// @notice Last update time
    uint256 public lastUpdateTime;
    /// @notice Reward per token stored
    uint256 public rewardPerTokenStored;
    /// @notice Total effective stake
    uint256 public totalEffectiveStake;

    // Tracking variables
    /// @notice Total flexible staked
    uint256 public totalFlexibleStaked;
    /// @notice Total locked staked
    uint256 public totalLockedStaked;
    /// @notice Total rewards claimed
    uint256 public totalRewardsClaimed;
    /// @notice Unique stakers
    uint256 public uniqueStakers;

    // Structs
    /// @notice Stake type
    enum StakeType { FLEXIBLE, LOCKED }

    /// @notice Locked option
    struct LockedOption {
        uint256 duration; // in seconds
        uint256 multiplier; // in 1e18
        bool active;
    }

    /// @notice Stake info
    struct StakeInfo {
        uint256 stakeId;
        address owner;
        StakeType stakeType;
        uint256 amount;
        uint256 effectiveAmount; // amount * multiplier
        uint256 multiplier;
        uint256 startTime;
        uint256 unlockTime; // 0 for flexible
        uint256 lastUpdateTime;
        uint256 userRewardPerTokenPaid;
        uint256 pendingRewards;
        uint256 lockId; // 0 for flexible, 1, 2, 3 for locked options
        bool active;
    }

    // Mappings
    /// @notice User nonce
    mapping(address => uint256) public userNonce;
    /// @notice Stakes (address user => stakeId => StakeInfo)
    mapping(address => mapping(uint256 => StakeInfo)) public stakes;
    /// @notice User stake IDs (address user => stakeIds[])
    mapping(address => uint256[]) public userStakeIds;
    /// @notice Locked options
    mapping(uint256 => LockedOption) public lockedOptions; // lockId => LockedOption
    /// @notice User total staked (address user => total staked)
    mapping(address => uint256) public userTotalStaked;
    /// @notice User total effective staked (address user => total effective staked)
    mapping(address => uint256) public userTotalEffectiveStaked;
    /// @notice User total rewards claimed (address user => total rewards claimed)
    mapping(address => uint256) public userTotalRewardsClaimed;

    // Lock options tracking
    /// @notice Active lock IDs
    uint256[] public activeLockIds;
    /// @notice Total staked per lock (lockId => total staked)
    mapping(uint256 => uint256) public totalStakedPerLock;

    // Events
    /// @notice Reward vault set
    event RewardVaultSet(address indexed rewardVault);

    /// @notice Staked event
    event Staked(
        address indexed user,
        uint256 indexed stakeId,
        StakeType stakeType,
        uint256 amount,
        uint256 effectiveAmount,
        uint256 lockDuration
    );
    
    /// @notice Unstaked event
    event Unstaked(
        address indexed user,
        uint256 indexed stakeId,
        uint256 amount,
        bool emergency
    );
    
    /// @notice Reward claimed event
    event RewardClaimed(
        address indexed user,
        uint256 indexed stakeId,
        uint256 reward
    );
    
    /// @notice All rewards claimed event
    event AllRewardsClaimed(
        address indexed user,
        uint256 totalReward
    );
    
    /// @notice Emergency unstaked event
    event EmergencyUnstaked(
        address indexed user,
        uint256 indexed stakeId,
        uint256 amount,
        uint256 forfeitedRewards
    );

    /**
     * @notice Emitted when a foreign token is withdrawn
     * @param token The address of the token 0x0000000000000000000000000000000000000000 for native token
     * @param recipient The address of the recipient
     * @param amount The amount of tokens withdrawn
     */
    event WithdrawForeignToken(address token, address recipient, uint256 amount);

    /**
     * @notice Emitted when the annual reward pool is updated
     * @param newAnnualRewardPool The new annual reward pool
     */
    event AnnualRewardPoolUpdated(uint256 newAnnualRewardPool);

    /**
     * @notice Emitted when a locked option is updated
     * @param lockId The ID of the lock option
     * @param duration The duration of the lock option
     * @param multiplier The multiplier of the lock option
     * @param active Whether the lock option is active
     */
    event LockedOptionUpdated(uint256 lockId, uint256 duration, uint256 multiplier, bool active);

    error InvalidStakeAmount();
    error InvalidLockOption();
    error LockOptionNotActive();
    error StakeStillLocked();
    error BalanceNotEnough();
    error NoPendingRewards();
    error NoStakes();
    error InvalidForYear();
    error InvalidTokenAddress();
    error InvalidAddress();
    error InvalidAmount();
    error InsufficientBalance();
    error InvalidDuration();
    error InvalidMultiplier();
    error InvalidRewardPool();
    error InsufficientAllowance();
    error StakeNotExists();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Receive function to receive native tokens
     */
    receive() external virtual payable {}

    /**
     * @dev Authorize upgrade
     * @param newImplementation New implementation address
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    /**
     * @dev Initializes the staking contract
     * @param _stakingToken Address of the token to be staked
     * @param _rewardToken Address of the reward token
     * @param _rewardVault Address of the reward vault
     * @param _rewardPool Total annual reward pool
     * @param _forYear Divider for the reward pool
     */
    /// @custom:oz-upgrades-validate-as-initializer
    function initialize(
        address _stakingToken,
        address _rewardToken,
        address _rewardVault,
        uint256 _rewardPool,
        uint8 _forYear
    ) external initializer {
        if (_stakingToken == address(0) || _rewardToken == address(0)) revert InvalidTokenAddress();
        if (_rewardPool == 0) revert InvalidRewardPool();
        if (_forYear == 0) revert InvalidForYear();

        __AccessControl_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _grantRole(OPERATOR_ROLE, _msgSender());

        stakingToken = IERC20Metadata(_stakingToken);
        rewardToken = IERC20Metadata(_rewardToken);
        _setRewardVault(_rewardVault);
        _setRewardPool(_rewardPool, _forYear);

        // Initialize default locked options
        _setLockedOption(1, 90 days, 125e16, true);   // 3 months, 1.25x
        _setLockedOption(2, 180 days, 150e16, true);  // 6 months, 1.5x
        _setLockedOption(3, 365 days, 200e16, true);  // 12 months, 2x
    }

    /**
     * @dev Update reward per token
     */
    modifier updateReward() {
        _updateReward();
        _;
    }

    /**
     * @dev Update stake information
     * @param user The user address
     * @param stakeId The stake ID
     */
    modifier updateStake(address user, uint256 stakeId) {
        _updateStake(user, stakeId);
        _;
    }

    /**
     * @dev Pause the contract
     */
    function pause() external onlyRole(OPERATOR_ROLE) {
        _pause();
    }

    /**
     * @dev Unpause the contract
     */
    function unpause() external onlyRole(OPERATOR_ROLE) {
        _unpause();
    }

    /**
     * @dev Stake tokens
     * @param amount The amount of tokens to stake
     * @param lockId The lock option ID. 0 for flexible, 1, 2, 3 for locked options
     * @return stakeId The ID of the stake
     */
    function stake(uint256 amount, uint256 lockId) external virtual nonReentrant whenNotPaused returns (uint256 stakeId) {
        return _stake(amount, lockId);
    }

    /**
     * @dev Internal function to stake tokens
     * @param amount The amount of tokens to stake
     * @param lockId The lock option ID. 0 for flexible, 1, 2, 3 for locked options
     * @return stakeId The ID of the stake
     */
    function _stake(uint256 amount, uint256 lockId) internal virtual updateReward returns (uint256 stakeId) {
        if (amount == 0) revert InvalidStakeAmount();
        if (lockId > 0 && !lockedOptions[lockId].active) revert LockOptionNotActive();

        // transfer first to avoid reentrancy
        stakingToken.safeTransferFrom(_msgSender(), address(this), amount);

        if (userNonce[_msgSender()] == 0) {
            uniqueStakers++;
        }

        userNonce[_msgSender()]++;
        stakeId = userNonce[_msgSender()];

        StakeInfo storage newStake = stakes[_msgSender()][stakeId];
        newStake.stakeId = stakeId;
        newStake.owner = _msgSender();
        newStake.stakeType = lockId > 0 ? StakeType.LOCKED : StakeType.FLEXIBLE;
        newStake.multiplier = lockId > 0 ? lockedOptions[lockId].multiplier : PRECISION_FACTOR; // in 1e18
        newStake.amount = amount;
        newStake.effectiveAmount = amount * newStake.multiplier / PRECISION_FACTOR;
        newStake.startTime = block.timestamp;
        newStake.unlockTime = lockId > 0 ? block.timestamp + lockedOptions[lockId].duration : 0;
        newStake.userRewardPerTokenPaid = rewardPerTokenStored;
        newStake.lockId = lockId;
        newStake.active = true;

        userStakeIds[_msgSender()].push(stakeId);
        userTotalStaked[_msgSender()] += amount;
        userTotalEffectiveStaked[_msgSender()] += newStake.effectiveAmount;

        if (newStake.stakeType == StakeType.FLEXIBLE) {
            totalFlexibleStaked += amount;
        } else {
            totalLockedStaked += amount;
            totalStakedPerLock[lockId] += amount;
        }

        totalEffectiveStake += newStake.effectiveAmount;

        emit Staked(
            _msgSender(), 
            stakeId, 
            newStake.stakeType, 
            amount, 
            newStake.effectiveAmount, 
            newStake.stakeType == StakeType.LOCKED ? lockedOptions[lockId].duration : 0
        );

        return stakeId;
    }

    /**
     * @dev Unstake tokens
     * @param stakeId The stake ID
     */
    function unstake(uint256 stakeId) external virtual nonReentrant whenNotPaused {
        _unstake(stakeId, false);
    }

    /**
     * @dev Emergency unstake (forfeit rewards for locked stakes)
     * @param stakeId The stake ID
     */
    function emergencyUnstake(uint256 stakeId) external virtual nonReentrant whenNotPaused {
        _unstake(stakeId, true);
    }

    /**
     * @dev Internal function to unstake tokens
     * @param stakeId The stake ID
     * @param emergency Whether the unstake is an emergency unstake
     */
    function _unstake(uint256 stakeId, bool emergency) internal virtual updateReward updateStake(_msgSender(), stakeId) {
        StakeInfo storage stakeInfo = stakes[_msgSender()][stakeId];
        
        if (stakeInfo.stakeType == StakeType.LOCKED && !emergency) {
            if (block.timestamp < stakeInfo.unlockTime) revert StakeStillLocked();
        }

        uint256 amount = stakeInfo.amount;
        uint256 effectiveAmount = stakeInfo.effectiveAmount;
        uint256 forfeitedRewards = stakeInfo.pendingRewards;
        
        // Update totals
        userTotalStaked[_msgSender()] -= amount;
        userTotalEffectiveStaked[_msgSender()] -= effectiveAmount;
        totalEffectiveStake -= effectiveAmount;
        
        if (stakeInfo.stakeType == StakeType.FLEXIBLE) {
            totalFlexibleStaked -= amount;
        } else {
            totalLockedStaked -= amount;
            totalStakedPerLock[stakeInfo.lockId] -= amount;
        }

        // claim rewards first if stake type is flexible
        if (stakeInfo.stakeType == StakeType.FLEXIBLE) {
            _claimRewards(_msgSender(), stakeInfo.pendingRewards);
            forfeitedRewards = 0;
        }

        // claim rewards if stake type is locked and stake is unlocked (unlock period is over)
        if (stakeInfo.stakeType == StakeType.LOCKED && block.timestamp >= stakeInfo.unlockTime) {
            _claimRewards(_msgSender(), stakeInfo.pendingRewards);
            forfeitedRewards = 0;
        }

        // flag stake as inactive and remove from user stake ids
        stakeInfo.active = false;
        _removeStakeId(_msgSender(), stakeId);

        if (!emergency) {
            emit Unstaked(_msgSender(), stakeId, amount, false);
        } else {
            emit EmergencyUnstaked(_msgSender(), stakeId, amount, forfeitedRewards);
        }
        
        stakingToken.safeTransfer(_msgSender(), amount);
    }

    /**
     * @dev Claim rewards for a specific stake
     * @param stakeId The ID of the stake
     */
    function claim(uint256 stakeId) external virtual nonReentrant whenNotPaused updateReward updateStake(_msgSender(), stakeId) {
        StakeInfo storage stakeInfo = stakes[_msgSender()][stakeId];
        if (stakeInfo.pendingRewards == 0) revert NoPendingRewards();

        uint256 rewardAmount = stakeInfo.pendingRewards;
        stakeInfo.pendingRewards = 0;

        _claimRewards(_msgSender(), rewardAmount);

        emit RewardClaimed(_msgSender(), stakeId, rewardAmount);
    }

    /**
     * @dev Claim rewards for all user stakes
     */
    function claimAll() external virtual nonReentrant whenNotPaused updateReward {
        uint256[] memory stakeIds = userStakeIds[_msgSender()];
        if (stakeIds.length == 0) revert NoStakes();
        
        uint256 totalRewards = 0;
        
        for (uint256 i = 0; i < stakeIds.length; i++) {
            // update the stake info for calculating the pending rewards and update the paid rewards
            _updateStake(_msgSender(), stakeIds[i]);
            
            if (stakes[_msgSender()][stakeIds[i]].active) {
                // add the pending rewards to the total rewards
                totalRewards += stakes[_msgSender()][stakeIds[i]].pendingRewards;
                // reset the pending rewards to 0
                stakes[_msgSender()][stakeIds[i]].pendingRewards = 0;
            }
        }
        
        if (totalRewards == 0) revert NoPendingRewards();
        
        _claimRewards(_msgSender(), totalRewards);
        
        emit AllRewardsClaimed(_msgSender(), totalRewards);
    }

    /**
     * @dev Calculate current reward per token
     */
    function rewardPerToken() public view virtual returns (uint256) {
        if (totalEffectiveStake == 0) return 0;
        
        return rewardPerTokenStored + 
            (((block.timestamp - lastUpdateTime) * emissionPerSecond) / totalEffectiveStake);
    }

    /**
     * @dev Calculate earned rewards for a specific stake
     * @param account The address of the user
     * @param stakeId The ID of the stake
     * @return uint256 The earned rewards
     */
    function earned(address account, uint256 stakeId) public view virtual returns (uint256) {
        StakeInfo memory stakeInfo = stakes[account][stakeId];
        if (!stakeInfo.active) return 0;

        return (
            (stakeInfo.effectiveAmount * (rewardPerToken() - stakeInfo.userRewardPerTokenPaid)) / PRECISION_FACTOR
        ) + stakeInfo.pendingRewards;
    }

    /**
     * @dev Get current APR
     * @return uint256 The current APR
     */
    function getCurrentAPR() external view virtual returns (uint256) {
        if (totalEffectiveStake == 0) return 0;
        return (emissionPerSecond * SECONDS_PER_YEAR) / totalEffectiveStake;
    }

    /**
     * @dev Get total reward pool for all years
     * @return uint256 The total reward pool of all years
     */
    function getTotalRewardPoolAllYear() external view virtual returns (uint256) {
        return annualRewardPool * forYear / PRECISION_FACTOR;
    }

    /**
     * @dev Get annual reward pool
     * @return uint256 The annual reward pool
     */
    function getAnnualRewardPool() external view virtual returns (uint256) {
        return annualRewardPool / PRECISION_FACTOR;
    }

    /**
     * @dev Get emission per second
     * @return uint256 The emission per second
     */
    function getEmissionPerSecond() external view virtual returns (uint256) {
        return emissionPerSecond / PRECISION_FACTOR;
    }

    /**
     * @dev Get stake by stake ID
     * @param user The address of the user
     * @param stakeId The ID of the stake
     * @return StakeInfo The stake info
     */
    function getStakeById(address user, uint256 stakeId) external view virtual returns (StakeInfo memory) {
        return stakes[user][stakeId];
    }

    /**
     * @dev Get pending rewards for a specific stake
     * @param user The address of the user
     * @param stakeId The ID of the stake
     * @return uint256 The pending rewards
     */
    function getPendingRewards(address user, uint256 stakeId) external view virtual returns (uint256) {
        return earned(user, stakeId);
    }

    /**
     * @dev Get user total pending rewards
     * @param user The address of the user
     * @return totalRewards The total pending rewards
     */
    function getUserTotalPendingRewards(address user) external view virtual returns (uint256 totalRewards) {
        uint256[] memory stakeIds = userStakeIds[user];
        for (uint256 i = 0; i < stakeIds.length; i++) {
            totalRewards += earned(user, stakeIds[i]);
        }
    }

    /**
     * @dev Get user total staked
     * @param user The address of the user
     * @return totalStaked The total staked
     * @return totalEffectiveStaked The total effective staked
     */
    function getTotalUserStaked(address user) external view virtual returns (uint256 totalStaked, uint256 totalEffectiveStaked) {
        uint256[] memory stakeIds = userStakeIds[user];
        for (uint256 i = 0; i < stakeIds.length; i++) {
            totalStaked += stakes[user][stakeIds[i]].amount;
            totalEffectiveStaked += stakes[user][stakeIds[i]].effectiveAmount;
        }
    }

    /**
     * @dev Get active lock IDs
     */
    function getActiveLockIds() external view virtual returns (uint256[] memory) {
        return activeLockIds;
    }

    /**
     * @dev Get locked option
     * @param lockId The ID of the lock option
     * @return LockedOption The locked option
     */
    function getLockedOption(uint256 lockId) external view virtual returns (LockedOption memory) {
        return lockedOptions[lockId];
    }

    /**
     * @dev Get user stake count
     * @param user The address of the user
     * @return uint256 The number of stakes
     */
    function getUserStakeCount(address user) external view virtual returns (uint256) {
        return userStakeIds[user].length;
    }

    /**
     * @dev Get user stakes with pagination
     * @param user The address of the user
     * @param offset The offset of the stakes
     * @param limit The limit of the stakes
     * @return result The array of stakes
     * @return total The total number of stakes
     */
    function getUserStakes(address user, uint256 offset, uint256 limit) external virtual view returns (StakeInfo[] memory result, uint256 total) {
        uint256[] memory stakeIds = userStakeIds[user];
        total = stakeIds.length;
        
        if (offset >= stakeIds.length) {
            return (new StakeInfo[](0), total);
        }
        
        uint256 remaining = total - offset;
        uint256 actualLimit = remaining < limit ? remaining : limit;
        
        result = new StakeInfo[](actualLimit);
        
        for (uint256 i = 0; i < actualLimit; i++) {
            result[i] = stakes[user][stakeIds[offset + i]];
        }
        
        return (result, total);
    }

    /**
     * @dev Set reward vault
     * @param _rewardVault Address of the reward vault
     */
    function setRewardVault(address _rewardVault) external virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        _setRewardVault(_rewardVault);
    }

    /**
     * @dev Internal function to set reward vault
     * @param _rewardVault Address of the reward vault
     */
    function _setRewardVault(address _rewardVault) internal virtual {
        if (_rewardVault == address(0)) revert InvalidAddress();
        rewardVault = _rewardVault;

        emit RewardVaultSet(_rewardVault);
    }

    /**
     * @dev Update annual reward pool
     * @param _rewardPool The reward pool
     * @param _forYear Divider for the reward pool
     */
    function setRewardPool(uint256 _rewardPool, uint8 _forYear) external virtual onlyRole(OPERATOR_ROLE) {
        _setRewardPool(_rewardPool, _forYear);
    }

    /**
     * @dev Internal function to set reward pool
     * @param _rewardPool The reward pool in 1e18 precision
     * @param _forYear Divider for the reward pool
     */
    function _setRewardPool(uint256 _rewardPool, uint8 _forYear) internal virtual {
        if (_rewardPool == 0) revert InvalidRewardPool();
        if (_forYear == 0) revert InvalidForYear();
        
        // Update rewards before changing emission. It will update the rewardPerTokenStored and lastUpdateTime
        _updateReward();
        
        forYear = _forYear;
        annualRewardPool = (_rewardPool * PRECISION_FACTOR) / _forYear;
        emissionPerSecond = annualRewardPool / SECONDS_PER_YEAR;
        
        emit AnnualRewardPoolUpdated(annualRewardPool);
    }

    /**
     * @dev Set locked staking option
     * @param lockId The lock ID
     * @param duration The duration of the lock
     * @param multiplier The multiplier of the lock
     * @param active Whether the lock is active
     */
    function setLockedOption(uint256 lockId, uint256 duration, uint256 multiplier, bool active) external virtual onlyRole(OPERATOR_ROLE) {
        _setLockedOption(lockId, duration, multiplier, active);
    }

    /**
     * @dev Internal function to set locked option
     * @param lockId The lock ID
     * @param duration The duration of the lock
     * @param multiplier The multiplier of the lock
     * @param active Whether the lock is active
     */
    function _setLockedOption(uint256 lockId, uint256 duration, uint256 multiplier, bool active) internal virtual {        
        if (duration == 0) revert InvalidDuration();
        if (multiplier < 1e18) revert InvalidMultiplier();
        
        bool wasActive = lockedOptions[lockId].active;
        
        lockedOptions[lockId] = LockedOption({
            duration: duration,
            multiplier: multiplier,
            active: active
        });
        
        // Update active lock IDs array
        if (active && !wasActive) {
            activeLockIds.push(lockId);
        } 
        if (!active && wasActive) {
            _removeActiveLockId(lockId);
        }
        
        emit LockedOptionUpdated(lockId, duration, multiplier, active);
    }

    /**
     * @dev Withdraws foreign tokens to specified address
     * @param _token Address of the token to withdraw
     * @param _recipient Address to send the tokens to
     * @param _amount Amount of tokens to withdraw
     */
    function withdrawForeignToken(address _token, address _recipient, uint256 _amount) external virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_token == address(stakingToken) || _token == address(rewardToken)) revert InvalidTokenAddress();
        if (_recipient == address(0)) revert InvalidAddress();
        if (_amount == 0) revert InvalidAmount();

        if (_token == address(0)) {
            if (address(this).balance < _amount) revert InsufficientBalance();
            payable(_recipient).transfer(_amount);
        } else {
            uint256 contractBalance = uint256(IERC20Metadata(_token).balanceOf(address(this)));
            if (contractBalance < _amount) revert IERC20Errors.ERC20InsufficientBalance(address(this), contractBalance, _amount);
            IERC20Metadata(_token).safeTransfer(_recipient, _amount);
        }

        emit WithdrawForeignToken(_token, _recipient, _amount);
    }

    /**
     * @dev Update global reward info
     */
    function _updateReward() internal virtual {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = block.timestamp;
    }

    /**
     * @dev Update stake information
     * @param user The user address
     * @param stakeId The stake ID
     */
    function _updateStake(address user, uint256 stakeId) internal virtual {
        StakeInfo storage stakeInfo = stakes[user][stakeId];
        if (stakeInfo.stakeId == 0) revert StakeNotExists();
        
        stakeInfo.pendingRewards = earned(user, stakeId);
        stakeInfo.userRewardPerTokenPaid = rewardPerTokenStored;
    }

    /**
     * @dev Claim rewards
     * @param user The user address
     * @param rewardAmount The amount of rewards to claim in 1e18 precision
     */
    function _claimRewards(address user, uint256 rewardAmount) internal virtual {
        if (rewardToken.balanceOf(address(rewardVault)) < rewardAmount) revert BalanceNotEnough();
        if (rewardToken.allowance(rewardVault, address(this)) < rewardAmount) revert InsufficientAllowance();

        totalRewardsClaimed += rewardAmount;
        userTotalRewardsClaimed[user] += rewardAmount;
        IERC20Metadata(rewardToken).safeTransferFrom(rewardVault, user, rewardAmount);
    }

    /**
     * @dev Remove stake ID
     * @param user The user address
     * @param stakeId The stake ID
     */
    function _removeStakeId(address user, uint256 stakeId) internal virtual {
        uint256[] storage stakeIds = userStakeIds[user];
        for (uint256 i = 0; i < stakeIds.length; i++) {
            if (stakeIds[i] == stakeId) {
                stakeIds[i] = stakeIds[stakeIds.length - 1];
                stakeIds.pop();
                break;
            }
        }
    }

    /**
     * @dev Remove active lock ID
     * @param lockId The lock ID
     */
    function _removeActiveLockId(uint256 lockId) internal virtual {
        for (uint256 i = 0; i < activeLockIds.length; i++) {
            if (activeLockIds[i] == lockId) {
                activeLockIds[i] = activeLockIds[activeLockIds.length - 1];
                activeLockIds.pop();
                break;
            }
        }
    }
}