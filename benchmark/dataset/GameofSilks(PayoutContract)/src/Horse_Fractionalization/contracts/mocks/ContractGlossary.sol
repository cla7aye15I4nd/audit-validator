// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.17;

abstract contract ContractGlossary {
    function getAddress(
        string memory name
    )
    public
    view
    virtual
    returns (
        address
    );
    
    function owner()
    public
    view
    virtual
    returns (
        address
    );
}