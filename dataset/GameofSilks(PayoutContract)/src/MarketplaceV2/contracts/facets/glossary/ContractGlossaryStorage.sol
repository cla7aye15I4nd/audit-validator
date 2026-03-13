// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import { EnumerableSet } from "@solidstate/contracts/data/EnumerableSet.sol";
    
    struct GlossaryReference {
        uint256 glossaryId;
        string contractName;
        address contractAddress;
        bool valid;
    }

library ContractGlossaryStorage {
    
    bytes32 internal constant STORAGE_SLOT = keccak256('silks.contracts.storage.SilksContractGlossary');
    
    struct Layout {
        mapping(uint256 => string) indexToName;
        mapping(string => address) nameToAddress;
        mapping(address => string) addressToName;
        uint256 glossarySize;
    }
    
    // Function to retrieve the layout.
    function layout()
    internal
    pure
    returns (
        Layout storage _l
    ) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            _l.slot := slot
        }
    }
    
    function addContractGlossaryEntry(
        string memory name,
        address contractAddress
    )
    internal
    {
        if (layout().nameToAddress[name] == address(0)) {
            layout().indexToName[layout().glossarySize] = name;
            layout().glossarySize++;
        }
        layout().nameToAddress[name] = contractAddress;
        layout().addressToName[contractAddress] = name;
    }
}