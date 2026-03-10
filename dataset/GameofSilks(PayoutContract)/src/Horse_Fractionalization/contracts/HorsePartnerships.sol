// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.17;

import "./Diamond.sol";
import { ERC1155Storage } from "@gnus.ai/contracts-upgradeable-diamond/contracts/token/ERC1155/ERC1155Storage.sol";
import {AccessControlStorage} from "@gnus.ai/contracts-upgradeable-diamond/contracts/access/AccessControlStorage.sol";
import "@gnus.ai/contracts-upgradeable-diamond/contracts/access/AccessControlUpgradeable.sol";
import "@gnus.ai/contracts-upgradeable-diamond/contracts/utils/StringsUpgradeable.sol";
import "./interfaces/IDiamondLoupe.sol";
import "./libraries/LibHorsePartnership.sol";
import "./libraries/LibAccessControl.sol";
import "./facets/OwnershipFacet.sol";

contract HorsePartnerships is
    Diamond,
    OwnershipFacet
{
    using AccessControlStorage for AccessControlStorage.Layout;
    
    constructor(
        address _contractOwner,
        address _diamondCutFacet,
        string memory tokenUri,
        address indexContract,
        address royaltyReceiver,
        uint96 royaltyRate
    )
    payable
    Diamond(_contractOwner, _diamondCutFacet)
    {
        require(bytes(tokenUri).length > 0, "Invalid tokenUri");
        require(indexContract != address(0), "Invalid index contract address");
        require(royaltyReceiver != address(0), "Invalid royalty receive address");
        require(royaltyRate > 0 && royaltyRate <= 100, "Invalid royalty rate");
        
        ERC1155Storage.layout()._uri = tokenUri;
        
        LibHorsePartnership.HorsePartnershipStorage storage hps = LibHorsePartnership.horsePartnershipStorage();
        hps.partnershipCount = 0;
        hps.maxPartnershipShares = 9; // 1 Governance (Horse Owner) + 9 Partners
        hps.indexContract = ContractGlossary(indexContract);
        hps.royaltyReceiver = royaltyReceiver;
        hps.royaltyRate = royaltyRate;
    
        AccessControlStorage.Layout storage acs = AccessControlStorage.layout();
        acs._roles[LAC_CONTRACT_ADMIN_ROLE].adminRole = 0x00;
        acs._roles[LAC_FRACTIONALIZATION_ADMIN_ROLE].adminRole = 0x00;
        acs._roles[LAC_RECONSTITUTION_ADMIN_ROLE].adminRole = 0x00;
        acs._roles[LAC_CONFIG_ADMIN_ROLE].adminRole = 0x00;
        acs._roles[LAC_BURNER_ROLE].adminRole = 0x00;
        
        LibAccessControl.grantAllAdminRoles(_contractOwner);
    
        PausableStorage.layout()._paused = true;
    }
    
    function uri(
        uint tokenId
    )
    public
    view
    returns (
        string memory
    )
    {
        return (string(abi.encodePacked(ERC1155Storage.layout()._uri, StringsUpgradeable.toString(tokenId))));
    }
    
    function supportsInterface(
        bytes4 interfaceId
    )
    public
    view
    returns (
        bool
    ) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        return ds.supportedInterfaces[interfaceId];
    }
    
    function paused()
    external
    view
    returns (
        bool
    )
    {
        return PausableStorage.layout()._paused;
    }
    
    function pause()
    external
    {
        LibAccessControl.enforceHasContractAdminRole();
        PausableStorage.layout()._paused = true;
    }
    
    function unpause()
    external
    {
        LibAccessControl.enforceHasContractAdminRole();
        PausableStorage.layout()._paused = false;
    }
}