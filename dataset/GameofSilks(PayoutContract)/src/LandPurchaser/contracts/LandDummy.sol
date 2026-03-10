// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract LandDummy is ERC721, Ownable {
    using Address for address;
    
    // variables
    string public baseTokenURI;
    uint256 public mintPrice = 0 ether;
    
    uint256 tokenId = 0;
    
    address skyFallContractAddress; // Approved mintvial contract
    
    // constructor
    constructor() ERC721("SilksLandDummy", "SILKS_LAND_DUMMY") {}
    
    // public mint
    //    function publicMint(uint amount) external payable {
    //        _mintWithoutValidation(msg.sender, amount);
    //    }
    
    function eMint(
        address to,
        uint256 amount_req,
        string memory,
        bool
    )
    external
    virtual {
        _mintWithoutValidation(to, amount_req);
    }
    
    function mintTransfer(address to, uint256 amount) external {
        require(msg.sender == skyFallContractAddress, "Not authorized");
        
        _mintWithoutValidation(to, amount);
    }
    
    function _mintWithoutValidation(address to, uint256 amount) internal {
        for(uint i = 0; i < amount; i++){
            tokenId++;
            _safeMint(to, tokenId);
        }
    }
    
    // Change the skyfall address contract
    function setSkyFallContractAddress(address newAddress) public onlyOwner {
        skyFallContractAddress = newAddress;
    }
    
    function setBaseTokenURI(string memory _baseTokenURI) external onlyOwner {
        baseTokenURI = _baseTokenURI;
    }
    
    function withdrawAll() external onlyOwner {
        uint256 amount = address(this).balance;
        (bool success, ) = address(this.owner()).call{value: amount}("");
        require(success, "Failed to send ether");
    }
    
    // view
    function tokenURI(
        uint256 _tokenId
    )
    public
    view
    override(ERC721)
    returns (string memory)
    {
        return
        string(abi.encodePacked(baseTokenURI, Strings.toString(_tokenId)));
    }
}