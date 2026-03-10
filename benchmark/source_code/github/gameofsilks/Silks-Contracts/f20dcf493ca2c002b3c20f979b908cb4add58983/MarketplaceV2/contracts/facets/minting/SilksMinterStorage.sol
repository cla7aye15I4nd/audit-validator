// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import {EnumerableSet} from "@solidstate/contracts/data/EnumerableSet.sol";
import {ContractType} from "../../utils/constants.sol";

library SilksMinterStorage {
    using SilksMinterStorage for Layout;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;

    bytes32 internal constant STORAGE_SLOT =
        keccak256("silks.contracts.storage.Minter");

    // Custom errors for specific revert scenarios
    error ContractIdentifierDoesNotExist(address _contractAddress);
    error ContractAlreadyExists(address _contractAddress);
    error InvalidOverlapInDiscounts(uint256 _seasonId, uint256 _discountId);
    error IdentifierNotFound(address _contractAddress);
    error DuplicatePayTier(uint256 _tier);

    struct Discount {
        uint256 discount; // Percentage for discount
        uint256 discountExpiration; // Unix timestamp for discount expiration
        uint256 discountStartDate; // Unix timestamp for discount start date
        EnumerableSet.UintSet usedAvatarTokens; // Set of avatar tokens that have used the discount
        uint256 avatarStartId; // Start of avatar token range
        uint256 avatarEndId; // End of avatar token range
    }

    struct ContractData {
        address contractAddress; // Address of the contract
        string mintFunctionSignature; // Signature of the mint function
        ContractType contractType; // Type of contract
        bool isPriceUSD; // Boolean to check if price is in USD
        mapping(uint256 => uint256) tierToPrice; // Mapping of tier to price
        EnumerableSet.UintSet tiers; // Set of tiers
    }

    struct Layout {
        mapping(uint256 => Discount[]) seasonIdToDiscounts; // Mapping of seasonId to discounts
        mapping(address => ContractData) contractsData; // Mapping of contract address to contract data
        EnumerableSet.AddressSet addresses; // Set of contract addresses
        address avatarAddress; // Address of the avatar contract
        bool mintingExclusiveToAvatarHolders; // Boolean to check if minting is exclusive to avatar holders
        uint256 mintingExclusionStartDateTime; // Unix timestamp for minting exclusion start date
        uint256 mintingExclusionEndDateTime; // Unix timestamp for minting exclusion end date
        address priceFeedAddress; // Address of the price feed for ETH/USD conversion
    }

    struct AddPayTier {
        uint256 tier;
        uint256 price;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }

    function removeContractData(
        Layout storage l,
        address contractAddress
    ) internal {
        if (l.contractsData[contractAddress].contractAddress == address(0))
            revert ContractIdentifierDoesNotExist(contractAddress);
        delete l.contractsData[contractAddress];
        l.addresses.remove(contractAddress);
    }

    function contains(
        Layout storage l,
        address contractAddress
    ) internal view returns (bool) {
        return l.addresses.contains(contractAddress);
    }

    function addContract(
        Layout storage l,
        address contractAddress,
        string memory mintFunctionSignature,
        ContractType contractType,
        bool isPriceUSD,
        AddPayTier[] memory payTiers
    ) internal {
        if (l.contractsData[contractAddress].contractAddress != address(0))
            revert ContractAlreadyExists(contractAddress);

        ContractData storage contractData = l.contractsData[contractAddress];
        contractData.contractAddress = contractAddress;
        contractData.mintFunctionSignature = mintFunctionSignature;
        contractData.contractType = contractType;
        contractData.isPriceUSD = isPriceUSD;

        uint256 i;
        uint256 length = payTiers.length;
        for (; i < length; ) {
            setPayTier(l, contractAddress, payTiers[i].tier, payTiers[i].price);

            unchecked {
                ++i;
            }
        }

        l.addresses.add(contractAddress);
    }

    function addDiscount(
        Layout storage l,
        address contractAddress,
        uint256 discount,
        uint256 discountExpiration,
        uint256 discountStartDate,
        uint256 avatarStartId,
        uint256 avatarEndId,
        uint256 seasonId
    ) internal {
        if (l.contractsData[contractAddress].contractAddress == address(0))
            revert ContractIdentifierDoesNotExist(contractAddress);

        uint256 i;
        uint256 length = l.seasonIdToDiscounts[seasonId].length;
        for (; i < length; ) {
            Discount storage existingDiscount = l.seasonIdToDiscounts[seasonId][
                i
            ];
            bool isTimeOverlapping = (discountStartDate <
                existingDiscount.discountExpiration) &&
                (discountExpiration > existingDiscount.discountStartDate);
            bool isTokenIdRangeOverlapping = !(avatarEndId <
                existingDiscount.avatarStartId ||
                avatarStartId > existingDiscount.avatarEndId);
            if (isTimeOverlapping && isTokenIdRangeOverlapping)
                revert InvalidOverlapInDiscounts(seasonId, i);
            unchecked {
                ++i;
            }
        }

        Discount storage newDiscount = l.seasonIdToDiscounts[seasonId].push();

        newDiscount.discount = discount;
        newDiscount.discountExpiration = discountExpiration;
        newDiscount.discountStartDate = discountStartDate;
        newDiscount.avatarStartId = avatarStartId;
        newDiscount.avatarEndId = avatarEndId;
    }

    function removeContract(
        Layout storage l,
        address contractAddress
    ) internal {
        if (!l.contains(contractAddress))
            revert IdentifierNotFound(contractAddress);
        l.removeContractData(contractAddress);
    }

    function updateContract(
        Layout storage l,
        address oldContractAddress,
        address newContractAddress,
        string calldata newFunctionSignature,
        ContractType newContractType,
        bool isPriceUSD,
        AddPayTier[] calldata payTiers
    ) internal {
        if (!l.contains(oldContractAddress)) {
            revert IdentifierNotFound(oldContractAddress);
        }

        l.removeContractData(oldContractAddress);

        ContractData storage contractData = l.contractsData[newContractAddress];
        contractData.contractAddress = newContractAddress;
        contractData.mintFunctionSignature = newFunctionSignature;
        contractData.contractType = newContractType;
        contractData.isPriceUSD = isPriceUSD;
        

        uint256 i;
        uint256 length = contractData.tiers.length();
        for (; i < length; ) {
            delete contractData.tierToPrice[contractData.tiers.at(i)];

            unchecked {
                ++i;
            }
        }

        uint256 j;
        uint256 payTiersLength = payTiers.length;
        for (; j < payTiersLength; ) {
            setPayTier(
                l,
                newContractAddress,
                payTiers[j].tier,
                payTiers[j].price
            );

            unchecked {
                ++j;
            }
        }
    }

    function getContract(
        Layout storage l,
        address contractAddress
    ) internal view returns (ContractData storage) {
        if (l.contractsData[contractAddress].contractAddress == address(0)) {
            revert ContractIdentifierDoesNotExist(contractAddress);
        }

        return l.contractsData[contractAddress];
    }

    function getAllIdentifiers(
        Layout storage l
    ) internal view returns (address[] memory) {
        uint256 i;
        uint256 addressesLength = l.addresses.length();
        address[] memory addresses = new address[](addressesLength);

        for (; i < addressesLength; ) {
            addresses[i] = l.addresses.at(i);
            unchecked {
                ++i;
            }
        }
        return addresses;
    }

    /**
     * @notice Returns the Price Feed address
     * @return priceFeed Price Feed address
     */
    function getPriceFeed(
        Layout storage l
    ) internal view returns (AggregatorV3Interface priceFeed) {
        priceFeed = AggregatorV3Interface(l.priceFeedAddress);

        return priceFeed;
    }

    /**
     * @notice Returns the latest price
     * @return latest price
     */
    function getLatestPrice(Layout storage l) internal view returns (uint256) {
        AggregatorV3Interface priceFeed = l.getPriceFeed();
        (, int256 price, , , ) = priceFeed.latestRoundData();

        return uint256(price);
    }

    // convertUSDtoWei
    function convertUSDtoWei(
        Layout storage l,
        uint256 _price
    ) internal view returns (uint256) {
        return (1e18 / (getLatestPrice(l) / 1e6)) * _price;
    }

    function setPayTier(
        Layout storage l,
        address _contractAddress,
        uint256 _tier,
        uint256 _price
    ) public {
        ContractData storage contractData = getContract(l, _contractAddress);

        if (contractData.tiers.contains(_tier)) {
            revert DuplicatePayTier(_tier);
        }

        contractData.tiers.add(_tier);
        contractData.tierToPrice[_tier] = _price;        
    }
}
