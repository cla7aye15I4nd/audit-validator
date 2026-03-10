// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

// Import necessary interfaces and contracts
import { ERC165BaseInternal } from "@solidstate/contracts/introspection/ERC165/base/ERC165BaseInternal.sol";
import { IAccessControl } from "@solidstate/contracts/access/access_control/IAccessControl.sol";
import { IDiamondBase } from "@solidstate/contracts/proxy/diamond/base/IDiamondBase.sol";
import { IERC2981 } from "@solidstate/contracts/interfaces/IERC2981.sol";
import { IERC721 } from "@solidstate/contracts/interfaces/IERC721.sol";
import { IERC721Enumerable } from "@solidstate/contracts/token/ERC721/enumerable/IERC721Enumerable.sol";
import { IPartiallyPausable } from "@solidstate/contracts/security/partially_pausable/IPartiallyPausable.sol";
import { IPausable } from "@solidstate/contracts/security/pausable/IPausable.sol";
import { ISolidStateDiamond } from "@solidstate/contracts/proxy/diamond/ISolidStateDiamond.sol";
import { IERC721Metadata } from "@solidstate/contracts/token/ERC721/metadata/IERC721Metadata.sol";

/**
 * @title SilksHorseDiamondInit
 * @dev A Solidity smart contract for initializing supported interfaces in a Diamond upgradeable contract.
 */
contract SilksHorseDiamondInit is ERC165BaseInternal {
    /**
     * @dev Initialize supported interfaces within the Diamond contract.
     * @return success A boolean indicating whether the initialization was successful.
     */
    function init() external returns (bool success) {
        // Set support for multiple interfaces within the Diamond contract
        _setSupportsInterface(type(IAccessControl).interfaceId, true);
        _setSupportsInterface(type(IDiamondBase).interfaceId, true);
        _setSupportsInterface(type(IERC2981).interfaceId, true);
        _setSupportsInterface(type(IERC721).interfaceId, true);
        _setSupportsInterface(type(IERC721Enumerable).interfaceId, true);
        _setSupportsInterface(type(IPartiallyPausable).interfaceId, true);
        _setSupportsInterface(type(IPausable).interfaceId, true);
        _setSupportsInterface(type(ISolidStateDiamond).interfaceId, true);
        _setSupportsInterface(type(IERC721Metadata).interfaceId, true);
        
        return true;
    }
}
