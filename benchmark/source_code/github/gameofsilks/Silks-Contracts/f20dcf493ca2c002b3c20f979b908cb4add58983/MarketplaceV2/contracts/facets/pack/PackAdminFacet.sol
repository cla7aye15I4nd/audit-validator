// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {PartiallyPausableInternal} from "@solidstate/contracts/security/partially_pausable/PartiallyPausableInternal.sol";
import {PausableInternal} from "@solidstate/contracts/security/pausable/PausableInternal.sol";
import {PackStorage} from "./PackStorage.sol";
import {AccessControlInternal} from "@solidstate/contracts/access/access_control/AccessControlInternal.sol";
import {MINTER_ADMIN_ROLE} from "../../utils/constants.sol";

contract PackAdminFacet is
    PartiallyPausableInternal,
    PausableInternal,
    AccessControlInternal
{
    event PackAdded(
        uint256 indexed packId,
        uint256 pricePerPack,
        uint256 maxPurchasePerTx,
        bool isActive
    );
    event PackUpdated(
        uint256 indexed packId,
        uint256 pricePerPack,
        uint256 maxPurchasePerTx,
        bool isActive
    );
    event PackRemoved(uint256 indexed packId);


    // Adds a new pack
    function addPack(
        PackStorage.PackAsset[] memory assets,
        uint256 pricePerPack,
        uint256 maxPurchasePerTx,
        bool isActive
    ) external onlyRole(MINTER_ADMIN_ROLE) {
        uint256 packId = PackStorage.addPack(
            assets,
            pricePerPack,
            maxPurchasePerTx,
            isActive
        );
        emit PackAdded(packId, pricePerPack, maxPurchasePerTx, isActive);
    }

    function updatePack(
        uint256 packId,
        PackStorage.PackAsset[] memory assets,
        uint256 pricePerPack,
        uint256 maxPurchasePerTx,
        bool isActive
    ) external onlyRole(MINTER_ADMIN_ROLE) {
        PackStorage.updatePack(
            packId,
            assets,
            pricePerPack,
            maxPurchasePerTx,
            isActive
        );
        emit PackUpdated(packId, pricePerPack, maxPurchasePerTx, isActive);
    }

    // Removes a pack
    function removePack(uint256 packId) external onlyRole(MINTER_ADMIN_ROLE) {
        PackStorage.removePack(packId);
        emit PackRemoved(packId);
    }
}
