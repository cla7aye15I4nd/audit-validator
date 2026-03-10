// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IDiamondCut.sol";
import "../interfaces/IDiamondLoupe.sol";
import "../interfaces/IFeeManagement.sol";
import "../interfaces/IRoleManagement.sol";

library LibDiamond {
    using Address for address;

    /**
     * @dev Struct for storing diamond-related state.
     */
    struct DiamondStorage {
        bool initialized; ///< Whether the contract is initialized.
        bool paused; ///< Whether the contract is paused.

        address WBONE; ///< Address of the WBONE token.
        address shibTokenAddress; ///< Address of the Shiba token contract.
        address dexRouterAddress; ///< Address of the DEX router for token swaps.

        // Facets
        Facet facet; ///< The facet information.
        mapping(bytes4 => address) facets; ///< Mapping from function selectors to facet addresses.
        mapping(address => bytes4[]) facetFunctionSelectors; ///< Mapping from facet addresses to function selectors.

        // Token Registry
        address[] supportedTokens; ///< List of supported token addresses.
        mapping(address => bool) isTokenSupported; ///< Mapping to check if a token is supported.

        // Interest Rate
        InterestRate interestRate; ///< Struct containing interest rate information.
        mapping(address => mapping(address => uint256)) userLastCompoundedBlock; ///< Mapping of user to token to last compounded block number.
        mapping(address => mapping(address => uint256)) interestForFees; ///< Mapping of user to token to interest for fees.
        uint256 compoundingFrequency; ///< Number of blocks for compounding frequency.
        uint256 interestRateBasisPoints; ///< Interest rate in basis points.

        // Fee Management
        FeeManagement feeManagement; ///< Struct containing fee management information.
        mapping(address => uint256) _fees; ///< Mapping of address to accumulated fees.
        uint256 rewardPool; ///< Total reward pool.

        // Fee Distribution
        uint256 shibBurnFee; ///< Shiba burn fee in basis points.
        uint256 daoFoundationFee; ///< DAO foundation fee in basis points.
        uint256 donationFee; ///< Donation fee in basis points.
        uint256 rewardPoolFee; ///< Reward pool fee in basis points.
        uint256 ecosystemFee; ///< Ecosystem fee in basis points.

        // Fee Distribution Addresses
        address shibaBurnAddress; ///< Address for the Shiba burn fee.
        address daoFoundationAddress; ///< Address for the DAO foundation fee.
        address donationAddress; ///< Address for the donation fee.
        address ecosystemAddress; ///< Address for the ecosystem fee.

        // Lending Pool
        uint256 MIN_COLLATERAL_RATIO; ///< Minimum collateral ratio.
        uint256 baseRewardAmount; ///< Base reward amount.
        uint256 stakingRewardRate; ///< Staking reward rate.
        UserTokenPair[] usersOrderedByLastCompounded; ///< Array of user-token pairs ordered by last compounded block.
        mapping(address => LendingPool) lendingPools; ///< Mapping of tokens to lending pool information.
        mapping(address => UserCompoundingData) userCompoundingData; ///< Mapping of users to compounding data.
        mapping(address => bool) allowedCollateralTokens; ///< Mapping of allowed collateral tokens.
        mapping(address => mapping(address => uint256)) userBorrowedAmounts; ///< Mapping of user to token to borrowed amounts.
        mapping(address => mapping(address => uint256)) userToTokenLastCompounded; ///< Mapping of user to token to last compounded block.
        mapping(address => mapping(address => StakingRewards)) stakingRewards; ///< Mapping of user to token to staking rewards.

        // Collateral Management
        mapping(address => mapping(address => uint256)) userDeposits; ///< Mapping of user to token to deposits.
        mapping(address => mapping(address => uint256)) userBorrows; ///< Mapping of user to token to borrow amounts.
        mapping(address => mapping(address => uint256)) userCollateral; ///< Mapping of user to token to collateral amounts.

        // Roles
        IRoleManagement roleManagement; ///< Contract managing roles.
        mapping(bytes32 => mapping(address => bool)) roles; ///< Mapping of roles to addresses.

        // Margin Accounts
        address[] marginAccountsUsers; ///< List of users with margin accounts.
        mapping(address => MarginAccount) marginAccounts; ///< Mapping of users to margin accounts.
        mapping(address => mapping(address => uint256)) collateral; ///< Mapping of users to tokens to collateral.

        // Margin Trading
        mapping(address => LeveragedPosition[]) leveragedPositions; ///< Mapping of users to leveraged positions.
        mapping(address => uint256) leveragedPositionsLength; ///< Mapping of users to the number of leveraged positions.
        mapping(address => uint256) nextPositionId; ///< Mapping of users to the next position ID.
        mapping(address => uint256) tokenSlippageRates; ///< Mapping of tokens to slippage rates.

        // Order Matching
        mapping(uint256 => uint256) partialOrders; ///< Mapping of partially filled orders.

        // Liquidation Engine
        mapping(address => PriceData[]) priceHistory; ///< Mapping of tokens to price history.
        mapping(address => LiquidationEvent[]) liquidationHistory; ///< Mapping of tokens to liquidation event history.

        // Price Oracle
        address router; ///< Address of the OoO Router.
        address xfund; ///< Address of the xfund.
        address oooDataProvider; ///< Address of the default data provider.
        uint256 oooFee; ///< Default fee for OoO requests.
        mapping(address => uint256) nonces; ///< Mapping of addresses to nonces.
        mapping(bytes32 => bool) pendingRequests; ///< Mapping to track pending requests.
        mapping(address => TokenPriceData) tokenPriceCache; ///< Mapping of tokens to price data.

        // New facets and parameters
        address emergencyManagementFacet; ///< Address of the Emergency Management Facet.
        address feeManagementFacet; ///< Address of the Fee Management Facet.
        address governanceFacet; ///< Address of the Governance Facet.
        address interestRateModelFacet; ///< Address of the Interest Rate Model Facet.
        address lendingPoolFacet; ///< Address of the Lending Pool Facet.
        address priceOracleFacet; ///< Address of the Price Oracle Facet.
        address marginAccountsFacet; ///< Address of the Margin Accounts Facet.
        address marginTradingFacet; ///< Address of the Margin Trading Facet.
        address roleManagementFacet; ///< Address of the Role Management Facet.
        address tokenRegistryFacet; ///< Address of the Token Registry Facet.

        address lendingToken; ///< Address of the lending token.
        uint256 initialRate; ///< Initial rate for the lending token.
        address oracleAddress; ///< Address of the price oracle.
        address marginToken; ///< Address of the margin token.
        address registryAdmin; ///< Address of the registry admin.
    }

    /// @dev Struct for storing collateral rewards information.
    struct CollateralRewards {
        uint256 APY; ///< Annual percentage yield.
        uint256 SECONDS_IN_A_YEAR; ///< Number of seconds in a year.
        mapping(address => mapping(address => uint256)) lastClaimedTimestamp; ///< Mapping of user to token to the last claimed timestamp.
        mapping(address => mapping(address => uint256)) eligibleAmount; ///< Mapping of user to token to the eligible amount.
    }

    /// @dev Struct for storing lending pool information.
    struct LendingPool {
        uint256 totalDeposited; ///< Total amount deposited in the lending pool.
        uint256 totalBorrowed; ///< Total amount borrowed from the lending pool.
        uint256 borrowRate; ///< Current borrow rate.
        address[] userCollateralTokens; ///< List of collateral tokens held by users.
    }

    /// @dev Struct for storing margin account information.
    struct MarginAccount {
        mapping(address => uint256) balance; ///< Mapping of token to balance in the margin account.
        uint256 borrowed; ///< Total amount borrowed in the margin account.
        uint256 lastUpdate; ///< Block number of the last update.
        uint256 lockedMargin; ///< Amount of locked margin in the margin account.
    }

    /// @dev Struct for storing order matching information.
    struct OrderMatching {
        uint256 timestamp; ///< Timestamp of the order match.
    }

    /// @dev Struct for storing order information.
    struct Order {
        address trader; ///< Address of the trader.
        address token; ///< Address of the token being traded.
        uint256 price; ///< Price of the token.
        uint256 amount; ///< Amount of tokens being traded.
        bool isBuy; ///< Whether the order is a buy order.
        uint256 transactionTime; ///< Time of the transaction.
    }

    /// @dev Struct for managing fees.
    struct FeeManagement {
        address feeRecipient; ///< Address of the fee recipient.
        address ShibaSwapRouterAddress; ///< Address of the ShibaSwap router.
        IERC20 feeToken; ///< ERC-20 token used for fees.
        uint256 tradingFeeBasisPoints; ///< Trading fee in basis points.
        uint256 borrowingFeeBasisPoints; ///< Borrowing fee in basis points.
        uint256 lendingFeeBasisPoints; ///< Lending fee in basis points.
    }

    /// @dev Struct for storing price data.
    struct PriceData {
        uint256 price; ///< Price of the token.
        uint256 timestamp; ///< Timestamp of the price.
        uint256 duration; ///< Duration for which the price is valid.
    }

    /// @dev Struct for storing token price data.
    struct TokenPriceData {
        uint256[] prices; ///< Array of token prices.
        uint256 lastUpdated; ///< Block number of the last update.
    }

    /// @dev Struct for storing liquidation event information.
    struct LiquidationEvent {
        address liquidator; ///< Address of the liquidator.
        uint256 amount; ///< Amount liquidated.
        uint256 reward; ///< Reward for the liquidator.
        uint256 timestamp; ///< Timestamp of the liquidation event.
    }

    /// @dev Struct for storing leveraged position information.
    struct LeveragedPosition {
        uint256 positionId; ///< Position ID.
        uint256 entryPrice; ///< Entry price of the leveraged position.
        uint256 size; ///< Size of the leveraged position.
        uint256 leverage; ///< Leverage applied to the position.
        bool isLong; ///< Whether the position is a long position.
        bool isOpen; ///< Whether the position is open.
        IERC20 token; ///< ERC-20 token for the position.
        uint256 amount; ///< Amount of tokens in the position.
    }

    /// @dev Struct for storing interest rate information.
    struct InterestRate {
        uint256 baseRatePerYear; ///< Base rate per year in basis points.
        uint256 multiplierPerYear; ///< Multiplier per year in basis points.
    }

    /// @dev Struct for storing user compounding data.
    struct UserCompoundingData {
        uint256 lastCompoundedBlock; ///< Last block number when the user's interest was compounded.
        uint256 indexInOrderedArray; ///< Index in the ordered array for compounding.
    }

    /// @dev Struct for associating users with tokens.
    struct UserTokenPair {
        address user; ///< Address of the user.
        address token; ///< Address of the token.
    }

    /// @dev Struct for storing staking rewards information.
    struct StakingRewards {
        uint256 lastUpdated; ///< Block number of the last update.
        uint256 rewards; ///< Accumulated rewards.
        uint256 stakedAmount; ///< Amount staked by the user.
    }

    /// @dev Struct for storing facet information.
    struct Facet {
        bytes4[] selectors; ///< Array of function selectors.
        address[] facetAddresses; ///< Array of facet addresses.
        uint256 selectorCount; ///< Count of function selectors.
    }

    /**
     * @notice Accesses the diamond storage instance.
     * @return ds The diamond storage instance.
     */
    function diamondStorage() internal pure returns (DiamondStorage storage ds) {
        bytes32 storagePosition = keccak256("diamond.standard.diamond.storage");
        assembly {
            ds.slot := storagePosition
        }
    }

    /**
     * @notice Executes a diamond cut, adding, replacing, or removing facets.
     * @param _diamondCut Array of FacetCut structs defining the diamond cut actions.
     * @param _init The address of the contract or facet to execute _calldata.
     * @param _calldata Function call, including function selector and arguments, to execute on _init after facets are cut.
     */
    function diamondCut(
        IDiamondCut.FacetCut[] memory _diamondCut,
        address _init,
        bytes memory _calldata
    ) internal {
        DiamondStorage storage ds = diamondStorage();

        for (uint256 facetIndex; facetIndex < _diamondCut.length; facetIndex++) {
            IDiamondCut.FacetCut memory cut = _diamondCut[facetIndex];
            require(cut.functionSelectors.length > 0, "LibDiamond: No selectors in facet to cut");
            require(isContract(cut.target), "LibDiamond: Facet cut target has no code");

            if (cut.action == IDiamondCut.FacetCutAction.Add) {
                enforceHasContractCode(cut.target, "LibDiamond: Add facet has no code");
                for (uint256 selectorIndex; selectorIndex < cut.functionSelectors.length; selectorIndex++) {
                    bytes4 selector = cut.functionSelectors[selectorIndex];
                    address oldFacet = ds.facets[selector];
                    require(oldFacet == address(0), "LibDiamond: Selector already exists");
                    ds.facets[selector] = cut.target;
                    ds.facet.selectorCount++;
                    ds.facetFunctionSelectors[cut.target].push(selector);
                    ds.facet.facetAddresses.push(cut.target);
                }
            } else if (cut.action == IDiamondCut.FacetCutAction.Replace) {
                enforceHasContractCode(cut.target, "LibDiamond: Replace facet has no code");
                for (uint256 selectorIndex; selectorIndex < cut.functionSelectors.length; selectorIndex++) {
                    bytes4 selector = cut.functionSelectors[selectorIndex];
                    address oldFacet = ds.facets[selector];
                    require(oldFacet != address(0), "LibDiamond: Selector does not exist");
                    require(oldFacet != cut.target, "LibDiamond: Cannot replace function with same function");
                    ds.facets[selector] = cut.target;
                    bool isNewFacet = true;
                    for (uint256 i = 0; i < ds.facet.facetAddresses.length; i++) {
                        if (ds.facet.facetAddresses[i] == cut.target) {
                            isNewFacet = false;
                            break;
                        }
                    }
                    if (isNewFacet) {
                        ds.facet.facetAddresses.push(cut.target);
                    }
                }
            } else if (cut.action == IDiamondCut.FacetCutAction.Remove) {
                for (uint256 selectorIndex; selectorIndex < cut.functionSelectors.length; selectorIndex++) {
                    bytes4 selector = cut.functionSelectors[selectorIndex];
                    address oldFacet = ds.facets[selector];
                    require(oldFacet != address(0), "LibDiamond: Selector does not exist");
                    ds.facets[selector] = address(0);
                    ds.facet.selectorCount--;
                    bool isAssociated = false;
                    for (uint256 i = 0; i < ds.facetFunctionSelectors[oldFacet].length; i++) {
                        if (ds.facets[ds.facetFunctionSelectors[oldFacet][i]] == oldFacet) {
                            isAssociated = true;
                            break;
                        }
                    }
                    if (!isAssociated) {
                        for (uint256 i = 0; i < ds.facet.facetAddresses.length; i++) {
                            if (ds.facet.facetAddresses[i] == oldFacet) {
                                ds.facet.facetAddresses[i] = ds.facet.facetAddresses[ds.facet.facetAddresses.length - 1];
                                ds.facet.facetAddresses.pop();
                                break;
                            }
                        }
                    }
                }
            } else {
                revert("LibDiamond: Incorrect FacetCutAction");
            }
        }          
        if (_init != address(0)) {
            require(isContract(_init), "LibDiamond: _init has no code");
            if (_calldata.length > 0) {
                (bool success, bytes memory error) = _init.delegatecall(_calldata);
                if (!success) {
                    if (error.length > 0) {
                        revert(string(abi.encodePacked("LibDiamond: _init function reverted with message: ", error)));
                    } else {
                        revert("LibDiamond: _init function reverted without a message");
                    }
                }
            }
        }
    }

    /**
     * @notice Enforces that the given address contains contract code.
     * @param _contract The address of the contract to check.
     * @param _errorMessage Error message to revert with if the address does not contain contract code.
     */
    function enforceHasContractCode(address _contract, string memory _errorMessage) internal view {
        require(isContract(_contract), _errorMessage);
    }

    /**
     * @notice Executes the fallback function for the diamond storage.
     */
    function executeFallback() internal {
        DiamondStorage storage ds = diamondStorage();
        address facet = ds.facets[msg.sig];
        require(facet != address(0), "LibDiamond: Function does not exist");
        assembly {
            let ptr := mload(0x40)
            calldatacopy(ptr, 0, calldatasize())
            let result := delegatecall(gas(), facet, ptr, calldatasize(), 0, 0)
            let size := returndatasize()
            returndatacopy(ptr, 0, size)
            switch result
                case 0 {
                    revert(ptr, size)
                }
                default {
                    return(ptr, size)
                }
        }
    }

    /**
     * @notice Returns an array of all facets with their function selectors.
     * @return facets_ An array of Facet structs.
     */
    function facets() internal view returns (IDiamondLoupe.Facet[] memory) {
        DiamondStorage storage ds = diamondStorage();
        IDiamondLoupe.Facet[] memory facets_ = new IDiamondLoupe.Facet[](ds.facet.selectorCount);
        for (uint256 facetIndex; facetIndex < facets_.length; facetIndex++) {
            address facetAddress_ = ds.facet.facetAddresses[facetIndex];
            facets_[facetIndex] = IDiamondLoupe.Facet({
                facetAddress: facetAddress_,
                functionSelectors: ds.facetFunctionSelectors[facetAddress_]
            });
        }
        return facets_;
    }

    /**
     * @notice Returns an array of function selectors supported by a specific facet.
     * @param _facet The address of the facet.
     * @return An array of function selectors.
     */
    function facetFunctionSelectors(address _facet) internal view returns (bytes4[] memory) {
        DiamondStorage storage ds = diamondStorage();
        return ds.facetFunctionSelectors[_facet];
    }

    /**
     * @notice Returns an array of all facet addresses used by the diamond.
     * @return An array of facet addresses.
     */
    function facetAddresses() internal view returns (address[] memory) {
        DiamondStorage storage ds = diamondStorage();
        address[] memory facetAddresses_ = new address[](ds.facet.selectorCount);
        for (uint256 facetIndex; facetIndex < facetAddresses_.length; facetIndex++) {
            facetAddresses_[facetIndex] = ds.facet.facetAddresses[facetIndex];
        }
        return facetAddresses_;
    }

    /**
     * @notice Returns the facet address that implements a specific function.
     * @param _functionSelector The function selector.
     * @return The address of the facet that implements _functionSelector.
     */
    function facetAddress(bytes4 _functionSelector) internal view returns (address) {
        DiamondStorage storage ds = diamondStorage();
        return ds.facets[_functionSelector];
    }

    /**
     * @notice Checks if an address is a contract.
     * @param _addr The address to check.
     * @return True if the address contains contract code, false otherwise.
     */
    function isContract(address _addr) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(_addr)
        }
        return size > 0;
    }
}