
// SPDX-License-Identifier: undefined
pragma solidity ^0.8.18;

contract DummyDiamond721Implementation {
    event Approval(address indexed  owner, address indexed  operator, uint256 indexed  tokenId);
    event ApprovalForAll(address indexed  owner, address indexed  operator, bool approved);
    event HorseMinted(uint8 indexed  method, uint256 indexed  cropId, uint256 indexed  payoutTier, address to, uint256 tokenId);
    event PartiallyPaused(address account, bytes32 key);
    event PartiallyUnpaused(address account, bytes32 key);
    event Paused(address account);
    event RoleAdminChanged(bytes32 indexed  role, bytes32 indexed  previousAdminRole, bytes32 indexed  newAdminRole);
    event RoleGranted(bytes32 indexed  role, address indexed  account, address indexed  sender);
    event RoleRevoked(bytes32 indexed  role, address indexed  account, address indexed  sender);
    event Transfer(address indexed  from, address indexed  to, uint256 indexed  tokenId);
    event Unpaused(address account);
    event OwnershipTransferred(address indexed  previousOwner, address indexed  newOwner);

   function airdrop(uint256  _cropId, uint256  _payoutTier, uint256  _quantity, address  _to) external {}
   function approve(address  operator, uint256  tokenId) external payable {}
   function balanceOf(address  account) external view returns (uint256 ) {}
   function getApproved(uint256  tokenId) external view returns (address ) {}
   function isApprovedForAll(address  account, address  operator) external view returns (bool ) {}
   function name() external view returns (string memory) {}
   function ownerOf(uint256  tokenId) external view returns (address ) {}
   function purchase(uint256  _cropId, uint256  _payoutTier, uint256  _quantity) external payable {}
   function safeTransferFrom(address  from, address  to, uint256  tokenId) external payable {}
   function safeTransferFrom(address  from, address  to, uint256  tokenId, bytes memory data) external payable {}
   function setApprovalForAll(address  operator, bool  status) external {}
   function supportsInterface(bytes4  interfaceId) external view returns (bool ) {}
   function symbol() external view returns (string memory) {}
   function tokenByIndex(uint256  index) external view returns (uint256 ) {}
   function tokenOfOwnerByIndex(address  owner, uint256  index) external view returns (uint256 ) {}
   function tokenURI(uint256  tokenId) external view returns (string memory) {}
   function totalSupply() external view returns (uint256 ) {}
   function transferFrom(address  from, address  to, uint256  tokenId) external payable {}
   function baseURI() external view returns (string memory uri) {}
   function cropInfo(uint256  _cropId) external view returns (uint256  cropId, string memory description, bool  paused, bool  valid) {}
   function hasContractAdminRole(address  _admin) external view returns (bool  hasRole) {}
   function hasMintAdminRole(address  _admin) external view returns (bool  hasRole) {}
   function horsePayoutTier(uint256  _tokenId) external view returns (uint256  tokenId, uint256  tierId, string memory description, uint256  price, uint256  maxPerTx, uint256  payoutPct, bool  paused, bool  valid) {}
   function horsePurchasesPaused() external view returns (bool  paused) {}
   function horseReferenceNumberByTokenId(uint256  _tokenId) external view returns (string memory referenceNumber) {}
   function horseTokenIdByReferenceNumber(string memory _refNum) external view returns (uint256  tokenId) {}
   function payoutTier(uint256  _payoutTier) external view returns (uint256  tierId, string memory description, uint256  price, uint256  maxPerTx, uint256  payoutPct, bool  paused, bool  valid) {}
   function getRoleAdmin(bytes32  role) external view returns (bytes32 ) {}
   function getRoleMember(bytes32  role, uint256  index) external view returns (address ) {}
   function getRoleMemberCount(bytes32  role) external view returns (uint256 ) {}
   function grantRole(bytes32  role, address  account) external {}
   function hasRole(bytes32  role, address  account) external view returns (bool ) {}
   function pause() external {}
   function pauseHorsePurchases() external {}
   function paused() external view returns (bool  status) {}
   function renounceRole(bytes32  role) external {}
   function revokeRole(bytes32  role, address  account) external {}
   function setBaseURI(string memory _baseURI) external {}
   function setContractAdminRole(address  _admin, bool  _grant) external {}
   function setCropInfo(uint256  _cropId, string memory _desc, bool  _paused, bool  _valid) external {}
   function setHorsePayoutTier(uint256  _tokenId, uint256  _payoutTier) external {}
   function setMintAdminRole(address  _admin, bool  _grant) external {}
   function setPayoutTier(uint256  _payoutTierId, string memory _desc, uint256  _price, uint256  _maxPerTx, uint256  _payoutPct, bool  _paused, bool  _valid) external {}
   function setRoleAdmin(bytes32  role, bytes32  adminRole) external {}
   function setRoyaltyInfo(address  _royaltyReceiver, uint16  _royaltyBasePoints) external {}
   function setTokenIdReferenceNumber(uint256  _tokenId, string memory _refNum) external {}
   function unpause() external {}
   function unpauseHorsePurchases() external {}
}
