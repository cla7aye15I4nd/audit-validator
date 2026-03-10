// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IDiamondCut.sol";
import "../interfaces/IDiamondLoupe.sol";
import "../interfaces/IFeeManagement.sol";
import "../interfaces/IRoleManagement.sol";

/**
 * @title LibDiamond
 * @dev Library for managing Diamond storage and operations
 */
library LibDiamond {
    /// @dev Storage slot for diamond storage
    bytes32 constant DIAMOND_STORAGE_POSITION = keccak256("diamond.standard.diamond.storage");

    /// @dev Reentrancy guard constants
    uint256 internal constant _NOT_ENTERED = 1;
    uint256 internal constant _ENTERED = 2;

    /**
     * @dev Struct for emergency withdrawal requests
     */
    struct EmergencyWithdrawal {
        address token;
        address recipient;
        uint256 amount;
        uint256 scheduledTime;
        bool executed;
    }

    /**
     * @dev Struct for circuit breaker state
     */
    struct CircuitBreaker {
        bool triggered;
        uint256 triggerTime;
        uint256 recoveryTime;
        uint256 triggerCount;
    }

    /**
     * @dev Struct for storing token information
     */
    struct TokenInfo {
        uint256 decimals;
        uint256 minCollateralRatio;
        uint256 liquidationThreshold;
        uint256 liquidationPenalty;
        bool isActive;
    }

    /**
     * @dev Struct for storing interest rate information
     */
    struct InterestRate {
        uint256 baseRatePerYear;
        uint256 multiplierPerYear;
        uint256 jumpMultiplierPerYear;
        uint256 optimal;
        uint256 reserve;
    }

    /**
     * @dev Struct for storing fee management information
     */
    struct FeeManagement {
        address feeRecipient;
        address ShibaSwapRouterAddress;
        IERC20 feeToken;
        uint256 tradingFeeBasisPoints;
        uint256 borrowingFeeBasisPoints;
        uint256 lendingFeeBasisPoints;
        uint256 liquidationFeeBasisPoints;
    }

    /**
     * @dev Struct for storing lending pool information
     */
    struct LendingPool {
        uint256 totalDeposited;
        uint256 totalBorrowed;
        uint256 reservedForStaking;
        uint256 borrowRate;
        uint256 supplyRate;
        uint256 lastUpdateBlock;
        uint256 reserveFactor;
        address[] userCollateralTokens;
    }

    /**
     * @dev Struct for storing user compounding data
     */
    struct UserCompoundingData {
        uint256 lastCompoundedBlock;
        uint256 indexInOrderedArray;
        uint256 lastInterestIndex;
    }

    /**
     * @dev Struct for storing staking rewards information
     */
    struct StakingRewards {
        uint256 lastUpdated;
        uint256 rewards;
        uint256 stakedAmount;
        uint256 rewardDebt;
    }

    /**
     * @dev Struct for storing margin account information
     */
    struct MarginAccount {
        mapping(address => uint256) balance;
        uint256 borrowed;
        uint256 lastUpdate;
        uint256 lockedMargin;
        uint256 liquidationThreshold;
    }

    /**
     * @dev Struct for storing leveraged position information
     */
    struct LeveragedPosition {
        uint256 positionId;
        uint256 entryPrice;
        uint256 size;
        uint256 leverage;
        uint256 liquidationPrice;
        bool isLong;
        bool isOpen;
        IERC20 token;
        uint256 amount;
        uint256 collateralAmount;
    }

    /**
     * @dev Struct for storing price data information
     */
    struct PriceData {
        uint256 price;
        uint256 timestamp;
        uint256 confidence;
        uint256 sources;
    }

    /**
     * @dev Struct for storing liquidation event information
     */
    struct LiquidationEvent {
        address liquidator;
        uint256 amount;
        uint256 reward;
        uint256 timestamp;
        uint256 collateralPrice;
        uint256 debtPrice;
    }

    /**
     * @dev Struct for storing token price data information
     */
    struct TokenPriceData {
        uint256[] prices;
        uint256 lastUpdated;
        uint256 heartbeat;
        uint256 deviation;
    }

    /**
     * @dev Struct representing a pending role action.
     */
    struct PendingRoleAction {
        bool isGrant;
        uint256 effectiveTime;
        bool executed;
    }

    /**
     * @dev Struct for storing facet information
     */
    struct FacetInfo {
        bytes4[] selectors;
        uint256 selectorCount;
        bool initialized;
    }

    /**
     * @dev Struct for storing diamond-related state
     */
    struct DiamondStorage {
        // Reentrancy guard status
        uint256 reentrantStatus;
        mapping(bytes32 => bool) groupReentrantStatus;
        mapping(bytes4 => bool) facetReentrantStatus;
        mapping(address => bool) criticalOperationStatus;

        // Core state
        bool initialized;
        bool paused;
        uint256 lastInitializedVersion;
        
        // Core addresses
        address WBONE;
        address shibTokenAddress;
        address dexRouterAddress;

        // Facets
        mapping(bytes4 => address) selectorToFacetMap;
        mapping(address => FacetInfo) facetToInfoMap;
        address[] facetAddresses;

        // Token Registry
        address[] supportedTokens;
        mapping(address => bool) isTokenSupported;
        mapping(address => TokenInfo) tokenInfo;

        // Interest Rate
        InterestRate interestRate;
        mapping(address => mapping(address => uint256)) userLastCompoundedBlock;
        mapping(address => mapping(address => uint256)) interestForFees;
        uint256 compoundingFrequency;
        uint256 interestRateBasisPoints;
        uint256 globalInterestIndex;
        uint256 lastInterestUpdateBlock;

        // Fee Management
        FeeManagement feeManagement;
        mapping(address => uint256) fees;
        uint256 rewardPool;

        // Fee Distribution
        uint256 shibBurnFee;
        uint256 daoFoundationFee;
        uint256 donationFee;
        uint256 rewardPoolFee;
        uint256 ecosystemFee;

        // Fee Distribution Addresses
        address shibaBurnAddress;
        address daoFoundationAddress;
        address donationAddress;
        address ecosystemAddress;

        // Lending Pool
        uint256 MIN_COLLATERAL_RATIO;
        uint256 baseRewardAmount;
        uint256 stakingRewardRate;
        mapping(address => LendingPool) lendingPools;
        mapping(address => UserCompoundingData) userCompoundingData;
        mapping(address => bool) allowedCollateralTokens;
        mapping(address => mapping(address => uint256)) userBorrowedAmounts;
        mapping(address => mapping(address => uint256)) userToTokenLastCompounded;
        mapping(address => mapping(address => StakingRewards)) stakingRewards;

        // Collateral Management
        mapping(address => mapping(address => uint256)) userDeposits;
        mapping(address => mapping(address => uint256)) userBorrows;
        mapping(address => mapping(address => uint256)) userCollateral;

        // Roles
        mapping(bytes32 => mapping(address => bool)) roles;
        mapping(bytes32 => uint256) roleMemberCount;
        mapping(bytes32 => bytes32) roleAdmins;
        mapping(bytes32 => PendingRoleAction) pendingRoleActions;

        // Margin Accounts
        address[] marginAccountsUsers;
        mapping(address => MarginAccount) marginAccounts;
        mapping(address => mapping(address => uint256)) collateral;

        // Margin Trading
        mapping(address => LeveragedPosition[]) leveragedPositions;
        mapping(address => uint256) leveragedPositionsLength;
        mapping(address => uint256) nextPositionId;
        mapping(address => uint256) tokenSlippageRates;

        // Order Matching
        mapping(uint256 => uint256) partialOrders;

        // Liquidation Engine
        mapping(address => PriceData[]) priceHistory;
        mapping(address => LiquidationEvent[]) liquidationHistory;

        // Price Oracle
        address router;
        address xfund;
        address oooDataProvider;
        uint256 oooFee;
        mapping(address => uint256) nonces;
        mapping(bytes32 => bool) pendingRequests;
        mapping(bytes32 => address) requestIdToToken;
        mapping(address => TokenPriceData) tokenPriceCache;

        // Emergency Management
        mapping(bytes32 => EmergencyWithdrawal) emergencyWithdrawals;
        mapping(bytes32 => CircuitBreaker) circuitBreakers;

        // Facet Addresses
        address emergencyManagementFacet;
        address feeManagementFacet;
        address interestRateModelFacet;
        address lendingPoolFacet;
        address priceOracleFacet;
        address marginAccountsFacet;
        address marginTradingFacet;
        address roleManagementFacet;
        address tokenRegistryFacet;
        address reentrancyGuardFacet;
    }

    /**
     * @dev Accesses the diamond storage instance
     * @return ds The diamond storage instance
     */
    function diamondStorage() internal pure returns (DiamondStorage storage ds) {
        bytes32 position = DIAMOND_STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }

    /**
     * @dev Executes a diamond cut, adding, replacing, or removing facets
     * @param _diamondCut Array of FacetCut structs defining the diamond cut actions
     * @param _init The address of the contract or facet to execute _calldata
     * @param _calldata Function call, including function selector and arguments
     */
    function diamondCut(
        IDiamondCut.FacetCut[] memory _diamondCut,
        address _init,
        bytes memory _calldata
    ) internal {
        DiamondStorage storage ds = diamondStorage();
        require(!ds.paused, "Diamond is paused");
        
        for (uint256 facetIndex; facetIndex < _diamondCut.length; facetIndex++) {
            IDiamondCut.FacetCut memory cut = _diamondCut[facetIndex];
            
            require(cut.target != address(0), "Invalid facet address");
            require(cut.target.code.length > 0, "No code at facet address");
            
            if (cut.action == IDiamondCut.FacetCutAction.Add) {
                addFacet(ds, cut.target, cut.functionSelectors);
            } else if (cut.action == IDiamondCut.FacetCutAction.Replace) {
                replaceFacet(ds, cut.target, cut.functionSelectors);
            } else if (cut.action == IDiamondCut.FacetCutAction.Remove) {
                removeFacet(ds, cut.target, cut.functionSelectors);
            } else {
                revert("Invalid facet action");
            }
        }

        emit DiamondCut(_diamondCut, _init, _calldata);

        if (_init != address(0)) {
            require(_init.code.length > 0, "Init address has no code");
            
            (bool success, bytes memory error) = _init.delegatecall(_calldata);
            if (!success) {
                if (error.length > 0) {
                    // bubble up the error
                    revert(string(error));
                } else {
                    revert("Diamond init failed");
                }
            }
        }
    }

    /**
     * @dev Adds a new facet
     * @param ds The diamond storage
     * @param _facetAddress The facet address
     * @param _selectors Array of function selectors
     */
    function addFacet(
        DiamondStorage storage ds,
        address _facetAddress,
        bytes4[] memory _selectors
    ) internal {
        require(_selectors.length > 0, "No selectors provided");
        FacetInfo storage facetInfo = ds.facetToInfoMap[_facetAddress];
        
        for (uint256 i = 0; i < _selectors.length; i++) {
            bytes4 selector = _selectors[i];
            address oldFacet = ds.selectorToFacetMap[selector];
            require(oldFacet == address(0), "Selector already exists");
            
            ds.selectorToFacetMap[selector] = _facetAddress;
            facetInfo.selectors.push(selector);
            facetInfo.selectorCount++;
        }
        
        if (!facetInfo.initialized) {
            ds.facetAddresses.push(_facetAddress);
            facetInfo.initialized = true;
        }
    }

    /**
     * @dev Replaces selectors of an existing facet
     * @param ds The diamond storage
     * @param _facetAddress The facet address
     * @param _selectors Array of function selectors
     */
    function replaceFacet(
        DiamondStorage storage ds,
        address _facetAddress,
        bytes4[] memory _selectors
    ) internal {
        require(_selectors.length > 0, "No selectors provided");
        FacetInfo storage facetInfo = ds.facetToInfoMap[_facetAddress];
        
        for (uint256 i = 0; i < _selectors.length; i++) {
            bytes4 selector = _selectors[i];
            address oldFacet = ds.selectorToFacetMap[selector];
            require(oldFacet != address(0), "Selector doesn't exist");
            require(oldFacet != _facetAddress, "Can't replace with same facet");
            
            // Remove selector from old facet
            FacetInfo storage oldFacetInfo = ds.facetToInfoMap[oldFacet];
            for (uint256 j = 0; j < oldFacetInfo.selectors.length; j++) {
                if (oldFacetInfo.selectors[j] == selector) {
                    oldFacetInfo.selectors[j] = oldFacetInfo.selectors[oldFacetInfo.selectors.length - 1];
                    oldFacetInfo.selectors.pop();
                    oldFacetInfo.selectorCount--;
                    break;
                }
            }
            
            // Add selector to new facet
            ds.selectorToFacetMap[selector] = _facetAddress;
            facetInfo.selectors.push(selector);
            facetInfo.selectorCount++;
        }
    }

    /**
     * @dev Removes selectors from a facet
     * @param ds The diamond storage
     * @param _facetAddress The facet address
     * @param _selectors Array of function selectors
     */
    function removeFacet(
        DiamondStorage storage ds,
        address _facetAddress,
        bytes4[] memory _selectors
    ) internal {
        require(_selectors.length > 0, "No selectors provided");
        FacetInfo storage facetInfo = ds.facetToInfoMap[_facetAddress];
        
        for (uint256 i = 0; i < _selectors.length; i++) {
            bytes4 selector = _selectors[i];
            address targetFacet = ds.selectorToFacetMap[selector];
            require(targetFacet == _facetAddress, "Selector not found in facet");
            
            delete ds.selectorToFacetMap[selector];
            
            for (uint256 j = 0; j < facetInfo.selectors.length; j++) {
                if (facetInfo.selectors[j] == selector) {
                    facetInfo.selectors[j] = facetInfo.selectors[facetInfo.selectors.length - 1];
                    facetInfo.selectors.pop();
                    facetInfo.selectorCount--;
                    break;
                }
            }
        }
        
        if (facetInfo.selectorCount == 0) {
            for (uint256 i = 0; i < ds.facetAddresses.length; i++) {
                if (ds.facetAddresses[i] == _facetAddress) {
                    ds.facetAddresses[i] = ds.facetAddresses[ds.facetAddresses.length - 1];
                    ds.facetAddresses.pop();
                    break;
                }
            }
            delete ds.facetToInfoMap[_facetAddress];
        }
    }

    /**
     * @dev Returns all function selectors supported by a specific facet
     * @param _facet The facet address
     * @return selectors Array of function selectors
     */
    function facetFunctionSelectors(address _facet) internal view returns (bytes4[] memory) {
        LibDiamond.DiamondStorage storage ds = diamondStorage();
        require(_facet != address(0), "LibDiamond: Invalid facet address");
        require(ds.facetToInfoMap[_facet].initialized, "LibDiamond: Facet not found");
        
        return ds.facetToInfoMap[_facet].selectors;
    }

    /**
     * @dev Returns all facet addresses used by the diamond
     * @return Array of facet addresses
     */
    function facetAddresses() internal view returns (address[] memory) {
        LibDiamond.DiamondStorage storage ds = diamondStorage();
        return ds.facetAddresses;
    }

    /**
     * @dev Returns the facet that supports the given function
     * @param _functionSelector The function selector
     * @return facetAddr The address of the facet
     */
    function facetAddress(bytes4 _functionSelector) internal view returns (address facetAddr) {
        LibDiamond.DiamondStorage storage ds = diamondStorage();
        facetAddr = ds.selectorToFacetMap[_functionSelector];
        require(facetAddr != address(0), "LibDiamond: Function does not exist");
        return facetAddr;
    }

    /**
     * @dev Returns all facets and their selectors
     * @return facets_ Array of Facet structs
     */
    function facets() internal view returns (IDiamondLoupe.Facet[] memory facets_) {
        LibDiamond.DiamondStorage storage ds = diamondStorage();
        uint256 numFacets = ds.facetAddresses.length;
        facets_ = new IDiamondLoupe.Facet[](numFacets);
        
        for (uint256 i = 0; i < numFacets; i++) {
            address currentFacet = ds.facetAddresses[i];  // Changed variable name
            facets_[i] = IDiamondLoupe.Facet({
                facetAddress: currentFacet,
                functionSelectors: ds.facetToInfoMap[currentFacet].selectors
            });
        }
        
        return facets_;
    }

    /**
     * @dev Event emitted when diamond cut is executed
     */
    event DiamondCut(IDiamondCut.FacetCut[] _diamondCut, address _init, bytes _calldata);
}