// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "./FacetBase.sol";
import "./ReentrancyGuardBase.sol";
import "../libraries/LibDiamond.sol";
import "../libraries/RoleConstants.sol";
import "../interfaces/IInterestRateModelFacet.sol";

/**
 * @title InterestRateModelFacet
 * @dev Manages interest rate calculations and compounding for the protocol
 * @notice Implements interest rate model with jump rates and utilization curve
 * @custom:security-contact security@koyodex.com
 */
contract InterestRateModelFacet is FacetBase, ReentrancyGuardBase, IInterestRateModelFacet {
    uint256 private constant SECONDS_PER_YEAR = 31536000;
    uint256 private constant BASIS_POINTS_DIVISOR = 10000;
    uint256 private constant OPTIMAL_UTILIZATION = 8000; // 80%
    uint256 private constant EXCESS_UTILIZATION_RATE = 2000; // 20%
    uint256 private constant SCALE = 1e18;

    /**
     * @dev Emitted when the global index is updated
     */
    event GlobalIndexUpdated(
        uint256 oldIndex,
        uint256 newIndex,
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
     * @notice Initializes the interest rate model
     * @dev Sets up initial rates and parameters
     * @param _baseRatePerYear The base interest rate per year
     * @param _multiplierPerYear The rate multiplier per year
     * @param _jumpMultiplierPerYear The jump multiplier per year
     * @param _optimal The optimal utilization rate
     * @param _reserve The reserve factor
     * @param _compoundingFrequency The frequency of compounding
     */
    function initializeInterestRate(
        uint256 _baseRatePerYear,
        uint256 _multiplierPerYear,
        uint256 _jumpMultiplierPerYear,
        uint256 _optimal,
        uint256 _reserve,
        uint256 _compoundingFrequency
    ) external onlyRole(RoleConstants.ADMIN_ROLE) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        require(!ds.initialized, "Already initialized");
        
        require(_baseRatePerYear > 0, "Base rate must be > 0");
        require(_multiplierPerYear > 0, "Multiplier must be > 0");
        require(_jumpMultiplierPerYear >= _multiplierPerYear, "Jump multiplier must be >= multiplier");
        require(_optimal <= BASIS_POINTS_DIVISOR, "Optimal must be <= 100%");
        require(_reserve <= BASIS_POINTS_DIVISOR, "Reserve must be <= 100%");
        require(_compoundingFrequency > 0, "Invalid compounding frequency");

        ds.interestRate.baseRatePerYear = _baseRatePerYear;
        ds.interestRate.multiplierPerYear = _multiplierPerYear;
        ds.interestRate.jumpMultiplierPerYear = _jumpMultiplierPerYear;
        ds.interestRate.optimal = _optimal;
        ds.interestRate.reserve = _reserve;
        ds.compoundingFrequency = _compoundingFrequency;
        ds.globalInterestIndex = SCALE;
        ds.lastInterestUpdateBlock = block.number;

        ds.initialized = true;

        emit InterestRatesUpdated(
            _baseRatePerYear,
            _multiplierPerYear,
            _jumpMultiplierPerYear,
            _optimal,
            _reserve,
            block.timestamp
        );
    }

    /**
     * @notice Updates the global interest index
     * @dev Updates the global interest index based on time elapsed and current rates
     */
    function updateGlobalIndex() public override {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        
        uint256 blocksSinceLastUpdate = block.number - ds.lastInterestUpdateBlock;
        if (blocksSinceLastUpdate > 0) {
            uint256 utilizationRate = calculateUtilizationRate();
            uint256 borrowRate = getBorrowRate(utilizationRate);
            uint256 ratePerBlock = borrowRate / SECONDS_PER_YEAR * 15; // Assuming 15 second blocks
            uint256 interestFactor = (ratePerBlock * blocksSinceLastUpdate) + SCALE;
            
            uint256 oldIndex = ds.globalInterestIndex;
            ds.globalInterestIndex = (ds.globalInterestIndex * interestFactor) / SCALE;
            ds.lastInterestUpdateBlock = block.number;

            emit GlobalIndexUpdated(
                oldIndex,
                ds.globalInterestIndex,
                block.timestamp
            );
        }
    }

    /**
     * @notice Calculates the current utilization rate
     * @return The utilization rate scaled by 1e18
     */
    function calculateUtilizationRate() public view override returns (uint256) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        
        uint256 totalBorrows = ds.lendingPools[address(ds.feeManagement.feeToken)].totalBorrowed;
        uint256 totalDeposits = ds.lendingPools[address(ds.feeManagement.feeToken)].totalDeposited;
        
        if (totalDeposits == 0) return 0;
        
        return (totalBorrows * SCALE) / totalDeposits;
    }

    /**
     * @notice Gets the borrow rate based on utilization
     * @param utilizationRate The current utilization rate
     * @return The borrow rate per year, scaled by 1e18
     */
    function getBorrowRate(uint256 utilizationRate) public view override returns (uint256) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        
        if (utilizationRate <= ds.interestRate.optimal) {
            return ds.interestRate.baseRatePerYear + 
                   (utilizationRate * ds.interestRate.multiplierPerYear) / SCALE;
        }

        uint256 normalRate = ds.interestRate.baseRatePerYear + 
                           (ds.interestRate.optimal * ds.interestRate.multiplierPerYear) / SCALE;
        
        uint256 excessUtilization = utilizationRate - ds.interestRate.optimal;
        uint256 jumpRate = (excessUtilization * ds.interestRate.jumpMultiplierPerYear) / SCALE;
        
        return normalRate + jumpRate;
    }

    /**
     * @notice Gets the current supply rate
     * @return The supply rate per year, scaled by 1e18
     */
    function getSupplyRate() public view override returns (uint256) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        
        uint256 utilizationRate = calculateUtilizationRate();
        uint256 borrowRate = getBorrowRate(utilizationRate);
        uint256 reserveFactor = SCALE - ((ds.interestRate.reserve * SCALE) / BASIS_POINTS_DIVISOR);
        
        return (utilizationRate * borrowRate * reserveFactor) / (SCALE * SCALE);
    }

    /**
     * @notice Calculates interest for a borrowed amount
     * @param _borrowedAmount The amount borrowed
     * @return The calculated interest amount
     */
    function calculateInterest(uint256 _borrowedAmount) public view override returns (uint256) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        uint256 ratePerCompound = ds.interestRateBasisPoints / ds.compoundingFrequency;
        return (_borrowedAmount * ratePerCompound) / SCALE;
    }

    /**
     * @notice Compounds interest for a user
     * @param _user The user address
     * @param _token The token address
     */
    function compoundInterestForUser(address _user, address _token) external override {
        updateGlobalIndex();
        
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        LibDiamond.UserCompoundingData storage userData = ds.userCompoundingData[_user];
        
        if (userData.lastInterestIndex == 0) {
            userData.lastInterestIndex = SCALE;
        }

        if (userData.lastInterestIndex < ds.globalInterestIndex) {
            uint256 userBorrows = ds.userBorrows[_user][_token];
            if (userBorrows > 0) {
                uint256 interestFactor = (ds.globalInterestIndex - userData.lastInterestIndex);
                uint256 interestAccrued = (userBorrows * interestFactor) / SCALE;
                
                ds.userBorrows[_user][_token] += interestAccrued;
                ds.lendingPools[_token].totalBorrowed += interestAccrued;
                
                uint256 reserveAmount = (interestAccrued * ds.interestRate.reserve) / BASIS_POINTS_DIVISOR;
                ds.lendingPools[_token].reservedForStaking += reserveAmount;

                emit InterestAccrued(
                    _token,
                    _user,
                    interestAccrued,
                    ds.userBorrows[_user][_token],
                    block.timestamp
                );
            }
            
            userData.lastInterestIndex = ds.globalInterestIndex;
        }
    }

    /**
     * @notice Gets the current global interest index
     * @return The current global interest index
     */
    function getGlobalIndex() external view returns (uint256) {
        return LibDiamond.diamondStorage().globalInterestIndex;
    }

    /**
     * @notice Returns the function selectors for this facet
     * @return selectors Array of function selectors
     */
    function getInterestRateFacetSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](8);
        selectors[0] = this.initializeInterestRate.selector;
        selectors[1] = this.updateGlobalIndex.selector;
        selectors[2] = this.calculateUtilizationRate.selector;
        selectors[3] = this.getBorrowRate.selector;
        selectors[4] = this.getSupplyRate.selector;
        selectors[5] = this.calculateInterest.selector;
        selectors[6] = this.compoundInterestForUser.selector;
        selectors[7] = this.getGlobalIndex.selector;
        return selectors;
    } 
}