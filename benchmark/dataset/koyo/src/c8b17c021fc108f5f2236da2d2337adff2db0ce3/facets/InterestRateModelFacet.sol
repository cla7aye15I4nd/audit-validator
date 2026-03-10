// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "./FacetBase.sol";
import "../interfaces/IFacetInterface.sol";
import "../libraries/RoleConstants.sol";
import "../libraries/LibDiamond.sol";

/**
 * @title InterestRateModelFacet
 * @dev Facet contract for managing interest rates within the diamond.
 */
contract InterestRateModelFacet is FacetBase, IFacetInterface {

    // State variable to check if the contract has been initialized
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
     * @notice Initializes the InterestRateModelFacet contract.
     * @dev Can only be called by accounts with the ADMIN_ROLE.
     * @param _baseRatePerYear The base rate per year.
     * @param _multiplierPerYear The multiplier per year.
     * @param _compoundingFrequency The compounding frequency in blocks.
     */
    function initializeInterestRate(uint256 _baseRatePerYear, uint256 _multiplierPerYear, uint256 _compoundingFrequency) external onlyRole(RoleConstants.ADMIN_ROLE) {
        LibDiamond.DiamondStorage storage ds = diamondStorage();
        require(!initialized, "InterestRateModelFacet: Already initialized");
        require(_baseRatePerYear > 0, "Base rate per year should be greater than 0");
        require(_multiplierPerYear > 0, "Multiplier per year should be greater than 0");

        ds.interestRate.baseRatePerYear = _baseRatePerYear;
        ds.interestRate.multiplierPerYear = _multiplierPerYear;
        ds.compoundingFrequency = _compoundingFrequency;

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
     * @notice Calculates the interest for a borrowed amount.
     * @param _borrowedAmount The amount borrowed.
     * @return interest The interest calculated for the borrowed amount.
     */
    function calculateInterest(uint256 _borrowedAmount) public view returns (uint256 interest) {
        LibDiamond.DiamondStorage storage ds = diamondStorage();
        uint256 secondsInYear = 31536000;
        uint256 interestPerSecond = ds.interestRateBasisPoints * 10 ** 18 * secondsInYear;
        interest = _borrowedAmount * interestPerSecond / 10 ** 18;
    }

    /**
     * @notice Gets the borrow rate based on the utilization rate.
     * @param utilizationRate The current utilization rate.
     * @return borrowRate The borrow rate in basis points.
     */
    function getBorrowRate(uint256 utilizationRate) public view returns (uint256 borrowRate) {
        LibDiamond.DiamondStorage storage ds = diamondStorage();
        require(utilizationRate >= 0, "Utilization rate should be greater than or equal to 0");
        borrowRate = ds.interestRate.baseRatePerYear + (utilizationRate * ds.interestRate.multiplierPerYear) / 1e18;
    }

    /**
     * @notice Gets the function selectors for the facet.
     * @return selectors An array of function selectors.
     */
    function facetFunctionSelectors() public pure override returns (bytes4[] memory selectors) {
        selectors = new bytes4[](5);
        selectors[0] = this.calculateInterest.selector;
        selectors[1] = this.getBorrowRate.selector;
        selectors[2] = this.setInterestRateBasisPoints.selector;
        selectors[3] = this.compoundInterestForUser.selector;
        selectors[4] = this.initializeInterestRate.selector;
    }

    // --------------------------------------------------------------------------------------------- EXTERNAL ---------------------------------------------------------------------------------------

    /**
     * @notice Sets the interest rate in basis points.
     * @dev Can only be called by accounts with the ADMIN_ROLE.
     * @param _interestRateBasisPoints The interest rate in basis points.
     */
    function setInterestRateBasisPoints(uint256 _interestRateBasisPoints) external onlyRole(RoleConstants.ADMIN_ROLE) {
        LibDiamond.DiamondStorage storage ds = diamondStorage();
        ds.interestRateBasisPoints = _interestRateBasisPoints;
    }

    /**
     * @notice Compounds interest for a user's token holdings.
     * @param _user The address of the user.
     * @param _token The address of the token.
     */
    function compoundInterestForUser(address _user, address _token) external {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();

        // Fetch the last block when the user's interest for this token was compounded
        uint256 lastCompoundedBlock = ds.userLastCompoundedBlock[_user][_token];
        uint256 blocksSinceLast = block.number - lastCompoundedBlock;

        if (blocksSinceLast >= ds.compoundingFrequency) {
            uint256 timesToCompound = blocksSinceLast / ds.compoundingFrequency;
            uint256 owed = ds.userBorrows[_user][_token];

            // Get the borrow rate for the token (we'll have to fetch it from InterestRateModelFacet)
            uint256 utilizationRate = (ds.lendingPools[_token].totalBorrowed * 1e18) / ds.lendingPools[_token].totalDeposited;
            uint256 borrowRate = getBorrowRate(utilizationRate);

            for (uint256 i = 0; i < timesToCompound; i++) {
                uint256 interest = (owed * borrowRate) / 1e18;
                owed += interest;
            }

            ds.userBorrows[_user][_token] = owed;
            ds.userLastCompoundedBlock[_user][_token] = block.number;
        }

        emit InterestCompounded(_user, ds.userBorrows[_user][_token], ds.userLastCompoundedBlock[_user][_token]);
    }

    // --------------------------------------------------------------------------------------------- EVENTS ---------------------------------------------------------------------------------------

    /**
     * @dev Emitted when interest is compounded for a user.
     * @param User The address of the user.
     * @param BorrowedAmount The new borrowed amount after compounding.
     * @param LastCompoundedBlock The block number when interest was last compounded.
     */
    event InterestCompounded(address indexed User, uint256 indexed BorrowedAmount, uint256 indexed LastCompoundedBlock);
}