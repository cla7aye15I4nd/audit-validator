// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library Og721Storage {
    bytes32 internal constant STORAGE_SLOT = keccak256("anome.og.nft.721.contracts.storage.v1");

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }

    struct Layout {
        uint256 mintPrice;
        uint256 maxSupply;
        uint256 currentId;
        uint256 totalMinted;
        address payable mintRecipient;
        mapping(uint256 => string) idSponsor;
        mapping(string => uint256) sponsorMintCount;
        mapping(string => bool) isReferralCodeAllowed;
    }
}
