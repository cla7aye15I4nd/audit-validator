// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.17;

import "@gnus.ai/contracts-upgradeable-diamond/contracts/proxy/utils/Initializable.sol";

contract TestFacetV1 is
    Initializable
{
    function __TestFacetV1_init()
    internal
    onlyInitializing
    {
        __TestFacetV1_init_unchained();
    }
    
    function __TestFacetV1_init_unchained()
    internal
    onlyInitializing
    {}
    
    function getMessage()
    external
    pure
    returns (
        string memory
    )
    {
        return "V1";
    }
}