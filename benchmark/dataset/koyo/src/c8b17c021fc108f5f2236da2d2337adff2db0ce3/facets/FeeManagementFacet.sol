// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "./FacetBase.sol";
import "../libraries/LibDiamond.sol";
import "../libraries/RoleConstants.sol";
import "../interfaces/IShibaBurn.sol";
import "../interfaces/IFacetInterface.sol";

/**
 * @title FeeManagementFacet
 * @dev Facet contract for managing fees within the diamond.
 */
contract FeeManagementFacet is FacetBase {
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

    /**
     * @dev Modifier that checks if the contract is not paused.
     */
    modifier whenNotPaused() {
        require(!diamondStorage().paused, "Pausable: paused");
        _;
    }

    /**
     * @dev Modifier that checks if the contract is paused.
     */
    modifier whenPaused() {
        require(diamondStorage().paused, "Pausable: not paused");
        _;
    }

    constructor() {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        ds.roles[RoleConstants.ADMIN_ROLE][msg.sender] = true;
    }

    /**
     * @notice Initializes the FeeManagementFacet contract.
     * @dev Can only be called by accounts with the ADMIN_ROLE.
     * @param _tradingFeeBasisPoints The trading fee in basis points.
     * @param _borrowingFeeBasisPoints The borrowing fee in basis points.
     * @param _lendingFeeBasisPoints The lending fee in basis points.
     * @param _feeRecipient The address of the fee recipient.
     * @param _feeToken The ERC20 fee token.
     * @param _ShibaSwapRouterAddress The address of the ShibaSwap router.
     */
    function initializeFeeManagement(uint256 _tradingFeeBasisPoints, uint256 _borrowingFeeBasisPoints, uint256 _lendingFeeBasisPoints, address _feeRecipient, IERC20 _feeToken, address _ShibaSwapRouterAddress) external onlyRole(RoleConstants.ADMIN_ROLE) {
        require(!initialized, "FeeManagementFacet: Already initialized");

        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        ds.facet.selectorCount = 0; // Initialize selectorCount to 0

        ds.feeManagement.tradingFeeBasisPoints = _tradingFeeBasisPoints;
        ds.feeManagement.borrowingFeeBasisPoints = _borrowingFeeBasisPoints;
        ds.feeManagement.lendingFeeBasisPoints = _lendingFeeBasisPoints;

        ds.feeManagement.feeRecipient = _feeRecipient;
        ds.feeManagement.feeToken = _feeToken;
        ds.feeManagement.ShibaSwapRouterAddress = _ShibaSwapRouterAddress;

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
     * @notice Gets the fee recipient address.
     * @return The address of the fee recipient.
     */
    function getFeeRecipient() public view returns (address) {
        return LibDiamond.diamondStorage().feeManagement.feeRecipient;
    }

    /**
     * @notice Calculates the trading fee for a given trade amount.
     * @param _tradeAmount The amount being traded.
     * @return The trading fee.
     */
    function calculateTradingFee(uint256 _tradeAmount) public view returns (uint256) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();

        require(_tradeAmount > 0, "Trade amount should be greater than 0");
        return ((_tradeAmount * ds.feeManagement.tradingFeeBasisPoints) / 10000);
    }

    /**
     * @notice Calculates the borrowing fee for a given borrow amount.
     * @param _borrowAmount The amount being borrowed.
     * @return The borrowing fee.
     */    
    function calculateBorrowingFee(uint256 _borrowAmount) public view returns (uint256) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();

        require(_borrowAmount > 0, "Borrow amount should be greater than 0");
        return ((_borrowAmount * ds.feeManagement.borrowingFeeBasisPoints) / 10000);
    }

    /**
     * @notice Calculates the lending fee for a given lend amount.
     * @param _lendAmount The amount being lent.
     * @return The lending fee.
     */    
    function calculateLendingFee(uint256 _lendAmount) public view returns (uint256) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();

        require(_lendAmount > 0, "Lend amount should be greater than 0");
        return ((_lendAmount * ds.feeManagement.lendingFeeBasisPoints) / 10000);
    }

    /**
     * @notice Gets the function selectors for the facet.
     * @return selectors An array of function selectors.
     */    
    function facetFunctionSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](11);
        selectors[0] = this.setFeeRecipient.selector;
        selectors[1] = this.getFeeRecipient.selector;
        selectors[2] = this.collectFee.selector;
        selectors[3] = this.setTradingFeeBasisPoints.selector;
        selectors[4] = this.setBorrowingFeeBasisPoints.selector;
        selectors[5] = this.setLendingFeeBasisPoints.selector;
        selectors[6] = this.calculateTradingFee.selector;
        selectors[7] = this.calculateBorrowingFee.selector;
        selectors[8] = this.calculateLendingFee.selector;
        selectors[9] = this.initializeFeeManagement.selector;
        selectors[10] = this.setToken.selector;
        return selectors;
    }

    // --------------------------------------------------------------------------------------------- EXTERNAL ---------------------------------------------------------------------------------------

    /**
     * @notice Sets the fee recipient address.
     * @dev Can only be called by accounts with the ADMIN_ROLE.
     * @param feeRecipient_ The address of the fee recipient.
     */    
    function setFeeRecipient(address feeRecipient_) external onlyRole(RoleConstants.ADMIN_ROLE) {
        require(feeRecipient_ != address(0), "Fee recipient cannot be zero address");

        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        ds.feeManagement.feeRecipient = feeRecipient_;
    }

    /**
     * @notice Sets the fee token.
     * @dev Can only be called by accounts with the ADMIN_ROLE.
     * @param _feeToken The ERC20 fee token.
     */    
    function setToken(IERC20 _feeToken) external onlyRole(RoleConstants.ADMIN_ROLE) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        ds.feeManagement.feeToken = _feeToken;
    }

    /**
     * @notice Collects fees from a specified token.
     * @param token The address of the token.
     * @param amount The amount of tokens to collect as fees.
     */    
    function collectFee(address token, uint256 amount) external whenNotPaused onlyRole(RoleConstants.PLATFORM_CONTRACT_ROLE) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();

        require(amount > 0, "Amount should be greater than 0");
        uint256 allowance = IERC20(token).allowance(msg.sender, address(this));
        require(allowance >= amount, "Token allowance too small");

        if (token != address(ds.WBONE)) {
            uint256 balanceBeforeSwap = IERC20(ds.feeManagement.feeToken).balanceOf(address(this));
            swapTokens(token, amount);
            uint256 balanceAfterSwap = IERC20(ds.feeManagement.feeToken).balanceOf(address(this));
            amount = balanceAfterSwap - balanceBeforeSwap;
        }

        // Distribute the fee based on the new structure
        uint256 shibBurnAmount = ((amount * diamondStorage().shibBurnFee) / 100);
        uint256 daoFoundationAmount = ((amount * diamondStorage().daoFoundationFee) / 100);
        uint256 donationAmount = ((amount * diamondStorage().donationFee) / 100);
        uint256 rewardPoolAmount = ((amount * diamondStorage().rewardPoolFee) / 100);
        uint256 ecosystemAmount = ((amount * diamondStorage().ecosystemFee) / 100);

        // Use the IShibaBurn interface to burn $SHIB
        IShibaBurn(diamondStorage().shibaBurnAddress).buyAndBurn(ds.shibTokenAddress, shibBurnAmount);

        // Transfer other amounts to respective destinations
        ds.feeManagement.feeToken.transfer(diamondStorage().daoFoundationAddress, daoFoundationAmount);
        ds.feeManagement.feeToken.transfer(diamondStorage().donationAddress, donationAmount);
        ds.rewardPool += rewardPoolAmount;  // Update the reward pool
        ds.feeManagement.feeToken.transfer(diamondStorage().ecosystemAddress, ecosystemAmount);

        // Update the fee balance for the token
        ds._fees[token] += amount;
    }

    /**
    * @notice Sets the trading fee in basis points.
    * @dev Can only be called by accounts with the ADMIN_ROLE.
    * @param _tradingFeeBasisPoints The trading fee in basis points.
    */
    function setTradingFeeBasisPoints(uint256 _tradingFeeBasisPoints) external onlyRole(RoleConstants.ADMIN_ROLE) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();

        require(_tradingFeeBasisPoints <= 10000, "Invalid trading fee basis points");
        ds.feeManagement.tradingFeeBasisPoints = _tradingFeeBasisPoints;
    }

    /**
    * @notice Sets the borrowing fee in basis points.
    * @dev Can only be called by accounts with the ADMIN_ROLE.
    * @param _borrowingFeeBasisPoints The borrowing fee in basis points.
    */
    function setBorrowingFeeBasisPoints(uint256 _borrowingFeeBasisPoints) external onlyRole(RoleConstants.ADMIN_ROLE) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();

        require(_borrowingFeeBasisPoints <= 10000, "Invalid borrowing fee basis points");
        ds.feeManagement.borrowingFeeBasisPoints = _borrowingFeeBasisPoints;
    }

    /**
    * @notice Sets the lending fee in basis points.
    * @dev Can only be called by accounts with the ADMIN_ROLE.
    * @param _lendingFeeBasisPoints The lending fee in basis points.
    */
    function setLendingFeeBasisPoints(uint256 _lendingFeeBasisPoints) external onlyRole(RoleConstants.ADMIN_ROLE) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();

        require(_lendingFeeBasisPoints <= 10000, "Invalid lending fee basis points");
        ds.feeManagement.lendingFeeBasisPoints = _lendingFeeBasisPoints;
    }

    // --------------------------------------------------------------------------------------------- INTERNAL ---------------------------------------------------------------------------------------

    /**
    * @notice Sets the rates for various fees.
    * @param _shibBurnFee The fee percentage for Shiba burn.
    * @param _daoFoundationFee The fee percentage for the DAO foundation.
    * @param _donationFee The fee percentage for donations.
    * @param _rewardPoolFee The fee percentage for the reward pool.
    * @param _ecosystemFee The fee percentage for the ecosystem.
    */
    function setFeeRates(uint256 _shibBurnFee, uint256 _daoFoundationFee, uint256 _donationFee, uint256 _rewardPoolFee, uint256 _ecosystemFee) internal {
        LibDiamond.DiamondStorage storage ds = diamondStorage();
        ds.shibBurnFee = _shibBurnFee;
        ds.daoFoundationFee = _daoFoundationFee;
        ds.donationFee = _donationFee;
        ds.rewardPoolFee = _rewardPoolFee;
        ds.ecosystemFee = _ecosystemFee;
    }

    /**
    * @notice Sets the addresses for various fee recipients.
    * @param _shibaBurnAddress The address for the Shiba burn fee recipient.
    * @param _daoFoundationAddress The address for the DAO foundation fee recipient.
    * @param _donationAddress The address for the donation fee recipient.
    * @param _ecosystemAddress The address for the ecosystem fee recipient.
    */
    function setFeeAddresses(address _shibaBurnAddress, address _daoFoundationAddress, address _donationAddress, address _ecosystemAddress) internal {
        LibDiamond.DiamondStorage storage ds = diamondStorage();
        ds.shibaBurnAddress = _shibaBurnAddress;
        ds.daoFoundationAddress = _daoFoundationAddress;
        ds.donationAddress = _donationAddress;
        ds.ecosystemAddress = _ecosystemAddress;
    }

    // --------------------------------------------------------------------------------------------- PRIVATE ---------------------------------------------------------------------------------------

    /**
    * @notice Swaps tokens using the Uniswap router.
    * @param token The address of the token to swap.
    * @param amount The amount of tokens to swap.
    */
    function swapTokens(address token, uint256 amount) private {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();

        // Check the balance of the token
        require(IERC20(token).balanceOf(address(this)) >= amount, "Not enough tokens for swap");

        // Approve the router to spend the tokens
        IERC20(token).approve(ds.feeManagement.ShibaSwapRouterAddress, amount);

        IUniswapV2Router02 _router = IUniswapV2Router02(ds.feeManagement.ShibaSwapRouterAddress);

        // Define the path for the swap (from the fee token to the desired token)
        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = address(ds.feeManagement.feeToken);

        // Execute the swap
        _router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amount,
            0, // Accept any amount of the desired token
            path,
            address(this),
            block.timestamp
        );
    }
}