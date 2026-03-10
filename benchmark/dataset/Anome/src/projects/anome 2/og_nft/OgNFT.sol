// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC165} from "../../lib/solidstate/interfaces/IERC165.sol";
import {IERC721} from "../../lib/openzeppelin/token/ERC721/IERC721.sol";
import {IERC721Metadata} from "../../lib/solidstate/token/ERC721/metadata/IERC721Metadata.sol";
import {IERC721Enumerable} from "../../lib/solidstate/token/ERC721/enumerable/IERC721Enumerable.sol";
import {ERC721Base} from "../../lib/solidstate/token/ERC721/base/ERC721Base.sol";
import {ERC721Enumerable} from "../../lib/solidstate/token/ERC721/enumerable/ERC721Enumerable.sol";
import {ERC721Metadata} from "../../lib/solidstate/token/ERC721/metadata/ERC721Metadata.sol";
import {ERC721MetadataStorage} from "../../lib/solidstate/token/ERC721/metadata/ERC721MetadataStorage.sol";

import {Og721Storage} from "./erc721/Og721Storage.sol";

import {SolidStateDiamond} from "../../lib/solidstate/proxy/diamond/SolidStateDiamond.sol";
import {ERC165BaseInternal} from "../../lib/solidstate/introspection/ERC165/base/ERC165BaseInternal.sol";

contract OgNFT is ERC165BaseInternal, SolidStateDiamond {
    constructor(address erc721Target, string[] memory sponsors) SolidStateDiamond() {
        _addERC721FacetSelectors(erc721Target);
        ERC721MetadataStorage.Layout storage l = ERC721MetadataStorage.layout();
        l.name = "Anome OG NFT";
        l.symbol = "OG";
        l.baseURI = "ipfs://bafkreigvyea6zilwdwgeqoajyzrbodhtqvahynx2vr23budvtkw4kqfts4";

        Og721Storage.Layout storage l721 = Og721Storage.layout();
        l721.mintPrice = 0.9 ether;
        l721.maxSupply = 500;
        l721.totalMinted = 0;
        l721.mintRecipient = payable(0xD6170Af3Be3F503E0b2a0f5706F9c8565f1B9aa1);

        for (uint256 i = 0; i < sponsors.length; i++) {
            l721.isReferralCodeAllowed[sponsors[i]] = true;
        }
    }

    function _addERC721FacetSelectors(address target) internal {
        bytes4[] memory selectors = new bytes4[](15);

        selectors[0] = ERC721Base.balanceOf.selector;
        selectors[1] = ERC721Base.ownerOf.selector;
        selectors[2] = ERC721Base.getApproved.selector;
        selectors[3] = ERC721Base.isApprovedForAll.selector;
        selectors[4] = ERC721Base.transferFrom.selector;
        selectors[5] = bytes4(keccak256("safeTransferFrom(address,address,uint256)"));
        selectors[6] = bytes4(keccak256("safeTransferFrom(address,address,uint256,bytes)"));
        selectors[7] = ERC721Base.approve.selector;
        selectors[8] = ERC721Base.setApprovalForAll.selector;

        selectors[9] = ERC721Enumerable.totalSupply.selector;
        selectors[10] = ERC721Enumerable.tokenOfOwnerByIndex.selector;
        selectors[11] = ERC721Enumerable.tokenByIndex.selector;

        selectors[12] = ERC721Metadata.name.selector;
        selectors[13] = ERC721Metadata.symbol.selector;
        selectors[14] = ERC721Metadata.tokenURI.selector;

        _setSupportsInterface(type(IERC165).interfaceId, true);
        _setSupportsInterface(type(IERC721).interfaceId, true);
        _setSupportsInterface(type(IERC721Metadata).interfaceId, true);
        _setSupportsInterface(type(IERC721Enumerable).interfaceId, true);

        FacetCut[] memory facetCuts = new FacetCut[](1);
        facetCuts[0] = FacetCut({target: target, action: FacetCutAction.ADD, selectors: selectors});
        _diamondCut(facetCuts, address(0), "");
    }
}
