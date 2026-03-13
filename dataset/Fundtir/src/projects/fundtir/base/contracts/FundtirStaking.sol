// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title FNDRStaking
 * @dev A comprehensive staking contract for Fundtir tokens with USDT rewards and dividend distributions
 * 
 * Key Features:
 * - Multiple staking plans with different APY rates and durations
 * - Interest calculated in FNDR but paid in USDT based on dynamic price
 * - Dividend distributions in USDT with snapshot-based eligibility
 * - Governance checkpointing for DAO voting power
 * - Dynamic FNDR price management (no external oracle needed)
 * - Reentrancy protection and admin controls
 * 
 * Staking Plans:
 * - Plan 1: 8.97% APY for 90 days
 * - Plan 2: 14.35% APY for 365 days  
 * - Plan 3: 21.52% APY for 730 days
 * - Plan 4: 28.69% APY for 1460 days
 * 
 * @author Fundtir Team
 */
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract FNDRStaking is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============ TOKEN CONTRACTS ============
    
    /// @dev The Fundtir token contract (FNDR) - used for staking
    IERC20 public immutable fundtirToken;
    
    /// @dev The USDT token contract - used for rewards and dividend payments
    IERC20 public usdtToken;
    
    // ============ PRICING ============
    
    /// @dev Dynamic price of 1 FNDR token in USDT (with 6 decimals for USDT)
    /// @notice This price is used to convert FNDR interest to USDT rewards
    uint256 public fndrPriceInUSDT;

    // ============ STAKING ACCOUNTING ============
    
    /// @dev Total amount of FNDR tokens currently staked across all users
    uint256 public totalStakedAmount;

    // ============ STAKING PLANS ============
    
    /// @dev APY rates for each staking plan (in basis points, 10000 = 100%)
    uint256 public PLAN_1_APY = 897;  // 8.97%
    uint256 public PLAN_2_APY = 1435; // 14.35%
    uint256 public PLAN_3_APY = 2152; // 21.52%
    uint256 public PLAN_4_APY = 2869; // 28.69%

    /// @dev Staking durations for each plan
    uint256 public PLAN_1_DAYS = 90 days;   // 3 months
    uint256 public PLAN_2_DAYS = 365 days;  // 1 year
    uint256 public PLAN_3_DAYS = 730 days;  // 2 years
    uint256 public PLAN_4_DAYS = 1460 days; // 4 years

    // ============ DIVIDEND ELIGIBILITY ============
    
    /// @dev Minimum staking duration required to be eligible for dividend distributions
    /// @notice Users must stake for at least 60 days before a distribution to be eligible
    uint256 public constant MIN_DIVIDEND_LOCK = 60 days;

    // ============ DATA STRUCTURES ============
    
    /**
     * @dev Structure representing a single stake
     * @param amount Amount of FNDR tokens staked
     * @param startTime Timestamp when the stake was created
     * @param duration Duration of the stake in seconds
     * @param apy APY rate for this stake (in basis points)
     * @param withdrawn Whether this stake has been withdrawn
     */
    struct Stake {
        uint256 amount;      // Amount of FNDR tokens staked
        uint256 startTime;   // Stake creation timestamp
        uint256 duration;    // Stake duration in seconds
        uint256 apy;         // APY rate in basis points
        bool withdrawn;      // Withdrawal status
    }

    // ============ STAKING STORAGE ============
    
    /// @dev Mapping from user address to their array of stakes
    mapping(address => Stake[]) public stakes;
    
    /// @dev Array of all addresses that have ever staked (for dividend calculations)
    address[] public stakeHolders;

    /// @dev Quick cache of current active staked amounts per user (non-withdrawn)
    mapping(address => uint256) private _currentStaked;

    // ============ GOVERNANCE CHECKPOINTS ============
    
    /**
     * @dev Structure for governance checkpointing (used by DAO)
     * @param fromBlock Block number when this checkpoint was created
     * @param stake Staked amount at this checkpoint
     */
    struct Checkpoint {
        uint32 fromBlock;    // Block number
        uint256 stake;       // Staked amount at this block
    }
    
    /// @dev Mapping from user address to their checkpoint history
    mapping(address => Checkpoint[]) private _checkpoints;

    // ============ DIVIDEND DISTRIBUTIONS ============
    
    /**
     * @dev Structure representing a dividend distribution
     * @param id Unique identifier for this distribution
     * @param timestamp When the distribution was created
     * @param snapshotBlock Block number for the snapshot
     * @param totalAmount Total USDT amount to be distributed
     * @param eligibleTotal Total staked amount eligible for this distribution
     * @param exists Whether this distribution exists
     */
    struct Distribution {
        uint256 id;              // Distribution ID
        uint256 timestamp;       // Creation timestamp
        uint256 snapshotBlock;   // Snapshot block number
        uint256 totalAmount;     // Total USDT amount to distribute
        uint256 eligibleTotal;   // Total eligible stake amount
        bool exists;             // Distribution existence flag
    }
    
    /// @dev Counter for generating unique distribution IDs
    uint256 public distributionCounter;
    
    /// @dev Mapping from distribution ID to distribution details
    mapping(uint256 => Distribution) public distributions;
    
    /// @dev Mapping to track which users have claimed from which distributions
    mapping(uint256 => mapping(address => bool)) public hasClaimed;

    // ============ EVENTS ============
    
    /// @dev Emitted when a user stakes FNDR tokens
    event Staked(address indexed user, uint256 amount, uint256 duration, uint256 apy);
    
    /// @dev Emitted when a user unstakes and receives principal + USDT interest
    event Unstaked(address indexed user, uint256 amount, uint256 usdtInterest);
    
    /// @dev Emitted when a governance checkpoint is updated
    event CheckpointUpdated(address indexed user, uint32 fromBlock, uint256 stake);
    
    /// @dev Emitted when the FNDR price in USDT is updated
    event FNDRPriceUpdated(uint256 newPrice);
    
    /// @dev Emitted when a new dividend distribution is started
    event DistributionStarted(uint256 indexed id, uint256 snapshotBlock, uint256 totalAmount, uint256 eligibleTotal);
    
    /// @dev Emitted when a user claims their dividend share
    event DividendClaimed(uint256 indexed id, address indexed user, uint256 amount);
    
    /// @dev Emitted when admin deposits tokens to the contract
    event AdminDeposit(address indexed admin, address token, uint256 amount);
    
    /// @dev Emitted when admin withdraws tokens from the contract
    event AdminWithdraw(address indexed admin, address token, uint256 amount);
    
    /// @dev Emitted when APY rates are updated
    event APYUpdated(uint256 p1, uint256 p2, uint256 p3, uint256 p4);
    
    /// @dev Emitted when staking plan durations are updated
    event PlanDaysUpdated(uint256 d1, uint256 d2, uint256 d3, uint256 d4);

    /**
     * @dev Constructor initializes the staking contract with token addresses and initial price
     * @param _multiSigOwner Address that will become the contract owner
     * @param _fundtirToken Address of the Fundtir token contract (FNDR)
     * @param _usdtToken Address of the USDT token contract
     * @param _initialFNDRPrice Initial price of 1 FNDR in USDT (with 6 decimals)
     * 
     * Requirements:
     * - All addresses must be valid (non-zero)
     * - Initial FNDR price must be greater than 0
     */
    constructor(address _multiSigOwner, address _fundtirToken, address _usdtToken, uint256 _initialFNDRPrice) Ownable(_multiSigOwner) {
        require(_multiSigOwner != address(0), "owner 0");
        require(_fundtirToken != address(0), "fundtirToken 0");
        require(_usdtToken != address(0), "usdtToken 0");
        require(_initialFNDRPrice > 0, "price must be > 0");
        fundtirToken = IERC20(_fundtirToken);
        usdtToken = IERC20(_usdtToken);
        fndrPriceInUSDT = _initialFNDRPrice; // Price in USDT (6 decimals)
    }

    // ============ STAKING FUNCTIONS ============
    
    /**
     * @dev Allows users to stake FNDR tokens for a specified plan
     * @param amount Amount of FNDR tokens to stake
     * @param plan Staking plan number (1-4)
     * 
     * Requirements:
     * - Amount must be greater than 0
     * - Plan must be valid (1-4)
     * - User must have sufficient FNDR balance and allowance
     * 
     * Process:
     * 1. Validates plan and gets APY/duration details
     * 2. Transfers FNDR tokens from user to contract
     * 3. Creates new stake record
     * 4. Updates total staked amount and user's current stake
     * 5. Writes governance checkpoint for DAO voting power
     */
    function stake(uint256 amount, uint256 plan) external nonReentrant {
        require(amount > 0, "Invalid amount");
        (uint256 apy, uint256 duration) = getPlanDetails(plan);

        // Transfer FNDR tokens from user to contract
        fundtirToken.safeTransferFrom(msg.sender, address(this), amount);

        // Create new stake record
        stakes[msg.sender].push(Stake({
            amount: amount,
            startTime: block.timestamp,
            duration: duration,
            apy: apy,
            withdrawn: false
        }));

        // Add to stake holders list if this is user's first stake
        if (stakes[msg.sender].length == 1) {
            stakeHolders.push(msg.sender);
        }

        // Update total staked amount
        totalStakedAmount += amount;

        // Update current staked and write checkpoint for DAO snapshots
        _currentStaked[msg.sender] += amount;
        _writeCheckpoint(msg.sender, _currentStaked[msg.sender]);

        emit Staked(msg.sender, amount, duration, apy);
    }

    /**
     * @dev Allows users to unstake their tokens and receive principal + USDT interest
     * @param stakeIndex Index of the stake to unstake in the user's stakes array
     * 
     * Requirements:
     * - Stake index must be valid
     * - Stake must not already be withdrawn
     * - Stake must have reached its lock period
     * - Contract must have sufficient USDT for interest payment
     * 
     * Process:
     * 1. Validates stake and lock period
     * 2. Calculates interest based on actual staking duration
     * 3. Converts FNDR interest to USDT using current price
     * 4. Transfers FNDR principal back to user
     * 5. Transfers USDT interest to user
     * 6. Updates accounting and governance checkpoints
     */
    function unstake(uint256 stakeIndex) external nonReentrant {
        require(stakeIndex < stakes[msg.sender].length, "Invalid index");
        Stake storage s = stakes[msg.sender][stakeIndex];
        require(!s.withdrawn, "Already withdrawn");
        require(block.timestamp >= s.startTime + s.duration, "Stake locked");

        // Calculate interest based on actual staking duration
        uint256 actualDuration = block.timestamp - s.startTime;
        uint256 interest = calculateInterest(s.amount, s.apy, actualDuration);
        uint256 usdtInterest = convertFNDRToUSDT(interest);

        // Ensure contract has enough USDT for interest rewards
        require(usdtToken.balanceOf(address(this)) >= usdtInterest, "Insufficient USDT balance for interest");

        s.withdrawn = true;

        // Transfer principal in FNDR tokens
        fundtirToken.safeTransfer(msg.sender, s.amount);
        
        // Transfer interest in USDT tokens
        usdtToken.safeTransfer(msg.sender, usdtInterest);

        // Update total staked amount
        totalStakedAmount -= s.amount;

        // Update current staked and checkpoint
        require(_currentStaked[msg.sender] >= s.amount, "underflow");
        _currentStaked[msg.sender] -= s.amount;
        _writeCheckpoint(msg.sender, _currentStaked[msg.sender]);

        emit Unstaked(msg.sender, s.amount, usdtInterest);
    }

    // ============ APY AND PRICING HELPERS ============
    
    /**
     * @dev Returns APY and duration details for a given staking plan
     * @param plan Plan number (1-4)
     * @return apy APY rate in basis points (10000 = 100%)
     * @return duration Duration in seconds
     */
    function getPlanDetails(uint256 plan) public view returns (uint256 apy, uint256 duration) {
        if (plan == 1) return (PLAN_1_APY, PLAN_1_DAYS);
        if (plan == 2) return (PLAN_2_APY, PLAN_2_DAYS);
        if (plan == 3) return (PLAN_3_APY, PLAN_3_DAYS);
        if (plan == 4) return (PLAN_4_APY, PLAN_4_DAYS);
        revert("Invalid plan");
    }

    /**
     * @dev Calculates interest based on amount, APY, and duration
     * @param amount Principal amount in FNDR tokens
     * @param _apy APY rate in basis points (10000 = 100%)
     * @param duration Staking duration in seconds
     * @return Interest amount in FNDR tokens
     * 
     * Formula: (amount * apy * duration) / (365 days * 10000)
     */
    function calculateInterest(uint256 amount, uint256 _apy, uint256 duration) public pure returns (uint256) {
        // Linear interest calculation for duration (APY is in basis points)
        return (amount * _apy * duration) / (365 days * 10000);
    }

    /**
     * @dev Converts FNDR amount to USDT based on current price
     * @param fndrAmount Amount of FNDR tokens (with 18 decimals)
     * @return USDT amount (with 6 decimals)
     * 
     * Conversion: (fndrAmount * fndrPriceInUSDT) / 1e18
     * - FNDR has 18 decimals
     * - USDT has 6 decimals
     * - fndrPriceInUSDT is already in 6 decimals
     */
    function convertFNDRToUSDT(uint256 fndrAmount) public view returns (uint256) {
        require(fndrPriceInUSDT > 0, "FNDR price not set");
        
        uint256 usdtAmount = (fndrAmount * fndrPriceInUSDT) / 1e18;
        return usdtAmount;
    }

    // ============ GOVERNANCE CHECKPOINTS (FOR DAO) ============
    
    /**
     * @dev Internal function to write a governance checkpoint for a user
     * @param user Address of the user
     * @param newStake New staked amount at this checkpoint
     * 
     * This function is used to track voting power changes for DAO governance.
     * Checkpoints are created when users stake or unstake tokens.
     */
    function _writeCheckpoint(address user, uint256 newStake) internal {
        Checkpoint[] storage ckpts = _checkpoints[user];
        uint32 blk = uint32(block.number);
        if (ckpts.length == 0) {
            ckpts.push(Checkpoint({fromBlock: blk, stake: newStake}));
        } else {
            Checkpoint storage last = ckpts[ckpts.length - 1];
            if (last.fromBlock == blk) {
                last.stake = newStake;
            } else {
                ckpts.push(Checkpoint({fromBlock: blk, stake: newStake}));
            }
        }
        emit CheckpointUpdated(user, blk, newStake);
    }

    /**
     * @dev Returns the current staked balance for a user (DAO fallback)
     * @param user Address of the user
     * @return Current staked amount
     */
    function stakedBalance(address user) external view returns (uint256) {
        return _currentStaked[user];
    }

    /**
     * @dev Returns the staked balance at a specific block number (for DAO governance)
     * @param user Address of the user
     * @param blockNumber Block number to query
     * @return Staked amount at the specified block
     * 
     * Uses binary search for efficient lookup in checkpoint history.
     * This is used by DAO contracts to determine voting power at specific blocks.
     */
    function stakedAtBlock(address user, uint256 blockNumber) public view returns (uint256) {
        require(blockNumber <= block.number, "Future block");
        Checkpoint[] memory ckpts = _checkpoints[user];
        uint256 n = ckpts.length;
        if (n == 0) return 0;
        if (uint256(ckpts[0].fromBlock) > blockNumber) return 0;
        if (uint256(ckpts[n - 1].fromBlock) <= blockNumber) return ckpts[n - 1].stake;

        uint256 low = 0;
        uint256 high = n - 1;
        while (low < high) {
            uint256 mid = (low + high + 1) / 2;
            if (uint256(ckpts[mid].fromBlock) <= blockNumber) {
                low = mid;
            } else {
                high = mid - 1;
            }
        }
        return ckpts[low].stake;
    }

    /**
     * @dev Returns the number of checkpoints for a user
     * @param user Address of the user
     * @return Number of checkpoints
     */
    function numCheckpoints(address user) external view returns (uint256) {
        return _checkpoints[user].length;
    }

    /**
     * @dev Returns a specific checkpoint for a user
     * @param user Address of the user
     * @param index Index of the checkpoint
     * @return fromBlock Block number of the checkpoint
     * @return _stake Staked amount at this checkpoint
     */
    function getCheckpoint(address user, uint256 index) external view returns (uint32 fromBlock, uint256 _stake) {
        Checkpoint memory cp = _checkpoints[user][index];
        return (cp.fromBlock, cp.stake);
    }

    // ============ DIVIDEND DISTRIBUTIONS ============
    
    /**
     * @dev Updates the FNDR token price in USDT
     * @param _newPrice New price of 1 FNDR in USDT (with 6 decimals)
     * 
     * Requirements:
     * - Caller must be the contract owner
     * - New price must be greater than 0
     * 
     * @notice This price is used to convert FNDR interest to USDT rewards
     */
    function updateFNDRPrice(uint256 _newPrice) external onlyOwner {
        require(_newPrice > 0, "Price must be > 0");
        fndrPriceInUSDT = _newPrice;
        emit FNDRPriceUpdated(_newPrice);
    }

    /**
     * @dev Starts a new dividend distribution with snapshot-based eligibility
     * @param totalAmount Total USDT amount to be distributed
     * 
     * Requirements:
     * - Caller must be the contract owner
     * - Total amount must be greater than 0
     * - Contract must have sufficient USDT balance (use adminDeposit() first)
     * - There must be eligible stakers
     * 
     * Process:
     * 1. Takes a snapshot of current block and eligible stakers
     * 2. Calculates total eligible stake amount
     * 3. Creates distribution record
     * 4. Users can then claim their proportional share
     * 
     * @notice USDT tokens should be deposited to contract before calling this function
     * @notice Only users staked for >= MIN_DIVIDEND_LOCK are eligible
     */
    function startDistribution(uint256 totalAmount) external onlyOwner nonReentrant {
        require(totalAmount > 0, "Zero amount");
        require(usdtToken.balanceOf(address(this)) >= totalAmount, "Insufficient USDT funds - use adminDeposit() first");

        // Compute eligible total at current time
        uint256 eligibleTotal = _computeEligibleTotalAt(block.timestamp);
        require(eligibleTotal > 0, "No eligible stakers");

        distributionCounter += 1;
        uint256 snapBlock = block.number;

        distributions[distributionCounter] = Distribution({
            id: distributionCounter,
            timestamp: block.timestamp,
            snapshotBlock: snapBlock,
            totalAmount: totalAmount,
            eligibleTotal: eligibleTotal,
            exists: true
        });

        emit DistributionStarted(distributionCounter, snapBlock, totalAmount, eligibleTotal);
    }

    /**
     * @dev Allows users to claim their share from a dividend distribution
     * @param distributionId ID of the distribution to claim from
     * 
     * Requirements:
     * - Distribution must exist
     * - User must not have already claimed from this distribution
     * - User must be eligible for this distribution (staked >= MIN_DIVIDEND_LOCK)
     * - User must have had stake at the snapshot block
     * - User's share must be greater than 0
     * 
     * Process:
     * 1. Validates distribution and user eligibility
     * 2. Calculates user's proportional share based on stake at snapshot
     * 3. Transfers USDT dividend to user
     * 4. Marks distribution as claimed for this user
     */
    function claimFromDistribution(uint256 distributionId) external nonReentrant {
        Distribution memory d = distributions[distributionId];
        require(d.exists, "No such distribution");
        require(!hasClaimed[distributionId][msg.sender], "Already claimed");

        // Eligibility: user must have at least one active stake whose startTime + MIN_DIVIDEND_LOCK <= distribution timestamp
        require(_eligibleAt(msg.sender, d.timestamp), "Not eligible for this distribution");

        // Determine stake at snapshot
        uint256 userStake = stakedAtBlock(msg.sender, d.snapshotBlock);
        require(userStake > 0, "No stake at snapshot");

        uint256 share = (userStake * d.totalAmount) / d.eligibleTotal;
        require(share > 0, "Zero share");

        hasClaimed[distributionId][msg.sender] = true;

        // Always pay dividends in USDT
        usdtToken.safeTransfer(msg.sender, share);

        emit DividendClaimed(distributionId, msg.sender, share);
    }

    /**
     * @dev Internal function to check if a user is eligible for dividend at a specific timestamp
     * @param user Address of the user
     * @param atTimestamp Timestamp to check eligibility at
     * @return True if user is eligible (has stake >= MIN_DIVIDEND_LOCK)
     */
    function _eligibleAt(address user, uint256 atTimestamp) internal view returns (bool) {
        Stake[] memory arr = stakes[user];
        for (uint256 i = 0; i < arr.length; i++) {
            if (arr[i].withdrawn) continue;
            if (arr[i].startTime + MIN_DIVIDEND_LOCK <= atTimestamp) return true;
        }
        return false;
    }

    /**
     * @dev Internal function to compute total eligible stake amount at a specific timestamp
     * @param atTimestamp Timestamp to compute eligible total at
     * @return Total amount of eligible stakes
     */
    function _computeEligibleTotalAt(uint256 atTimestamp) internal view returns (uint256) {
        uint256 sum = 0;
        for (uint256 i = 0; i < stakeHolders.length; i++) {
            address u = stakeHolders[i];
            if (_eligibleAt(u, atTimestamp)) {
                sum += _currentStaked[u];
            }
        }
        return sum;
    }

    // ============ ADMIN FUNCTIONS ============
    
    /**
     * @dev Allows admin to deposit tokens to the contract (used for dividend distributions)
     * @param tokenAddr Address of the token to deposit
     * @param amount Amount of tokens to deposit
     * 
     * Requirements:
     * - Caller must be the contract owner
     * - Amount must be greater than 0
     * - Admin must have sufficient balance and allowance
     */
    function adminDeposit(address tokenAddr, uint256 amount) external onlyOwner nonReentrant {
        require(amount > 0, "Zero amount");
        IERC20(tokenAddr).safeTransferFrom(msg.sender, address(this), amount);
        emit AdminDeposit(msg.sender, tokenAddr, amount);
    }

    /**
     * @dev Allows admin to withdraw tokens from the contract
     * @param tokenAddr Address of the token to withdraw
     * @param amount Amount of tokens to withdraw
     * @param to Address to send tokens to
     * 
     * Requirements:
     * - Caller must be the contract owner
     * - Recipient address must be valid
     * - If withdrawing staking token, must not withdraw more than available (total - staked)
     */
    function adminWithdraw(address tokenAddr, uint256 amount, address to) external onlyOwner nonReentrant {
        require(to != address(0), "zero to");
        IERC20 token = IERC20(tokenAddr);
        // If withdrawing staking token, ensure we don't withdraw more than available
        if (tokenAddr == address(fundtirToken)) {
            uint256 balance = token.balanceOf(address(this));
            uint256 available = balance - totalStakedAmount; // Available = Total - Staked
            require(available >= amount, "Not enough available fundtirToken");
        }
        token.safeTransfer(to, amount);
        emit AdminWithdraw(msg.sender, tokenAddr, amount);
    }

    /**
     * @dev Updates APY rates for all staking plans
     * @param _p1 New APY for plan 1 (in basis points)
     * @param _p2 New APY for plan 2 (in basis points)
     * @param _p3 New APY for plan 3 (in basis points)
     * @param _p4 New APY for plan 4 (in basis points)
     * 
     * Requirements:
     * - Caller must be the contract owner
     * - All APY values must be greater than 0
     * - All APY values must be <= 10000 (100%)
     */
    function updateAPY(uint256 _p1, uint256 _p2, uint256 _p3, uint256 _p4) external onlyOwner {
        require(_p1 > 0 && _p2 > 0 && _p3 > 0 && _p4 > 0, "APY >0");
        require(_p1 <= 10000 && _p2 <= 10000 && _p3 <= 10000 && _p4 <= 10000, "APY <=10000");
        PLAN_1_APY = _p1;
        PLAN_2_APY = _p2;
        PLAN_3_APY = _p3;
        PLAN_4_APY = _p4;
        emit APYUpdated(_p1, _p2, _p3, _p4);
    }

    /**
     * @dev Updates staking durations for all plans
     * @param d1 New duration for plan 1 (in seconds)
     * @param d2 New duration for plan 2 (in seconds)
     * @param d3 New duration for plan 3 (in seconds)
     * @param d4 New duration for plan 4 (in seconds)
     * 
     * Requirements:
     * - Caller must be the contract owner
     * - All durations must be greater than 0
     */
    function updatePlanDays(uint256 d1, uint256 d2, uint256 d3, uint256 d4) external onlyOwner {
        require(d1 > 0 && d2 > 0 && d3 > 0 && d4 > 0, "days>0");
        PLAN_1_DAYS = d1;
        PLAN_2_DAYS = d2;
        PLAN_3_DAYS = d3;
        PLAN_4_DAYS = d4;
        emit PlanDaysUpdated(d1, d2, d3, d4);
    }

    // ============ VIEW FUNCTIONS ============
    
    /**
     * @dev Returns all stakes for a specific user
     * @param user Address of the user
     * @return Array of all stakes for the user
     */
    function getUserStakes(address user) external view returns (Stake[] memory) {
        return stakes[user];
    }

    /**
     * @dev Returns the contract's balance of a specific token
     * @param tokenAddr Address of the token contract
     * @return Token balance of the contract
     */
    function getContractBal(address tokenAddr) external view returns (uint256) {
        require(tokenAddr != address(0), "zero token");
        return IERC20(tokenAddr).balanceOf(address(this));
    }

    /**
     * @dev Returns the current staked amount for a user
     * @param user Address of the user
     * @return Current staked amount (active, non-withdrawn)
     */
    function currentStakedOf(address user) external view returns (uint256) {
        return _currentStaked[user];
    }

    /**
     * @dev Returns the total number of stake holders
     * @return Number of addresses that have ever staked
     */
    function stakeHoldersCount() external view returns (uint256) {
        return stakeHolders.length;
    }

    // ============ USDT REWARDS VIEW FUNCTIONS ============
    
    /**
     * @dev Returns the current FNDR price in USDT
     * @return price Current FNDR price in USDT (with 6 decimals)
     */
    function getFNDRPrice() external view returns (uint256 price) {
        return fndrPriceInUSDT;
    }

    /**
     * @dev Previews the USDT interest a user would earn for a given stake
     * @param fndrAmount Amount of FNDR tokens to stake
     * @param plan Staking plan number (1-4)
     * @return usdtInterest USDT interest amount that would be earned
     */
    function previewUSDTInterest(uint256 fndrAmount, uint256 plan) external view returns (uint256 usdtInterest) {
        (uint256 apy, uint256 duration) = getPlanDetails(plan);
        uint256 fndrInterest = calculateInterest(fndrAmount, apy, duration);
        return convertFNDRToUSDT(fndrInterest);
    }

    /**
     * @dev Returns the USDT token contract address
     * @return Address of the USDT token contract
     */
    function getUSDTTokenAddress() external view returns (address) {
        return address(usdtToken);
    }

    /**
     * @dev Returns the available FNDR balance (total - staked)
     * @return Available FNDR tokens that can be withdrawn by admin
     */
    function getAvailableFNDRBalance() external view returns (uint256) {
        uint256 balance = fundtirToken.balanceOf(address(this));
        return balance - totalStakedAmount;
    }
}
