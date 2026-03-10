// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.17;

abstract contract ERC721 {
    function ownerOf(
        uint tokenId
    )
    public
    view
    virtual
    returns (
        address
    );
}