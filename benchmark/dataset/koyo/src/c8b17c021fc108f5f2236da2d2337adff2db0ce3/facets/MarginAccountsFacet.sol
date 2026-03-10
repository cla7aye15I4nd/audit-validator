// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./FacetBase.sol";
import "./FeeManagementFacet.sol";
import "./LendingPoolFacet.sol";
import "./PriceOracleFacet.sol";
import "../libraries/RoleConstants.sol";
import "../libraries/LibDiamond.sol";
import "../libraries/DexHandler.sol";
import "../interfaces/IRoleManagement.sol";
import "../interfaces/IFacetInterface.sol";

/**
 * @title MarginAccountFacet
 * @dev Facet contract for managing margin accounts within the diamond.
 */
contract MarginAccountFacet is FacetBase, ReentrancyGuard {
    FeeManagementFacet public feeManagement;
    LendingPoolFacet public lendingPool;

    bool internal initialized = false;
    uint256 lastCheckedIndex;

    uint256 public constant MIN_GAS_REQUIREMENT = 50000;

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
     * @notice Initializes the MarginAccountFacet contract.
     * @dev Can only be called by accounts with the ADMIN_ROLE.
     * @param _feeManagement The address of the fee management contract.
     * @param _lendingPool The address of the lending pool contract.
     */
    function initializeMarginAccounts(address _feeManagement, address _lendingPool) external onlyRole(RoleConstants.ADMIN_ROLE) {
        require(!initialized, "Facet has already been initialized.");
        feeManagement = FeeManagementFacet(_feeManagement);
        lendingPool = LendingPoolFacet(_lendingPool);

        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        ds.facet.selectorCount = 0; // Initialize selectorCount to 0

        ds.roles[RoleConstants.MARGIN_TRADING_FACET_ROLE][address(this)] = true;

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
     * @notice Gets the balances of the user's margin account.
     * @return tokens The array of token addresses.
     * @return balances The array of token balances.
     * @return totalAmount The total amount of all token balances.
     */
    function getBalances() public view returns (address[] memory tokens, uint256[] memory balances, uint256 totalAmount) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();

        for(uint256 i = 0; i < ds.supportedTokens.length; i++) {
            tokens[i] = ds.supportedTokens[i];
            balances[i] = ds.marginAccounts[msg.sender].balance[tokens[i]];
            totalAmount += balances[i];
        }

        return (tokens, balances, totalAmount);
    }
    
    /**
     * @notice Gets the function selectors for the facet.
     * @return selectors An array of function selectors.
     */
    function facetFunctionSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](5);
        selectors[0] = this.deposit.selector;
        selectors[1] = this.withdraw.selector;
        selectors[2] = this.getBalances.selector;
        selectors[3] = this.userLiquidityCheck.selector;
        selectors[4] = this.initializeMarginAccounts.selector;
    }
    
    // --------------------------------------------------------------------------------------------- EXTERNAL ---------------------------------------------------------------------------------------

    /**
     * @notice Deposits tokens into the margin account.
     * @param token The address of the token to deposit.
     * @param amount The amount of tokens to deposit.
     */
    function deposit(address token, uint256 amount) public nonReentrant {
        // Fetch Diamond storage
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();

        // Check if the token is supported
        require(ds.isTokenSupported[token], "Token not supported");

        // Update the user's margin balance
        ds.marginAccounts[msg.sender].balance[token] += amount;
        ds.marginAccountsUsers.push(msg.sender);

        // Grant Margin Trader Role
        grantMarginTraderRole(msg.sender);

        emit Deposited(msg.sender, token, amount);
    }

    /**
     * @notice Withdraws tokens from the user's margin account balance.
     * @param token The address of the token to withdraw.
     * @param amount The amount of tokens to withdraw.
     */
    function withdraw(address token, uint256 amount) external nonReentrant onlyRole(RoleConstants.MARGIN_TRADER_ROLE) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        uint256 userBalance = ds.marginAccounts[msg.sender].balance[token];
        require(userBalance >= amount, "Insufficient balance");
        require(ds.marginAccounts[msg.sender].borrowed == 0, "Must pay off outstanding loan before withdrawing");
        
        // Update user's balance
        ds.marginAccounts[msg.sender].balance[token] -= amount;
        
        // Send token to the user
        IERC20(token).transfer(msg.sender, amount);

        (, , uint256 totalAmount) = getBalances(); // Check if user has any deposited tokens remaining
        if(totalAmount == 0) {
            revokeMarginTraderRole(msg.sender);
        }

        // Emit an event
        emit Withdrawn(msg.sender, amount);
    }

    /**
     * @notice Performs a liquidity check on users and potentially liquidates them.
     */
    function userLiquidityCheck() external nonReentrant {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        require(ds.usersOrderedByLastCompounded.length > 0, "No users available");

        uint256 initialGas = gasleft();
        uint256 userCount = 0;
        bool liquidate;

        while(gasleft() > initialGas - MIN_GAS_REQUIREMENT && !liquidate) {
            
            liquidate = shouldLiquidate(ds.marginAccountsUsers[lastCheckedIndex]);
            lastCheckedIndex++;
            userCount++;
        }

        if(liquidate) {
            liquidateUser(ds.marginAccountsUsers[lastCheckedIndex]);
        }

        // Reward the caller based on how many users had their interest compounded
        uint256 totalReward = userCount * ds.baseRewardAmount;
        rewardCaller(msg.sender, totalReward);
    }

    // --------------------------------------------------------------------------------------------- INTERNAL ---------------------------------------------------------------------------------------

    /**
     * @dev Grants the MARGIN_TRADER_ROLE to a user.
     * @param user The address of the user.
     */
    function grantMarginTraderRole(address user) internal {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();

        // Fetch the facet address for the grantRole function
        bytes4 grantRoleSelector = bytes4(keccak256("grantRole(bytes32,address)"));
        address roleManagementFacetAddress = ds.facets[grantRoleSelector];

        // Create an instance of IRoleManagement for roleManagementFacetAddress
        IRoleManagement roleManagement = IRoleManagement(roleManagementFacetAddress);
        roleManagement.grantRole(RoleConstants.MARGIN_TRADER_ROLE, user);
    }

    /**
     * @dev Liquidates a user's account if their collateral value is insufficient.
     * @param _user The address of the user to liquidate.
     */
    function liquidateUser(address _user) internal {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();

        uint256 collateralRepaid;
        uint256 tradingFee;
        
        for(uint256 i = 0; i < ds.supportedTokens.length; i++) {
            bytes4 getPriceSelector = bytes4(keccak256("getPrice(address)"));
            address priceOracleFacetAddress = ds.facets[getPriceSelector];

            // Get the current price of the token in ETH
            uint256 currentPrice = PriceOracleFacet(priceOracleFacetAddress).getPrice(address(ds.supportedTokens[i])); // Adjusted for the actual function call
            uint256 expectedEthAmount = (ds.marginAccounts[_user].balance[ds.supportedTokens[i]] * currentPrice) / 1 ether; // Assuming price is given per 1 ether of token

            // Define acceptable slippage (e.g., 1%)
            uint256 minEthAmount = (99 * expectedEthAmount) / 100; // 99% of expected amount to account for 1% slippage

            // Sell token in open market
            uint256 receivedETH = DexHandler.executeTokenForEthSwap(address(ds.supportedTokens[i]), ds.marginAccounts[_user].balance[ds.supportedTokens[i]], minEthAmount);

            // Calculate trading fee for the selling process
            tradingFee = FeeManagementFacet(address(this)).calculateTradingFee(ds.marginAccounts[_user].balance[ds.supportedTokens[i]]);
            collateralRepaid = receivedETH - tradingFee;
        }
        feeManagement.collectFee(ds.WBONE, tradingFee);
    }

    /**
     * @dev Revokes the MARGIN_TRADER_ROLE from a user.
     * @param user The address of the user.
     */
    function revokeMarginTraderRole(address user) internal {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();

        // Fetch the facet address for the grantRole function
        bytes4 grantRoleSelector = bytes4(keccak256("grantRole(bytes32,address)"));
        address roleManagementFacetAddress = ds.facets[grantRoleSelector];

        // Create an instance of IRoleManagement for roleManagementFacetAddress
        IRoleManagement roleManagement = IRoleManagement(roleManagementFacetAddress);
        roleManagement.revokeRole(RoleConstants.MARGIN_TRADER_ROLE, user);
    }

    /**
     * @dev Checks if a user's account should be liquidated based on their collateral value.
     * @param _accountToCheck The address of the user to check.
     * @return liquidate True if the user's account should be liquidated, false otherwise.
     */
    function shouldLiquidate(address _accountToCheck) internal view returns(bool liquidate) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        
        uint256 collateralValue;
        
        for(uint256 i = 0; i < ds.supportedTokens.length; i++) {
            bytes4 getPriceSelector = bytes4(keccak256("getPrice(address)"));
            address priceOracleFacetAddress = ds.facets[getPriceSelector];

            // Get the current price of the token in ETH
            uint256 currentPrice = PriceOracleFacet(priceOracleFacetAddress).getPrice(ds.supportedTokens[i]); // Adjusted for the actual function call
            uint256 expectedEthAmount = (ds.marginAccounts[_accountToCheck].balance[ds.supportedTokens[i]] * currentPrice) / 1 ether; // Assuming price is given per 1 ether of token

            // Define acceptable slippage (e.g., 1%)
            collateralValue += (95 * expectedEthAmount) / 100; // 95% of expected amount to account for slippage and fees
        }

        liquidate = collateralValue < ds.marginAccounts[_accountToCheck].borrowed;

        return liquidate;
    }

    /**
     * @dev Rewards the caller for performing liquidation or user check actions.
     * @param _caller The address of the caller.
     * @param _rewardAmount The amount of ETH to reward the caller.
     */
    function rewardCaller(address _caller, uint256 _rewardAmount) internal {
        require(address(this).balance >= _rewardAmount, "Not enough ETH in contract to reward caller");
        payable(_caller).transfer(_rewardAmount);
    }

    // --------------------------------------------------------------------------------------------- EVENTS ---------------------------------------------------------------------------------------

    /**
     * @dev Emitted when a user deposits tokens into the margin account.
     * @param user The address of the user.
     * @param token The address of the deposited token.
     * @param depositedAmount The amount of tokens deposited.
     */
    event Deposited(address indexed user, address indexed token, uint256 depositedAmount);

    /**
     * @dev Emitted when a user withdraws tokens from the margin account.
     * @param user The address of the user.
     * @param amount The amount of tokens withdrawn.
     */
    event Withdrawn(address indexed user, uint256 amount);

    /**
     * @dev Emitted when a user borrows tokens from the margin account.
     * @param user The address of the user.
     * @param tokenAddress The address of the borrowed token.
     * @param amount The amount of tokens borrowed.
     * @param fee The fee for the borrow transaction.
     */
    event Borrow(address indexed user, address indexed tokenAddress, uint256 amount, uint256 fee);

    /**
     * @dev Emitted when a user repays borrowed tokens to the margin account.
     * @param user The address of the user.
     * @param tokenAddress The address of the repaid token.
     * @param amount The amount of tokens repaid.
     */
    event Repay(address indexed user, address indexed tokenAddress, uint256 amount);
}