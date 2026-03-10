// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { LibDiamondEtherscan } from "../libraries/LibDiamondEtherscan.sol";
import { AccessControlInternal } from "@solidstate/contracts/access/access_control/AccessControlInternal.sol";
import {CONTRACT_ADMIN_ROLE} from "../libraries/LibSilksHorseDiamond.sol";

contract DiamondEtherscanFacet is AccessControlInternal {
    function setDummyImplementation(address _implementation) external onlyRole(CONTRACT_ADMIN_ROLE) {
        LibDiamondEtherscan._setDummyImplementation(_implementation);
    }

    function implementation() external view returns (address) {
        return LibDiamondEtherscan._dummyImplementation();
    }
}