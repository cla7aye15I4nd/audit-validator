// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "./FacetBase.sol";
import "./ReentrancyGuardBase.sol";
import "../libraries/LibDiamond.sol";
import "../libraries/RoleConstants.sol";
import "../interfaces/IPriceOracleFacet.sol";
import "@unification-com/xfund-router/contracts/interfaces/IRouter.sol";
import "@unification-com/xfund-router/contracts/interfaces/IERC20_Ex.sol";

/**
 * @title PriceOracleFacet
 * @dev Manages price feeds and aggregation for the protocol
 * @notice Implements price oracle functionality with TWAP, heartbeat checks, and circuit breakers
 * @custom:security-contact security@koyodex.com
 */
contract PriceOracleFacet is FacetBase, ReentrancyGuardBase, IPriceOracleFacet {
    uint256 private constant SCALE = 1e18;
    uint256 private constant MAX_PRICE_DEVIATION = 1000; // 10%
    uint256 private constant MIN_PRICE_AGE = 5 minutes;
    uint256 private constant MAX_PRICE_AGE = 60 minutes;
    uint256 private constant MIN_SOURCES = 2;
    uint256 private constant CACHE_SIZE = 10;
    uint256 private constant PRICE_PRECISION = 1e8;

    /**
     * @dev Modifier that checks if the caller has the specified role
     */
    modifier onlyRole(bytes32 role) {
        require(LibDiamond.diamondStorage().roles[role][msg.sender], "Must have required role");
        _;
    }

    /**
     * @notice Initializes the price oracle
     * @param _router The address of the oracle router
     * @param _xfund The address of the xFUND token
     * @param _dataProvider The address of the data provider
     * @param _fee The fee for oracle requests
     * @param _heartbeat The heartbeat interval
     * @param _deviation The maximum allowed deviation
     */
    function initializePriceOracle(
        address _router,
        address _xfund,
        address _dataProvider,
        uint256 _fee,
        uint256 _heartbeat,
        uint256 _deviation
    ) external onlyRole(RoleConstants.ADMIN_ROLE) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        require(!ds.initialized, "Already initialized");
        
        require(_router != address(0), "Invalid router");
        require(_xfund != address(0), "Invalid xfund");
        require(_dataProvider != address(0), "Invalid data provider");
        require(_fee > 0, "Invalid fee");
        require(_heartbeat >= MIN_PRICE_AGE && _heartbeat <= MAX_PRICE_AGE, "Invalid heartbeat");
        require(_deviation > 0 && _deviation <= MAX_PRICE_DEVIATION, "Invalid deviation");

        ds.router = _router;
        ds.xfund = _xfund;
        ds.oooDataProvider = _dataProvider;
        ds.oooFee = _fee;
        ds.initialized = true;

        ds.roles[RoleConstants.OOO_ROUTER_ROLE][_router] = true;

        emit PriceFeedUpdated(address(0), _heartbeat, _deviation, MIN_SOURCES);
    }

    /**
     * @notice Sets the OOO router address
     * @param _router The new router address
     */
    function setOOORouter(address _router) external override onlyRole(RoleConstants.ADMIN_ROLE) {
        require(_router != address(0), "Invalid router");
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        
        if (ds.router != address(0)) {
            ds.roles[RoleConstants.OOO_ROUTER_ROLE][ds.router] = false;
        }

        ds.router = _router;
        ds.roles[RoleConstants.OOO_ROUTER_ROLE][_router] = true;
    }

    /**
     * @notice Sets the OOO data provider
     * @param _dataProvider The new data provider address
     */
    function setOOODataProvider(address _dataProvider) external override onlyRole(RoleConstants.ADMIN_ROLE) {
        require(_dataProvider != address(0), "Invalid data provider");
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        ds.oooDataProvider = _dataProvider;
    }

    /**
     * @notice Sets the OOO fee
     * @param _fee The new fee amount
     */
    function setOOOFee(uint256 _fee) external override onlyRole(RoleConstants.ADMIN_ROLE) {
        require(_fee > 0, "Invalid fee");
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        ds.oooFee = _fee;
    }

    /**
     * @notice Updates the cached price for a token
     * @param _token The token address
     * @param _price The new price
     */
    function updateCachedPrice(
        address _token,
        uint256 _price
    ) public override onlyRole(RoleConstants.PRICE_MANAGER) {
        require(_price > 0, "Invalid price");
        
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        LibDiamond.TokenPriceData storage priceData = ds.tokenPriceCache[_token];

        require(
            block.timestamp - priceData.lastUpdated <= priceData.heartbeat,
            "Price update too old"
        );

        // Check deviation if there are existing prices
        if (priceData.prices.length > 0) {
            uint256 lastPrice = priceData.prices[0]; // Most recent price is at index 0
            uint256 deviation = calculateDeviation(_price, lastPrice);
            require(deviation <= priceData.deviation, "Price deviation too high");

            if (deviation >= MAX_PRICE_DEVIATION) {
                emit CircuitBreaker(_token, lastPrice, _price, deviation);
                return;
            }
        }

        // Shift prices right and add new price at index 0 (FIFO)
        if (priceData.prices.length == CACHE_SIZE) {
            for (uint256 i = CACHE_SIZE - 1; i > 0; i--) {
                priceData.prices[i] = priceData.prices[i - 1];
            }
            priceData.prices[0] = _price;
        } else {
            // If cache isn't full, add new slot at beginning
            uint256 currentLength = priceData.prices.length;
            priceData.prices.push();
            for (uint256 i = currentLength; i > 0; i--) {
                priceData.prices[i] = priceData.prices[i - 1];
            }
            priceData.prices[0] = _price;
        }

        priceData.lastUpdated = block.timestamp;

        emit PriceUpdated(_token, _price, block.timestamp, SCALE, MIN_SOURCES);
    }

    /**
     * @notice Requests prices for all supported tokens
     */
    function requestAllPrices() external override onlyRole(RoleConstants.PRICE_MANAGER) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();

        for (uint256 i = 0; i < ds.supportedTokens.length; i++) {
            address tokenAddress = ds.supportedTokens[i];
            bytes32 data = keccak256(abi.encodePacked("PRICE", tokenAddress));
            bytes32 requestId = _requestData(ds.oooDataProvider, ds.oooFee, data);
            ds.pendingRequests[requestId] = true;
            ds.requestIdToToken[requestId] = tokenAddress;
            
            emit PriceRequested(tokenAddress, requestId, block.timestamp);
        }
    }

    /**
     * @notice Gets the current price of a token
     * @param _token The token address
     * @return The current price
     */
    function getPrice(address _token) external view override returns (uint256) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        LibDiamond.TokenPriceData storage priceData = ds.tokenPriceCache[_token];

        require(priceData.prices.length > 0, "No price data");
        require(
            block.timestamp - priceData.lastUpdated <= priceData.heartbeat,
            "Price too old"
        );

        return getAveragePrice(_token);
    }

    /**
     * @notice Gets the average price of a token
     * @param _token The token address
     * @return The average price
     */
    function getAveragePrice(address _token) public view override returns (uint256) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        LibDiamond.TokenPriceData storage priceData = ds.tokenPriceCache[_token];

        require(priceData.prices.length > 0, "No price data");

        uint256 sum = 0;
        for (uint256 i = 0; i < priceData.prices.length; i++) {
            sum += priceData.prices[i];
        }

        return sum / priceData.prices.length;
    }

    /**
     * @notice Checks if a price is stale
     * @param _token The token address
     * @return Whether the price is stale
     */
    function isPriceStale(address _token) external view override returns (bool) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        LibDiamond.TokenPriceData storage priceData = ds.tokenPriceCache[_token];

        return block.timestamp - priceData.lastUpdated > priceData.heartbeat;
    }

    /**
     * @notice Handles raw price data from the oracle
     * @param _price The received price
     * @param _requestId The request ID
     */
    function rawReceiveData(
        uint256 _price,
        bytes32 _requestId
    ) external override onlyRole(RoleConstants.OOO_ROUTER_ROLE) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        require(ds.pendingRequests[_requestId], "Request not found");

        address token = ds.requestIdToToken[_requestId];
        require(token != address(0), "Invalid token");

        updateCachedPrice(token, _price);

        delete ds.pendingRequests[_requestId];
        delete ds.requestIdToToken[_requestId];
    }

    /**
     * @notice Returns the function selectors for this facet
     * @return selectors Array of function selectors
     */
    function getOracleFacetSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](11);
        selectors[0] = this.initializePriceOracle.selector;
        selectors[1] = this.setOOORouter.selector;
        selectors[2] = this.setOOODataProvider.selector;
        selectors[3] = this.setOOOFee.selector;
        selectors[4] = this.requestAllPrices.selector;
        selectors[5] = this.updateCachedPrice.selector;
        selectors[6] = this.getPrice.selector;
        selectors[7] = this.getAveragePrice.selector;
        selectors[8] = this.isPriceStale.selector;
        selectors[9] = this.rawReceiveData.selector;
        selectors[10] = this.calculateDeviation.selector;
        return selectors;
    }

    /**
     * @notice Calculates the deviation between two prices
     * @param price1 The first price
     * @param price2 The second price
     * @return The calculated deviation
     */
    function calculateDeviation(
        uint256 price1,
        uint256 price2
    ) public pure returns (uint256) {
        if (price1 > price2) {
            return ((price1 - price2) * SCALE) / price2;
        }
        return ((price2 - price1) * SCALE) / price2;
    }

    /**
     * @notice Requests price data from the oracle
     * @param dataProvider The data provider address
     * @param fee The fee for the request
     * @param data The request data
     * @return requestId The generated request ID
     */
    function _requestData(
        address dataProvider,
        uint256 fee,
        bytes32 data
    ) internal returns (bytes32 requestId) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();

        requestId = keccak256(
            abi.encodePacked(
                address(this),
                dataProvider,
                ds.router,
                ds.nonces[dataProvider],
                data
            )
        );

        require(
            IRouter(ds.router).initialiseRequest(dataProvider, fee, data),
            "Request initialization failed"
        );

        ds.nonces[dataProvider]++;

        return requestId;
    }
}