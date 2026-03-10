// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@unification-com/xfund-router/contracts/lib/ConsumerBase.sol";
import "@unification-com/xfund-router/contracts/interfaces/IRouter.sol";
import "@unification-com/xfund-router/contracts/interfaces/IERC20_Ex.sol";
import "../libraries/LibDiamond.sol";
import "../libraries/RoleConstants.sol";
import "../interfaces/IFacetInterface.sol";

/**
 * @title PriceOracleFacet
 * @dev Facet contract for managing price oracle operations within the diamond.
 */
contract PriceOracleFacet {
    uint256 public constant CACHE_SIZE = 10; // Maximum size of the price cache
    bool internal initialized = false;

    /**
     * @dev Modifier that checks if the caller has the specified role.
     * @param role The role identifier.
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
     * @notice Initializes the PriceOracleFacet contract.
     * @dev Can only be called by accounts with the ADMIN_ROLE.
     * @param _router The address of the router contract.
     * @param _xfund The address of the xFund token contract.
     * @param _dataProvider The address of the data provider.
     * @param _fee The fee for the data request.
     */
    function initializePriceOracle(
        address _router, 
        address _xfund, 
        address _dataProvider, 
        uint256 _fee
    ) external onlyRole(RoleConstants.ADMIN_ROLE) {
        require(!initialized, "PriceOracleFacet: Already initialized.");

        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        
        // Manually set the state variables that the ConsumerBase's constructor would have set
        ds.router = address(IRouter(_router));
        ds.xfund = address(IERC20_Ex(_xfund));
        ds.oooDataProvider = _dataProvider;
        ds.oooFee = _fee; 

        setRouter(_router); // Since your facet has setRouter, call it to set the router address

        // Assign OOO_ROUTER_ROLE to the router address
        ds.roles[RoleConstants.OOO_ROUTER_ROLE][_router] = true;

        initialized = true;
    }

    /**
     * @notice Requests prices for all supported tokens.
     * @dev Can only be called by accounts with the PRICE_MANAGER role.
     */
    function requestAllPrices() public onlyRole(RoleConstants.PRICE_MANAGER) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        
        // Iterate over all supported tokens and request their prices
        for (uint256 i = 0; i < ds.supportedTokens.length; i++) {
            address tokenAddress = ds.supportedTokens[i];
            bytes32 data = keccak256(abi.encodePacked("PRICE", tokenAddress));  // Create a unique data request for the token price
            bytes32 requestId = requestData(ds.oooDataProvider, ds.oooFee, data);
            ds.pendingRequests[requestId] = true;
        }
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
     * @notice Updates the cached price for a token.
     * @dev Can only be called by accounts with the PRICE_MANAGER role.
     * @param _token The address of the token.
     * @param _price The new price to cache.
     */
    function updateCachedPrice(address _token, uint256 _price) public onlyRole(RoleConstants.PRICE_MANAGER) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        if (ds.tokenPriceCache[_token].prices.length == CACHE_SIZE) {
            // Remove the oldest price if cache size is exceeded
            ds.tokenPriceCache[_token].prices.pop();
        }
        ds.tokenPriceCache[_token].prices.push(_price);
        ds.tokenPriceCache[_token].lastUpdated = block.timestamp;
    }

    /**
     * @notice Gets the average price of a token.
     * @param _token The address of the token.
     * @return The average price.
     */
    function getAveragePrice(address _token) public view returns (uint256) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        uint256[] memory prices = ds.tokenPriceCache[_token].prices;
        require(prices.length > 0, "No prices cached");

        uint256 total = 0;
        for (uint256 i = 0; i < prices.length; i++) {
            total += prices[i];
        }

        return total / prices.length;
    }

    /**
     * @notice Checks if the price of a token is stale.
     * @param _token The address of the token.
     * @return True if the price is stale, false otherwise.
     */
    function isPriceStale(address _token) public view returns (bool) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        uint256 STALE_THRESHOLD = 1 hours;  // Adjust as needed
        return block.timestamp - ds.tokenPriceCache[_token].lastUpdated > STALE_THRESHOLD;
    }

    /**
     * @notice Gets the most recent price of a token, ensuring it's not stale.
     * @param _token The address of the token.
     * @return The most recent price.
     */
    function getPrice(address _token) public view returns (uint256) {
        require(!isPriceStale(_token), "Price is stale");
        return getAveragePrice(_token);
    }

    /**
     * @notice Gets the function selectors for the facet.
     * @return An array of function selectors.
     */
    function facetFunctionSelectors() public pure returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = this.requestAllPrices.selector;
        selectors[1] = this.setOOORouter.selector;
        selectors[2] = this.setOOODataProvider.selector;
        selectors[3] = this.setOOOFee.selector;
        selectors[4] = this.initializePriceOracle.selector;
        return selectors;
    }

    // --------------------------------------------------------------------------------------------- EXTERNAL ---------------------------------------------------------------------------------------

    /**
     * @notice Sets the address of the On-Chain Oracle (OOO) router.
     * @dev Can only be called by accounts with the ADMIN_ROLE.
     * @param _router The address of the OOO router.
     */
    function setOOORouter(address _router) external onlyRole(RoleConstants.ADMIN_ROLE) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        
        // Remove the OOO_ROUTER_ROLE from the previous router if it exists
        if (ds.router != address(0)) {
            ds.roles[RoleConstants.OOO_ROUTER_ROLE][ds.router] = false;
        }

        // Assign OOO_ROUTER_ROLE to the new router address
        ds.router = _router;
        ds.roles[RoleConstants.OOO_ROUTER_ROLE][_router] = true;

        setRouter(_router);
    }

    /**
     * @notice Sets the address of the On-Chain Oracle (OOO) data provider.
     * @dev Can only be called by accounts with the ADMIN_ROLE.
     * @param _dataProvider The address of the OOO data provider.
     */
    function setOOODataProvider(address _dataProvider) external onlyRole(RoleConstants.ADMIN_ROLE) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        ds.oooDataProvider = _dataProvider;
    }

    /**
     * @notice Sets the fee for the On-Chain Oracle (OOO) data request.
     * @dev Can only be called by accounts with the ADMIN_ROLE.
     * @param _fee The fee for the data request.
     */
    function setOOOFee(uint256 _fee) external onlyRole(RoleConstants.ADMIN_ROLE) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        ds.oooFee = _fee;
    }

    /**
     * @notice Handles the receipt of raw price data from the oracle.
     * @dev Can only be called by the address with OOO_ROUTER_ROLE.
     * @param price The received price.
     * @param requestId The request ID associated with the price data.
     */
    function rawReceiveData(uint256 price, bytes32 requestId) external onlyRole(RoleConstants.OOO_ROUTER_ROLE) {
        receiveData(price, requestId);
    }

    // --------------------------------------------------------------------------------------------- INTERNAL ---------------------------------------------------------------------------------------

    /**
     * @dev Processes the received data and updates the cached price.
     * @param _price The received price.
     * @param _requestId The request ID associated with the price data.
     */
    function receiveData(uint256 _price, bytes32 _requestId) internal {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        require(ds.pendingRequests[_requestId], "Request not found");

        // Update the cached price
        updateCachedPrice(msg.sender, _price);

        delete ds.pendingRequests[_requestId];
    }

    /**
     * @dev Requests price data from the oracle.
     * @param dataProvider The address of the data provider.
     * @param fee The fee for the data request.
     * @param data The data request payload.
     * @return requestId The generated request ID.
     */
    function requestData(address dataProvider, uint256 fee, bytes32 data) internal returns (bytes32 requestId) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();

        // Create request ID using the same logic as in RequestIdBase.makeRequestId()
        requestId = keccak256(abi.encodePacked(address(this), dataProvider, ds.router, ds.nonces[dataProvider], data));

        // Call the Router contract's initialiseRequest() function
        require(IRouter(ds.router).initialiseRequest(dataProvider, fee, data), "Initialization of data request failed");
        
        // Increment the nonce for the next request
        ds.nonces[dataProvider] = ds.nonces[dataProvider] += 1;

        // Handle the pending request by storing request ID
        ds.pendingRequests[requestId] = true;

        return requestId;
    }

    /**
     * @dev Sets the address of the router contract.
     * @param newRouter The address of the new router.
     */
    function setRouter(address newRouter) internal {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        
        // Validate new router address
        require(newRouter != address(0), "router cannot be the zero address");
        
        // Update the router address in diamond storage
        ds.router = newRouter;
    }

    // --------------------------------------------------------------------------------------------- EVENTS ---------------------------------------------------------------------------------------
}