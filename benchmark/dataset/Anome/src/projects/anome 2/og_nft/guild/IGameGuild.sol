// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IGameGuildInternal} from "./IGameGuildInternal.sol";
import {GameGuildStorage} from "./GameGuildStorage.sol";

interface IGameGuild is IGameGuildInternal {
    struct TeamInfo {
        uint256 teamOgCount;
        uint256 teamAccountCount;
        uint256 teamBattleCount;
        uint256 teamBattleDestroValue;
        uint256 claimableProfit;
        uint256 totalRecruitBattleProfit;
        uint256 totalHorizontalProfit;
    }

    struct RecruitOgBindInfo {
        uint256 ogId;
        uint256 battleCount;
        uint256 timestamp;
    }

    struct RecruitAccountBindInfo {
        address account;
        uint256 battleCount;
        uint256 timestamp;
    }

    struct OgStatistic {
        uint256 ogId;
        uint256 totalWinCount;
        uint256 totalLossCount;
        uint256 totalDestroValue;
        uint256 totalRecruitAccountCount;
        uint256 totalRecruitOgCount;
        uint256 totalRecruitBattleProfit;
        uint256 totalHorizontalProfit;
        uint256 claimableProfit;
    }

    function bindOgNft(string memory code) external;

    function claimProfit(uint256 ogId) external;

    function onCardDestroy(
        address losser,
        address winner,
        uint256 usdaAmount
    ) external returns (uint256 profitAmount);

    function getOgCodes(address account) external view returns (string[] memory);

    function isAccountBoundSponsor(address account) external view returns (bool);

    function getTeamInfo(uint256 ogId) external view returns (TeamInfo memory);

    function getRecruitOgBindRecord(uint256 ogId) external view returns (RecruitOgBindInfo[] memory);

    function getRecruitAccountBindRecord(uint256 ogId) external view returns (RecruitAccountBindInfo[] memory);

    function getClaimProfitRecord(
        uint256 ogId
    ) external view returns (GameGuildStorage.OgClaimProfitRecord[] memory);

    function getOgSponsorOgId(uint256 ogId) external view returns (uint256);

    function getAccountSponsorOgId(address account) external view returns (uint256);

    function getOgStatistic(uint256 ogId) external view returns (OgStatistic memory);

    function getAllOgStatistic() external view returns (OgStatistic[] memory);
}
