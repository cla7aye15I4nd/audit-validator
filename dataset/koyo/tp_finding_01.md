# `userLiquidityCheck()` WIll Not Be Able To Liquidate Users If They Pass Check Once


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🔴 Critical |
| Triage Verdict | ✅ Valid |
| Project ID | `234c8620-4de2-11ef-8bdf-012e5d16c648` |
| Commit | `c8b17c021fc108f5f2236da2d2337adff2db0ce3` |

## Location

- **Local path:** `./src/c8b17c021fc108f5f2236da2d2337adff2db0ce3/facets/MarginAccountsFacet.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/234c8620-4de2-11ef-8bdf-012e5d16c648/source?file=$/github/Koyo-Token/Koyo/c8b17c021fc108f5f2236da2d2337adff2db0ce3/facets/MarginAccountsFacet.sol
- **Lines:** 158–181

## Description

The function `userLiquidityCheck()` is designed to be called by entities to check through users and liquidate them if they are eligible for liquidation. A user's address is pushed to `marginAccountsUsers[]` whenever they make a deposit and the logic checks `ds.marginAccountsUsers[lastCheckedIndex]`, where `lastCheckedIndex` is a global variable that is increased by 1 whenever a user's liquidity is checked and they are not eligible for liquidation. However, this index is never decreased and thus will only check each user's liquidity once if they are not currently eligible for liquidation.

## Recommendation

We recommend refactoring the liquidation check and process to ensure that users can be liquidated whenever their collateralization ratio becomes too high. In addition, we recommend not having a check that continually iterates through all users as this consumes a large amount of gas that the caller must then be rewarded for.

## Vulnerable Code

```
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
```
