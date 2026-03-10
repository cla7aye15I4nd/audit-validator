// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "./FacetBase.sol";
import "./ReentrancyGuardBase.sol";
import "../libraries/LibDiamond.sol";
import "../libraries/RoleConstants.sol";
import "../interfaces/IShibaBurn.sol";
import "../interfaces/IFeeManagement.sol";
import "../interfaces/IPriceOracleFacet.sol";

/**
 * @title FeeManagementFacet
 * @dev Manages protocol fees, including collection, distribution, and AMM interactions
 */
contract FeeManagementFacet is FacetBase, ReentrancyGuardBase, IFeeManagement {
    using SafeERC20 for IERC20;

    uint256 private constant SCALE = 1e18;
    uint256 private constant MAX_FEE = 1000; // 10%
    uint256 private constant MAX_SLIPPAGE = 300; // 3%
    uint256 private constant MIN_SWAP_DELAY = 5 minutes;
    uint256 private constant MAX_SWAP_DELAY = 20 minutes;

    event FeeDistributionUpdated(
        uint256 burnShare,
        uint256 daoShare,
        uint256 rewardShare,
        uint256 ecosystemShare,
        uint256 timestamp
    );

    modifier onlyRole(bytes32 role) {
        require(LibDiamond.diamondStorage().roles[role][msg.sender], "Must have required role");
        _;
    }

    function initializeFeeSystem(
        uint256 _tradingFeeBasisPoints,
        uint256 _borrowingFeeBasisPoints,
        uint256 _lendingFeeBasisPoints,
        uint256 _liquidationFeeBasisPoints,
        address _feeRecipient,
        IERC20 _feeToken,
        address _dexRouter
    ) external onlyRole(RoleConstants.ADMIN_ROLE) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        require(!ds.initialized, "Already initialized");
        
        require(_tradingFeeBasisPoints <= MAX_FEE, "Trading fee too high");
        require(_borrowingFeeBasisPoints <= MAX_FEE, "Borrowing fee too high");
        require(_lendingFeeBasisPoints <= MAX_FEE, "Lending fee too high");
        require(_liquidationFeeBasisPoints <= MAX_FEE, "Liquidation fee too high");
        require(_feeRecipient != address(0), "Invalid fee recipient");
        require(address(_feeToken) != address(0), "Invalid fee token");
        require(_dexRouter != address(0), "Invalid DEX router");

        ds.feeManagement.tradingFeeBasisPoints = _tradingFeeBasisPoints;
        ds.feeManagement.borrowingFeeBasisPoints = _borrowingFeeBasisPoints;
        ds.feeManagement.lendingFeeBasisPoints = _lendingFeeBasisPoints;
        ds.feeManagement.liquidationFeeBasisPoints = _liquidationFeeBasisPoints;
        ds.feeManagement.feeRecipient = _feeRecipient;
        ds.feeManagement.feeToken = _feeToken;
        ds.feeManagement.ShibaSwapRouterAddress = _dexRouter;

        ds.initialized = true;

        emit FeeParametersUpdated(
            _tradingFeeBasisPoints,
            _borrowingFeeBasisPoints,
            _lendingFeeBasisPoints,
            block.timestamp
        );
    }

    function setTradingFeeBasisPoints(uint256 _tradingFeeBasisPoints) external override onlyRole(RoleConstants.ADMIN_ROLE) {
        require(_tradingFeeBasisPoints <= MAX_FEE, "Fee too high");
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        ds.feeManagement.tradingFeeBasisPoints = _tradingFeeBasisPoints;
        
        emit FeeParametersUpdated(
            _tradingFeeBasisPoints,
            ds.feeManagement.borrowingFeeBasisPoints,
            ds.feeManagement.lendingFeeBasisPoints,
            block.timestamp
        );
    }

    function setBorrowingFeeBasisPoints(uint256 _borrowingFeeBasisPoints) external override onlyRole(RoleConstants.ADMIN_ROLE) {
        require(_borrowingFeeBasisPoints <= MAX_FEE, "Fee too high");
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        ds.feeManagement.borrowingFeeBasisPoints = _borrowingFeeBasisPoints;
        
        emit FeeParametersUpdated(
            ds.feeManagement.tradingFeeBasisPoints,
            _borrowingFeeBasisPoints,
            ds.feeManagement.lendingFeeBasisPoints,
            block.timestamp
        );
    }

    function setLendingFeeBasisPoints(uint256 _lendingFeeBasisPoints) external override onlyRole(RoleConstants.ADMIN_ROLE) {
        require(_lendingFeeBasisPoints <= MAX_FEE, "Fee too high");
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        ds.feeManagement.lendingFeeBasisPoints = _lendingFeeBasisPoints;
        
        emit FeeParametersUpdated(
            ds.feeManagement.tradingFeeBasisPoints,
            ds.feeManagement.borrowingFeeBasisPoints,
            _lendingFeeBasisPoints,
            block.timestamp
        );
    }

    function collectFee(
        address token,
        uint256 amount
    ) external override nonReentrant onlyRole(RoleConstants.PLATFORM_CONTRACT_ROLE) {
        require(amount > 0, "Amount must be greater than 0");
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        uint256 feeTokenAmount = amount;
        if (token != address(ds.feeManagement.feeToken)) {
            feeTokenAmount = _swapToFeeToken(token, amount);
        }

        _distributeFees(feeTokenAmount);

        emit FeesCollected(token, amount, block.timestamp);
    }

    function calculateTradingFee(uint256 amount) external view override returns (uint256) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        return (amount * ds.feeManagement.tradingFeeBasisPoints) / 10000;
    }

    function calculateBorrowingFee(uint256 amount) external view override returns (uint256) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        return (amount * ds.feeManagement.borrowingFeeBasisPoints) / 10000;
    }

    function calculateLendingFee(uint256 amount) external view override returns (uint256) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        return (amount * ds.feeManagement.lendingFeeBasisPoints) / 10000;
    }

    function getFeeFacetSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](11);
        selectors[0] = this.initializeFeeSystem.selector;
        selectors[1] = this.setTradingFeeBasisPoints.selector;
        selectors[2] = this.setBorrowingFeeBasisPoints.selector;
        selectors[3] = this.setLendingFeeBasisPoints.selector;
        selectors[4] = this.collectFee.selector;
        selectors[5] = this.calculateTradingFee.selector;
        selectors[6] = this.calculateBorrowingFee.selector;
        selectors[7] = this.calculateLendingFee.selector;
        selectors[8] = this.updateFeeDistribution.selector;
        selectors[9] = this.setFeeRecipient.selector;
        selectors[10] = this.setFeeToken.selector;
        return selectors;
    }

    function setFeeRecipient(address _feeRecipient) external onlyRole(RoleConstants.ADMIN_ROLE) {
        require(_feeRecipient != address(0), "Invalid fee recipient");
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        ds.feeManagement.feeRecipient = _feeRecipient;
    }

    function setFeeToken(IERC20 _feeToken) external onlyRole(RoleConstants.ADMIN_ROLE) {
        require(address(_feeToken) != address(0), "Invalid fee token");
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        ds.feeManagement.feeToken = _feeToken;
    }

    function updateFeeDistribution(
        uint256 _burnShare,
        uint256 _daoShare,
        uint256 _rewardShare,
        uint256 _ecosystemShare
    ) external onlyRole(RoleConstants.ADMIN_ROLE) {
        require(_burnShare + _daoShare + _rewardShare + _ecosystemShare == 10000, "Invalid shares");
        
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        ds.shibBurnFee = _burnShare;
        ds.daoFoundationFee = _daoShare;
        ds.rewardPoolFee = _rewardShare;
        ds.ecosystemFee = _ecosystemShare;

        emit FeeDistributionUpdated(
            _burnShare,
            _daoShare,
            _rewardShare,
            _ecosystemShare,
            block.timestamp
        );
    }

    function _swapToFeeToken(
        address inputToken,
        uint256 amount
    ) internal returns (uint256) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        
        uint256 inputPrice = IPriceOracleFacet(ds.priceOracleFacet).getPrice(inputToken);
        uint256 feeTokenPrice = IPriceOracleFacet(ds.priceOracleFacet).getPrice(address(ds.feeManagement.feeToken));
        
        uint256 expectedOutput = (amount * inputPrice * (10000 - MAX_SLIPPAGE)) / (feeTokenPrice * 10000);
        
        IERC20(inputToken).forceApprove(ds.feeManagement.ShibaSwapRouterAddress, amount);

        address[] memory path = new address[](2);
        path[0] = inputToken;
        path[1] = address(ds.feeManagement.feeToken);

        uint256[] memory amounts = IUniswapV2Router02(ds.feeManagement.ShibaSwapRouterAddress)
            .swapExactTokensForTokens(
                amount,
                expectedOutput,
                path,
                address(this),
                block.timestamp + MIN_SWAP_DELAY
            );

        return amounts[amounts.length - 1];
    }

    function _distributeFees(uint256 amount) internal {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();

        uint256 burnAmount = (amount * ds.shibBurnFee) / 10000;
        uint256 daoAmount = (amount * ds.daoFoundationFee) / 10000;
        uint256 rewardAmount = (amount * ds.rewardPoolFee) / 10000;
        uint256 ecosystemAmount = (amount * ds.ecosystemFee) / 10000;

        if (burnAmount > 0) {
            ds.feeManagement.feeToken.forceApprove(ds.shibaBurnAddress, burnAmount);
            IShibaBurn(ds.shibaBurnAddress).buyAndBurn(address(ds.feeManagement.feeToken), burnAmount);
        }

        if (daoAmount > 0) {
            ds.feeManagement.feeToken.safeTransfer(ds.daoFoundationAddress, daoAmount);
        }

        if (rewardAmount > 0) {
            ds.rewardPool += rewardAmount;
        }

        if (ecosystemAmount > 0) {
            ds.feeManagement.feeToken.safeTransfer(ds.ecosystemAddress, ecosystemAmount);
        }

        emit FeesDistributed(
            burnAmount,
            daoAmount,
            rewardAmount,
            ecosystemAmount,
            block.timestamp
        );
    }
}