// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../libraries/LibDiamond.sol";
import "../libraries/RoleConstants.sol";
import "./FacetBase.sol";
import "./ReentrancyGuardBase.sol";
import "../interfaces/IFeeManagement.sol";
import "../interfaces/IRoleManagement.sol";
import "../interfaces/IInterestRateModelFacet.sol";
import "../interfaces/IPriceOracleFacet.sol";

/**
 * @title LendingPoolFacet
 * @dev Manages lending pool operations including deposits, withdrawals, borrowing, and staking rewards
 * @notice Implements lending pool functionality with proper collateral checks and deflationary token support
 * @custom:security-contact security@koyodex.com
 */
contract LendingPoolFacet is FacetBase, ReentrancyGuardBase {
    using SafeERC20 for IERC20;

    uint256 private constant SCALE = 1e18;
    uint256 private constant MAX_UTILIZATION_RATE = 9000; // 90%
    uint256 private constant MIN_COLLATERAL_RATIO = 12500; // 125%
    uint256 private constant LIQUIDATION_THRESHOLD = 11000; // 110%
    uint256 private constant REWARD_PRECISION = 1e12;
    uint256 private constant SECONDS_PER_YEAR = 31536000;
    uint256 private constant MAX_UINT = type(uint256).max;

    /**
     * @dev Emitted when tokens are deposited
     */
    event Deposited(
        address indexed user,
        address indexed token,
        uint256 requested,
        uint256 actual,
        uint256 timestamp
    );

    /**
     * @dev Emitted when tokens are withdrawn
     */
    event Withdrawn(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 timestamp
    );

    /**
     * @dev Emitted when tokens are borrowed
     */
    event Borrowed(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 fee,
        uint256 timestamp
    );

    /**
     * @dev Emitted when tokens are repaid
     */
    event Repaid(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 interest,
        uint256 timestamp
    );

    /**
     * @dev Emitted when rewards are claimed
     */
    event RewardsClaimed(
        address indexed user,
        address indexed token,
        uint256 amount,
        uint256 timestamp
    );

    /**
     * @dev Emitted when staking rate is updated
     */
    event StakingRateUpdated(
        uint256 oldRate,
        uint256 newRate,
        uint256 timestamp
    );

    /**
     * @dev Emitted when collateral is converted
     */
    event CollateralConverted(
        address indexed user,
        address indexed token,
        uint256 amount,
        bool isToMargin,
        uint256 timestamp
    );

    /**
     * @dev Modifier that checks if the caller has the specified role
     */
    modifier onlyRole(bytes32 role) {
        require(LibDiamond.diamondStorage().roles[role][msg.sender], "Must have required role");
        _;
    }

    /**
     * @dev Modifier to update rewards before executing function
     */
    modifier updateReward(address account, address token) {
        _updateReward(account, token);
        _;
    }

    /**
     * @dev Modifier to validate token
     */
    modifier validToken(address token) {
        require(token != address(0), "Invalid token address");
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        require(ds.isTokenSupported[token], "Token not supported");
        require(ds.tokenInfo[token].isActive, "Token not active");
        _;
    }

    /**
     * @notice Initializes the lending pool
     * @param _interestRateModel The address of the interest rate model contract
     * @param _feeManagement The address of the fee management contract
     * @param _stakingRewardRate The initial staking reward rate
     */
    function initializeLendingPool(
        address _interestRateModel,
        address _feeManagement,
        uint256 _stakingRewardRate
    ) external onlyRole(RoleConstants.ADMIN_ROLE) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        require(!ds.initialized, "Already initialized");
        
        require(_interestRateModel != address(0), "Invalid interest rate model");
        require(_feeManagement != address(0), "Invalid fee management");
        require(_stakingRewardRate > 0, "Invalid staking rate");

        ds.interestRateModelFacet = _interestRateModel;
        ds.feeManagementFacet = _feeManagement;
        ds.stakingRewardRate = _stakingRewardRate;
        ds.initialized = true;

        emit StakingRateUpdated(0, _stakingRewardRate, block.timestamp);
    }

    /**
     * @notice Sets the staking reward rate
     * @param _newRate The new staking reward rate
     */
    function setStakingRewardRate(
        uint256 _newRate
    ) external onlyRole(RoleConstants.ADMIN_ROLE) {
        require(_newRate > 0, "Invalid rate");
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        uint256 oldRate = ds.stakingRewardRate;
        ds.stakingRewardRate = _newRate;
        
        emit StakingRateUpdated(oldRate, _newRate, block.timestamp);
    }

    /**
     * @notice Deposits tokens into the lending pool
     * @dev Handles deflationary tokens by checking actual received amount
     * @param token The token to deposit
     * @param amount The amount to deposit
     */
    function deposit(
        address token,
        uint256 amount
    ) external nonReentrant updateReward(msg.sender, token) validToken(token) {
        require(amount > 0, "Amount must be greater than 0");
        
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();

        // Get initial balance for deflationary token support
        uint256 balanceBefore = IERC20(token).balanceOf(address(this));
        
        // Transfer tokens with SafeERC20
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        
        // Calculate actual received amount for deflationary tokens
        uint256 balanceAfter = IERC20(token).balanceOf(address(this));
        uint256 actualAmount = balanceAfter - balanceBefore;
        
        require(actualAmount > 0, "No tokens received");

        // Update state with actual received amount
        ds.userDeposits[msg.sender][token] += actualAmount;
        ds.lendingPools[token].totalDeposited += actualAmount;
        
        // Update staking rewards
        _updateUserStaking(msg.sender, token, actualAmount, true);

        // Grant staked trader role
        _grantStakedTraderRole(msg.sender);

        emit Deposited(msg.sender, token, amount, actualAmount, block.timestamp);
    }

    /**
     * @notice Withdraws tokens from the lending pool
     * @dev Checks borrow status and collateral ratio before withdrawal
     * @param token The token to withdraw
     * @param amount The amount to withdraw
     */
    function withdraw(
        address token,
        uint256 amount
    ) external nonReentrant updateReward(msg.sender, token) validToken(token) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        require(amount > 0, "Amount must be greater than 0");
        require(ds.userDeposits[msg.sender][token] >= amount, "Insufficient balance");

        // Check utilization rate
        uint256 utilizationRate = _calculateUtilizationRate(token);
        require(utilizationRate <= MAX_UTILIZATION_RATE, "Utilization too high");

        // Check for outstanding borrows
        require(ds.userBorrows[msg.sender][token] == 0, "Outstanding borrows exist");

        // Check collateral ratio if user has any borrows
        bool hasAnyBorrows = false;
        for (uint256 i = 0; i < ds.supportedTokens.length; i++) {
            if (ds.userBorrows[msg.sender][ds.supportedTokens[i]] > 0) {
                hasAnyBorrows = true;
                break;
            }
        }

        if (hasAnyBorrows) {
            require(
                _checkCollateralRatio(msg.sender, token, amount, true),
                "Would break collateral ratio"
            );
        }

        // Update state
        ds.userDeposits[msg.sender][token] -= amount;
        ds.lendingPools[token].totalDeposited -= amount;
        
        // Update staking rewards
        _updateUserStaking(msg.sender, token, amount, false);

        // Check if user still has any deposits
        bool hasDeposits = false;
        for (uint256 i = 0; i < ds.supportedTokens.length; i++) {
            if (ds.userDeposits[msg.sender][ds.supportedTokens[i]] > 0) {
                hasDeposits = true;
                break;
            }
        }

        // Revoke staked trader role if no deposits remain
        if (!hasDeposits) {
            _revokeStakedTraderRole(msg.sender);
        }

        // Transfer tokens
        IERC20(token).safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, token, amount, block.timestamp);
    }

    /**
     * @notice Borrows tokens from the lending pool
     * @dev Implements proper collateral checks and fee handling
     * @param token The token to borrow
     * @param amount The amount to borrow
     */
    function borrow(
        address token,
        uint256 amount
    ) external nonReentrant updateReward(msg.sender, token) validToken(token) {
        require(amount > 0, "Amount must be greater than 0");
        
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();

        // Check utilization rate
        uint256 utilizationRate = _calculateUtilizationRate(token);
        require(utilizationRate <= MAX_UTILIZATION_RATE, "Utilization too high");

        // Calculate and collect fees
        uint256 fee = IFeeManagement(ds.feeManagementFacet).calculateBorrowingFee(amount);
        uint256 totalAmount = amount + fee;

        // Check collateral ratio with total amount
        require(
            _checkCollateralRatio(msg.sender, token, totalAmount, false),
            "Insufficient collateral"
        );

        // Update state
        ds.userBorrows[msg.sender][token] += totalAmount;
        ds.lendingPools[token].totalBorrowed += totalAmount;

        // Update interest tracking
        _updateInterest(msg.sender, token);

        // Transfer tokens
        IERC20(token).safeTransfer(msg.sender, amount);
        
        // Collect fee
        IFeeManagement(ds.feeManagementFacet).collectFee(token, fee);

        emit Borrowed(msg.sender, token, amount, fee, block.timestamp);
    }

    /**
     * @notice Repays borrowed tokens
     * @dev Handles interest calculation and fee collection
     * @param token The token to repay
     * @param amount The amount to repay
     */
    function repay(
        address token,
        uint256 amount
    ) external nonReentrant updateReward(msg.sender, token) validToken(token) {
        require(amount > 0, "Amount must be greater than 0");
        
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        require(ds.userBorrows[msg.sender][token] > 0, "No outstanding borrows");

        // Update interest before repayment
        _updateInterest(msg.sender, token);

        // Calculate interest
        uint256 interest = IInterestRateModelFacet(ds.interestRateModelFacet).calculateInterest(
            ds.userBorrows[msg.sender][token]
        );

        uint256 totalDue = amount + interest;

        // Transfer tokens with SafeERC20
        IERC20(token).safeTransferFrom(msg.sender, address(this), totalDue);

        // Update state
        ds.userBorrows[msg.sender][token] -= amount;
        ds.lendingPools[token].totalBorrowed -= amount;

        // Collect interest as fee
        IFeeManagement(ds.feeManagementFacet).collectFee(token, interest);

        emit Repaid(msg.sender, token, amount, interest, block.timestamp);
    }

    /**
     * @notice Claims staking rewards
     * @dev Ensures no outstanding loans before claiming
     * @param token The token to claim rewards for
     */
    function claimRewards(
        address token
    ) external nonReentrant updateReward(msg.sender, token) validToken(token) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        
        // Check for outstanding loans
        require(!_hasOutstandingLoans(msg.sender), "Cannot claim with outstanding loans");

        LibDiamond.StakingRewards storage rewards = ds.stakingRewards[msg.sender][token];
        uint256 reward = rewards.rewards;
        require(reward > 0, "No rewards to claim");

        // Reset rewards before transfer
        rewards.rewards = 0;

        // Transfer rewards using SafeERC20
        IERC20(token).safeTransfer(msg.sender, reward);

        emit RewardsClaimed(msg.sender, token, reward, block.timestamp);
    }

    /**
     * @notice Converts collateral between lending and margin pools
     * @param token The token to convert
     * @param amount The amount to convert
     * @param toMargin Whether to convert to margin pool
     */
    function convertCollateral(
        address token,
        uint256 amount,
        bool toMargin
    ) external nonReentrant updateReward(msg.sender, token) validToken(token) {
        require(amount > 0, "Amount must be greater than 0");
        
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();

        if (toMargin) {
            require(ds.userDeposits[msg.sender][token] >= amount, "Insufficient lending deposit");
            require(ds.userBorrows[msg.sender][token] == 0, "Outstanding loans exist");

            ds.userDeposits[msg.sender][token] -= amount;
            ds.lendingPools[token].totalDeposited -= amount;
            ds.marginAccounts[msg.sender].balance[token] += amount;
        } else {
            require(ds.marginAccounts[msg.sender].balance[token] >= amount, "Insufficient margin balance");
            require(ds.marginAccounts[msg.sender].borrowed == 0, "Outstanding margin loans exist");

            ds.marginAccounts[msg.sender].balance[token] -= amount;
            ds.userDeposits[msg.sender][token] += amount;
            ds.lendingPools[token].totalDeposited += amount;
        }

        emit CollateralConverted(msg.sender, token, amount, toMargin, block.timestamp);
    }

    /**
     * @notice Returns the function selectors for this facet
     * @return selectors Array of function selectors
     */
    function getLendingPoolFacetSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](8);
        selectors[0] = this.initializeLendingPool.selector;
        selectors[1] = this.setStakingRewardRate.selector;
        selectors[2] = this.deposit.selector;
        selectors[3] = this.withdraw.selector;
        selectors[4] = this.borrow.selector;
        selectors[5] = this.repay.selector;
        selectors[6] = this.claimRewards.selector;
        selectors[7] = this.convertCollateral.selector;
        return selectors;
    }

    /**
     * @dev Updates reward state for user
     * @param account The user address
     * @param token The token address
     */
    function _updateReward(address account, address token) internal {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        LibDiamond.StakingRewards storage rewards = ds.stakingRewards[account][token];

        uint256 timeElapsed = block.timestamp - rewards.lastUpdated;
        if (timeElapsed > 0 && rewards.stakedAmount > 0) {
            uint256 rewardRate = (ds.stakingRewardRate * REWARD_PRECISION) / SECONDS_PER_YEAR;
            uint256 reward = (rewards.stakedAmount * rewardRate * timeElapsed) / REWARD_PRECISION;
            rewards.rewards += reward;
        }
        rewards.lastUpdated = block.timestamp;
    }

    /**
     * @dev Updates user staking state
     * @param user The user address
     * @param token The token address
     * @param amount The amount to update
     * @param isDeposit Whether this is a deposit operation
     */
    function _updateUserStaking(
        address user,
        address token,
        uint256 amount,
        bool isDeposit
    ) internal {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        LibDiamond.StakingRewards storage rewards = ds.stakingRewards[user][token];

        if (isDeposit) {
            rewards.stakedAmount += amount;
        } else {
            rewards.stakedAmount = rewards.stakedAmount >= amount ? 
                rewards.stakedAmount - amount : 0;
        }
    }

    /**
     * @dev Calculates utilization rate for a token
     * @param token The token address
     * @return The utilization rate
     */
    function _calculateUtilizationRate(
        address token
    ) internal view returns (uint256) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        LibDiamond.LendingPool storage pool = ds.lendingPools[token];

        if (pool.totalDeposited == 0) return 0;
        return (pool.totalBorrowed * SCALE) / pool.totalDeposited;
    }

    /**
     * @dev Checks if collateral ratio is maintained
     * @param user The user address
     * @param token The token address
     * @param amount The amount to check
     * @param isWithdraw Whether this is a withdrawal operation
     * @return Whether the collateral ratio is maintained
     */
    function _checkCollateralRatio(
        address user,
        address token,
        uint256 amount,
        bool isWithdraw
    ) internal view returns (bool) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        uint256 totalCollateralValue = 0;
        uint256 totalBorrowValue = 0;

        for (uint256 i = 0; i < ds.supportedTokens.length; i++) {
            address currentToken = ds.supportedTokens[i];
            uint256 price = IPriceOracleFacet(ds.priceOracleFacet).getPrice(currentToken);

            // Calculate collateral value
            uint256 collateral = ds.userDeposits[user][currentToken];
            if (currentToken == token && isWithdraw) {
                collateral = collateral > amount ? collateral - amount : 0;
            }
            totalCollateralValue += (collateral * price) / SCALE;

            // Calculate borrow value
            uint256 borrowed = ds.userBorrows[user][currentToken];
            if (currentToken == token && !isWithdraw) {
                borrowed += amount;
            }
            totalBorrowValue += (borrowed * price) / SCALE;
        }

        if (totalBorrowValue == 0) return true;
        return (totalCollateralValue * SCALE) / totalBorrowValue >= MIN_COLLATERAL_RATIO;
    }

    /**
     * @dev Updates interest for a user's position
     * @param user The user address
     * @param token The token address
     */
    function _updateInterest(address user, address token) internal {
        IInterestRateModelFacet(LibDiamond.diamondStorage().interestRateModelFacet)
            .compoundInterestForUser(user, token);
    }

    /**
     * @dev Checks if a user has any outstanding loans
     * @param user The user address
     * @return Whether the user has outstanding loans
     */
    function _hasOutstandingLoans(address user) internal view returns (bool) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        
        for (uint256 i = 0; i < ds.supportedTokens.length; i++) {
            if (ds.userBorrows[user][ds.supportedTokens[i]] > 0) {
                return true;
            }
        }
        return false;
    }

    /**
     * @dev Grants staked trader role to a user
     * @param user The user address
     */
    function _grantStakedTraderRole(address user) internal {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        if (!ds.roles[RoleConstants.STAKED_TRADER_ROLE][user]) {
            ds.roles[RoleConstants.STAKED_TRADER_ROLE][user] = true;
        }
    }

    /**
     * @dev Revokes staked trader role from a user
     * @param user The user address
     */
    function _revokeStakedTraderRole(address user) internal {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        if (ds.roles[RoleConstants.STAKED_TRADER_ROLE][user]) {
            ds.roles[RoleConstants.STAKED_TRADER_ROLE][user] = false;
        }
    }
}