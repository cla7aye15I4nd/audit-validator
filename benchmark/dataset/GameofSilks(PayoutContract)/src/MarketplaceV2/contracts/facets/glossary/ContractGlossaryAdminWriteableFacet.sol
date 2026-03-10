// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import { AccessControlInternal } from "@solidstate/contracts/access/access_control/AccessControlInternal.sol";

import "./ContractGlossaryStorage.sol";
import "../../SilksMarketplaceStorage.sol";

contract ContractGlossaryAdminWriteableFacet is
    AccessControlInternal
{
    function addContractGlossaryEntry(
        string memory name,
        address contractAddress
    )
    public
    onlyRole(CONTRACT_ADMIN_ROLE)
    {
        ContractGlossaryStorage.addContractGlossaryEntry(name, contractAddress);
    }
}