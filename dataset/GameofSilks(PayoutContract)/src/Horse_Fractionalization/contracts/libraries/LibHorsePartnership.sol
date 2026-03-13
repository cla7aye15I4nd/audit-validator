// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@gnus.ai/contracts-upgradeable-diamond/contracts/security/PausableStorage.sol";
import {AccessControlStorage} from "@gnus.ai/contracts-upgradeable-diamond/contracts/access/AccessControlStorage.sol";
import "../mocks/ContractGlossary.sol";
import "../mocks/MarketPlace.sol";
import "../mocks/ERC721.sol";

struct Partnership {
    address[] partners;
    uint maxPartnershipShares;
    bool isFractionalized;
}

library LibHorsePartnership {
    bytes32 internal constant STORAGE_SLOT = keccak256('silks.contracts.storage.HorsePartnerships');
    
    struct HorsePartnershipStorage {
        bool fractionalizationPaused;
        bool reconstitutionPaused;
        uint partnershipCount;
        uint maxPartnershipShares;
        address royaltyReceiver;
        uint96 royaltyRate; // 8 = 8%
        mapping(uint => Partnership)  partnerships;
        ContractGlossary indexContract;
    }
    
    function horsePartnershipStorage()
    internal
    pure
    returns
    (HorsePartnershipStorage storage hps) {
        bytes32 position = STORAGE_SLOT;
        assembly {
            hps.slot := position
        }
    }
    
    event HorseFractionalized(
        address indexed operator,
        address indexed account,
        uint indexed horseId
    );
    
    event HorseReconstituted(
        address indexed operator,
        address indexed account,
        uint indexed horseId
    );
    
    function addPartnership(
        uint horseId
    )
    internal
    {
        address[] memory partners;
        LibHorsePartnership.HorsePartnershipStorage storage hps = horsePartnershipStorage();
        hps.partnerships[horseId] = Partnership(partners, hps.maxPartnershipShares, true);
        hps.partnershipCount += 1;
    }
    
    function removePartnership(
        uint horseId
    )
    internal
    {
        address[] memory partners;
        LibHorsePartnership.HorsePartnershipStorage storage hps = horsePartnershipStorage();
        hps.partnerships[horseId] = Partnership(partners, 0, false);
        hps.partnershipCount -= 1;
    }
    
    function beforeFractionalization(
        address account,
        uint horseId
    )
    internal
    {
        require(
            !PausableStorage.layout()._paused,
            "CONTRACT-PAUSED"
        );
    
        LibHorsePartnership.HorsePartnershipStorage storage hps = horsePartnershipStorage();
        require(
            !hps.fractionalizationPaused,
            "FRACTIONALIZATION-PAUSED"
        );
        
        require(
            ERC721(hps.indexContract.getAddress("Horse")).ownerOf(horseId) == account,
            "NOT-TOKEN-OWNER"
        );
        
        require(
            !hps.partnerships[horseId].isFractionalized,
            "HORSE-FRACTIONALIZED"
        );
    
        addPartnership(horseId);
        
        ContractGlossary indexContract = hps.indexContract;
        MarketPlace marketPlaceContract = MarketPlace(indexContract.getAddress("Marketplace"));
        // Delete any offers
        marketPlaceContract.extDeleteOffer(horseId);
        // Delete any listings
        marketPlaceContract.extDeleteMarketItem(horseId);
    }
    
    function afterFractionalization(
        address operator,
        address account,
        uint horseId
    )
    internal
    {
        emit HorseFractionalized(operator, account, horseId);
    }
    
    function beforeReconstitution(
        address account,
        uint horseId
    )
    internal
    view
    {
        require(
            !PausableStorage.layout()._paused,
            "CONTRACT-PAUSED"
        );
    
        LibHorsePartnership.HorsePartnershipStorage storage hps = horsePartnershipStorage();
        require(
            !hps.reconstitutionPaused,
            "RECONSTITUTION-PAUSED"
        );
        
        ContractGlossary indexContract = hps.indexContract;
        
        require(
            ERC721(indexContract.getAddress("Horse")).ownerOf(horseId) == account,
            "NOT-TOKEN-OWNER"
        );
        
        require(
            hps.partnerships[horseId].isFractionalized,
            "HORSE-NOT-FRACTIONALIZED"
        );
        
        require(
            hps.partnerships[horseId].partners.length == 0,
            "HAS-PARTNERS"
        );
    }
    
    function afterReconstitution(
        address operator,
        address account,
        uint horseId
    )
    internal
    {
        removePartnership(horseId);
        emit HorseReconstituted(operator, account, horseId);
    }
}