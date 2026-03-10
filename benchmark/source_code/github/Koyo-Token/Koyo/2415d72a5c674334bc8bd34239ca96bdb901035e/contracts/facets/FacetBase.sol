// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "../libraries/LibDiamond.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title FacetBase
 * @dev Base contract for all facets, providing common functionality and storage access
 */
contract FacetBase {
    using Address for address;

    /**
     * @dev Error codes for common facet operations
     */
    bytes32 constant ERROR_ALREADY_INITIALIZED = keccak256("ALREADY_INITIALIZED");
    bytes32 constant ERROR_NOT_INITIALIZED = keccak256("NOT_INITIALIZED");
    bytes32 constant ERROR_INVALID_PARAMETER = keccak256("INVALID_PARAMETER");
    bytes32 constant ERROR_UNAUTHORIZED = keccak256("UNAUTHORIZED");
    bytes32 constant ERROR_PAUSED = keccak256("PAUSED");
    bytes32 constant ERROR_TOKEN_NOT_SUPPORTED = keccak256("TOKEN_NOT_SUPPORTED");

    /**
     * @dev Event emitted when a facet encounters an error
     */
    event FacetError(
        bytes32 indexed errorCode,
        string message,
        uint256 timestamp
    );

    /**
     * @dev Event emitted when a facet operation is executed
     */
    event FacetOperation(
        bytes4 indexed functionSelector,
        address indexed caller,
        uint256 timestamp
    );

    /**
     * @dev Provides access to the diamond storage instance
     * @return ds The diamond storage instance
     */
    function diamondStorage() internal pure virtual returns (LibDiamond.DiamondStorage storage ds) {
        return LibDiamond.diamondStorage();
    }

    /**
     * @dev Validates that the contract is initialized
     */
    modifier initializer() {
        LibDiamond.DiamondStorage storage ds = diamondStorage();
        require(!ds.initialized, _formatError(ERROR_ALREADY_INITIALIZED));
        ds.initialized = true;
        _;
    }

    /**
     * @dev Ensures the contract is initialized
     */
    modifier whenInitialized() {
        require(diamondStorage().initialized, _formatError(ERROR_NOT_INITIALIZED));
        _;
    }

    /**
     * @dev Ensures the contract is not paused
     */
    modifier whenNotPaused() {
        require(!diamondStorage().paused, _formatError(ERROR_PAUSED));
        _;
    }

    /**
     * @dev Validates a token is supported
     */
    modifier supportedToken(address token) {
        require(diamondStorage().isTokenSupported[token], _formatError(ERROR_TOKEN_NOT_SUPPORTED));
        _;
    }

    /**
     * @dev Logs function execution
     */
    modifier logOperation() {
        emit FacetOperation(msg.sig, msg.sender, block.timestamp);
        _;
    }

    /**
     * @dev Checks if an address is a contract
     * @param account The address to check
     * @return bool Whether the address is a contract
     */
    function isContract(address account) internal view virtual returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

    /**
     * @dev Safely transfers tokens from the contract
     * @param token The token to transfer
     * @param to The recipient address
     * @param amount The amount to transfer
     */
    function safeTransfer(
        address token,
        address to,
        uint256 amount
    ) internal {
        require(token != address(0), "Invalid token address");
        require(to != address(0), "Invalid recipient address");
        
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.transfer.selector, to, amount)
        );
        
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "Token transfer failed"
        );
    }

    /**
     * @dev Safely approves token spending
     * @param token The token to approve
     * @param spender The address to approve
     * @param amount The amount to approve
     */
    function safeApprove(
        address token,
        address spender,
        uint256 amount
    ) internal {
        require(token != address(0), "Invalid token address");
        require(spender != address(0), "Invalid spender address");
        
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.approve.selector, spender, amount)
        );
        
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "Token approval failed"
        );
    }

    /**
     * @dev Gets the current block timestamp
     * @return uint256 The current block timestamp
     */
    function getBlockTimestamp() internal view returns (uint256) {
        return block.timestamp;
    }

    /**
     * @dev Gets the current block number
     * @return uint256 The current block number
     */
    function getBlockNumber() internal view returns (uint256) {
        return block.number;
    }

    /**
     * @dev Formats an error message
     * @param errorCode The error code
     * @return string The formatted error message
     */
    function _formatError(bytes32 errorCode) internal pure returns (string memory) {
        return string(abi.encodePacked("FacetBase: ", errorCode));
    }

    /**
     * @dev Emits an error event
     * @param errorCode The error code
     * @param message The error message
     */
    function _emitError(bytes32 errorCode, string memory message) internal {
        emit FacetError(errorCode, message, block.timestamp);
    }

    /**
     * @dev Validates an address is not zero
     * @param addr The address to validate
     */
    function _validateAddress(address addr) internal pure {
        require(addr != address(0), _formatError(ERROR_INVALID_PARAMETER));
    }

    /**
     * @dev Validates an amount is not zero
     * @param amount The amount to validate
     */
    function _validateAmount(uint256 amount) internal pure {
        require(amount > 0, _formatError(ERROR_INVALID_PARAMETER));
    }

    /**
     * @dev Gets the facet address for a function selector
     * @param functionSelector The function selector
     * @return address The facet address
     */
    function _getFacetAddress(bytes4 functionSelector) internal view returns (address) {
        return diamondStorage().selectorToFacetMap[functionSelector];
    }

    /**
     * @dev Checks if a facet is registered
     * @param facetAddress The facet address
     * @return bool Whether the facet is registered
     */
    function _isFacetRegistered(address facetAddress) internal view returns (bool) {
        LibDiamond.DiamondStorage storage ds = diamondStorage();
        return ds.facetToInfoMap[facetAddress].initialized;
    }
}