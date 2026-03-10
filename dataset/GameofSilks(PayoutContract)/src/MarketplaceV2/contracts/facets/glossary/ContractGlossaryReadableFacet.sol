// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./ContractGlossaryStorage.sol";

contract ContractGlossaryReadableFacet {
    
    function getAddressFromContractGlossary(
        string memory contractName
    )
    public
    view
    returns (
        address contractAddress
    ){
        ContractGlossaryStorage.Layout storage lcg = ContractGlossaryStorage.layout();
        contractAddress = lcg.nameToAddress[contractName];
    }
    
    function getNameFromContractGlossary(
        address contractAddress
    )
    public
    view
    returns (
        string memory contractName
    ){
        ContractGlossaryStorage.Layout storage lcg = ContractGlossaryStorage.layout();
        contractName = lcg.addressToName[contractAddress];
    }
    
    function getContractGlossaryEntries()
    public
    view
    returns (
        GlossaryReference[] memory
    ){
        ContractGlossaryStorage.Layout storage lcg = ContractGlossaryStorage.layout();
        GlossaryReference[] memory glossaryEntries = new GlossaryReference[](lcg.glossarySize);
        uint256 i;
        for(; i < lcg.glossarySize;){
            glossaryEntries[i] = GlossaryReference(
                i,
                lcg.indexToName[i],
                lcg.nameToAddress[lcg.indexToName[i]],
                true
            );
            unchecked { i++; }
        }
        return glossaryEntries;
    }
}