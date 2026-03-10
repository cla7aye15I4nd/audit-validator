// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Og721Storage} from "../erc721/Og721Storage.sol";
import {GameGuildStorage} from "./GameGuildStorage.sol";
import {NumberEncoderLib} from "./NumberEncoderLib.sol";

import {IGameGuild} from "./IGameGuild.sol";
import {GameGuildInternal} from "./GameGuildInternal.sol";

contract GameGuild is IGameGuild, GameGuildInternal {
    function bindOgNft(string memory code) external override {
        uint256 sponsorOg = _getAndCheckOgNft(code);
        _ogBindSponsor(msg.sender, sponsorOg);
        _accountBindSponsor(msg.sender, sponsorOg);
    }

    function claimProfit(uint256 ogId) external override {
        _claimProfit(msg.sender, ogId);
    }

    function onCardDestroy(
        address losser,
        address winner,
        uint256 usdaAmount
    ) external override returns (uint256 profitAmount) {
        profitAmount = _onCardDestroy(losser, winner, usdaAmount);
    }

    function getOgCodes(address account) external view override returns (string[] memory) {
        uint256 ogCount = _balanceOf(account);
        string[] memory codes = new string[](ogCount);
        for (uint256 i = 0; i < ogCount; i++) {
            codes[i] = NumberEncoderLib.encode(_tokenOfOwnerByIndex(account, i));
        }
        return codes;
    }

    function isAccountBoundSponsor(address account) external view override returns (bool) {
        GameGuildStorage.Layout storage lg = GameGuildStorage.layout();
        return lg.isAccountBoundSponsor[account];
    }

    function getTeamInfo(uint256 ogId) external view override returns (TeamInfo memory) {
        GameGuildStorage.Layout storage lg = GameGuildStorage.layout();
        return
            TeamInfo({
                teamOgCount: lg.ogRecruitOgBindRecord[ogId].length,
                teamAccountCount: lg.ogRecruitAccountBindRecord[ogId].length,
                teamBattleCount: lg.ogTeamBattleLossCount[ogId],
                teamBattleDestroValue: lg.ogTeamBattleDestroyValue[ogId],
                claimableProfit: lg.ogClaimableProfit[ogId],
                totalRecruitBattleProfit: lg.ogTotalRecruitBattleProfit[ogId],
                totalHorizontalProfit: lg.ogTotalHorizontalProfit[ogId]
            });
    }

    function getRecruitOgBindRecord(uint256 ogId) external view override returns (RecruitOgBindInfo[] memory) {
        GameGuildStorage.Layout storage lg = GameGuildStorage.layout();
        RecruitOgBindInfo[] memory records = new RecruitOgBindInfo[](lg.ogRecruitOgBindRecord[ogId].length);
        for (uint256 i = 0; i < lg.ogRecruitOgBindRecord[ogId].length; i++) {
            GameGuildStorage.RecruitOgBindRecord memory record = lg.ogRecruitOgBindRecord[ogId][i];
            address ogOwner = _ownerOf(record.ogId);
            records[i] = RecruitOgBindInfo({
                ogId: record.ogId,
                battleCount: lg.accountLossCount[ogOwner],
                timestamp: record.timestamp
            });
        }
        return records;
    }

    function getRecruitAccountBindRecord(
        uint256 ogId
    ) external view override returns (RecruitAccountBindInfo[] memory) {
        GameGuildStorage.Layout storage lg = GameGuildStorage.layout();
        RecruitAccountBindInfo[] memory records = new RecruitAccountBindInfo[](
            lg.ogRecruitAccountBindRecord[ogId].length
        );
        for (uint256 i = 0; i < lg.ogRecruitAccountBindRecord[ogId].length; i++) {
            GameGuildStorage.RecruitAccountBindRecord memory record = lg.ogRecruitAccountBindRecord[ogId][i];
            records[i] = RecruitAccountBindInfo({
                account: record.account,
                battleCount: lg.accountLossCount[record.account],
                timestamp: record.timestamp
            });
        }
        return records;
    }

    function getClaimProfitRecord(
        uint256 ogId
    ) external view override returns (GameGuildStorage.OgClaimProfitRecord[] memory) {
        GameGuildStorage.Layout storage lg = GameGuildStorage.layout();
        return lg.ogClaimProfitRecord[ogId];
    }

    function getOgSponsorOgId(uint256 ogId) external view override returns (uint256) {
        GameGuildStorage.Layout storage lg = GameGuildStorage.layout();
        return lg.ogSponsorOgId[ogId];
    }

    function getAccountSponsorOgId(address account) external view override returns (uint256) {
        GameGuildStorage.Layout storage lg = GameGuildStorage.layout();
        return lg.accountSponsorOgId[account];
    }

    function getOgStatistic(uint256 ogId) public view override returns (OgStatistic memory) {
        GameGuildStorage.Layout storage lg = GameGuildStorage.layout();
        return
            OgStatistic({
                ogId: ogId,
                totalWinCount: lg.ogTeamBattleWinCount[ogId],
                totalLossCount: lg.ogTeamBattleLossCount[ogId],
                totalDestroValue: lg.ogTeamBattleDestroyValue[ogId],
                totalRecruitAccountCount: lg.ogRecruitAccountBindRecord[ogId].length,
                totalRecruitOgCount: lg.ogRecruitOgBindRecord[ogId].length,
                totalRecruitBattleProfit: lg.ogTotalRecruitBattleProfit[ogId],
                totalHorizontalProfit: lg.ogTotalHorizontalProfit[ogId],
                claimableProfit: lg.ogClaimableProfit[ogId]
            });
    }

    function getAllOgStatistic() external view override returns (OgStatistic[] memory) {
        OgStatistic[] memory statistics = new OgStatistic[](_totalSupply());
        for (uint256 i = 0; i < _totalSupply(); i++) {
            statistics[i] = getOgStatistic(_tokenByIndex(i));
        }
        return statistics;
    }
}
