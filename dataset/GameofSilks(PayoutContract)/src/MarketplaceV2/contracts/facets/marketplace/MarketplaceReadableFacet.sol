// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../../SilksMarketplaceStorage.sol";

contract MarketplaceReadableFacet {
    
    function getRoyaltyInfo()
    public
    view
    returns (
        address royaltyReceiver,
        uint256 royaltyBasePoints
    )
    {
        SilksMarketplaceStorage.Layout storage l = SilksMarketplaceStorage.layout();
        royaltyReceiver = l.royaltyReceiver;
        royaltyBasePoints = l.royaltyBasePoints;
    }
}