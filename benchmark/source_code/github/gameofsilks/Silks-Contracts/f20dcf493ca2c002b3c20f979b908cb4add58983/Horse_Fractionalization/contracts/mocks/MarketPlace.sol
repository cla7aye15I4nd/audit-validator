// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.17;

abstract contract MarketPlace {
    function extDeleteOffer(
        uint horseId
    )
    external
    virtual;
    
    function extDeleteMarketItem(
        uint horseId
    )
    external
    virtual;
    
    function extDeleteMarketItems(
        string memory tokenType,
        address account,
        uint tokenId,
        uint amount
    )
    external
    virtual;
}