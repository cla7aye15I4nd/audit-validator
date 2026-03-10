// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract NodeNFT is ERC721, Ownable {

    using Strings for uint256;

    string public baseURI;
    uint256 private _totalSupply;
    mapping(uint256 tokenId => uint8 level) public tokenLevel;

    constructor(address nftHolder) ERC721("ADS Node", "ADS Node") Ownable(_msgSender()) {
        for (uint256 i = 1; i <= 1000; i++) {
            _mint(nftHolder, i);
            _totalSupply++;
            uint8 level = i <= 500 ? 1 : i > 500 && i <= 800 ? 2 : 3;
            tokenLevel[i] = level;
        }
    }

    function setBaseURI(string memory _uri) external onlyOwner {
        baseURI = _uri;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        uint256 level = tokenLevel[tokenId];
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, level.toString(), ".json")) : "";
    }

    function totalSupply() public view virtual returns (uint256) {
        return _totalSupply;
    }

}
