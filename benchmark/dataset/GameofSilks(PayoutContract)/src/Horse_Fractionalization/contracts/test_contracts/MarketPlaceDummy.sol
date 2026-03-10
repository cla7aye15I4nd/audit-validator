// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MarketPlaceDummy is ERC721, Ownable {
    using Address for address;
    
    // variables
    string public baseTokenURI;
    uint256 public mintPrice;
    uint256 private currentTokenId = 0;
    
    // constructor
    constructor()
    ERC721("MarketPlaceDummy", "MARKETPLACE_DUMMY")
    {
        mintPrice = 0.0001 ether;
    }
    
    function totalSupply()
    public
    view
    returns (
        uint256
    ) {
        return currentTokenId;
    }
    
    function _mintWithoutValidation(
        address to,
        uint256 amount
    )
    internal
    {
        for (uint256 i = 0; i < amount; i++) {
            currentTokenId = currentTokenId + 1;
            _safeMint(to, currentTokenId);
        }
    }
    
    function setBaseTokenURI(
        string memory _baseTokenURI
    )
    external
    onlyOwner
    {
        baseTokenURI = _baseTokenURI;
    }
    
    function setMintPrice(
        uint256 _mintPrice
    )
    external
    onlyOwner
    {
        mintPrice = _mintPrice;
    }
    
    function extDeleteOffer(
        uint256 horseId
    )
    external
    virtual
    {
    
    }
    
    function extDeleteMarketItem(
        uint256 horseId
    )
    external
    virtual
    {
    
    }
    
    function extDeleteMarketItems(
        string memory tokenType,
        address account,
        uint256 tokenId,
        uint256 amount
    )
    external
    virtual
    {
    
    }
    
    function extMint(
        address to,
        uint256 amount_req
    )
    external
    virtual
    {
        _mintWithoutValidation(to, amount_req);
    }
    
    function withdrawAll()
    external
    onlyOwner {
        uint256 amount = address(this).balance;
        (bool success,) = address(this.owner()).call{value : amount}("");
        require(success, "Failed to send ether");
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