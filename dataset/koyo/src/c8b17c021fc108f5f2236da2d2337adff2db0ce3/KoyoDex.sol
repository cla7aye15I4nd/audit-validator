// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./libraries/LibDiamond.sol";
import "./libraries/RoleConstants.sol";
import "./facets/EmergencyManagementFacet.sol";
import "./facets/FeeManagementFacet.sol";
import "./facets/GovernanceFacet.sol";
import "./facets/InterestRateModelFacet.sol";
import "./facets/LendingPoolFacet.sol";
import "./facets/PriceOracleFacet.sol";
import "./facets/MarginAccountsFacet.sol";
import "./facets/MarginTradingFacet.sol";
import "./facets/RoleManagementFacet.sol";
import "./facets/TokenRegistryFacet.sol";
import "./interfaces/IDiamondCut.sol";
import "./interfaces/IDiamondLoupe.sol";
import "./interfaces/IFacetInterface.sol";

contract KoyoDex is IDiamondCut, IDiamondLoupe {
    using LibDiamond for LibDiamond.DiamondStorage;

    /// @dev Contains parameters for Fee Management.
    struct FeeManagementParams {
        uint256 tradingFeeBasisPoints;
        uint256 borrowingFeeBasisPoints;
        uint256 lendingFeeBasisPoints;
        address feeRecipient;
        IERC20 feeToken;
        address shibaSwapRouterAddress;
    }

    /// @dev Contains parameters for Interest Rate.
    struct InterestRateParams {
        uint256 baseRatePerYear;
        uint256 multiplierPerYear;
        uint256 compoundingFrequency;
    }

    /// @dev Contains parameters for Oracle.
    struct OracleParams {
        address router;
        address xfund;
        address dataProvider;
        uint256 fee;
    }

    /// @dev Contains addresses for facets.
    struct FacetAddresses {
        address emergencyManagementFacet;
        address feeManagementFacet;
        address governanceFacet;
        address interestRateModelFacet;
        address lendingPoolFacet;
        address priceOracleFacet;
        address marginAccountsFacet;
        address marginTradingFacet;
        address roleManagementFacet;
        address tokenRegistryFacet;
    }

    /**
     * @notice Constructor to initialize the KoyoDex contract.
     * @param _facetAddresses Addresses of the facets.
     * @param _feeParams Parameters for fee management.
     * @param _interestParams Parameters for interest rate.
     * @param _oracleParams Parameters for oracle.
     */
    constructor(
        FacetAddresses memory _facetAddresses,
        FeeManagementParams memory _feeParams,
        InterestRateParams memory _interestParams,
        OracleParams memory _oracleParams
    ) {
        _initializeStorage(
            _facetAddresses,
            _feeParams,
            _interestParams,
            _oracleParams
        );

        IDiamondCut.FacetCut[] memory cut = _createFacetCuts();
        LibDiamond.diamondCut(cut, address(0), "");
    }

    /**
     * @dev Internal function to initialize storage variables.
     * @param _facetAddresses Addresses of the facets.
     * @param _feeParams Parameters for fee management.
     * @param _interestParams Parameters for interest rate.
     * @param _oracleParams Parameters for oracle.
     */
    function _initializeStorage(
        FacetAddresses memory _facetAddresses,
        FeeManagementParams memory _feeParams,
        InterestRateParams memory _interestParams,
        OracleParams memory _oracleParams
    ) internal {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();

        ds.emergencyManagementFacet = _facetAddresses.emergencyManagementFacet;
        ds.feeManagementFacet = _facetAddresses.feeManagementFacet;
        ds.governanceFacet = _facetAddresses.governanceFacet;
        ds.interestRateModelFacet = _facetAddresses.interestRateModelFacet;
        ds.lendingPoolFacet = _facetAddresses.lendingPoolFacet;
        ds.priceOracleFacet = _facetAddresses.priceOracleFacet;
        ds.marginAccountsFacet = _facetAddresses.marginAccountsFacet;
        ds.marginTradingFacet = _facetAddresses.marginTradingFacet;
        ds.roleManagementFacet = _facetAddresses.roleManagementFacet;
        ds.tokenRegistryFacet = _facetAddresses.tokenRegistryFacet;

        ds.feeManagement.tradingFeeBasisPoints = _feeParams.tradingFeeBasisPoints;
        ds.feeManagement.borrowingFeeBasisPoints = _feeParams.borrowingFeeBasisPoints;
        ds.feeManagement.lendingFeeBasisPoints = _feeParams.lendingFeeBasisPoints;
        ds.feeManagement.feeRecipient = _feeParams.feeRecipient;
        ds.feeManagement.feeToken = _feeParams.feeToken;
        ds.feeManagement.ShibaSwapRouterAddress = _feeParams.shibaSwapRouterAddress;

        ds.interestRate.baseRatePerYear = _interestParams.baseRatePerYear;
        ds.interestRate.multiplierPerYear = _interestParams.multiplierPerYear;
        ds.compoundingFrequency = _interestParams.compoundingFrequency;

        ds.router = _oracleParams.router;
        ds.xfund = _oracleParams.xfund;
        ds.oooDataProvider = _oracleParams.dataProvider;
        ds.oooFee = _oracleParams.fee;
    }

    /**
     * @dev Internal function to create facet cuts.
     * @return cut Array of FacetCut struct.
     */
    function _createFacetCuts() internal view returns (IDiamondCut.FacetCut[] memory cut) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();

        cut = new IDiamondCut.FacetCut[](10);
        cut[0] = IDiamondCut.FacetCut({
            target: ds.emergencyManagementFacet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: generateFunctionSelectors(ds.emergencyManagementFacet)
        });
        cut[1] = IDiamondCut.FacetCut({
            target: ds.feeManagementFacet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: generateFunctionSelectors(ds.feeManagementFacet)
        });
        cut[2] = IDiamondCut.FacetCut({
            target: ds.governanceFacet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: generateFunctionSelectors(ds.governanceFacet)
        });
        cut[3] = IDiamondCut.FacetCut({
            target: ds.interestRateModelFacet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: generateFunctionSelectors(ds.interestRateModelFacet)
        });
        cut[4] = IDiamondCut.FacetCut({
            target: ds.lendingPoolFacet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: generateFunctionSelectors(ds.lendingPoolFacet)
        });
        cut[5] = IDiamondCut.FacetCut({
            target: ds.priceOracleFacet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: generateFunctionSelectors(ds.priceOracleFacet)
        });
        cut[6] = IDiamondCut.FacetCut({
            target: ds.marginAccountsFacet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: generateFunctionSelectors(ds.marginAccountsFacet)
        });
        cut[7] = IDiamondCut.FacetCut({
            target: ds.marginTradingFacet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: generateFunctionSelectors(ds.marginTradingFacet)
        });
        cut[8] = IDiamondCut.FacetCut({
            target: ds.roleManagementFacet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: generateFunctionSelectors(ds.roleManagementFacet)
        });
        cut[9] = IDiamondCut.FacetCut({
            target: ds.tokenRegistryFacet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: generateFunctionSelectors(ds.tokenRegistryFacet)
        });

        return cut;
    }

    /**
     * @notice Initializes the facets by calling their respective initialize functions.
     */
    function initializeFacets() external {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        require(ds.roles[RoleConstants.ADMIN_ROLE][msg.sender], "KoyoDex: Must have admin role to initialize");

        EmergencyManagementFacet(ds.emergencyManagementFacet).initialize(ds.lendingPoolFacet);
        FeeManagementFacet(ds.feeManagementFacet).initialize(ds.feeManagement.tradingFeeBasisPoints,
                                                             ds.feeManagement.borrowingFeeBasisPoints,
                                                             ds.feeManagement.lendingFeeBasisPoints,
                                                             ds.feeManagement.feeRecipient,
                                                             ds.feeManagement.feeToken,
                                                             ds.feeManagement.ShibaSwapRouterAddress);
        // GovernanceFacet(ds.governanceFacet).initialize();
        InterestRateModelFacet(ds.interestRateModelFacet).initialize(ds.interestRate.baseRatePerYear,
                                                                      ds.interestRate.multiplierPerYear,
                                                                      ds.compoundingFrequency);
        LendingPoolFacet(ds.lendingPoolFacet).initialize(ds.interestRateModelFacet, ds.feeManagementFacet);
        PriceOracleFacet(ds.priceOracleFacet).initialize(ds.router, ds.xfund, ds.oooDataProvider, ds.oooFee);
        MarginAccountFacet(ds.marginAccountsFacet).initialize(ds.feeManagementFacet, ds.lendingPoolFacet);
        MarginTradingFacet(ds.marginTradingFacet).initialize(ds.marginAccountsFacet, ds.priceOracleFacet, ds.feeManagementFacet);
        RoleManagementFacet(ds.roleManagementFacet).initialize();
        TokenRegistryFacet(ds.tokenRegistryFacet).initialize();
    }

    /**
     * @dev Internal function to generate function selectors for a given facet.
     * @param _facet The address of the facet.
     * @return selectors Array of function selectors.
     */
    function generateFunctionSelectors(address _facet) internal pure returns (bytes4[] memory selectors) {
        IFacetInterface facet = IFacetInterface(_facet);
        return facet.facetFunctionSelectors();
    }

    /**
     * @notice Fallback function to handle calls to non-existent functions.
     */
    fallback() external payable {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        address facet = ds.facets[msg.sig];
        require(facet != address(0), "LibDiamond: Function does not exist");
        LibDiamond.executeFallback();
    }

    /**
     * @notice Receive function to handle incoming Ether transfers.
     */
    receive() external payable {}

    /**
     * @notice Executes a diamond cut to add, replace, or remove facets and optionally executes a function call.
     * @param _diamondCut Array of FacetCut structs defining the diamond cut actions.
     * @param _init The address of the contract or facet to execute _calldata.
     * @param _calldata A function call, including function selector and arguments, to execute on _init after facets are cut.
     */
    function diamondCut(
        IDiamondCut.FacetCut[] calldata _diamondCut,
        address _init,
        bytes calldata _calldata
    ) external override {
        LibDiamond.diamondCut(_diamondCut, _init, _calldata);
    }

    /**
     * @notice Returns an array of all facets with their function selectors.
     * @return facets_ An array of Facet structs.
     */
    function facets() external view override returns (Facet[] memory) {
        return LibDiamond.facets();
    }

    /**
     * @notice Returns an array of function selectors supported by a specific facet.
     * @param _facet The address of the facet.
     * @return An array of function selectors.
     */
    function facetFunctionSelectors(address _facet) external view override returns (bytes4[] memory) {
        return LibDiamond.facetFunctionSelectors(_facet);
    }

    /**
     * @notice Returns an array of all facet addresses used by the diamond.
     * @return An array of facet addresses.
     */
    function facetAddresses() external view override returns (address[] memory) {
        return LibDiamond.facetAddresses();
    }

    /**
     * @notice Returns the facet address that implements a specific function.
     * @param _functionSelector The function selector.
     * @return The address of the facet that implements _functionSelector.
     */
    function facetAddress(bytes4 _functionSelector) external view override returns (address) {
        return LibDiamond.facetAddress(_functionSelector);
    }
}