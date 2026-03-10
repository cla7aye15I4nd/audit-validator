// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../libraries/LibDiamond.sol";
import "../libraries/RoleConstants.sol";
import "./FacetBase.sol";
import "./MarginAccountsFacet.sol";
import "./PriceOracleFacet.sol";
import "../interfaces/IFacetInterface.sol";
import "../interfaces/IFeeManagement.sol";
import "../interfaces/IRoleManagement.sol";
import "../interfaces/IInterestRateModelFacet.sol";

/**
 * @title LendingPoolFacet
 * @dev Facet contract for managing lending pool operations within the diamond.
 */
contract LendingPoolFacet is FacetBase, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IInterestRateModelFacet public interestRateModel;
    IFeeManagement public feeManagement;

    uint256 public constant MIN_GAS_REQUIREMENT = 50000;
    bool internal initialized = false;

    /**
     * @dev Modifier that checks if the caller has the specified role.
     * @param role The role required to execute the function.
     */
    modifier onlyRole(bytes32 role) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        require(ds.roles[role][msg.sender], "Must have required role");
        _;
    }

    constructor() {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        ds.roles[RoleConstants.ADMIN_ROLE][msg.sender] = true;
    }

    /**
     * @notice Initializes the LendingPoolFacet contract.
     * @dev Can only be called by accounts with the ADMIN_ROLE.
     * @param _interestRateModel The address of the interest rate model contract.
     * @param _feeManagement The address of the fee management contract.
     */
    function initializeLendingPool(address _interestRateModel, address _feeManagement) external onlyRole(RoleConstants.ADMIN_ROLE) {
        require(!initialized, "LendingPoolFacet: Already initialized");

        interestRateModel = IInterestRateModelFacet(_interestRateModel);
        feeManagement = IFeeManagement(_feeManagement);

        initialized = true;
    }

        /**
     * @notice Grants a role to a specified account.
     * @dev Can only be called by accounts with the ADMIN_ROLE.
     * @param account The account to grant the role to.
     */
    function grantRole(address account) external onlyRole(RoleConstants.ADMIN_ROLE) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        ds.roles[RoleConstants.ADMIN_ROLE][account] = true;
    }

    // --------------------------------------------------------------------------------------------- PUBLIC ---------------------------------------------------------------------------------------

    /**
     * @notice Gets the user's deposit and borrowed balances for a specific token.
     * @param _tokenAddress The address of the token.
     * @param _user The address of the user.
     * @return deposit The user's deposit balance.
     * @return borrowed The user's borrowed balance.
     */
    function getUserBalance(address _tokenAddress, address _user) public view returns (uint256 deposit, uint256 borrowed) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();

        deposit = ds.userDeposits[_user][_tokenAddress];
        borrowed = ds.userBorrows[_user][_tokenAddress];

        return(deposit, borrowed);
    }

    /**
     * @notice Checks if a user has an outstanding loan.
     * @param _user The address of the user.
     * @return True if the user has an outstanding loan, false otherwise.
     */
    function hasOutstandingLoan(address _user) public view returns (bool) {
        return diamondStorage().marginAccounts[_user].borrowed > 0;
    }

    /**
     * @notice Gets the function selectors for the facet.
     * @return selectors An array of function selectors.
     */
    function facetFunctionSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](8);
        selectors[0] = this.getUserBalance.selector;
        selectors[1] = this.depositToLendingPool.selector;
        selectors[2] = this.withdrawFromLendingPool.selector;
        selectors[3] = this.borrow.selector;
        selectors[4] = this.repay.selector;
        selectors[5] = this.hasOutstandingLoan.selector;
        selectors[6] = this.claimRewards.selector;
        selectors[7] = this.initializeLendingPool.selector;
    }

    // --------------------------------------------------------------------------------------------- EXTERNAL ---------------------------------------------------------------------------------------

    /**
     * @notice Deposits tokens into the lending pool.
     * @param _tokenAddress The address of the token to deposit.
     * @param _amount The amount of tokens to deposit.
     */
    function depositToLendingPool(address _tokenAddress, uint256 _amount) external nonReentrant {
        updateUserInteraction(msg.sender, _tokenAddress);
        interestRateModel.compoundInterestForUser(msg.sender, _tokenAddress);
        require(_amount > 0, "Invalid deposit amount");
        require(diamondStorage().allowedCollateralTokens[_tokenAddress], "Token not allowed as collateral");

        IERC20 token = IERC20(_tokenAddress);

        // Transfer tokens from the user to this contract
        token.safeTransferFrom(msg.sender, address(this), _amount);

        // Ensure that the contract has received the correct amount of tokens
        require(token.balanceOf(address(this)) >= diamondStorage().lendingPools[_tokenAddress].totalDeposited, "Insufficient token transfer");

        // Update the lending pool's total deposited amount
        diamondStorage().lendingPools[_tokenAddress].totalDeposited += _amount;
        diamondStorage().userDeposits[msg.sender][_tokenAddress] += _amount;

        // Update the staking rewards
        updateStakingRewards(msg.sender, _tokenAddress);
        diamondStorage().stakingRewards[msg.sender][_tokenAddress].stakedAmount += _amount;

        // Set Role
        grantStakedTraderRole(msg.sender);

        // Emit event
        emit DepositToLendingPool(msg.sender, _tokenAddress, _amount);
    }

    /**
     * @notice Withdraws tokens from the lending pool.
     * @param _tokenAddress The address of the token to withdraw.
     * @param _amount The amount of tokens to withdraw.
     */
    function withdrawFromLendingPool(address _tokenAddress, uint256 _amount) external nonReentrant onlyRole(RoleConstants.STAKED_TRADER_ROLE) {
        updateUserInteraction(msg.sender, _tokenAddress);
        interestRateModel.compoundInterestForUser(msg.sender, _tokenAddress);
        require(diamondStorage().userDeposits[msg.sender][_tokenAddress] >= _amount, "Insufficient deposit balance");

        IERC20 token = IERC20(_tokenAddress);

        // Update the lending pool's total deposited amount
        diamondStorage().lendingPools[_tokenAddress].totalDeposited -= _amount;
        diamondStorage().userDeposits[msg.sender][_tokenAddress] -= _amount;

        // Update the staking rewards
        updateStakingRewards(msg.sender, _tokenAddress);
        diamondStorage().stakingRewards[msg.sender][_tokenAddress].stakedAmount -= _amount;

        // Ensure that the contract has the necessary balance before transferring tokens
        require(token.balanceOf(address(this)) >= _amount, "Contract has insufficient balance");

        checkStakedTokenHoldings();

        // Transfer tokens from this contract to the user
        token.safeTransfer(msg.sender, _amount);

        // Emit event
        emit WithdrawFromLendingPool(msg.sender, _tokenAddress, _amount);
    }

    /**
     * @notice Converts collateral from the lending pool to the margin pool.
     * @param _tokenAddress The address of the token to convert.
     * @param _amount The amount of tokens to convert.
     */
    function convertCollateralToMargin(address _tokenAddress, uint256 _amount) external nonReentrant onlyRole(RoleConstants.STAKED_TRADER_ROLE) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();

        // Input validation
        require(_tokenAddress != address(0), "Invalid token address");
        require(_amount > 0, "Amount must be positive");
        
        // Check for outstanding loans
        require(ds.userBorrows[msg.sender][_tokenAddress] == 0, "Outstanding loan exists");

        // Compound interest and update user interaction
        interestRateModel.compoundInterestForUser(msg.sender, _tokenAddress);
        updateUserInteraction(msg.sender, _tokenAddress);

        // Check for sufficient deposit balance
        require(ds.userDeposits[msg.sender][_tokenAddress] >= _amount, "Insufficient deposit balance");

        // Transfer collateral to margin account and update balances
        ds.userDeposits[msg.sender][_tokenAddress] -= _amount;
        ds.lendingPools[_tokenAddress].totalDeposited -= _amount;
        ds.marginAccounts[msg.sender].balance[_tokenAddress] += _amount;

        // Update staking rewards and check role
        updateStakingRewards(msg.sender, _tokenAddress);
        checkStakedTokenHoldings();

        emit CollateralConvertedToMargin(msg.sender, _tokenAddress, _amount);
    }

    /**
     * @notice Borrows tokens from the lending pool.
     * @param _tokenAddress The address of the token to borrow.
     * @param _amount The amount of tokens to borrow.
     */
    function borrow(address _tokenAddress, uint256 _amount) external nonReentrant onlyRole(RoleConstants.STAKED_TRADER_ROLE) {
        updateUserInteraction(msg.sender, _tokenAddress);
        interestRateModel.compoundInterestForUser(msg.sender, _tokenAddress);
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        require(diamondStorage().allowedCollateralTokens[_tokenAddress], "Token not allowed for borrowing/repayment");
        require(checkCollateralRatio(_tokenAddress, _amount, msg.sender), "LendingPoolFacet: Insufficient collateral");
        require(_amount > 0, "Invalid borrow amount");

        // Calculate the borrow fee
        uint256 borrowFee = feeManagement.calculateBorrowingFee(_amount);

        require(_amount > borrowFee, "Borrow amount must be greater than borrow fee");

        // Collect the fee
        feeManagement.collectFee(_tokenAddress, borrowFee);

        // Update the lending pool's total borrowed amount and user's borrowed amount
        ds.lendingPools[_tokenAddress].totalBorrowed += _amount;
        ds.marginAccounts[msg.sender].borrowed += _amount;
        ds.userBorrows[msg.sender][_tokenAddress] += _amount;

        // Transfer the borrowed amount minus fees to the user
        IERC20 token = IERC20(_tokenAddress);
        token.safeTransfer(msg.sender, _amount - borrowFee);

        // Emit event
        emit Borrow(msg.sender, _tokenAddress, _amount, borrowFee);
    }

    /**
     * @notice Repays borrowed tokens.
     * @param _tokenAddress The address of the token to repay.
     * @param _amount The amount of tokens to repay.
     */
    function repay(address _tokenAddress, uint256 _amount) external nonReentrant onlyRole(RoleConstants.STAKED_TRADER_ROLE) {
        updateUserInteraction(msg.sender, _tokenAddress);
        interestRateModel.compoundInterestForUser(msg.sender, _tokenAddress);

        require(_amount > 0, "Invalid repayment amount");
        require(diamondStorage().userBorrows[msg.sender][_tokenAddress] >= _amount, "Insufficient borrow balance");
        require(diamondStorage().allowedCollateralTokens[_tokenAddress], "Token not allowed for borrowing/repayment");

        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();

        uint256 totalInterest = ds.interestForFees[msg.sender][_tokenAddress]; 
        uint256 totalDue = _amount + totalInterest;

        // Transfer tokens from the user to this contract
        IERC20 token = IERC20(_tokenAddress);
        token.safeTransferFrom(msg.sender, address(this), totalDue);

        // Collect the fee based on the totalInterest
        feeManagement.collectFee(_tokenAddress, totalInterest);

        // Update the lending pool's total borrowed amount and user's borrowed amount
        ds.lendingPools[_tokenAddress].totalBorrowed -= _amount;
        ds.marginAccounts[msg.sender].borrowed -= _amount;
        ds.userBorrows[msg.sender][_tokenAddress] -= _amount;

        // Emit event
        emit Repay(msg.sender, _tokenAddress, _amount);
    }

    /**
     * @notice Claims rewards for staking.
     * @param _tokenAddress The address of the token to claim rewards for.
     */
    function claimRewards(address _tokenAddress) external onlyRole(RoleConstants.STAKED_TRADER_ROLE) {
        require(!hasOutstandingLoan(msg.sender), "Cannot claim rewards with an outstanding loan");
        
        updateStakingRewards(msg.sender, _tokenAddress);
        uint256 rewards = diamondStorage().stakingRewards[msg.sender][_tokenAddress].rewards;
        diamondStorage().stakingRewards[msg.sender][_tokenAddress].rewards = 0;
        IERC20(address(_tokenAddress)).transfer(msg.sender, rewards);
    }

    /**
     * @notice Triggers the compounding of interest for users.
     */
    function triggerCompoundInterestForUsers() external nonReentrant {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        require(ds.usersOrderedByLastCompounded.length > 0, "No users available");

        LibDiamond.UserTokenPair memory oldestUserTokenPair = ds.usersOrderedByLastCompounded[0];

        uint256 lastCompoundedBlock = ds.userLastCompoundedBlock[oldestUserTokenPair.user][oldestUserTokenPair.token];
        require((block.number - lastCompoundedBlock) > 1000, "No user's to compound");

        uint256 initialGas = gasleft();
        uint256 compoundedCount = 0;

        while(gasleft() > initialGas - MIN_GAS_REQUIREMENT && ds.usersOrderedByLastCompounded.length > 0) {
            oldestUserTokenPair = ds.usersOrderedByLastCompounded[0];
            interestRateModel.compoundInterestForUser(oldestUserTokenPair.user, oldestUserTokenPair.token);

            // Move the user-token pair to the end of the list
            uint256 lastIndex = ds.usersOrderedByLastCompounded.length - 1;
            for (uint256 i = 0; i < lastIndex; i++) {
                ds.usersOrderedByLastCompounded[i] = ds.usersOrderedByLastCompounded[i + 1];
            }
            ds.usersOrderedByLastCompounded[lastIndex] = oldestUserTokenPair;

            compoundedCount++;
        }

        // Reward the caller based on how many users had their interest compounded
        uint256 totalReward = compoundedCount * ds.baseRewardAmount;
        rewardCaller(msg.sender, totalReward);
    }

    // --------------------------------------------------------------------------------------------- INTERNAL ---------------------------------------------------------------------------------------

    /**
     * @dev Grants the STAKED_TRADER_ROLE to a user.
     * @param _user The address of the user.
     */
    function grantStakedTraderRole(address _user) internal {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();

        // Fetch the facet address for the grantRole function
        bytes4 grantRoleSelector = bytes4(keccak256("grantRole(bytes32,address)"));
        address roleManagementFacetAddress = ds.facets[grantRoleSelector];

        // Create an instance of IRoleManagement for roleManagementFacetAddress
        IRoleManagement roleManagement = IRoleManagement(roleManagementFacetAddress);
        roleManagement.grantRole(RoleConstants.STAKED_TRADER_ROLE, _user);
    }

    /**
     * @dev Revokes the STAKED_TRADER_ROLE from a user.
     * @param _user The address of the user.
     */
    function revokeStakedTraderRole(address _user) internal {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();

        // Fetch the facet address for the revokeRole function
        bytes4 revokeRoleSelector = bytes4(keccak256("revokeRole(bytes32,address)"));
        address roleManagementFacetAddress = ds.facets[revokeRoleSelector];

        // Create an instance of IRoleManagement for roleManagementFacetAddress
        IRoleManagement roleManagement = IRoleManagement(roleManagementFacetAddress);
        roleManagement.revokeRole(RoleConstants.STAKED_TRADER_ROLE, _user);
    }

    /**
     * @dev Rewards the caller for performing certain actions.
     * @param _caller The address of the caller.
     * @param _rewardAmount The amount of ETH to reward the caller.
     */
    function rewardCaller(address _caller, uint256 _rewardAmount) internal {
        require(address(this).balance >= _rewardAmount, "Not enough ETH in contract to reward caller");
        payable(_caller).transfer(_rewardAmount);
    }

    /**
     * @dev Updates staking rewards for a user and token.
     * @param _user The address of the user.
     * @param _tokenAddress The address of the token.
     */
    function updateStakingRewards(address _user, address _tokenAddress) internal {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        LibDiamond.StakingRewards storage rewards = ds.stakingRewards[_user][_tokenAddress];

        uint256 timeElapsed = block.number - rewards.lastUpdated;
        
        uint256 newRewards = timeElapsed * (rewards.stakedAmount + ds.marginAccounts[_user].balance[_tokenAddress]) * ds.stakingRewardRate;

        rewards.rewards += newRewards;
        rewards.lastUpdated = block.number;
    }

    /**
     * @dev Updates user interaction for tracking purposes.
     * @param _user The address of the user.
     * @param _token The address of the token.
     */
    function updateUserInteraction(address _user, address _token) internal {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        
        ds.userToTokenLastCompounded[_user][_token] = block.number;

        LibDiamond.UserTokenPair memory newUserTokenPair = LibDiamond.UserTokenPair({
            user: _user,
            token: _token
        });
        ds.usersOrderedByLastCompounded.push(newUserTokenPair);
    }

    /**
     * @notice Checks if the user's collateral ratio is sufficient for borrowing.
     * @param _token The address of the token to check.
     * @param _borrowAmount The amount of tokens to borrow.
     * @param _user The address of the user.
     * @return sufficient Whether the collateral ratio is sufficient or not.
     */    
    function checkCollateralRatio(address _token, uint256 _borrowAmount, address _user) internal view returns (bool sufficient) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        bytes4 getPriceSelector = bytes4(keccak256("getPrice(address)"));
        address priceOracleFacetAddress = ds.facets[getPriceSelector];

        // Fetch the price of the borrowed token
        uint256 borrowPrice = PriceOracleFacet(priceOracleFacetAddress).getPrice(_token);

        // Calculate the value of the new borrow including existing borrowings
        uint256 existingBorrowValue = ds.marginAccounts[_user].borrowed * borrowPrice;
        uint256 newBorrowValue = borrowPrice * _borrowAmount;
        uint256 totalBorrowValue = existingBorrowValue + newBorrowValue;

        // Sum up the value of all types of collateral
        uint256 totalCollateralValue = 0;
        for (uint256 i = 0; i < ds.lendingPools[_user].userCollateralTokens.length; i++) {
            address collateralToken = ds.lendingPools[_user].userCollateralTokens[i];
            uint256 collateralPrice = PriceOracleFacet(priceOracleFacetAddress).getPrice(collateralToken);
            uint256 collateralAmount = ds.collateral[_user][collateralToken];
            totalCollateralValue = totalCollateralValue + (collateralPrice * collateralAmount);
        }

        // Calculate the new collateral ratio
        uint256 collateralRatio = totalCollateralValue / totalBorrowValue;

        // Compare the new collateral ratio to the minimum ratio
        sufficient = collateralRatio >= ds.MIN_COLLATERAL_RATIO;
    }

    /**
     * @notice Checks and revokes the staked trader role if the user does not hold any tokens.
     */
    function checkStakedTokenHoldings() internal {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        address _user = msg.sender;
        uint256 stakedAmount;

        while (stakedAmount == 0) {
            for (uint256 i = 0; i < ds.lendingPools[_user].userCollateralTokens.length; i++) {
                stakedAmount += ds.collateral[_user][ds.lendingPools[_user].userCollateralTokens[i]];
            }
        }
        if (stakedAmount > 0) {
            return;
        } else {
            revokeStakedTraderRole(_user);
        }
    } 

    /**
     * @notice Returns the minimum of two unsigned integers.
     * @param a The first integer.
     * @param b The second integer.
     * @return The smaller of the two integers.
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
    
    // --------------------------------------------------------------------------------------------- EVENTS ---------------------------------------------------------------------------------------

    /**
     * @dev Emitted when a user deposits tokens into the lending pool.
     * @param user The address of the user.
     * @param tokenAddress The address of the token.
     * @param amount The amount of tokens deposited.
     */
    event DepositToLendingPool(address indexed user, address indexed tokenAddress, uint256 amount);

    /**
     * @dev Emitted when a user withdraws tokens from the lending pool.
     * @param user The address of the user.
     * @param tokenAddress The address of the token.
     * @param amount The amount of tokens withdrawn.
     */
    event WithdrawFromLendingPool(address indexed user, address indexed tokenAddress, uint256 amount);

    /**
     * @dev Emitted when a user borrows tokens from the lending pool.
     * @param user The address of the user.
     * @param tokenAddress The address of the token.
     * @param amount The amount of tokens borrowed.
     * @param fee The fee for borrowing the tokens.
     */
    event Borrow(address indexed user, address indexed tokenAddress, uint256 amount, uint256 fee);

    /**
     * @dev Emitted when a user repays borrowed tokens to the lending pool.
     * @param user The address of the user.
     * @param tokenAddress The address of the token.
     * @param amount The amount of tokens repaid.
     */
    event Repay(address indexed user, address indexed tokenAddress, uint256 amount);

    /**
     * @dev Emitted when collateral is converted from the lending pool to the margin pool.
     * @param user The address of the user.
     * @param token The address of the token.
     * @param amountConverted The amount of tokens converted.
     */
    event CollateralConvertedToMargin(address indexed user, address token, uint256 amountConverted);
}