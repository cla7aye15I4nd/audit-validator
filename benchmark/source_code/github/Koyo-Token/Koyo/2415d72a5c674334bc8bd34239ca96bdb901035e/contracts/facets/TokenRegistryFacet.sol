// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../libraries/LibDiamond.sol";
import "../libraries/RoleConstants.sol";
import "./FacetBase.sol";
import "./ReentrancyGuardBase.sol";
import "../interfaces/IPriceOracleFacet.sol";

/**
 * @title TokenRegistryFacet
 * @dev Manages the registration and configuration of supported tokens
 */
contract TokenRegistryFacet is FacetBase, ReentrancyGuardBase {
    uint256 private constant MAX_TOKENS = 100;
    uint256 private constant MIN_DECIMALS = 6;
    uint256 private constant MAX_DECIMALS = 18;
    uint256 private constant DEFAULT_LIQUIDATION_THRESHOLD = 8000; // 80%
    uint256 private constant DEFAULT_LIQUIDATION_PENALTY = 500; // 5%
    uint256 private constant SCALE = 1e18;

    event TokenAdded(
        address indexed token,
        string name,
        string symbol,
        uint256 decimals,
        uint256 minCollateralRatio,
        uint256 timestamp
    );

    event TokenRemoved(
        address indexed token,
        uint256 timestamp
    );

    event TokenParametersUpdated(
        address indexed token,
        uint256 minCollateralRatio,
        uint256 liquidationThreshold,
        uint256 liquidationPenalty,
        uint256 timestamp
    );

    event TokenStatusUpdated(
        address indexed token,
        bool isActive,
        uint256 timestamp
    );

    modifier onlyRole(bytes32 role) {
        require(LibDiamond.diamondStorage().roles[role][msg.sender], "Must have required role");
        _;
    }

    modifier validToken(address token) {
        require(token != address(0), "Invalid token address");
        require(isContract(token), "Token must be a contract");
        _;
    }

    function initializeTokenRegistry() external onlyRole(RoleConstants.ADMIN_ROLE) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        require(!ds.initialized, "Already initialized");
        ds.initialized = true;
    }

    function addToken(
        address token,
        uint256 minCollateralRatio,
        uint256 liquidationThreshold,
        uint256 liquidationPenalty
    ) external nonReentrant onlyRole(RoleConstants.TOKEN_ADMIN_ROLE) validToken(token) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        require(!ds.isTokenSupported[token], "Token already supported");
        require(ds.supportedTokens.length < MAX_TOKENS, "Max tokens reached");
        
        IERC20Metadata tokenContract = IERC20Metadata(token);
        uint256 decimals = tokenContract.decimals();
        require(decimals >= MIN_DECIMALS && decimals <= MAX_DECIMALS, "Invalid decimals");

        require(minCollateralRatio > liquidationThreshold, "Invalid collateral ratio");
        require(liquidationThreshold > 0 && liquidationThreshold < 10000, "Invalid liquidation threshold");
        require(liquidationPenalty > 0 && liquidationPenalty < 2000, "Invalid liquidation penalty");

        ds.supportedTokens.push(token);
        ds.isTokenSupported[token] = true;

        LibDiamond.TokenInfo storage tokenInfo = ds.tokenInfo[token];
        tokenInfo.decimals = decimals;
        tokenInfo.minCollateralRatio = minCollateralRatio;
        tokenInfo.liquidationThreshold = liquidationThreshold;
        tokenInfo.liquidationPenalty = liquidationPenalty;
        tokenInfo.isActive = true;

        emit TokenAdded(
            token,
            tokenContract.name(),
            tokenContract.symbol(),
            decimals,
            minCollateralRatio,
            block.timestamp
        );
    }

    function removeToken(
        address token
    ) external nonReentrant onlyRole(RoleConstants.TOKEN_ADMIN_ROLE) validToken(token) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        require(ds.isTokenSupported[token], "Token not supported");
        require(ds.lendingPools[token].totalDeposited == 0, "Token has deposits");
        require(ds.lendingPools[token].totalBorrowed == 0, "Token has borrows");

        for (uint256 i = 0; i < ds.supportedTokens.length; i++) {
            if (ds.supportedTokens[i] == token) {
                ds.supportedTokens[i] = ds.supportedTokens[ds.supportedTokens.length - 1];
                ds.supportedTokens.pop();
                break;
            }
        }

        delete ds.isTokenSupported[token];
        delete ds.tokenInfo[token];
        delete ds.lendingPools[token];

        emit TokenRemoved(token, block.timestamp);
    }

    function updateTokenParameters(
        address token,
        uint256 minCollateralRatio,
        uint256 liquidationThreshold,
        uint256 liquidationPenalty
    ) external nonReentrant onlyRole(RoleConstants.TOKEN_ADMIN_ROLE) validToken(token) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        require(ds.isTokenSupported[token], "Token not supported");

        require(minCollateralRatio > liquidationThreshold, "Invalid collateral ratio");
        require(liquidationThreshold > 0 && liquidationThreshold < 10000, "Invalid liquidation threshold");
        require(liquidationPenalty > 0 && liquidationPenalty < 2000, "Invalid liquidation penalty");

        LibDiamond.TokenInfo storage tokenInfo = ds.tokenInfo[token];
        tokenInfo.minCollateralRatio = minCollateralRatio;
        tokenInfo.liquidationThreshold = liquidationThreshold;
        tokenInfo.liquidationPenalty = liquidationPenalty;

        emit TokenParametersUpdated(
            token,
            minCollateralRatio,
            liquidationThreshold,
            liquidationPenalty,
            block.timestamp
        );
    }

    function updateTokenStatus(
        address token,
        bool isActive
    ) external nonReentrant onlyRole(RoleConstants.TOKEN_ADMIN_ROLE) validToken(token) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        require(ds.isTokenSupported[token], "Token not supported");

        ds.tokenInfo[token].isActive = isActive;

        emit TokenStatusUpdated(token, isActive, block.timestamp);
    }

    function getTokenInfo(
        address token
    ) external view returns (
        uint256 decimals,
        uint256 minCollateralRatio,
        uint256 liquidationThreshold,
        uint256 liquidationPenalty,
        bool isActive
    ) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        require(ds.isTokenSupported[token], "Token not supported");

        LibDiamond.TokenInfo storage tokenInfo = ds.tokenInfo[token];
        return (
            tokenInfo.decimals,
            tokenInfo.minCollateralRatio,
            tokenInfo.liquidationThreshold,
            tokenInfo.liquidationPenalty,
            tokenInfo.isActive
        );
    }

    function getSupportedTokens() external view returns (
        address[] memory tokens,
        bool[] memory isActive
    ) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        tokens = ds.supportedTokens;
        isActive = new bool[](tokens.length);
        
        for (uint256 i = 0; i < tokens.length; i++) {
            isActive[i] = ds.tokenInfo[tokens[i]].isActive;
        }
    }

    function getTokenRegistryFacetSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](7);
        selectors[0] = this.initializeTokenRegistry.selector;
        selectors[1] = this.addToken.selector;
        selectors[2] = this.removeToken.selector;
        selectors[3] = this.updateTokenParameters.selector;
        selectors[4] = this.updateTokenStatus.selector;
        selectors[5] = this.getTokenInfo.selector;
        selectors[6] = this.getSupportedTokens.selector;
        return selectors;
    }

    function isContract(address addr) internal view virtual override returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }
}