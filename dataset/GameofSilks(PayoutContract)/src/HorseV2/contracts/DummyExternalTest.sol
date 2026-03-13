// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

abstract contract AbstractSilksHorseDiamond {
    function externalMint(
        uint256 _cropId,
        uint256 _payoutTier,
        uint256 _quantity,
        address _to
    )
    external
    virtual;
}

contract DummyExternalTest {
    
    address diamondAddress;
    
    constructor(
        address _diamondAddress
    )
    {
        diamondAddress = _diamondAddress;
    }
    
    function testExternalMint(
        uint256 _cropId,
        uint256 _payoutTier,
        uint256 _quantity,
        address _to
    )
    public
    {
        AbstractSilksHorseDiamond diamond = AbstractSilksHorseDiamond(diamondAddress);
        diamond.externalMint(_cropId, _payoutTier, _quantity, _to);
    }
}