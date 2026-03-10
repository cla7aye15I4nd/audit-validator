// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {PartiallyPausableInternal} from "@solidstate/contracts/security/partially_pausable/PartiallyPausableInternal.sol";
import {PausableInternal} from "@solidstate/contracts/security/pausable/PausableInternal.sol";
import {PackStorage} from "./PackStorage.sol";
import {IAvatarNFT} from "../../interfaces/IAvatarNFT.sol";
import {IHorseNFT} from "../../interfaces/IHorseNFT.sol";
import {ContractType} from "../../utils/constants.sol";
import {AccessControlInternal} from "@solidstate/contracts/access/access_control/AccessControlInternal.sol";
import {MINTER_ADMIN_ROLE} from "../../utils/constants.sol";

contract PackFacet is
    PartiallyPausableInternal,
    PausableInternal,
    AccessControlInternal
{
    // using PackStorage for PackStorage.Layout;

    event PackPurchased(
        uint256 indexed packId,
        address indexed buyer,
        uint256 quantity
    );
    event PackAirDropped(
        uint256 indexed packId,
        address indexed receiver,
        uint256 quantity
    );

    bytes32 constant PACK_PURCHASES_PAUSED = "PACK_PURCHASES_PAUSED";

    error PackNotActive(uint256 packId);
    error MaxPerTxExceeded(uint256 requested, uint256 maxAllowed);
    error InvalidEthTotal(uint256 sentEth, uint256 requiredEth);

    function purchasePack(uint256 packId, uint256 quantity) external payable {
        PackStorage.Pack memory pack = PackStorage.getPack(packId);

        if (!pack.isActive) {
            revert PackNotActive(packId);
        }

        if (pack.maxPurchasePerTx < quantity) {
            revert MaxPerTxExceeded(quantity, pack.maxPurchasePerTx);
        }

        if ((pack.pricePerPack * quantity) != msg.value) {
            revert InvalidEthTotal(msg.value, (pack.pricePerPack * quantity));
        }

        // Mint the assets to the user
        mintAssets(packId, msg.sender, quantity);
    }

    function airDropPack(
        uint256 packId,
        address to,
        uint256 quantity
    ) external onlyRole(MINTER_ADMIN_ROLE) {
        // Mint the assets to the user
        mintAssets(packId, to, quantity);

        emit PackAirDropped(packId, to, quantity);
    }

    function mintAssets(uint256 packId, address to, uint256 quantity) internal {
        PackStorage.Pack memory pack = PackStorage.getPack(packId);

        // Get the addresses of the assets in the pack and the quantity of each
        uint256 assetsLength = pack.assets.length;
        uint256 i; // Defaults to zero, saves gas by not initializing
        for (; i < assetsLength; ) {
            //  Depending on contract type, call a specific function to mint the asset
            if (pack.assets[i].assetType == ContractType.Avatar) {
                IAvatarNFT(pack.assets[i].assetAddress).mint(
                    to,
                    pack.assets[i].amount * quantity
                );
            } else if (pack.assets[i].assetType == ContractType.HorseV2) {
                IHorseNFT(pack.assets[i].assetAddress).externalMint(
                    pack.assets[i].seasonId,
                    pack.assets[i].payoutTier,
                    pack.assets[i].amount * quantity,
                    to
                );
            }

            unchecked {
                ++i;
            }
        }

        emit PackPurchased(packId, msg.sender, quantity);
    }

    // Retrieves a pack by ID
    function getPack(
        uint256 packId
    ) external view returns (PackStorage.Pack memory) {
        return PackStorage.getPack(packId);
    }

    // Retrieves all pack IDs
    function getAllPackIds() external view returns (uint256[] memory) {
        return PackStorage.getAllPackIds();
    }

    // Retrieves all active packs
    function getActivePacks()
        external
        view
        returns (PackStorage.Pack[] memory)
    {
        return PackStorage.getActivePacks();
    }
}
