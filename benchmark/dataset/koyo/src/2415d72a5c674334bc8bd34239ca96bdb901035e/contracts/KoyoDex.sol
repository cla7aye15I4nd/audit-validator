// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "./libraries/LibDiamond.sol";
import "./libraries/RoleConstants.sol";
import "./facets/EmergencyManagementFacet.sol";
import "./facets/FeeManagementFacet.sol";
import "./facets/InterestRateModelFacet.sol";
import "./facets/LendingPoolFacet.sol";
import "./facets/PriceOracleFacet.sol";
import "./facets/MarginAccountsFacet.sol";
import "./facets/MarginTradingFacet.sol";
import "./facets/RoleManagementFacet.sol";
import "./facets/TokenRegistryFacet.sol";
import "./facets/ReentrancyGuardFacet.sol";
import "./interfaces/IDiamondCut.sol";
import "./interfaces/IDiamondLoupe.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title KoyoDex
 * @dev Main contract implementing diamond pattern for upgradeable DeFi protocol
 */
contract KoyoDex is IDiamondCut, IDiamondLoupe {
    /**
     * @dev Struct containing parameters for Fee Management
     */
    struct FeeManagementParams {
        uint256 tradingFeeBasisPoints;
        uint256 borrowingFeeBasisPoints;
        uint256 lendingFeeBasisPoints;
        uint256 liquidationFeeBasisPoints;
        address feeRecipient;
        IERC20 feeToken;
        address shibaSwapRouterAddress;
    }

    /**
     * @dev Struct containing parameters for Interest Rate
     */
    struct InterestRateParams {
        uint256 baseRatePerYear;
        uint256 multiplierPerYear;
        uint256 jumpMultiplierPerYear;
        uint256 optimal;
        uint256 reserve;
        uint256 compoundingFrequency;
    }

    /**
     * @dev Struct containing parameters for Oracle
     */
    struct OracleParams {
        address router;
        address xfund;
        address dataProvider;
        uint256 fee;
        uint256 heartbeat;
        uint256 deviation;
    }

    /**
     * @dev Struct containing addresses for facets
     */
    struct FacetAddresses {
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
     * @dev Event emitted when diamond is initialized
     */
    event DiamondInitialized(uint256 version);

    /**
     * @dev Event emitted when facets are initialized
     */
    event FacetsInitialized(address indexed initializer);

    /**
     * @dev Modifier that checks if the caller has the specified role
     * @param role The role required to execute the function
     */
    modifier onlyRole(bytes32 role) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        require(ds.roles[role][msg.sender], "KoyoDex: Must have required role");
        _;
    }

    /**
     * @dev Constructor to initialize the KoyoDex contract
     * @param _facetAddresses Addresses of the facets
     * @param _feeParams Parameters for fee management
     * @param _interestParams Parameters for interest rate
     * @param _oracleParams Parameters for oracle
     */
    constructor(
        FacetAddresses memory _facetAddresses,
        FeeManagementParams memory _feeParams,
        InterestRateParams memory _interestParams,
        OracleParams memory _oracleParams
    ) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        
        require(!ds.initialized, "KoyoDex: Already initialized");
        
        ds.initialized = true;
        ds.lastInitializedVersion = 1;
        ds.roles[RoleConstants.ADMIN_ROLE][msg.sender] = true;
        ds.roleMemberCount[RoleConstants.ADMIN_ROLE] = 1;

        _initializeStorage(
            _facetAddresses,
            _feeParams,
            _interestParams,
            _oracleParams
        );

        IDiamondCut.FacetCut[] memory cut = _createFacetCuts(_facetAddresses);
        LibDiamond.diamondCut(cut, address(0), "");

        emit DiamondInitialized(1);
    }

    /**
     * @dev Internal function to initialize storage variables
     */
    function _initializeStorage(
        FacetAddresses memory _facetAddresses,
        FeeManagementParams memory _feeParams,
        InterestRateParams memory _interestParams,
        OracleParams memory _oracleParams
    ) internal {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();

        // Store facet addresses
        ds.emergencyManagementFacet = _facetAddresses.emergencyManagementFacet;
        ds.feeManagementFacet = _facetAddresses.feeManagementFacet;
        ds.interestRateModelFacet = _facetAddresses.interestRateModelFacet;
        ds.lendingPoolFacet = _facetAddresses.lendingPoolFacet;
        ds.priceOracleFacet = _facetAddresses.priceOracleFacet;
        ds.marginAccountsFacet = _facetAddresses.marginAccountsFacet;
        ds.marginTradingFacet = _facetAddresses.marginTradingFacet;
        ds.roleManagementFacet = _facetAddresses.roleManagementFacet;
        ds.tokenRegistryFacet = _facetAddresses.tokenRegistryFacet;
        ds.reentrancyGuardFacet = _facetAddresses.reentrancyGuardFacet;

        // Initialize fee management
        ds.feeManagement.tradingFeeBasisPoints = _feeParams.tradingFeeBasisPoints;
        ds.feeManagement.borrowingFeeBasisPoints = _feeParams.borrowingFeeBasisPoints;
        ds.feeManagement.lendingFeeBasisPoints = _feeParams.lendingFeeBasisPoints;
        ds.feeManagement.liquidationFeeBasisPoints = _feeParams.liquidationFeeBasisPoints;
        ds.feeManagement.feeRecipient = _feeParams.feeRecipient;
        ds.feeManagement.feeToken = _feeParams.feeToken;
        ds.feeManagement.ShibaSwapRouterAddress = _feeParams.shibaSwapRouterAddress;

        // Initialize interest rate
        ds.interestRate.baseRatePerYear = _interestParams.baseRatePerYear;
        ds.interestRate.multiplierPerYear = _interestParams.multiplierPerYear;
        ds.interestRate.jumpMultiplierPerYear = _interestParams.jumpMultiplierPerYear;
        ds.interestRate.optimal = _interestParams.optimal;
        ds.interestRate.reserve = _interestParams.reserve;
        ds.compoundingFrequency = _interestParams.compoundingFrequency;
        ds.lastInterestUpdateBlock = block.number;
        ds.globalInterestIndex = 1e18;

        // Initialize oracle
        ds.router = _oracleParams.router;
        ds.xfund = _oracleParams.xfund;
        ds.oooDataProvider = _oracleParams.dataProvider;
        ds.oooFee = _oracleParams.fee;

        // Initialize protocol parameters
        ds.MIN_COLLATERAL_RATIO = 150; // 150% collateralization ratio
        ds.baseRewardAmount = 0.01 ether;
        ds.stakingRewardRate = 100; // 1% annual rate
        ds.reentrantStatus = LibDiamond._NOT_ENTERED;
    }

    /**
     * @dev Internal function to create facet cuts
     * @return cut Array of FacetCut struct
     */
    function _createFacetCuts(FacetAddresses memory _facetAddresses) internal pure returns (IDiamondCut.FacetCut[] memory cut) {
        cut = new IDiamondCut.FacetCut[](10);

        cut[0] = IDiamondCut.FacetCut({
            target: _facetAddresses.emergencyManagementFacet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: _generateSelectors(_facetAddresses.emergencyManagementFacet)
        });

        cut[1] = IDiamondCut.FacetCut({
            target: _facetAddresses.feeManagementFacet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: _generateSelectors(_facetAddresses.feeManagementFacet)
        });

        cut[2] = IDiamondCut.FacetCut({
            target: _facetAddresses.interestRateModelFacet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: _generateSelectors(_facetAddresses.interestRateModelFacet)
        });

        cut[3] = IDiamondCut.FacetCut({
            target: _facetAddresses.lendingPoolFacet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: _generateSelectors(_facetAddresses.lendingPoolFacet)
        });

        cut[4] = IDiamondCut.FacetCut({
            target: _facetAddresses.priceOracleFacet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: _generateSelectors(_facetAddresses.priceOracleFacet)
        });

        cut[5] = IDiamondCut.FacetCut({
            target: _facetAddresses.marginAccountsFacet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: _generateSelectors(_facetAddresses.marginAccountsFacet)
        });

        cut[6] = IDiamondCut.FacetCut({
            target: _facetAddresses.marginTradingFacet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: _generateSelectors(_facetAddresses.marginTradingFacet)
        });

        cut[7] = IDiamondCut.FacetCut({
            target: _facetAddresses.roleManagementFacet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: _generateSelectors(_facetAddresses.roleManagementFacet)
        });

        cut[8] = IDiamondCut.FacetCut({
            target: _facetAddresses.tokenRegistryFacet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: _generateSelectors(_facetAddresses.tokenRegistryFacet)
        });

        cut[9] = IDiamondCut.FacetCut({
            target: _facetAddresses.reentrancyGuardFacet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: _generateSelectors(_facetAddresses.reentrancyGuardFacet)
        });

        return cut;
    }

    /**
     * @dev Internal function to generate function selectors for a facet
     * @param _facet The address of the facet
     * @return selectors Array of function selectors
     */
    function _generateSelectors(address _facet) internal pure returns (bytes4[] memory) {
        try EmergencyManagementFacet(_facet).getEmergencyFacetSelectors() returns (bytes4[] memory selectors) {
            return selectors;
        } catch {}
        
        try FeeManagementFacet(_facet).getFeeFacetSelectors() returns (bytes4[] memory selectors) {
            return selectors;
        } catch {}
        
        try InterestRateModelFacet(_facet).getInterestRateFacetSelectors() returns (bytes4[] memory selectors) {
            return selectors;
        } catch {}
        
        try LendingPoolFacet(_facet).getLendingPoolFacetSelectors() returns (bytes4[] memory selectors) {
            return selectors;
        } catch {}
        
        try PriceOracleFacet(_facet).getOracleFacetSelectors() returns (bytes4[] memory selectors) {
            return selectors;
        } catch {}
        
        try MarginAccountsFacet(_facet).getMarginAccountsFacetSelectors() returns (bytes4[] memory selectors) {
            return selectors;
        } catch {}
        
        try MarginTradingFacet(_facet).getMarginTradingFacetSelectors() returns (bytes4[] memory selectors) {
            return selectors;
        } catch {}
        
        try RoleManagementFacet(_facet).getRoleFacetSelectors() returns (bytes4[] memory selectors) {
            return selectors;
        } catch {}
        
        try TokenRegistryFacet(_facet).getTokenRegistryFacetSelectors() returns (bytes4[] memory selectors) {
            return selectors;
        } catch {}
        
        try ReentrancyGuardFacet(_facet).getReentrancyGuardFacetSelectors() returns (bytes4[] memory selectors) {
            return selectors;
        } catch {}

        revert("KoyoDex: Unknown facet");
    }

    /**
     * @dev Executes a diamond cut to add, replace, or remove facets
     * @param _diamondCut Array of FacetCut structs defining the diamond cut actions
     * @param _init The address of the contract to execute _calldata
     * @param _calldata A function call, including function selector and arguments
     */
    function diamondCut(
        IDiamondCut.FacetCut[] calldata _diamondCut,
        address _init,
        bytes calldata _calldata
    ) external override onlyRole(RoleConstants.ADMIN_ROLE) {
        LibDiamond.diamondCut(_diamondCut, _init, _calldata);
    }

    /**
     * @dev Returns all facets and their selectors
     * @return facets_ An array of Facet structs
     */
    function facets() external view override returns (IDiamondLoupe.Facet[] memory) {
        return LibDiamond.facets();
    }

    /**
     * @dev Returns all function selectors supported by a specific facet
     * @param _facet The address of the facet
     * @return An array of function selectors
     */
    function facetFunctionSelectors(address _facet) external view override returns (bytes4[] memory) {
        return LibDiamond.facetFunctionSelectors(_facet);
    }

    /**
     * @dev Returns all facet addresses used by the diamond
     * @return An array of facet addresses
     */
    function facetAddresses() external view override returns (address[] memory) {
        return LibDiamond.facetAddresses();
    }

    /**
     * @dev Returns the facet that supports the given function
     * @param _functionSelector The function selector
     * @return The address of the facet
     */
    function facetAddress(bytes4 _functionSelector) external view override returns (address) {
        return LibDiamond.facetAddress(_functionSelector);
    }

    /**
     * @dev Fallback function that delegates calls to facets
     */
    fallback() external payable {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        address facet = ds.selectorToFacetMap[msg.sig];
        require(facet != address(0), "KoyoDex: Function does not exist");

        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), facet, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }

    /**
     * @dev Receive function to accept ETH
     */
    receive() external payable {}
}