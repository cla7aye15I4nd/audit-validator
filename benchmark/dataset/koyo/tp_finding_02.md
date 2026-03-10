# `_updateInterest()` is called after `userBorrows` update


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🔴 Critical |
| Triage Verdict | ✅ Valid |
| Project ID | `b4af2580-e772-11ef-b757-b39dfeac56e5` |
| Commit | `2415d72a5c674334bc8bd34239ca96bdb901035e` |

## Location

- **Local path:** `./src/2415d72a5c674334bc8bd34239ca96bdb901035e/contracts/facets/LendingPoolFacet.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/b4af2580-e772-11ef-b757-b39dfeac56e5/source?file=$/github/Koyo-Token/Koyo/2415d72a5c674334bc8bd34239ca96bdb901035e/contracts/facets/LendingPoolFacet.sol
- **Lines:** 309–309

## Description

```sol=305
        ds.userBorrows[msg.sender][token] += totalAmount;
        ds.lendingPools[token].totalBorrowed += totalAmount;

        // Update interest tracking
        _updateInterest(msg.sender, token);
```
`LendingPoolFacet.borrow()` updates `userBorrows` before calling `_updateInterest()`. As a result, the interest will be accrued for the borrow that was just taken.

```sol=188
        if (userData.lastInterestIndex == 0) {
            userData.lastInterestIndex = SCALE;
        }

        if (userData.lastInterestIndex < ds.globalInterestIndex) {
            uint256 userBorrows = ds.userBorrows[_user][_token];
            if (userBorrows > 0) {
                uint256 interestFactor = (ds.globalInterestIndex - userData.lastInterestIndex);
                uint256 interestAccrued = (userBorrows * interestFactor) / SCALE;
```
In `InterestRateModelFacet.compoundInterestForUser()` if the interest index is calculated for the first time for the user, the value is initialized with `SCALE`. This practically means that the user will pay interest from the moment of project deployment.

## Recommendation

We recommend updating the interest before updating of the `userBorrows`, `lastInterestIndex` should be initialized with `globalInterestIndex`.

## Vulnerable Code

```
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
```
