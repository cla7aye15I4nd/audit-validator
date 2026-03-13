// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {SilksMinterStorage} from "./SilksMinterStorage.sol";
import {EnumerableSet} from "@solidstate/contracts/data/EnumerableSet.sol";
import {ContractType} from "../../utils/constants.sol";
import {IERC721Mintable} from "../../interfaces/IERC721Mintable.sol";
import {IAvatarNFT} from "../../interfaces/IAvatarNFT.sol";
import {IHorseNFT} from "../../interfaces/IHorseNFT.sol";
import {AccessControlInternal} from "@solidstate/contracts/access/access_control/AccessControlInternal.sol";
import {MINTER_ADMIN_ROLE} from "../../utils/constants.sol";

contract SilksMinterFacet is AccessControlInternal {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;
    using SilksMinterStorage for SilksMinterStorage.Layout;

    /// @notice Emitted when new tokens are minted
    /// @param contractAddress The address of the contract where minting occurred
    /// @param to The address receiving the minted tokens
    /// @param quantity The number of tokens minted
    /// @param value The value associated with the minting event
    event Minted(
        address contractAddress,
        address indexed to,
        uint256 quantity,
        uint256 value
    );

    /// @notice Emitted when tokens are airdropped to an address
    /// @param contractAddress The address of the contract from which the airdrop is initiated
    /// @param to The address receiving the airdropped tokens
    /// @param quantity The number of tokens airdropped
    event Airdropped(
        address contractAddress,
        address indexed to,
        uint256 quantity
    );

    /// @dev Parameters required for minting operations, specifying season and payout tier for Horses, alongside quantity and recipient address
    /// @param seasonId The season ID related to the Horse
    /// @param payoutTier The payout tier for the Horse
    /// @param quantity The number of tokens to mint
    /// @param to The recipient address for the minted tokens
    struct MintParams {
        uint256 seasonId;
        uint256 payoutTier;
        uint256 quantity;
        address to;
    }

    /// @dev Structure defining a HorseV2 discount an avatar is entitled to, including the AvatarID, index, and percentage of the discount
    /// @param avatarId The unique ID for the avatar
    /// @param discountIndex The index for tracking the discount
    /// @param discountPercentage The percentage of the discount
    struct AvatarDiscount {
        uint256 avatarId;
        int256 discountIndex;
        uint256 discountPercentage;
    }

    /// @dev Represents the return structure for a discount query, detailing the discount, its validity period, and affected avatars
    /// @param discount The discount percentage
    /// @param discountStartDate The start date for the discount period
    /// @param discountExpiration The expiration date for the discount period
    /// @param avatarStartId The starting ID of avatars eligible for the discount
    /// @param avatarEndId The ending ID of avatars eligible for the discount
    /// @param usedAvatarTokens The IDs of avatars that have already used the discount
    struct DiscountReturn {
        uint256 discount;
        uint256 discountStartDate;
        uint256 discountExpiration;
        uint256 avatarStartId;
        uint256 avatarEndId;
        uint256[] usedAvatarTokens;
    }

    error MintExlusiveToAvatarHolders();
    error InsufficientFunds(uint256 _required, uint256 _sent);
    error MintingFailed(bytes data);
    error IncorrectAvatarOwner(
        uint256 _avatarId,
        address _owner,
        address _sender
    );
    error DiscountNotFound(uint256 _discountIndex);
    error AvatarNotEligibleForDiscount(uint256 _avatarId, uint256 _seasonId);
    error InvalidPayoutTier(uint256 _payoutTier);

    /**
     * @notice Modifier to check if HorseV2 minting is exclusive to Avatar holders
     * @param contractAddress The address of the contract that tokens are being
     * minted for
     */
    modifier checkMintingExclusiveToAvatarHolders(address contractAddress) {
        SilksMinterStorage.Layout storage l = SilksMinterStorage.layout();

        // If the contractAddress is for contractType.HorseV2, then we need to
        // check if the minting is exclusive to Avatar holders
        if (l.mintingExclusiveToAvatarHolders) {
            if (
                l.getContract(contractAddress).contractType ==
                ContractType.HorseV2
            ) {
                if (
                    block.timestamp >= l.mintingExclusionStartDateTime &&
                    block.timestamp <= l.mintingExclusionEndDateTime
                ) {
                    if (
                        IAvatarNFT(l.avatarAddress).balanceOf(msg.sender) == 0
                    ) {
                        revert MintExlusiveToAvatarHolders();
                    }
                }
            }
        }

        _;
    }

    /**
     * @notice External function to mint tokens to the specified address
     * @dev This is the main function for web3 minting to purchase and mint tokens.
     * @param contractAddress The address of the contract to mint tokens to
     * @param params The minting parameters
     * @param additionalPayload The additional payload to be used for minting
     * @param avatarIds The avatarIds to be added to the usedAvatarTokens list
     */
    function mint(
        address contractAddress,
        MintParams memory params,
        bytes memory additionalPayload,
        uint256[] calldata avatarIds
    ) public payable checkMintingExclusiveToAvatarHolders(contractAddress) {
        SilksMinterStorage.Layout storage l = SilksMinterStorage.layout();
        SilksMinterStorage.ContractData storage contractData = l.getContract(
            contractAddress
        );
        IAvatarNFT avatarContract = IAvatarNFT(l.avatarAddress);

        mintTokens(contractAddress, params, additionalPayload);

        // Calculate price and check if the user has sent enough value
        uint256 pricePerToken = tokenPrice(contractAddress, params.payoutTier);
        uint256 requiredValue = pricePerToken * params.quantity;

        if (contractData.contractType == ContractType.HorseV2) {
            uint256 totalDiscount = calculateDiscount(
                avatarIds,
                pricePerToken,
                avatarContract,
                params.quantity,
                params.seasonId
            );

            requiredValue -= totalDiscount;
        }

        // Emit an event with mint details
        emit Minted(contractAddress, params.to, params.quantity, requiredValue);

        if (msg.value < requiredValue) {
            revert InsufficientFunds(requiredValue, msg.value);
        }

        // Refund excess value
        if (msg.value > requiredValue) {
            payable(msg.sender).transfer(msg.value - requiredValue);
        }
    }

    /**
     * Airdrops tokens to the specified address and adds the avatarIds to the usedAvatarTokens list
     * @param contractAddress The address of the contract to airdrop tokens to
     * @param params The minting parameters
     * @param additionalPayload The additional payload to be used for minting
     */
    function airdrop(
        address contractAddress,
        MintParams memory params,
        bytes memory additionalPayload
    ) external onlyRole(MINTER_ADMIN_ROLE) {
        mintTokens(contractAddress, params, additionalPayload);

        emit Airdropped(contractAddress, params.to, params.quantity);
    }

    /**
     * Airdrops tokens to the specified address and adds the avatarIds to the usedAvatarTokens list
     * @param contractAddress The address of the contract to airdrop tokens to
     * @param params The minting parameters
     * @param additionalPayload The additional payload to be used for minting
     * @param avatarIds The avatarIds to be added to the usedAvatarTokens list
     */
    function airdrop(
        address contractAddress,
        MintParams memory params,
        bytes memory additionalPayload,
        uint256[] calldata avatarIds
    ) external onlyRole(MINTER_ADMIN_ROLE) {
        mintTokens(contractAddress, params, additionalPayload);

        emit Airdropped(contractAddress, params.to, params.quantity);

        uint256 i;
        uint256 tokenIdLength = avatarIds.length;
        for (; i < tokenIdLength; ) {
            (int256 discountIndex, ) = getDiscountForAvatar(
                avatarIds[i],
                params.seasonId
            );

            if (discountIndex == -1) {
                revert AvatarNotEligibleForDiscount(
                    avatarIds[i],
                    params.seasonId
                );
            }

            SilksMinterStorage
                .layout()
                .seasonIdToDiscounts[params.seasonId][uint256(discountIndex)]
                .usedAvatarTokens
                .add(avatarIds[i]);

            unchecked {
                ++i;
            }
        }
    }

    function tokenPrice(
        address contractAddress,
        uint256 tier // 0 for no tiers
    ) public view returns (uint256 price) {
        SilksMinterStorage.Layout storage l = SilksMinterStorage.layout();
        SilksMinterStorage.ContractData storage contractData = l.getContract(
            contractAddress
        );
        if (!contractData.tiers.contains(tier)) {
            revert InvalidPayoutTier(tier);
        }

        uint256 _tokenPrice = contractData.tierToPrice[tier];

        return
            contractData.isPriceUSD
                ? l.convertUSDtoWei(_tokenPrice)
                : _tokenPrice;
    }

    /**
     *  Mint tokens to the specified address
     * @param contractAddress  The address of the contract to mint tokens to
     * @param params The minting parameters
     * @param additionalPayload  The additional payload to be used for minting
     */
    function mintTokens(
        address contractAddress,
        MintParams memory params,
        bytes memory additionalPayload
    ) internal {
        SilksMinterStorage.Layout storage l = SilksMinterStorage.layout();
        SilksMinterStorage.ContractData storage contractData = l.getContract(
            contractAddress
        );

        IERC721Mintable tokenContract = IERC721Mintable(
            contractData.contractAddress
        );

        if (contractData.contractType == ContractType.HorseV2) {
            IHorseNFT(contractData.contractAddress).externalMint(
                params.seasonId,
                params.payoutTier,
                params.quantity,
                params.to
            );
        } else if (contractData.contractType == ContractType.Avatar) {
            IAvatarNFT(contractData.contractAddress).mint(
                params.to,
                params.quantity
            );
        } else {
            (bool success, bytes memory data) = address(tokenContract).call(
                additionalPayload
            );
            if (!success) {
                revert MintingFailed(data);
            }
        }
    }

    function calculateDiscount(
        uint256[] calldata avatarIds,
        uint256 pricePerToken,
        IAvatarNFT avatarContract,
        uint256 maxDiscounts,
        uint256 seasonId
    ) internal returns (uint256 totalDiscount) {
        SilksMinterStorage.Layout storage l = SilksMinterStorage.layout();

        uint256 appliedDiscounts;
        uint256 i;
        uint256 avatarsLength = avatarIds.length;
        for (; i < avatarsLength; ) {
            if (appliedDiscounts >= maxDiscounts) {
                break;
            }

            uint256 avatarId = avatarIds[i];
            uint256 j = 0;
            uint256 discountLength = l.seasonIdToDiscounts[seasonId].length;
            for (; j < discountLength; ) {
                SilksMinterStorage.Discount storage discount = l
                    .seasonIdToDiscounts[seasonId][j];

                if (
                    block.timestamp >= discount.discountStartDate &&
                    block.timestamp <= discount.discountExpiration &&
                    avatarId >= discount.avatarStartId &&
                    avatarId <= discount.avatarEndId &&
                    !discount.usedAvatarTokens.contains(avatarId)
                ) {
                    if (avatarContract.ownerOf(avatarId) != msg.sender) {
                        revert IncorrectAvatarOwner(
                            avatarId,
                            avatarContract.ownerOf(avatarId),
                            msg.sender
                        );
                    }

                    totalDiscount += (pricePerToken * discount.discount) / 100;
                    appliedDiscounts++;

                    discount.usedAvatarTokens.add(avatarId);

                    break;
                }

                unchecked {
                    ++j;
                }
            }

            unchecked {
                ++i;
            }
        }
    }

    /**
     * Check if an avatar is eligible for a discount
     * @param avatarId  The avatar ID to check for discount
     * @param seasonId  The season ID to check for discount
     */
    function isAvatarEligibleForDiscount(
        uint256 avatarId,
        uint256 seasonId
    ) public view returns (bool) {
        SilksMinterStorage.Layout storage l = SilksMinterStorage.layout();

        uint256[] memory currentDiscounts = getActiveDiscountIds(seasonId);

        uint256 i;
        uint256 currentDiscountsLength = currentDiscounts.length;
        for (; i < currentDiscountsLength; ) {
            SilksMinterStorage.Discount storage discount = l
                .seasonIdToDiscounts[seasonId][currentDiscounts[i]];

            if (
                avatarId >= discount.avatarStartId &&
                avatarId <= discount.avatarEndId &&
                !discount.usedAvatarTokens.contains(avatarId)
            ) {
                return true;
            }

            unchecked {
                ++i;
            }
        }
        return false;
    }

    /**
     * Get the count of active discounts for a given seasonId
     * @param seasonId The season ID to check for active discounts
     * @return currentDiscountsCount uint256 The count of active discounts
     */
    function getActiveDiscountCount(
        uint256 seasonId
    ) public view returns (uint256 currentDiscountsCount) {
        SilksMinterStorage.Layout storage l = SilksMinterStorage.layout();

        uint256 i;
        uint256 discountLength = l.seasonIdToDiscounts[seasonId].length;
        for (; i < discountLength; ) {
            SilksMinterStorage.Discount storage discount = l
                .seasonIdToDiscounts[seasonId][i];

            if (
                block.timestamp >= discount.discountStartDate &&
                block.timestamp <= discount.discountExpiration
            ) {
                currentDiscountsCount++;
            }

            unchecked {
                ++i;
            }
        }

        return currentDiscountsCount;
    }

    /**
     * @notice Returns the discount IDs that are currently active for a given seasonId
     * @param seasonId The season ID to check for active discounts
     * @return currentDiscounts uint256[] The active discount IDs
     */
    function getActiveDiscountIds(
        uint256 seasonId
    ) public view returns (uint256[] memory currentDiscounts) {
        SilksMinterStorage.Layout storage l = SilksMinterStorage.layout();

        uint256 count = getActiveDiscountCount(seasonId);
        uint256[] memory activeDiscounts = new uint256[](count);

        uint256 activeDiscountTrackerIndex = 0;
        uint256 i;
        uint256 discountLength = l.seasonIdToDiscounts[seasonId].length;
        for (; i < discountLength; ) {
            SilksMinterStorage.Discount storage discount = l
                .seasonIdToDiscounts[seasonId][i];

            if (
                block.timestamp >= discount.discountStartDate &&
                block.timestamp <= discount.discountExpiration
            ) {
                activeDiscounts[activeDiscountTrackerIndex] = i;
                activeDiscountTrackerIndex++;
            }

            unchecked {
                ++i;
            }
        }
        return activeDiscounts;
    }

    /**
     * @notice Returns the active discounts for a given seasonId
     * @param seasonId The season ID to check for active discounts
     * @return activeDiscounts DiscountReturn[] The active discounts
     */
    function getActiveDiscounts(
        uint256 seasonId
    ) public view returns (DiscountReturn[] memory activeDiscounts) {
        SilksMinterStorage.Layout storage l = SilksMinterStorage.layout();

        uint256 count = getActiveDiscountCount(seasonId);
        activeDiscounts = new DiscountReturn[](count);

        uint256 activeDiscountTrackerIndex = 0;
        uint256 i;
        uint256 discountLength = l.seasonIdToDiscounts[seasonId].length;
        for (; i < discountLength; ) {
            SilksMinterStorage.Discount storage discount = l
                .seasonIdToDiscounts[seasonId][i];

            if (
                block.timestamp >= discount.discountStartDate &&
                block.timestamp <= discount.discountExpiration
            ) {
                // activeDiscounts[activeDiscountTrackerIndex] = discount;
                DiscountReturn memory _discount = DiscountReturn({
                    discount: discount.discount,
                    discountExpiration: discount.discountExpiration,
                    discountStartDate: discount.discountStartDate,
                    usedAvatarTokens: discount.usedAvatarTokens.toArray(),
                    avatarStartId: discount.avatarStartId,
                    avatarEndId: discount.avatarEndId
                });
                activeDiscounts[activeDiscountTrackerIndex] = _discount;
                activeDiscountTrackerIndex++;
            }

            unchecked {
                ++i;
            }
        }
        return activeDiscounts;
    }

    /**
     * @notice Returns all discounts for a given seasonId, regardless of whether they are active or not
     * @param seasonId The season ID to check for active discounts
     * @return allDiscounts DiscountReturn[] The active discounts
     */
    function getAllDiscounts(
        uint256 seasonId
    ) public view returns (DiscountReturn[] memory allDiscounts) {
        SilksMinterStorage.Layout storage l = SilksMinterStorage.layout();

        uint256 count = l.seasonIdToDiscounts[seasonId].length;
        allDiscounts = new DiscountReturn[](count);

        uint256 i;
        for (; i < count; ) {
            SilksMinterStorage.Discount storage discount = l
                .seasonIdToDiscounts[seasonId][i];

            DiscountReturn memory _discount = DiscountReturn({
                discount: discount.discount,
                discountExpiration: discount.discountExpiration,
                discountStartDate: discount.discountStartDate,
                usedAvatarTokens: discount.usedAvatarTokens.toArray(),
                avatarStartId: discount.avatarStartId,
                avatarEndId: discount.avatarEndId
            });
            allDiscounts[i] = _discount;

            unchecked {
                ++i;
            }
        }
        return allDiscounts;
    }

    struct ContractDataReturn {
        address contractAddress;
        string mintFunctionSignature;
        ContractType contractType;
        bool isPriceUSD;
        SilksMinterStorage.AddPayTier[] payTiers;
        uint256[] tiers;
    }

    /**
     * @notice Get the contract data for a given contract address
     * @param _contractAddress The address of the contract to get ContractData for
     * @return _contractData SilksMinterStorage.ContractData The ContractData for the contract
     */
    function getContract(
        address _contractAddress
    )
        public
        view
        returns (ContractDataReturn memory _contractData)
    // address contractAddress,
    // string memory mintFunctionSignature,
    // ContractType contractType,
    // bool isPriceUSD,
    // SilksMinterStorage.AddPayTier[] memory payTiers,
    // uint256[] memory tiers
    {
        SilksMinterStorage.ContractData
            storage contractData = SilksMinterStorage.layout().getContract(
                _contractAddress
            );

        _contractData.contractAddress = contractData.contractAddress;
        _contractData.mintFunctionSignature = contractData
            .mintFunctionSignature;
        _contractData.contractType = contractData.contractType;
        _contractData.isPriceUSD = contractData.isPriceUSD;
        _contractData.payTiers = new SilksMinterStorage.AddPayTier[](
            contractData.tiers.length()
        );
        _contractData.tiers = contractData.tiers.toArray();

        uint256 i;
        uint256 tiersLength = contractData.tiers.length();
        for (; i < tiersLength; ) {
            _contractData.payTiers[i] = SilksMinterStorage.AddPayTier({
                tier: _contractData.tiers[i],
                price: contractData.tierToPrice[_contractData.tiers[i]]
            });

            unchecked {
                ++i;
            }
        }

        return (_contractData);
    }

    /**
     * @notice Return all contract data currently on the marketplace
     * @return contractData SilksMinterStorage.ContractData[] The ContractData for all contracts on the marketplace
     */
    function getContracts()
        public
        view
        returns (ContractDataReturn[] memory contractData)
    {
        SilksMinterStorage.Layout storage l = SilksMinterStorage.layout();

        uint256 count = l.addresses.length();
        uint256 i;
        contractData = new ContractDataReturn[](count);
        for (; i < count; ) {
            contractData[i] = getContract(l.addresses.at(i));

            unchecked {
                ++i;
            }
        }

        return contractData;
    }

    /**
     * @notice Get the discount data for a given discount index and seasonId
     * @param discountIndex The index of the discount to get data for
     * @param seasonId The season ID to get discount data for
     * @return discountPercentage The discount percentage
     * @return discountStartDate Unix timestamp for the start date of the discount
     * @return discountExpiration Unix timestamp for the expiration date of the discount
     * @return usedAvatarTokens Array of avatar tokens that have used the discount
     * @return avatarStartId Start ID of the AvatarNFT's range for this discount
     * @return avatarEndId End ID of the AvatarNFT's range for this discount
     */
    function getDiscount(
        uint256 discountIndex,
        uint256 seasonId
    )
        public
        view
        returns (
            uint256 discountPercentage,
            uint256 discountStartDate,
            uint256 discountExpiration,
            uint256[] memory usedAvatarTokens, // Using EnumerableSet for efficient tracking
            uint256 avatarStartId, // Start ID of the AvatarNFT's range for this discount
            uint256 avatarEndId // End ID of the AvatarNFT's range for this discount
        )
    {
        SilksMinterStorage.Layout storage l = SilksMinterStorage.layout();

        if (l.seasonIdToDiscounts[seasonId].length <= discountIndex) {
            revert DiscountNotFound(discountIndex);
        }

        SilksMinterStorage.Discount storage discountData = SilksMinterStorage
            .layout()
            .seasonIdToDiscounts[seasonId][discountIndex];

        discountPercentage = discountData.discount;
        discountStartDate = discountData.discountStartDate;
        discountExpiration = discountData.discountExpiration;
        avatarStartId = discountData.avatarStartId;
        avatarEndId = discountData.avatarEndId;
        usedAvatarTokens = discountData.usedAvatarTokens.toArray();

        return (
            discountPercentage,
            discountStartDate,
            discountExpiration,
            usedAvatarTokens,
            avatarStartId,
            avatarEndId
        );
    }

    /**
     * @notice Get the address for the Avatar contract on this chain.
     */
    function getAvatarAddress() public view returns (address) {
        return SilksMinterStorage.layout().avatarAddress;
    }

    /**
     * @notice Get the address for the price feed.
     */
    function getPriceFeed() public view returns (address) {
        return SilksMinterStorage.layout().priceFeedAddress;
    }

    /**
     * Given an array of avatarIds and a seasonId, return the avatars that are eligible for a discount
     * @param avatarIds Array of avatarIds to check for discount
     * @param seasonId Season ID to check for discount
     */
    function getEligibleAvatarsForDiscount(
        uint256[] calldata avatarIds,
        uint256 seasonId
    ) public view returns (uint256[] memory eligibleAvatars) {
        uint256 avatarLength = avatarIds.length;
        uint256 eligibleAvatarTrackerIndex;
        uint256 i;
        for (; i < avatarLength; ) {
            if (isAvatarEligibleForDiscount(avatarIds[i], seasonId)) {
                eligibleAvatars[eligibleAvatarTrackerIndex] = avatarIds[i];
                eligibleAvatarTrackerIndex++;
            }

            unchecked {
                ++i;
            }
        }

        return eligibleAvatars;
    }

    /**
     * Given an avatarId and a seasonId, return the discount index and percentage for the avatar.
     * @param avatarId Avatar ID to check for discount
     * @param seasonId  Season ID to check for discount
     * @return discountIndex int256 The index of the discount
     * @return discountPercentage uint256 The discount percentage
     */
    function getDiscountForAvatar(
        uint256 avatarId,
        uint256 seasonId
    ) private view returns (int256 discountIndex, uint256 discountPercentage) {
        SilksMinterStorage.Layout storage l = SilksMinterStorage.layout();

        uint256[] memory currentDiscounts = getActiveDiscountIds(seasonId);

        uint256 i;
        uint256 currentDiscountsLength = currentDiscounts.length;
        for (; i < currentDiscountsLength; ) {
            SilksMinterStorage.Discount storage discount = l
                .seasonIdToDiscounts[seasonId][currentDiscounts[i]];

            if (
                avatarId >= discount.avatarStartId &&
                avatarId <= discount.avatarEndId &&
                !discount.usedAvatarTokens.contains(avatarId)
            ) {
                return (int256(currentDiscounts[i]), discount.discount);
            }

            unchecked {
                ++i;
            }
        }

        discountIndex = -1;
        discountPercentage = 0;
        return (discountIndex, discountPercentage);
    }

    /**
     * Given an array of avatarIds and a seaosonId, return the avatars that are eligible for a discount
     * and the discountIndex for the given avatarId.
     * @param avatarIds Array of avatarIds to check for discount
     * @param seasonId Season ID to check for discount
     * @return eligibleAvatarsDiscounts AvatarDiscount[] Array of eligible avatars and their discountIndexes
     */
    function getDiscountsForAvatars(
        uint256[] calldata avatarIds,
        uint256 seasonId
    ) public view returns (AvatarDiscount[] memory eligibleAvatarsDiscounts) {
        uint256 avatarLength = avatarIds.length;
        eligibleAvatarsDiscounts = new AvatarDiscount[](avatarLength); // Initialize with maximum possible size
        uint256 eligibleAvatarCount = 0;

        for (uint256 i = 0; i < avatarLength; i++) {
            if (isAvatarEligibleForDiscount(avatarIds[i], seasonId)) {
                eligibleAvatarsDiscounts[eligibleAvatarCount]
                    .avatarId = avatarIds[i];
                // Set discountIndex and discountPercentage
                (
                    eligibleAvatarsDiscounts[eligibleAvatarCount].discountIndex,
                    eligibleAvatarsDiscounts[eligibleAvatarCount]
                        .discountPercentage
                ) = getDiscountForAvatar(avatarIds[i], seasonId);
                eligibleAvatarCount++;
            }
        }
        // Note: Here, you might need to adjust the array size if you want to strictly return only the eligible ones

        return eligibleAvatarsDiscounts;
    }
}
