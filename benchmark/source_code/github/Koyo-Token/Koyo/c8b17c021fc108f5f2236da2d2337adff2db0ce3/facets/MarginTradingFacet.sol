// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./FacetBase.sol";
import "./MarginAccountsFacet.sol";
import "./FeeManagementFacet.sol";
import "./PriceOracleFacet.sol";
import "../libraries/LibDiamond.sol";
import "../libraries/RoleConstants.sol";
import "../interfaces/IRoleManagement.sol";
import "../interfaces/IFacetInterface.sol";

/**
 * @title MarginTradingFacet
 * @dev Facet contract for managing margin trading operations within the diamond.
 */
contract MarginTradingFacet is FacetBase, ReentrancyGuard {
    FeeManagementFacet public feeManagement;
    MarginAccountFacet marginAccount;
    PriceOracleFacet public oracle;

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
     * @notice Initializes the MarginTradingFacet contract.
     * @dev Replaces the constructor. Can only be called by accounts with the ADMIN_ROLE.
     * @param _marginAccount The address of the margin account contract.
     * @param _oracle The address of the price oracle contract.
     * @param _feeManagement The address of the fee management contract.
     */
    function initializeMarginTrading(
        address _marginAccount,
        address _oracle,
        address _feeManagement
    ) external onlyRole(RoleConstants.ADMIN_ROLE) {
        require(!initialized, "Facet has already been initialized.");

        marginAccount = MarginAccountFacet(_marginAccount);
        oracle = PriceOracleFacet(_oracle);
        feeManagement = FeeManagementFacet(_feeManagement);


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
     * @notice Gets the leveraged positions for a user.
     * @param _user The address of the user.
     * @return An array of leveraged positions.
     */
    function LeveragedPositions(address _user) public view returns (LibDiamond.LeveragedPosition[] memory) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        return ds.leveragedPositions[_user];
    }

    /**
     * @notice Gets the function selectors for the facet.
     * @return An array of function selectors.
     */
    function facetFunctionSelectors() public pure returns (bytes4[] memory) {
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = this.openPosition.selector;
        selectors[1] = this.closePosition.selector;
        selectors[2] = this.LeveragedPositions.selector;
        selectors[3] = this.initializeMarginTrading.selector;
        selectors[4] = this.convertCollateralToLending.selector;
        return selectors;
    }

    // --------------------------------------------------------------------------------------------- EXTERNAL ---------------------------------------------------------------------------------------

    /**
     * @notice Converts margin trading collateral to lending pool collateral.
     * @param token The address of the token to convert.
     * @param amount The amount of tokens to convert.
     */
    function convertCollateralToLending(address token, uint256 amount) external nonReentrant onlyRole(RoleConstants.MARGIN_TRADER_ROLE) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();

        // Input validation
        require(token != address(0), "Invalid token address");
        require(amount > 0, "Amount must be positive");

        // Check for sufficient collateral and no open positions
        require(ds.marginAccounts[msg.sender].balance[token] >= amount, "Insufficient collateral");
        bool hasOpenPositions = false;
        LibDiamond.LeveragedPosition[] memory positions = LeveragedPositions(msg.sender);
        for (uint256 i = 0; i < positions.length; i++) {
            if (positions[i].isOpen) {
                hasOpenPositions = true;
                break;
            }
        }
        require(!hasOpenPositions, "Cannot convert collateral with open margin positions");

        ds.userDeposits[msg.sender][token] += amount;
        ds.lendingPools[token].totalDeposited += amount;
        ds.marginAccounts[msg.sender].balance[token] -= amount;

        emit CollateralConvertedToLending(msg.sender, token, amount);
    }

    /**
     * @notice Opens a leveraged position.
     * @param token The address of the token to trade.
     * @param amount The amount of tokens to trade.
     * @param isLong Whether the position is long (true) or short (false).
     * @param leverage The leverage multiplier for the position.
     */
    function openPosition(address token, uint256 amount, bool isLong, uint256 leverage) external nonReentrant onlyRole(RoleConstants.MARGIN_TRADER_ROLE) {
        require(leverage >= 100 && leverage <= 175, "Invalid leverage"); // Ensure valid leverage

        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        uint256 buyingPower = calculateBuyingPower(); // Leverage of deposit

        bytes4 getPriceSelector = bytes4(keccak256("getPrice(address)"));
        address priceOracleFacetAddress = ds.facets[getPriceSelector];

        uint256 tokenPriceInETH = PriceOracleFacet(priceOracleFacetAddress).getPrice(token); // Get current price of token in ETH

        uint256 costInETH = (((tokenPriceInETH * amount) * 101) / 100); // 101% of expected amount to account for 1% slippage

        // Calculate trading fee
        uint256 tradingFee = FeeManagementFacet(address(this)).calculateTradingFee(amount);
        costInETH = costInETH;
        ds.marginAccounts[msg.sender].borrowed += costInETH;
        require(((buyingPower + tradingFee) >= costInETH), "Insufficient buying power after trading fee deduction");
        
        ds.marginAccounts[msg.sender].borrowed += (costInETH + tradingFee);

        // Purchase token from open market
        DexHandler.executeEthForTokenSwap(token, costInETH, amount);
        feeManagement.collectFee(ds.WBONE, tradingFee);

        // Update user's position
        ds.nextPositionId[msg.sender] += 1;
        ds.leveragedPositions[msg.sender].push(
            LibDiamond.LeveragedPosition({
                positionId: ds.nextPositionId[msg.sender],
                entryPrice: tokenPriceInETH,
                size: amount,
                leverage: leverage,
                isLong: isLong,
                isOpen: true,
                token: IERC20(token),
                amount: amount
            })
        );
        ds.leveragedPositionsLength[msg.sender] += 1;
        
        emit PositionOpened(msg.sender, token, amount, (costInETH + tradingFee), isLong, leverage);
    }

    /**
     * @notice Closes a leveraged position.
     * @param positionId The ID of the position to close.
     */
    function closePosition(uint256 positionId) external nonReentrant onlyRole(RoleConstants.MARGIN_TRADER_ROLE) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        LibDiamond.LeveragedPosition storage userPosition = ds.leveragedPositions[msg.sender][positionId];
        require(userPosition.isOpen, "Position is already closed or doesn't exist");

        bytes4 getPriceSelector = bytes4(keccak256("getPrice(address)"));
        address priceOracleFacetAddress = ds.facets[getPriceSelector];

        // Get the current price of the token in ETH
        uint256 currentPrice = PriceOracleFacet(priceOracleFacetAddress).getPrice(address(userPosition.token)); // Adjusted for the actual function call
        uint256 expectedEthAmount = (userPosition.amount * currentPrice) / 1 ether; // Assuming price is given per 1 ether of token

        // Define acceptable slippage (e.g., 1%)
        uint256 minEthAmount = (99 * expectedEthAmount) / 100; // 99% of expected amount to account for 1% slippage

        // Sell token in open market
        uint256 receivedETH = DexHandler.executeTokenForEthSwap(address(userPosition.token), userPosition.amount, minEthAmount);

        // Calculate trading fee for the selling process
        uint256 tradingFee = FeeManagementFacet(address(this)).calculateTradingFee(userPosition.amount);
        receivedETH -= tradingFee;
        feeManagement.collectFee(ds.WBONE, tradingFee);

        // Update user's balance and close position
        ds.marginAccounts[msg.sender].balance[ds.WBONE] += receivedETH;
        userPosition.isOpen = false;

        emit PositionClosed(msg.sender, address(userPosition.token), userPosition.amount, receivedETH);
    }

    /**
     * @notice Repays all borrowed amounts.
     */
    function repayBorrowed() external payable {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        
        uint256 owedAmount = ds.marginAccounts[msg.sender].borrowed;
        
        require(msg.value == owedAmount, "Sent value does not match the total borrowed amount");
        // No need to deduct from user's balance since they're sending ETH directly in this function.

        ds.marginAccounts[msg.sender].borrowed = 0;
    }

    // --------------------------------------------------------------------------------------------- INTERNAL ---------------------------------------------------------------------------------------

    /**
     * @dev Returns the absolute value of a signed integer.
     * @param x The signed integer.
     * @return The absolute value.
     */
    function abs(int256 x) internal pure returns (uint256) {
        return x >= 0 ? uint256(x) : uint256(-x);
    }

    /**
     * @dev Grants the MARGIN_TRADER_ROLE to the specified contract.
     * @param _marginTradingContract The address of the margin trading contract.
     */
    function grantMarginTraderRole(address _marginTradingContract) internal {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();

        // Fetch the facet address for the grantRole function
        bytes4 grantRoleSelector = bytes4(keccak256("grantRole(bytes32,address)"));
        address roleManagementFacetAddress = ds.facets[grantRoleSelector];

        // Create an instance of IRoleManagement for roleManagementFacetAddress
        IRoleManagement roleManagement = IRoleManagement(roleManagementFacetAddress);
        roleManagement.grantRole(RoleConstants.MARGIN_TRADER_ROLE, _marginTradingContract);
    }

    /**
     * @dev Calculates the buying power of the user based on their collateral and borrowed amounts.
     * @return buyingPower The user's buying power.
     */
    function calculateBuyingPower() internal view returns (uint256 buyingPower) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        bytes4 getPriceSelector = bytes4(keccak256("getPrice(address)"));
        address priceOracleFacetAddress = ds.facets[getPriceSelector];

        for (uint256 i = 0; i < ds.supportedTokens.length; i++) {
            buyingPower += PriceOracleFacet(priceOracleFacetAddress).getPrice(ds.supportedTokens[i]) * ds.marginAccounts[msg.sender].balance[ds.supportedTokens[i]];
        }

        buyingPower -= ds.marginAccounts[msg.sender].borrowed;
    }

    // --------------------------------------------------------------------------------------------- EVENTS ---------------------------------------------------------------------------------------

    /**
     * @dev Emitted when a leveraged position is opened.
     * @param user The address of the user who opened the position.
     * @param token The address of the traded token.
     * @param amount The amount of the traded token.
     * @param borrowedETH The amount of ETH borrowed.
     * @param isLong Whether the position is long (true) or short (false).
     * @param leverage The leverage multiplier applied.
     */
    event PositionOpened(address indexed user, address token, uint256 amount, uint256 borrowedETH, bool isLong, uint256 leverage);

    /**
     * @dev Emitted when a leveraged position is closed.
     * @param user The address of the user who closed the position.
     * @param token The address of the traded token.
     * @param userAmount The user's amount of the token.
     * @param receivedETH The amount of ETH received.
     */
    event PositionClosed(address indexed user, address token, uint256 userAmount, uint256 receivedETH);

    /**
     * @dev Emitted when collateral is converted to lending pool collateral.
     * @param user The address of the user.
     * @param token The address of the token.
     * @param lendingAmount The amount converted to lending pool collateral.
     */
    event CollateralConvertedToLending(address indexed user, address token, uint256 lendingAmount);
}