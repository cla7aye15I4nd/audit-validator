// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ContractType} from "../../utils/constants.sol";
import "hardhat/console.sol";

library PackStorage {
    using EnumerableSet for EnumerableSet.UintSet;

    error PackDoesNotExist(uint256 packId);
    error PackAlreadyExists(uint256 packId);

    struct PackAsset {
        uint256 amount; // Quantity of the asset
        address assetAddress; // Contract address of the asset
        ContractType assetType; // Type of asset
        uint256 seasonId; // Season ID of the asset (HorseV2) or 0 for other assets
        uint256 payoutTier; // Payout tier of the asset (HorseV2) or 0 for other assets
    }

    struct Pack {
        // bool exists; // Indicates if the pack exists to avoid using a separate mapping or array
        PackAsset[] assets; // Array of assets included in the pack
        uint256 pricePerPack; // Price per pack
        uint256 maxPurchasePerTx; // Maximum number of packs purchasable in a single transaction
        bool isActive; // Indicates if the pack is currently active and purchasable
    }

    bytes32 internal constant STORAGE_SLOT =
        keccak256("silks.contracts.storage.Packs");

    struct Layout {
        EnumerableSet.UintSet packIds; // Set of all pack IDs
        mapping(uint256 => Pack) packs; // Mapping from pack ID to Pack details
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }

    function addPack(
        PackAsset[] memory assets,
        uint256 pricePerPack,
        uint256 maxPurchasePerTx,
        bool isActive
    ) internal returns (uint256) {
        Layout storage l = layout();
        uint256 packId = l.packIds.length();

        if (l.packIds.contains(packId)) {
            revert PackAlreadyExists(packId);
        }

        l.packIds.add(packId);
        Pack storage newPack = l.packs[packId];
        newPack.pricePerPack = pricePerPack;
        newPack.maxPurchasePerTx = maxPurchasePerTx;
        newPack.isActive = isActive;

        // Manually copy each element from the memory array to the storage array
        uint256 i;
        uint256 assetsLength = assets.length;
        for (; i < assetsLength; ) {
            newPack.assets.push(assets[i]);

            unchecked {
                ++i;
            }
        }

        return packId;
    }

    function updatePack(
        uint256 packId,
        PackAsset[] memory assets,
        uint256 pricePerPack,
        uint256 maxPurchasePerTx,
        bool isActive
    ) internal {
        Layout storage l = layout();
        if (!l.packIds.contains(packId)) {
            revert PackDoesNotExist(packId);
        }

        Pack storage pack = l.packs[packId];
        delete pack.assets; // Clear the existing assets array

        uint256 i;
        uint256 assetsLength = assets.length;
        for (; i < assetsLength; ) {
            pack.assets.push(assets[i]); // Copy each asset from the memory array to the storage array
            unchecked {
                ++i;
            }
        }
        pack.pricePerPack = pricePerPack;
        pack.maxPurchasePerTx = maxPurchasePerTx;
        pack.isActive = isActive;
    }

    function removePack(uint256 packId) internal {
        Layout storage l = layout();
        if (!l.packIds.contains(packId)) {
            revert PackDoesNotExist(packId);
        }
        l.packIds.remove(packId);
        delete l.packs[packId];
    }

    function packExists(uint256 packId) internal view returns (bool) {
        Layout storage l = layout();
        return l.packIds.contains(packId);
    }

    function getPack(uint256 packId) internal view returns (Pack memory) {
        Layout storage l = layout();
        require(l.packIds.contains(packId), "Pack does not exist");
        return l.packs[packId];
    }

    function getAllPackIds() internal view returns (uint256[] memory) {
        Layout storage l = layout();
        uint256[] memory ids = new uint256[](l.packIds.length());

        uint256 i;
        uint256 length = l.packIds.length();
        for (; i < length; ) {
            ids[i] = l.packIds.at(i);
            unchecked {
                ++i;
            }
        }
        return ids;
    }

    function getActivePacks() internal view returns (Pack[] memory) {
        Layout storage l = layout();
        uint256 count = 0;

        uint256 i;
        uint256 assetsLength = l.packIds.length();
        for (; i < assetsLength; ) {
            if (l.packs[l.packIds.at(i)].isActive) {
                count++;
            }

            unchecked {
                ++i;
            }
        }

        Pack[] memory activePacks = new Pack[](count);
        uint256 index = 0;

        i = 0;
        for (; i < assetsLength; ) {
            uint256 id = l.packIds.at(i);
            if (l.packs[id].isActive) {
                activePacks[index] = l.packs[id];
                index++;
            }

            unchecked {
                ++i;
            }
        }
        return activePacks;
    }
}
