// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import { AccessControlInternal } from "@solidstate/contracts/access/access_control/AccessControlInternal.sol";
import { Pausable } from "@solidstate/contracts/security/pausable/Pausable.sol";
import { AddressUtils } from "@solidstate/contracts/utils/AddressUtils.sol";

import "../../SilksMarketplaceStorage.sol";

contract MarketplaceAdminWriteableFacet is
    AccessControlInternal,
    Pausable
{
    /**
    * @dev Pause the contract.
     */
    function pause()
    public
    onlyRole(CONTRACT_ADMIN_ROLE)
    {
        _pause();
    }
    
    /**
     * @dev Unpause the contract.
     */
    function unpause()
    public
    onlyRole(CONTRACT_ADMIN_ROLE)
    {
        _unpause();
    }
    
    /**
     * @dev Set royalty information.
     * @param _royaltyReceiver The address of the royalty receiver.
     * @param _royaltyBasePoints The royalty base points to be set. 800 is 8%
     */
    function setRoyaltyInfo(
        address _royaltyReceiver,
        uint16 _royaltyBasePoints
    )
    public
    onlyRole(CONTRACT_ADMIN_ROLE)
    {
        if (_royaltyReceiver == address(0)){
            revert InvalidAddress(
                _royaltyReceiver
            );
        }
        
        SilksMarketplaceStorage.Layout storage sms = SilksMarketplaceStorage.layout();
        sms.royaltyReceiver = _royaltyReceiver;
        sms.royaltyBasePoints = _royaltyBasePoints;
    }
    
    // Basic withdrawal of funds function in order to transfer ETH out of the smart contract
    function withdrawFunds(
        address payable _to
    )
    public
    onlyRole(CONTRACT_ADMIN_ROLE)
    {
        if (_to == address(0)){
            revert InvalidAddress(
                _to
            );
        }
        AddressUtils.sendValue(_to, address(this).balance);
    }
}