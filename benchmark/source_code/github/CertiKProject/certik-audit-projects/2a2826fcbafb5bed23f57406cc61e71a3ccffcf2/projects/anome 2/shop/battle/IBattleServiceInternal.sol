// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IBattleServiceInternal {
    error OnlyProxy();
    error OgNftAmountExceeded();
    error CardDestroyedAmountExceeded();

    event OnBattleRewawrd(address indexed account, uint256 reward);
    event OnReferralRewawrd(address indexed account, uint256 reward);
    event CardDestroyed(
        uint256 indexed index,
        address indexed card,
        uint256 releasedUsda,
        address ip,
        uint256 ipAmount,
        address destroyPayee,
        uint256 destroyPayeeAmount,
        address winnerSponsor,
        uint256 winnerSponsorAmount,
        address loserSponsor,
        uint256 loserSponsorAmount
    );
}
