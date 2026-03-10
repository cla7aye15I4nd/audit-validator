// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

/**
 * @title IPriceOracleFacet
 * @dev Interface for managing price feeds and aggregation
 * @notice Defines the interface for price oracle operations with proper validation and updates
 */
interface IPriceOracleFacet {
    /**
     * @dev Emitted when a price is updated
     */
    event PriceUpdated(
        address indexed token,
        uint256 price,
        uint256 timestamp,
        uint256 confidence,
        uint256 sources
    );

    /**
     * @dev Emitted when price feed parameters are updated
     */
    event PriceFeedUpdated(
        address indexed token,
        uint256 heartbeat,
        uint256 deviation,
        uint256 minSources
    );

    /**
     * @dev Emitted when a price request is initiated
     */
    event PriceRequested(
        address indexed token,
        bytes32 indexed requestId,
        uint256 timestamp
    );

    /**
     * @dev Emitted when circuit breaker is triggered
     */
    event CircuitBreaker(
        address indexed token,
        uint256 oldPrice,
        uint256 newPrice,
        uint256 deviation
    );

    /**
     * @notice Initializes the price oracle
     * @param _router The oracle router address
     * @param _xfund The xFUND token address
     * @param _dataProvider The data provider address
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
    ) external;

    /**
     * @notice Sets the OOO router address
     * @param _router The new router address
     */
    function setOOORouter(address _router) external;

    /**
     * @notice Sets the OOO data provider
     * @param _dataProvider The new data provider address
     */
    function setOOODataProvider(address _dataProvider) external;

    /**
     * @notice Sets the OOO fee
     * @param _fee The new fee amount
     */
    function setOOOFee(uint256 _fee) external;

    /**
     * @notice Updates the cached price for a token
     * @param _token The token address
     * @param _price The new price
     */
    function updateCachedPrice(address _token, uint256 _price) external;

    /**
     * @notice Requests prices for all supported tokens
     */
    function requestAllPrices() external;

    /**
     * @notice Gets the current price of a token
     * @param _token The token address
     * @return The current price
     */
    function getPrice(address _token) external view returns (uint256);

    /**
     * @notice Gets the average price of a token
     * @param _token The token address
     * @return The average price
     */
    function getAveragePrice(address _token) external view returns (uint256);

    /**
     * @notice Checks if a price is stale
     * @param _token The token address
     * @return Whether the price is stale
     */
    function isPriceStale(address _token) external view returns (bool);

    /**
     * @notice Handles raw price data from the oracle
     * @param _price The received price
     * @param _requestId The request ID
     */
    function rawReceiveData(uint256 _price, bytes32 _requestId) external;
}