// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC721Metadata, ERC721Metadata} from "../../../lib/solidstate/token/ERC721/metadata/ERC721Metadata.sol";
import {ERC721MetadataStorage} from "../../../lib/solidstate/token/ERC721/metadata/ERC721MetadataStorage.sol";

import {Og721Storage} from "./Og721Storage.sol";

import {IOg721} from "./IOg721.sol";
import {SolidStateERC721} from "../../../lib/solidstate/token/ERC721/SolidStateERC721.sol";
import {SafeOwnable} from "../../../lib/solidstate/access/ownable/SafeOwnable.sol";

contract Og721 is IOg721, SolidStateERC721, SafeOwnable {
    function tokenURI(uint256 id) public view override(ERC721Metadata, IERC721Metadata) returns (string memory) {
        id;
        return ERC721MetadataStorage.layout().baseURI;
    }

    function mint(address to, uint256 count, string memory referralCode) external payable override {
        Og721Storage.Layout storage l = Og721Storage.layout();
        if (msg.value < l.mintPrice * count) {
            revert IncorrectPaymentAmount();
        }

        if (!l.isReferralCodeAllowed[referralCode]) {
            revert ReferralCodeNotAllowed();
        }

        if ((l.totalMinted + count) > l.maxSupply) {
            revert SoldOut();
        }

        for (uint256 i = 0; i < count; i++) {
            l.currentId += 1;
            uint256 id = l.currentId;
            _mint(to, id);
            l.idSponsor[id] = referralCode;
        }

        l.mintRecipient.transfer(msg.value);
        l.totalMinted += count;
        l.sponsorMintCount[referralCode] += count;
    }

    function getStatus()
        external
        view
        override
        returns (uint256 mintPrice, uint256 maxSupply, uint256 totalMinted)
    {
        Og721Storage.Layout storage l = Og721Storage.layout();
        return (l.mintPrice, l.maxSupply, l.totalMinted);
    }

    function getSponsorsMintCount(string memory referralCode) external view override returns (uint256) {
        Og721Storage.Layout storage l = Og721Storage.layout();
        return l.sponsorMintCount[referralCode];
    }

    function isReferralCodeAllowed(string memory referralCode) external view override returns (bool) {
        Og721Storage.Layout storage l = Og721Storage.layout();
        return l.isReferralCodeAllowed[referralCode];
    }

    function setMintPrice(uint256 newMintPrice) external onlyOwner {
        Og721Storage.Layout storage l = Og721Storage.layout();
        l.mintPrice = newMintPrice;
    }

    function getIdSponsor(uint256 id) external view override returns (string memory) {
        Og721Storage.Layout storage l = Og721Storage.layout();
        return l.idSponsor[id];
    }

    function setReferralCodeAllowed(string[] memory referralCodes, bool allowed) external onlyOwner {
        Og721Storage.Layout storage l = Og721Storage.layout();
        for (uint256 i = 0; i < referralCodes.length; i++) {
            l.isReferralCodeAllowed[referralCodes[i]] = allowed;
        }
    }

    function adminMint(address to, uint256 count, string memory referralCode) external onlyOwner {
        Og721Storage.Layout storage l = Og721Storage.layout();

        if (!l.isReferralCodeAllowed[referralCode]) {
            revert ReferralCodeNotAllowed();
        }

        if ((l.totalMinted + count) > l.maxSupply) {
            revert SoldOut();
        }

        for (uint256 i = 0; i < count; i++) {
            l.currentId += 1;
            uint256 id = l.currentId;
            _mint(to, id);
            l.idSponsor[id] = referralCode;
        }

        l.totalMinted += count;
        l.sponsorMintCount[referralCode] += count;
    }
}
