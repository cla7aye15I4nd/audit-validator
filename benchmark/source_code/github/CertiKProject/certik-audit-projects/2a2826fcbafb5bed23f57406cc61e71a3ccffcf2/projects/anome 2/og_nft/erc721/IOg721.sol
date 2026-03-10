// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IOg721 {
    error IncorrectPaymentAmount();
    error ReferralCodeNotAllowed();
    error SoldOut();

    function mint(address to, uint256 count, string memory referralCode) external payable;

    function getStatus() external view returns (uint256 mintPrice, uint256 maxSupply, uint256 totalMinted);

    function getSponsorsMintCount(string memory referralCode) external view returns (uint256);

    function isReferralCodeAllowed(string memory referralCode) external view returns (bool);

    function getIdSponsor(uint256 id) external view returns (string memory);

    function setReferralCodeAllowed(string[] memory referralCodes, bool allowed) external;

    function adminMint(address to, uint256 count, string memory referralCode) external;
}
