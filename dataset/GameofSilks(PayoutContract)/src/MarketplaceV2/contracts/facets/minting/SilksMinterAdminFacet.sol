// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {SilksMinterStorage} from "./SilksMinterStorage.sol";
import {EnumerableSet} from "@solidstate/contracts/data/EnumerableSet.sol";
import {ContractType} from "../../utils/constants.sol";
import {IAvatarNFT} from "../../interfaces/IAvatarNFT.sol";
import {AccessControlInternal} from "@solidstate/contracts/access/access_control/AccessControlInternal.sol";
import {MINTER_ADMIN_ROLE} from "../../utils/constants.sol";
import {CONTRACT_ADMIN_ROLE} from "../../SilksMarketplaceStorage.sol";

contract SilksMinterAdminFacet is AccessControlInternal {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;
    using SilksMinterStorage for SilksMinterStorage.Layout;

    // Custom errors
    error InvalidDiscountIndex();
    error DiscountMustBeGreaterThanZero();
    error InvalidDiscountDuration();
    error InvalidAvatarIdRange();
    error DiscountAvatarIdRangeOverlap();

    function addUsedAvatarTokenId(
        uint256 tokenId,
        uint256 seasonId,
        uint256 discountIndex
    ) external onlyRole(MINTER_ADMIN_ROLE) {
        EnumerableSet.UintSet storage usedAvatarTokens = SilksMinterStorage
        .layout()
        .seasonIdToDiscounts[seasonId][discountIndex].usedAvatarTokens;

        usedAvatarTokens.add(tokenId);
    }

    function addUsedAvatarTokenIds(
        uint256[] calldata tokenIds,
        uint256 seasonId,
        uint256 discountIndex
    ) external onlyRole(MINTER_ADMIN_ROLE) {
        EnumerableSet.UintSet storage usedAvatarTokens = SilksMinterStorage
        .layout()
        .seasonIdToDiscounts[seasonId][discountIndex].usedAvatarTokens;

        uint256 i;
        uint256 tokenIdLength = tokenIds.length;
        for (; i < tokenIdLength; ) {
            usedAvatarTokens.add(tokenIds[i]);

            unchecked {
                ++i;
            }
        }
    }

    function removeUsedAvatarTokenId(
        uint256 tokenId,
        uint256 seasonId,
        uint256 discountIndex
    ) external onlyRole(MINTER_ADMIN_ROLE) {
        EnumerableSet.UintSet storage usedAvatarTokens = SilksMinterStorage
        .layout()
        .seasonIdToDiscounts[seasonId][discountIndex].usedAvatarTokens;

        usedAvatarTokens.remove(tokenId);
    }

    function removeUsedAvatarTokenIds(
        uint256[] calldata tokenIds,
        uint256 seasonId,
        uint256 discountIndex
    ) external onlyRole(MINTER_ADMIN_ROLE) {
        EnumerableSet.UintSet storage usedAvatarTokens = SilksMinterStorage
        .layout()
        .seasonIdToDiscounts[seasonId][discountIndex].usedAvatarTokens;

        uint256 i;
        uint256 tokenIdLength = tokenIds.length;
        for (; i < tokenIdLength; ) {
            usedAvatarTokens.remove(tokenIds[i]);

            unchecked {
                ++i;
            }
        }
    }

    function updateDiscount(
        uint256 discountIndex,
        uint256 newDiscountPercentage,
        uint256 newDiscountStartDate,
        uint256 newDiscountExpiration,
        uint256 avatarStartId,
        uint256 avatarEndId,
        uint256 seasonId
    ) external onlyRole(MINTER_ADMIN_ROLE) {
        SilksMinterStorage.Layout storage l = SilksMinterStorage.layout();
        if (discountIndex >= l.seasonIdToDiscounts[seasonId].length)
            revert InvalidDiscountIndex();

        SilksMinterStorage.Discount storage discount = l.seasonIdToDiscounts[
            seasonId
        ][discountIndex];

        discount.discount = newDiscountPercentage;
        discount.discountStartDate = newDiscountStartDate;
        discount.discountExpiration = newDiscountExpiration;
        discount.avatarStartId = avatarStartId;
        discount.avatarEndId = avatarEndId;
    }

    function removeDiscount(
        uint256 discountIndex,
        uint256 seasonId
    ) external onlyRole(MINTER_ADMIN_ROLE) {
        SilksMinterStorage.Layout storage l = SilksMinterStorage.layout();
        if (discountIndex >= l.seasonIdToDiscounts[seasonId].length)
            revert InvalidDiscountIndex();

        uint256 lastIndex = l.seasonIdToDiscounts[seasonId].length - 1;
        if (discountIndex != lastIndex) {
            if (discountIndex != lastIndex) {
                // Copy the last element to the index to be removed
                uint256 seasonLength = l.seasonIdToDiscounts[seasonId].length;

                l.seasonIdToDiscounts[seasonId][discountIndex].discount = l
                .seasonIdToDiscounts[seasonId][seasonLength - 1].discount;

                l
                .seasonIdToDiscounts[seasonId][discountIndex]
                    .discountStartDate = l
                .seasonIdToDiscounts[seasonId][seasonLength - 1]
                    .discountStartDate;

                l
                .seasonIdToDiscounts[seasonId][discountIndex]
                    .discountExpiration = l
                .seasonIdToDiscounts[seasonId][seasonLength - 1]
                    .discountExpiration;

                l.seasonIdToDiscounts[seasonId][discountIndex].avatarStartId = l
                .seasonIdToDiscounts[seasonId][seasonLength - 1].avatarStartId;

                l.seasonIdToDiscounts[seasonId][discountIndex].avatarEndId = l
                .seasonIdToDiscounts[seasonId][seasonLength - 1].avatarEndId;

                EnumerableSet.UintSet storage idsToRemove = l
                .seasonIdToDiscounts[seasonId][discountIndex].usedAvatarTokens;
                EnumerableSet.UintSet storage idsToReplaceIt = l
                .seasonIdToDiscounts[seasonId][seasonLength - 1]
                    .usedAvatarTokens;

                // Remove all from idsToRemove
                uint256 i;
                uint256 idsToRemoveLength = idsToRemove.length();
                for (; i < idsToRemoveLength; ) {
                    idsToRemove.remove(idsToRemove.at(i));

                    unchecked {
                        ++i;
                    }
                }

                // Add all from idsToReplaceIt
                i = 0;
                for (; i < idsToRemoveLength; ) {
                    idsToRemove.add(idsToReplaceIt.at(i));

                    unchecked {
                        ++i;
                    }
                }
            }
        }
        l.seasonIdToDiscounts[seasonId].pop();
    }

    function addDiscount(
        uint256 discountPercentage,
        uint256 discountStartDate,
        uint256 discountExpiration,
        uint256 avatarStartId,
        uint256 avatarEndId,
        uint256 seasonId
    ) external onlyRole(MINTER_ADMIN_ROLE) {
        if (discountPercentage == 0) revert DiscountMustBeGreaterThanZero();
        if (discountExpiration <= discountStartDate)
            revert InvalidDiscountDuration();
        if (avatarEndId < avatarStartId) revert InvalidAvatarIdRange();

        SilksMinterStorage.Layout storage l = SilksMinterStorage.layout();

        // Check for avatarId range overlap with existing discounts for the same season
        uint256 length = l.seasonIdToDiscounts[seasonId].length;
        for (uint256 i = 0; i < length; i++) {
            SilksMinterStorage.Discount storage existingDiscount = l
                .seasonIdToDiscounts[seasonId][i];
            // Check for overlapping avatarId regardless of the discount date range
            bool isOverlappingAvatarId = avatarStartId <=
                existingDiscount.avatarEndId &&
                avatarEndId >= existingDiscount.avatarStartId;
            if (isOverlappingAvatarId) {
                // If avatarId ranges overlap, revert regardless of the date overlap
                revert DiscountAvatarIdRangeOverlap();
            }
        }

        // Push the new Discount to the storage array
        SilksMinterStorage.Discount storage newDiscount = l
            .seasonIdToDiscounts[seasonId]
            .push();
        // Assign the values to the new Discount
        newDiscount.discount = discountPercentage;
        newDiscount.discountStartDate = discountStartDate;
        newDiscount.discountExpiration = discountExpiration;
        newDiscount.avatarStartId = avatarStartId;
        newDiscount.avatarEndId = avatarEndId;
    }

    // Add a new contract with its mint function
    function addContract(
        address contractAddress,
        string calldata mintFunctionSignature,
        ContractType contractType,
        bool isPriceUSD,
        SilksMinterStorage.AddPayTier[] calldata payTiers
    ) external onlyRole(MINTER_ADMIN_ROLE) {
        SilksMinterStorage.layout().addContract(
            contractAddress,
            mintFunctionSignature,
            contractType,
            isPriceUSD,
            payTiers
        );
    }

    // Remove a contract
    function removeContract(
        address contractAddres
    ) external onlyRole(MINTER_ADMIN_ROLE) {
        SilksMinterStorage.layout().removeContract(contractAddres);
    }

    // Update a contract
    function updateContract(
        address oldAddress,
        address newAddress,
        string calldata mintFunctionSignature,
        ContractType newContractType,
        bool isPriceUSD,
        SilksMinterStorage.AddPayTier[] calldata newPrices
    ) external onlyRole(MINTER_ADMIN_ROLE) {
        SilksMinterStorage.layout().updateContract(
            oldAddress,
            newAddress,
            mintFunctionSignature,
            newContractType,
            isPriceUSD,
            newPrices
        );
    }

    function updateMintExclusion(
        bool enable,
        uint256 startTime,
        uint256 endTime
    ) external onlyRole(MINTER_ADMIN_ROLE) {
        SilksMinterStorage.Layout storage l = SilksMinterStorage.layout();

        l.mintingExclusiveToAvatarHolders = enable;
        l.mintingExclusionStartDateTime = startTime;
        l.mintingExclusionEndDateTime = endTime;
    }

    function updateAvatarAddress(
        address newAvatarAddress
    ) external onlyRole(MINTER_ADMIN_ROLE) {
        SilksMinterStorage.layout().avatarAddress = newAvatarAddress;
    }

    function updatePriceFeedAddress(
        address newPriceFeedAddress
    ) external onlyRole(MINTER_ADMIN_ROLE) {
        SilksMinterStorage.layout().priceFeedAddress = newPriceFeedAddress;
    }

    function grantMinterAdminRole(
        address newAdmin
    ) external onlyRole(CONTRACT_ADMIN_ROLE) {
        _grantRole(MINTER_ADMIN_ROLE, newAdmin);
    }

    function revokeMinterAdminRole(
        address admin
    ) external onlyRole(CONTRACT_ADMIN_ROLE) {
        _revokeRole(MINTER_ADMIN_ROLE, admin);
    }

    // AvatarProxy Functions
    // Transfer AvatarOwnership
    function setAvatarSaleInformation(
        uint256 publicSaleTime,
        uint256 preSaleTime,
        uint256 maxPerAddress,
        uint256 presaleMaxPerAddress,
        uint256 price,
        uint256 presalePrice,
        bytes32 merkleRoot,
        uint256 maxTxPerAddress
    ) external onlyRole(MINTER_ADMIN_ROLE) {
        IAvatarNFT(SilksMinterStorage.layout().avatarAddress)
            .setSaleInformation(
                publicSaleTime,
                preSaleTime,
                maxPerAddress,
                presaleMaxPerAddress,
                price,
                presalePrice,
                merkleRoot,
                maxTxPerAddress
            );
    }

    // Set the base URI for the Avatar NFT metadata
    function setAvatarBaseUri(
        string memory baseUri
    ) external onlyRole(MINTER_ADMIN_ROLE) {
        IAvatarNFT(SilksMinterStorage.layout().avatarAddress).setBaseUri(
            baseUri
        );
    }

    // Set the Merkle root for the presale whitelist
    function setAvatarMerkleRoot(
        bytes32 merkleRoot
    ) external onlyRole(MINTER_ADMIN_ROLE) {
        IAvatarNFT(SilksMinterStorage.layout().avatarAddress).setMerkleRoot(
            merkleRoot
        );
    }

    // Pause the Avatar NFT minting process
    function pauseAvatarMinting() external onlyRole(MINTER_ADMIN_ROLE) {
        IAvatarNFT(SilksMinterStorage.layout().avatarAddress).pause();
    }

    // Unpause the Avatar NFT minting process
    function unpauseAvatarMinting() external onlyRole(MINTER_ADMIN_ROLE) {
        IAvatarNFT(SilksMinterStorage.layout().avatarAddress).unpause();
    }

    // Transfer the ownership of the Avatar NFT contract
    function transferAvatarOwnership(
        address newOwner
    ) external onlyRole(MINTER_ADMIN_ROLE) {
        IAvatarNFT(SilksMinterStorage.layout().avatarAddress).transferOwnership(
                newOwner
            );
    }
}
