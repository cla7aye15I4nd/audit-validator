// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

import {IFivePillarsToken} from "./interfaces/IFivePillarsToken.sol";
import {IPancakeRouter01} from "./interfaces/IPancakeRouter01.sol";

/**
 * @title InvestmentManager
 * @notice Manages investments, rewards, and pool participation for the Five Pillars ecosystem.
 * Implements a comprehensive reward system that includes:
 * - Daily rewards based on investment amount
 * - Referral rewards for direct and indirect referrals
 * - Pool rewards based on investment tiers and criteria
 * @dev The contract uses a multi-tier reward system with automatic fee collection
 * and redistribution mechanisms
 */
contract InvestmentManager is Ownable2Step {
    error ZeroAddress();
    error InvalidFee();
    error InvalidPoolId();
    error InvalidArrayLengths();
    error InvalidStartTime();
    error SmallDepositOrClaimAmount();
    error DepositNotYetAvailable();
    error SetPoolCriteriaNotYetAvailable();
    error RefererAlreadySetted();
    error HalfRequirementViolated();
    error PoolCriteriaUpdateNotEnded();
    error SequencePoolCriteriaBroken();
    error InvalidReferer();
    error SendEtherFailed(address to);
    error InvestorAlreadyWhitelisted();
    error InvestorAlreadyNotWhitelisted();
    error RefererCirculationDetected();

    /// @notice Unix timestamp when the contract starts accepting investments
    uint256 public startTimestamp;

    /// @notice Duration of each reward round in seconds (24 hours)
    uint256 public constant roundDuration = 60 * 60 * 24;

    /// @notice Minimum time between deposits for an investor in seconds (4 hours)
    uint256 public constant depositDelay = 60 * 60 * 4;

    /// @notice Minimum time between pool criteria updates in seconds (30 hours)
    uint256 public constant poolCriteriaUpdateDelay = 60 * 60 * 30;

    /// @notice Timestamp of the last pool criteria update
    uint256 public lastUpdatePoolCriteriaTimestamp;

    /// @notice Timestamp of the last pool reward update
    uint256 public lastUpdatePoolRewardTimestamp;

    /// @notice Total amount of tokens deposited across all investors
    uint256 public totalDepositAmount;

    /// @notice Deposit fee in basis points (1 basis point = 0.0001%)
    uint256 public depositFeeInBp;

    /// @notice Claim fee in basis points (1 basis point = 0.0001%)
    uint256 public claimFeeInBp;

    /// @notice Min swap price for send fees
    /// @dev In 18 decimals. ETH/5PT
    uint256 public minSwapPrice = 0;

    /// @notice Maximum allowed fee in basis points (10%)
    uint256 public constant MAX_FEE = 1000000;

    /// @notice Basis points denominator (10,000,000 = 100%)
    uint256 public constant BASIS_POINTS = 10000000;
    
    /// @notice Address of the primary treasury for fee collection
    address public treasury;

    /// @notice Address of the secondary treasury for fee collection
    address public treasury2;

    /// @notice Address of the PancakeSwap router for fee swaps
    address public dexRouter;

    /// @notice Interface for the Five Pillars token contract
    IFivePillarsToken public fivePillarsToken;

    /// @notice Array of all investor addresses
    address[] private _investors;

    /// @notice Flag indicating if pool criteria update is in progress
    bool public isUpdateCriteriaActive;

    /// @notice Array of pool IDs being updated in the current criteria update
    uint8[] private _updateCriteriaPoolIds;

    /// @notice Current investor index in the criteria update process
    uint256 private _updateCriteriaCurInvestorId;

    /// @notice Mapping of investor address and pool ID to their participation status
    mapping(address => mapping(uint8 => bool)) public isInvestorInPool;

    /// @notice Mapping of investor address to their investment information
    mapping(address => InvestorInfo) public accountToInvestorInfo;

    /// @notice Mapping of investor address and poolId to their whitelist status
    mapping(address => mapping(uint8 => bool)) public isWhitelisted;

    /// @notice The number of investors on a white list who does not have a deposit
    uint256 public onlyWhitelistedInvestorsCount;

    /// @notice Array of pool information for all 9 pools
    PoolInfo[9] public pools;

    /**
     * @notice Structure defining the criteria for pool participation
     * @param personalInvestRequired Minimum personal investment required
     * @param totalDirectInvestRequired Minimum total investment from direct referrals
     * @param directRefsRequired Minimum number of direct referrals required
     */
    struct PoolCriteria {
        uint128 personalInvestRequired;
        uint128 totalDirectInvestRequired;
        uint8 directRefsRequired;
    }

    /**
     * @notice Structure containing information about each investment pool
     * @param isActive Whether the pool is currently active
     * @param curReward Current round's reward for the pool
     * @param lastReward Last round's reward
     * @param participantsCount Number of participants in the pool
     * @param rewardPerInvestorStored Accumulated rewards per investor
     * @param personalInvestRequired Minimum personal investment required
     * @param totalDirectInvestRequired Minimum total investment from direct referrals
     * @param directRefsRequired Minimum number of direct referrals required
     * @param share Pool's share of rewards in basis points
     */
    struct PoolInfo {
        bool isActive;
        uint256 curReward;
        uint256 lastReward;
        uint256 participantsCount;
        uint256 rewardPerInvestorStored;
        uint128 personalInvestRequired;
        uint128 totalDirectInvestRequired;
        uint8 directRefsRequired;
        uint16 share;
    }

    /**
     * @notice Structure containing information about each investor
     * @param totalDeposit Total amount deposited by the investor
     * @param directRefsCount Number of direct referrals
     * @param downlineRefsCount Number of indirect referrals
     * @param directRefsDeposit Total investment from direct referrals
     * @param downlineRefsDeposit Total investment from indirect referrals
     * @param referer Address of the investor's referer
     * @param lastDailyReward Last daily reward amount
     * @param lastRefReward Last referral reward amount
     * @param accumulatedReward Total accumulated unclaimed rewards
     * @param poolRewardPerInvestorPaid Array of rewards per investor for each pool
     * @param lastClaimTimestamp Timestamp of last reward claim
     * @param lastDepositTimestamp Timestamp of last deposit
     * @param updateRefRewardTimestamp Timestamp of last referral reward update
     */
    struct InvestorInfo {
        uint256 totalDeposit;
        uint128 directRefsCount;
        uint128 downlineRefsCount;
        uint256 directRefsDeposit;
        uint256 downlineRefsDeposit;
        address referer;
        uint256 lastDailyReward;
        uint256 lastRefReward;
        uint256 accumulatedReward;
        uint256[9] poolRewardPerInvestorPaid;
        uint32 lastClaimTimestamp;
        uint32 lastDepositTimestamp;
        uint32 updateRefRewardTimestamp;
    }

    modifier NotInPoolCriteriaUpdate {
        if (isUpdateCriteriaActive) revert PoolCriteriaUpdateNotEnded();
        _;
    }

    /**
     * @notice Emitted when a user makes a deposit
     * @param investor Address of the investor making the deposit
     * @param referer Address of the referer who brought the investor
     * @param amount Amount of tokens deposited
     */
    event Deposit(address investor, address referer, uint256 amount);

    /**
     * @notice Emitted when a user claims their accumulated rewards
     * @param investor Address of the investor claiming rewards
     * @param amount Amount of tokens claimed as rewards
     */
    event ClaimReward(address investor, uint256 amount);

    /**
     * @notice Emitted when rewards are redistributed to the ecosystem
     * @param investor Address of the investor whose rewards are being redistributed
     * @param amount Amount of tokens being redistributed
     */
    event Redistribute(address investor, uint256 amount);

    /**
     * @notice Emitted when the deposit fee is updated by the owner
     * @param newDepositFeeInBp New deposit fee in basis points (1 basis point = 0.0001%)
     */
    event DepositFeeUpdated(uint256 newDepositFeeInBp);

    /**
     * @notice Emitted when the claim fee is updated by the owner
     * @param newClaimFeeInBp New claim fee in basis points (1 basis point = 0.0001%)
     */
    event ClaimFeeUpdated(uint256 newClaimFeeInBp);

    /**
     * @notice Emitted when the min swap price is updated by the owner
     * @param newMinSwapPrice New min swap price
     */
    event MinSwapPriceUpdated(uint256 newMinSwapPrice);

    /**
     * @notice Emitted when pool criteria are updated by the owner
     * @param poolIds Array of pool IDs that were updated with new criteria
     */
    event PoolsCriteriaUpdated(uint8[] poolIds);

    /**
     * @notice Emitted when the automatic fee swap to ETH fails
     * @param accumulatedFees Amount of tokens that failed to be swapped
     */
    event SwapFeesFailed(uint256 accumulatedFees);

    /**
     * @notice Emitted when an investor's whitelist status is updated
     * @param account Address of the investor being whitelisted/unwhitelisted
     * @param poolId Pool ID for which the whitelist is updated
     * @param add True if being added to whitelist, false if being removed
     */
    event WhitelistUpdated(address account, uint256 poolId, bool add);

    /**
     * @notice Initializes the InvestmentManager contract with required parameters
     * @param owner_ Address that will have owner privileges
     * @param startTime_ Unix timestamp when the contract will start accepting investments
     * @param treasury_ Address of the primary treasury for fee collection
     * @param treasury2_ Address of the secondary treasury for fee collection
     * @param dexRouter_ Address of the PancakeSwap router for fee swaps
     * @param fivePillarsToken_ Address of the Five Pillars token contract
     * @dev Initializes pools with default criteria and sets up initial contract state
     */
    constructor(
        address owner_,
        uint32 startTime_,
        address treasury_,
        address treasury2_,
        address dexRouter_,
        address fivePillarsToken_
    ) Ownable(owner_) {
        if (startTime_ < block.timestamp) revert InvalidStartTime();
        if (treasury_ == address(0)) revert ZeroAddress();
        if (treasury2_ == address(0)) revert ZeroAddress();
        if (dexRouter_ == address(0)) revert ZeroAddress();
        if (fivePillarsToken_ == address(0)) revert ZeroAddress();

        treasury = treasury_;
        treasury2 = treasury2_;
        dexRouter = dexRouter_;
        fivePillarsToken = IFivePillarsToken(fivePillarsToken_);

        startTimestamp = startTime_;
        lastUpdatePoolRewardTimestamp = startTime_;

        depositFeeInBp = MAX_FEE;
        claimFeeInBp = MAX_FEE;

        pools[0] = PoolInfo(
            false, 0, 0, 0, 0, 550 * 10 ** 21, 550 * 10 ** 21, 1, 1750
        );
        pools[1] = PoolInfo(
            false, 0, 0, 0, 0, 145 * 10 ** 22, 145 * 10 ** 22, 3, 1750
        );
        pools[2] = PoolInfo(
            false, 0, 0, 0, 0, 3 * 10 ** 24, 6 * 10 ** 24, 5, 1750
        );
        pools[3] = PoolInfo(
            false, 0, 0, 0, 0, 55 * 10 ** 23, 11 * 10 ** 24, 10, 1750
        );
        pools[4] = PoolInfo(
            false, 0, 0, 0, 0, 1425 * 10 ** 22, 285 * 10 ** 23, 15, 1750
        );
        pools[5] = PoolInfo(
            false, 0, 0, 0, 0, 285 * 10 ** 23, 855 * 10 ** 23, 20, 1000
        );
        pools[6] = PoolInfo(
            false, 0, 0, 0, 0, 57 * 10 ** 24, 171 * 10 ** 24, 20, 1000
        );
        pools[7] = PoolInfo(
            false, 0, 0, 0, 0, 0, 0, 0, 2000
        );
        pools[8] = PoolInfo(
            false, 0, 0, 0, 0, 0, 0, 0, 2000
        );
    }

    receive() external payable {}

    /**
     * @notice Gets the total accumulated rewards for the caller
     * @param investorAddress Investor"s address
     * @return Total accumulated rewards including:
     * - Daily rewards
     * - Referral rewards
     * - Pool rewards
     */
    function getAccumulatedRewards(address investorAddress) external view returns(uint256) {
        InvestorInfo memory investor = accountToInvestorInfo[investorAddress];
        (uint256 totalDailyReward,) = _calcInvestorDailyReward(investor);
        (uint256 totalRefReward,) = _calcInvestorRefRewards(investor, investorAddress);
        (uint256 totalPoolReward,) = _calcInvestorPoolRewards(investor, investorAddress);

        return investor.accumulatedReward +
            totalDailyReward +
            totalRefReward +
            totalPoolReward;
    }

    /**
     * @notice Gets the rewards from the last round for the caller
     * @param investorAddress Investor"s address
     * @return dailyReward Daily rewards from last round
     * @return refReward Referral rewards from last round
     * @return poolsReward Pool rewards from last round
     */
    function getLastRoundRewards(address investorAddress) external view returns(
        uint256 dailyReward,
        uint256 refReward,
        uint256 poolsReward
    ) {
        InvestorInfo memory investor = accountToInvestorInfo[investorAddress];
        uint32 dailyRewardLastUpdate = investor.lastDepositTimestamp > investor.lastClaimTimestamp ? investor.lastDepositTimestamp : investor.lastClaimTimestamp;
        uint256 endedRoundsFromLastDailyRewardUpdate = _calcCountOfRoundsSinceLastUpdate(dailyRewardLastUpdate);
        uint256 endedRoundsFromLastRefRewardUpdate = _calcCountOfRoundsSinceLastUpdate(investor.updateRefRewardTimestamp);
        uint256 endedRoundsFromLastPoolsRewardUpdate = _calcCountOfRoundsSinceLastUpdate(uint32(lastUpdatePoolRewardTimestamp));
        
        if (endedRoundsFromLastDailyRewardUpdate > 0) {
            (, dailyReward) = _calcInvestorDailyReward(investor);
        } else {
            dailyReward = investor.lastDailyReward;
        }

        if (endedRoundsFromLastRefRewardUpdate > 0) {
            (, refReward) = _calcInvestorRefRewards(investor, investorAddress);
        } else {
            refReward = investor.lastRefReward;
        }

        if (endedRoundsFromLastPoolsRewardUpdate > 0) {
            (, poolsReward) = _calcInvestorPoolRewards(investor, investorAddress);
        } else {
            for (uint8 i = 0; i < pools.length; i++) {
                if (!isInvestorInPool[investorAddress][i]) {
                    continue;
                }

                poolsReward += pools[i].lastReward;
            }
        }
    }

    function getInvestorPoolRewardPerTokenPaid(
        address investor,
        uint8 poolId
    ) external view returns(uint256) {
        return accountToInvestorInfo[investor].poolRewardPerInvestorPaid[poolId];
    }

    /**
     * @notice Gets the total number of investors in the system
     * @return Total count of unique investors who have made at least one deposit
     */
    function getTotalInvestorsCount() external view returns(uint256) {
        return _investors.length + onlyWhitelistedInvestorsCount;
    }

    /**
     * @notice Updates the deposit fee percentage
     * @param newDepositFeeInBp New deposit fee in basis points (1 basis point = 0.0001%)
     * @dev Only callable by owner
     * @dev Fee cannot exceed MAX_FEE (10%)
     */
    function setDepositFee(uint256 newDepositFeeInBp) external onlyOwner {
        if (newDepositFeeInBp > MAX_FEE) revert InvalidFee();

        depositFeeInBp = newDepositFeeInBp;

        emit DepositFeeUpdated(newDepositFeeInBp);
    }

    /**
     * @notice Updates the claim fee percentage
     * @param newClaimFeeInBp New claim fee in basis points (1 basis point = 0.0001%)
     * @dev Only callable by owner
     * @dev Fee cannot exceed MAX_FEE (10%)
     */
    function setClaimFee(uint256 newClaimFeeInBp) external onlyOwner {
        if (newClaimFeeInBp > MAX_FEE) revert InvalidFee();

        claimFeeInBp = newClaimFeeInBp;

        emit ClaimFeeUpdated(newClaimFeeInBp);
    }

    /**
     * @notice Updates the swap slippage for send fees
     * @param newMinSwapPrice New min swap price
     * @dev Only callable by owner
     */
    function setMinSwapPrice(uint256 newMinSwapPrice) external onlyOwner {
        minSwapPrice = newMinSwapPrice;

        emit MinSwapPriceUpdated(newMinSwapPrice);
    }

    /**
     * @notice Updates whitelist status in pools 8 and 9 for an investor
     * @param investor Address of the investor to update
     * @param poolId Pool ID for which the whitelist is updated
     * @param add True to add to whitelist, false to remove
     * @dev Only callable by owner
     * @dev Automatically updates pool participation for whitelisted investors
     */
    function setWhitelist(address investor, uint8 poolId, bool add) external onlyOwner {
        if (poolId != 7 && poolId != 8) revert InvalidPoolId();
        _updatePoolRewards();
        if (add) {
            if (isWhitelisted[investor][poolId]) revert InvestorAlreadyWhitelisted();

            if (
                accountToInvestorInfo[investor].totalDeposit == 0 &&
                !isWhitelisted[investor][poolId == 7 ? 8 : 7]
            ) onlyWhitelistedInvestorsCount += 1;

            isInvestorInPool[investor][poolId] = true;
            pools[poolId].participantsCount += 1;
            accountToInvestorInfo[investor].poolRewardPerInvestorPaid[poolId] = pools[poolId].rewardPerInvestorStored;

            if (!pools[poolId].isActive) {
                pools[poolId].isActive = true;
            }
        } else {
            if (!isWhitelisted[investor][poolId]) revert InvestorAlreadyNotWhitelisted();

            if (
                accountToInvestorInfo[investor].totalDeposit == 0 &&
                !isWhitelisted[investor][poolId == 7 ? 8 : 7]
            ) onlyWhitelistedInvestorsCount -= 1;

            _updateInvestorPoolRewards(investor);

            isInvestorInPool[investor][poolId] = false;
            pools[poolId].participantsCount -= 1;

            if (pools[poolId].participantsCount == 0) {
                pools[poolId].isActive = false;
            }
        }

        isWhitelisted[investor][poolId] = add;

        emit WhitelistUpdated(investor, poolId, add);
    }

    /**
     * @notice Updates pool criteria for specified pools
     * @param poolIds Array of pool IDs to update
     * @param criteriaOfPools Array of new criteria for each pool
     * @param checkCountLimit Maximum number of investors to check in one transaction
     * @dev Only callable by owner
     * @dev Updates are done in batches to avoid gas limits
     * @dev New criteria must maintain pool hierarchy
     */
    function setPoolCriteria(
        uint8[] calldata poolIds,
        PoolCriteria[] calldata criteriaOfPools,
        uint256 checkCountLimit
    ) external onlyOwner {        
        if (!isUpdateCriteriaActive) {
            if (block.timestamp - lastUpdatePoolCriteriaTimestamp < poolCriteriaUpdateDelay) revert SetPoolCriteriaNotYetAvailable();
            if (poolIds.length != criteriaOfPools.length) revert InvalidArrayLengths();
            _updatePoolRewards();
            for (uint8 i = 0; i < poolIds.length; i++) {
                if (poolIds[i] >= 7) revert InvalidPoolId();
                PoolInfo memory poolInfo = pools[poolIds[i]];
                _checkHalfRequirement(poolInfo.personalInvestRequired, criteriaOfPools[i].personalInvestRequired);
                _checkHalfRequirement(poolInfo.directRefsRequired, criteriaOfPools[i].directRefsRequired);
                _checkHalfRequirement(poolInfo.totalDirectInvestRequired, criteriaOfPools[i].totalDirectInvestRequired);

                pools[poolIds[i]].personalInvestRequired = criteriaOfPools[i].personalInvestRequired;
                pools[poolIds[i]].directRefsRequired = criteriaOfPools[i].directRefsRequired;
                pools[poolIds[i]].totalDirectInvestRequired = criteriaOfPools[i].totalDirectInvestRequired;
            }

            for (uint8 i = 0; i < 6; i++) {
                PoolInfo memory poolInfoPrev = pools[i];
                PoolInfo memory poolInfoNext = pools[i + 1];
                
                if (
                    poolInfoPrev.personalInvestRequired > poolInfoNext.personalInvestRequired ||
                    poolInfoPrev.directRefsRequired > poolInfoNext.directRefsRequired ||
                    poolInfoPrev.totalDirectInvestRequired > poolInfoNext.totalDirectInvestRequired
                ) revert SequencePoolCriteriaBroken();
            }
            
            lastUpdatePoolCriteriaTimestamp = block.timestamp;
            isUpdateCriteriaActive = true;
            _updateCriteriaPoolIds = poolIds;
        }

        uint8[] memory storedPoolIds = _updateCriteriaPoolIds;
        uint256 checkCount = 0;
        for (uint256 i = _updateCriteriaCurInvestorId; i < _investors.length; i++) {
            address investorAddress = _investors[i];
            InvestorInfo memory investorInfo = accountToInvestorInfo[investorAddress];
            for (uint8 j = 0; j < storedPoolIds.length; j++) {
                PoolInfo memory poolInfo = pools[storedPoolIds[j]];
                bool isShouldBeInPool = _checkInvestorPoolCriteria(poolInfo, investorInfo);
                bool isInPool = isInvestorInPool[investorAddress][storedPoolIds[j]];
                if (isInPool && !isShouldBeInPool) {
                    _updateInvestorPoolRewards(investorAddress);
                    if (poolInfo.participantsCount == 1) {
                        pools[storedPoolIds[j]].isActive = false;
                    }
                    isInvestorInPool[investorAddress][storedPoolIds[j]] = false;
                    pools[storedPoolIds[j]].participantsCount -= 1;
                } else if (!isInPool && isShouldBeInPool) {
                    if (poolInfo.participantsCount == 0) {
                        pools[storedPoolIds[j]].isActive = true;
                    }
                    isInvestorInPool[investorAddress][storedPoolIds[j]] = true;
                    pools[storedPoolIds[j]].participantsCount += 1;
                    accountToInvestorInfo[investorAddress].poolRewardPerInvestorPaid[storedPoolIds[j]] = poolInfo.rewardPerInvestorStored;
                }
            }
            checkCount += 1;
            if (checkCount >= checkCountLimit) {
                _updateCriteriaCurInvestorId = i + 1;
                // No revert here. Part of changes will take place
                return;
            }
        }
        emit PoolsCriteriaUpdated(_updateCriteriaPoolIds);
        _updateCriteriaCurInvestorId = 0;
        isUpdateCriteriaActive = false;
        delete _updateCriteriaPoolIds;
    }

    /**
     * @notice Allows users to deposit tokens and participate in the investment program
     * @param amount Amount of tokens to deposit (must be >= 1 token for first deposit)
     * @param referer Address of the referer (can be zero address for first deposit)
     * @dev Requires:
     * - Contract to be active (after startTime)
     * - Contract to not be in pool criteria update mode
     * - Deposit delay to have passed since last deposit
     * - Amount to be >= 1 token for first deposit
     * - Referer to be different from depositor and zero address for not first deposit
     */
    function deposit(uint256 amount, address referer) external NotInPoolCriteriaUpdate {
        address investorAddress = _msgSender();
        InvestorInfo storage investor = accountToInvestorInfo[investorAddress];
        if (
            block.timestamp < startTimestamp ||
            block.timestamp - investor.lastDepositTimestamp < depositDelay
        ) revert DepositNotYetAvailable();

        (uint256 toInvestor, uint256 fee) = _calcFee(amount, depositFeeInBp);
        fivePillarsToken.transferFrom(investorAddress, address(this), fee);
        fivePillarsToken.burnFrom(investorAddress, toInvestor);

        if (referer != address(0)) {
            if (investor.totalDeposit > 0) revert RefererAlreadySetted();
            if (investorAddress == referer) revert InvalidReferer();
            investor.referer = referer;
        }
        bool isFirstDeposit = investor.totalDeposit == 0;
        if (isFirstDeposit) {
            _checkDepositOrClaimAmount(amount);
            investor.referer = referer;
            _checkRefererCirculation(referer);
            _investors.push(investorAddress);
            if (isWhitelisted[investorAddress][7] || isWhitelisted[investorAddress][8]) onlyWhitelistedInvestorsCount -= 1;
        }
        if (investor.referer != address(0)) _updateReferers(investor.referer, toInvestor, isFirstDeposit);
        _updatePoolRewards(amount, investorAddress, investor.referer);

        (uint256 totalDailyReward, uint256 lastDailyReward) = _calcInvestorDailyReward(investor);
        if (totalDailyReward > 0) {
            investor.lastDailyReward = lastDailyReward;
        }
        investor.accumulatedReward += totalDailyReward;
        investor.lastDepositTimestamp = uint32(block.timestamp);
        investor.totalDeposit += toInvestor;
        totalDepositAmount += toInvestor;

        emit Deposit(investorAddress, investor.referer, toInvestor);

        _trySendFees();
    }

    /**
     * @notice Allows users to claim their accumulated rewards
     * @dev Requires:
     * - Contract to not be in pool criteria update mode
     * - Accumulated rewards to be >= 1 token
     * Automatically redistributes 50% of claimed rewards back to the ecosystem
     */
    function claimReward() external NotInPoolCriteriaUpdate {
        address investorAddress = _msgSender();
        _updateInvestorRewards(investorAddress);
        InvestorInfo memory investor = accountToInvestorInfo[investorAddress];
        _checkDepositOrClaimAmount(investor.accumulatedReward);

        accountToInvestorInfo[investorAddress].accumulatedReward = 0;
        accountToInvestorInfo[investorAddress].lastClaimTimestamp = uint32(block.timestamp);

        (uint256 toInvestor, uint256 fee) = _calcFee(investor.accumulatedReward, claimFeeInBp);
        uint256 toRedistribute = toInvestor * 50 / 100;
        toInvestor -= toRedistribute;
        fivePillarsToken.mint(address(this), fee);
        fivePillarsToken.mint(investorAddress, toInvestor);

        // Redistribute half user reward
        if (investor.totalDeposit == 0) {
            _investors.push(investorAddress);
            if (isWhitelisted[investorAddress][7] || isWhitelisted[investorAddress][8]) onlyWhitelistedInvestorsCount -= 1;
        }
        if (investor.referer != address(0)) _updateReferers(investor.referer, toRedistribute, false);
        _updatePoolRewards(toRedistribute, investorAddress, investor.referer);
        accountToInvestorInfo[investorAddress].totalDeposit += toRedistribute;
        totalDepositAmount += toRedistribute;

        emit Redistribute(investorAddress, toRedistribute);

        emit ClaimReward(investorAddress, toInvestor);

        _trySendFees();
    }

    function _checkDepositOrClaimAmount(uint256 amount) internal pure {
        if (amount < 10 ** 18) revert SmallDepositOrClaimAmount();
    }

    function _checkHalfRequirement(uint256 oldValue, uint256 newValue) internal pure {
        if (oldValue / 2 < (oldValue > newValue ? oldValue - newValue : newValue - oldValue)) revert HalfRequirementViolated();
    }

    function _checkRefererCirculation(address referer) internal view {
        address directReferer = referer;
        if (referer != address(0)) {
            for (uint i = 0; i < 9; i++) {
                referer = accountToInvestorInfo[referer].referer;
                if (referer == address(0)) break;
                if (referer == directReferer) revert RefererCirculationDetected();
            }
        }
    }

    function _calcCountOfRoundsSinceLastUpdate(uint32 lastUpdate) internal view returns(uint256) {
        uint256 startTime = startTimestamp;
        if (lastUpdate < startTime || block.timestamp < startTime) return 0;
        return (block.timestamp - startTime) / roundDuration - (lastUpdate - startTime) / roundDuration;
    }

    function _calcInvestorDailyReward(InvestorInfo memory investorInfo) internal view returns(uint256, uint256) {
        uint32 lastUpdate = investorInfo.lastDepositTimestamp > investorInfo.lastClaimTimestamp ? investorInfo.lastDepositTimestamp : investorInfo.lastClaimTimestamp;
        uint256 endedRounds = _calcCountOfRoundsSinceLastUpdate(lastUpdate);
        uint256 roundReward = investorInfo.totalDeposit * 30000 / BASIS_POINTS;

        return (roundReward * endedRounds, roundReward);
    }

    function _calcInvestorRefRewards(InvestorInfo memory investorInfo, address investor) internal view returns(uint256, uint256) {
        uint256 endedRounds = _calcCountOfRoundsSinceLastUpdate(investorInfo.updateRefRewardTimestamp);
        uint256 roundReward = investorInfo.directRefsDeposit * 2500 / BASIS_POINTS;
        if (isInvestorInPool[investor][2]) {
            roundReward += investorInfo.downlineRefsDeposit * 675 / BASIS_POINTS;
        }

        return (roundReward * endedRounds, roundReward);
    }

    function _calcInvestorPoolRewards(InvestorInfo memory investorInfo, address investor) internal view returns(uint256, uint256) {
        uint256 reward = 0;
        uint256 lastReward = 0;
        uint256 endedRounds = _calcCountOfRoundsSinceLastUpdate(uint32(lastUpdatePoolRewardTimestamp));
        for (uint8 i = 0; i < pools.length; i++) {
            if (!isInvestorInPool[investor][i]) continue;

            (uint256 poolReward, uint256 poolLastReward) = _calcInvestorPoolReward(investorInfo.poolRewardPerInvestorPaid[i], i, endedRounds);
            reward += poolReward;
            lastReward += poolLastReward;
        }

        return (reward, lastReward);
    }

    function _calcInvestorPoolReward(uint256 poolRewardPerInvestorPaid, uint256 poolId, uint256 endedRounds) internal view returns(uint256 reward, uint256 lastReward) {
        uint256 rewardPerInvestorStored = pools[poolId].rewardPerInvestorStored;
        if (endedRounds > 0) {
            rewardPerInvestorStored += pools[poolId].curReward * endedRounds / pools[poolId].participantsCount;
            lastReward = pools[poolId].curReward / pools[poolId].participantsCount;
        }

        reward += rewardPerInvestorStored - poolRewardPerInvestorPaid;
    }

    function _calcFee(uint256 amount, uint256 feeInBp) internal pure returns(uint256 toInvestor, uint256 fee) {
        fee = amount * feeInBp / BASIS_POINTS;
        toInvestor = amount - fee;
    }

    function _updateInvestorPoolRewards(address investor) internal {
        uint256 reward;
        for (uint8 i = 0; i < pools.length; i++) {
            if (!isInvestorInPool[investor][i]) continue;

            reward += _updateInvestorPoolReward(investor, i);
        }
        accountToInvestorInfo[investor].accumulatedReward += reward;
    }

    function _updateInvestorPoolReward(address investor, uint256 poolId) internal returns(uint256 reward) {
        uint256 rewardPerInvestorStored = pools[poolId].rewardPerInvestorStored;

        reward = rewardPerInvestorStored - accountToInvestorInfo[investor].poolRewardPerInvestorPaid[poolId];
        accountToInvestorInfo[investor].poolRewardPerInvestorPaid[poolId] = rewardPerInvestorStored;
    }

    function _updateInvestorRefReward(address investor) internal {
        InvestorInfo memory investorInfo = accountToInvestorInfo[investor];
        uint256 endedRounds = _calcCountOfRoundsSinceLastUpdate(investorInfo.updateRefRewardTimestamp);

        if (endedRounds > 0) {
            (uint256 totalRefRewards, uint256 lastRefReward) = _calcInvestorRefRewards(investorInfo, investor);
            accountToInvestorInfo[investor].lastRefReward = lastRefReward;
            accountToInvestorInfo[investor].accumulatedReward += totalRefRewards;
        }

        accountToInvestorInfo[investor].updateRefRewardTimestamp = uint32(block.timestamp);
    }

    function _updateInvestorRewards(address investor) internal {
        InvestorInfo memory investorInfo = accountToInvestorInfo[investor];
        (uint256 totalDailyReward, uint256 roundReward) = _calcInvestorDailyReward(investorInfo);
        accountToInvestorInfo[investor].accumulatedReward += totalDailyReward;
        if (totalDailyReward > 0) {
            accountToInvestorInfo[investor].lastDailyReward = roundReward;
        }
        _updateInvestorRefReward(investor);
        _updatePoolRewards();
        _updateInvestorPoolRewards(investor);
    }

    function _updateDownlineReferer(address referer, uint256 amount, bool isFirstDeposit) internal {
        _updateInvestorRefReward(referer);

        accountToInvestorInfo[referer].downlineRefsDeposit += amount;
        if (isFirstDeposit) accountToInvestorInfo[referer].downlineRefsCount += 1;
    }

    function _updateReferers(address referer, uint256 amount, bool isFirstDeposit) internal {
        _updateInvestorRefReward(referer);

        accountToInvestorInfo[referer].directRefsDeposit += amount;
        if (isFirstDeposit) accountToInvestorInfo[referer].directRefsCount += 1;

        for (uint i = 0; i < 9; i++) {
            referer = accountToInvestorInfo[referer].referer;
            if (referer == address(0)) break;
            _updateDownlineReferer(referer, amount, isFirstDeposit);
        }
    }

    function _updatePoolRewards(uint256 amount, address investor, address referer) internal {
        InvestorInfo memory investorInfo = accountToInvestorInfo[investor];
        InvestorInfo memory refererInfo = accountToInvestorInfo[referer];
        uint256 endedRounds = _calcCountOfRoundsSinceLastUpdate(uint32(lastUpdatePoolRewardTimestamp));
        for (uint8 i = 0; i < 7; i++) {
            PoolInfo storage poolInfo = pools[i];
            bool isPoolActive = poolInfo.isActive;

            if (isPoolActive) _updatePoolReward(poolInfo, endedRounds);

            bool isAddedToPool = _checkAndAddInvestorToPool(poolInfo, i, investorInfo, investor);
            if (referer != address(0)) {
                isAddedToPool = isAddedToPool || _checkAndAddInvestorToPool(poolInfo, i, refererInfo, referer);
            }

            if (!isPoolActive) {
                if (isAddedToPool) {
                    poolInfo.isActive = true;
                } else {
                    break;
                }
            }

            poolInfo.curReward += amount * poolInfo.share / BASIS_POINTS;
        }
        for (uint8 i = 7; i < 9; i++) {
            PoolInfo memory poolInfo = pools[i];
            if (poolInfo.isActive) {
                _updatePoolReward(pools[i], endedRounds);
                pools[i].curReward += amount * poolInfo.share / BASIS_POINTS;
            }
        }

        lastUpdatePoolRewardTimestamp = block.timestamp;
    }

    function _updatePoolRewards() internal {
        uint256 endedRounds = _calcCountOfRoundsSinceLastUpdate(uint32(lastUpdatePoolRewardTimestamp));

        for (uint8 i = 0; i < pools.length; i++) {
            if (pools[i].isActive) _updatePoolReward(pools[i], endedRounds);
        }

        lastUpdatePoolRewardTimestamp = block.timestamp;
    }

    function _updatePoolReward(PoolInfo storage poolInfo, uint256 endedRounds) internal {
        if (endedRounds > 0) {
            poolInfo.rewardPerInvestorStored += poolInfo.curReward * endedRounds / poolInfo.participantsCount;
            poolInfo.lastReward = poolInfo.curReward / poolInfo.participantsCount;
        }
    }

    function _checkInvestorPoolCriteria(
        PoolInfo memory poolInfo,
        InvestorInfo memory investorInfo
    ) internal pure returns(bool) {
        if (
            investorInfo.totalDeposit >= poolInfo.personalInvestRequired &&
            investorInfo.directRefsCount >= poolInfo.directRefsRequired && 
            investorInfo.directRefsDeposit >= poolInfo.totalDirectInvestRequired
        ) {
            return true;
        }
        return false;
    }

    function _checkAndAddInvestorToPool(
        PoolInfo memory poolInfo,
        uint8 poolId,
        InvestorInfo memory investorInfo,
        address investor
    ) internal returns(bool) {
        if (!isInvestorInPool[investor][poolId]) {
            if (
                investorInfo.totalDeposit >= poolInfo.personalInvestRequired &&
                investorInfo.directRefsCount >= poolInfo.directRefsRequired && 
                investorInfo.directRefsDeposit >= poolInfo.totalDirectInvestRequired
            ) {
                isInvestorInPool[investor][poolId] = true;
                pools[poolId].participantsCount += 1;
                accountToInvestorInfo[investor].poolRewardPerInvestorPaid[poolId] = poolInfo.rewardPerInvestorStored;
                return true;
            }
        }

        return false;
    }

    function _trySendFees() internal {
        uint256 accumulatedFees = fivePillarsToken.balanceOf(address(this));
        uint256 amountOutMin = accumulatedFees * minSwapPrice / 10 ** 18;
        if(accumulatedFees > 0) {
            fivePillarsToken.approve(dexRouter, accumulatedFees);
            address[] memory path = new address[](2);
            path[0] = address(fivePillarsToken);
            path[1] = IPancakeRouter01(dexRouter).WETH();
            (bool success, ) = dexRouter.call(abi.encodeWithSelector(
                IPancakeRouter01.swapExactTokensForETH.selector,
                accumulatedFees,
                amountOutMin,
                path,
                address(this),
                block.timestamp
            ));
            if (!success) {
                fivePillarsToken.approve(dexRouter, 0);
                emit SwapFeesFailed(accumulatedFees);
                return;
            }

            uint256 firstTreasuryAmount = address(this).balance * 70 / 100;
            (success,) = payable(treasury).call{value: firstTreasuryAmount}("");
            if (!success) revert SendEtherFailed(treasury);

            (success,) = payable(treasury2).call{value: address(this).balance}("");
            if (!success) revert SendEtherFailed(treasury2);
        }
    } 
}
