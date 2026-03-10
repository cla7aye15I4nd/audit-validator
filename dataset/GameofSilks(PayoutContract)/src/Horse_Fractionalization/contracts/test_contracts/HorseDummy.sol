// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract HorseDummy is ERC721Enumerable, Ownable {
    using Address for address;
    
    // variables
    string public baseTokenURI;
    uint256 public mintPrice;
    uint256 private currentTokenId = 0;
    
    // constructor
    constructor()
    ERC721("HorseDummy", "HORSE_DUMMY")
    {
        mintPrice = 0.0001 ether;
    }
    
    function _mintWithoutValidation(
        address to,
        uint256 amount
    ) internal {
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
    
    function publicMint(
        uint256 amount_req
    )
    external
    virtual
    {
        _mintWithoutValidation(msg.sender, amount_req);
    }
    
    function withdrawAll()
    external
    onlyOwner
    {
        uint256 amount = address(this).balance;
        (bool success,) = address(this.owner()).call{value : amount}("");
        require(success, "Failed to send ether");
    }
    
    // view
    function tokenURI(
        uint256 tokenId
    )
    public
    view
    override(ERC721)
    returns (string memory)
    {
        return
        string(abi.encodePacked(baseTokenURI, Strings.toString(tokenId)));
    }
}