// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";

contract SilksDummy is ERC721, Ownable {
    using Address for address;
    
    // variables
    string public baseTokenURI;
    uint256 public mintPrice;
    uint256 private currentTokenId;
    
    // constructor
    constructor()
    ERC721("SilksDummy", "SILKS_DUMMY")
    Ownable()
    {
        mintPrice = 0.00001 ether;
    }
    
    // public mint
    function publicMint(uint amount) external payable {
        _mintWithoutValidation(msg.sender, amount);
    }
    
    function totalSupply() public view returns (uint256) {
        return currentTokenId;
    }
    
    function _mintWithoutValidation(address to, uint256 amount) internal {
        uint256 startTokenId = totalSupply() + 1;
        for (uint256 i = 0; i < amount; i++) {
            _safeMint(to, startTokenId + i);
        }
    }
    
    function setBaseTokenURI(string memory _baseTokenURI) external onlyOwner {
        baseTokenURI = _baseTokenURI;
    }
    
    function withdrawAll() external onlyOwner {
        uint256 amount = address(this).balance;
        (bool success,) = address(this.owner()).call{value : amount}("");
        require(success, "Failed to send ether");
    }
    
    function setMintPrice(uint256 _mintPrice) external onlyOwner {
        mintPrice = _mintPrice;
    }
    
    // view
    function tokenURI(uint256 tokenId)
    public
    view
    override(ERC721)
    returns (string memory)
    {
        return
            string(abi.encodePacked(baseTokenURI, Strings.toString(tokenId)));
    }
}