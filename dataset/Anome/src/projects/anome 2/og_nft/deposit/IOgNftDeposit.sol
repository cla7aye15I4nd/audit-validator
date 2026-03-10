// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IOgNftDeposit {
    error NotDeposited();
    error AlreadyClaimed();
    error NotClaimable();
    error NotClaimableYet();
    error CardBalanceNotEnough(address card, uint256 balance, uint256 required);

    struct NftInfo {
        uint256 id;
        uint256 claimRequestTime;
    }

    function depositNft(uint256 id) external;

    function requestClaimNft(uint256 id) external;

    function claimNft(uint256 id) external;

    function claimCards(uint256 id) external;

    function getDepositedNft(address account) external view returns (uint256[] memory);

    function getNftClaimRequestTime(uint256 id) external view returns (uint256);
}
