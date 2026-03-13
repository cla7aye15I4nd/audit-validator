// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUSDA} from "../../token/usda/IUSDA.sol";

import {Og721Storage} from "../erc721/Og721Storage.sol";
import {GameGuildStorage} from "./GameGuildStorage.sol";
import {NumberEncoderLib} from "./NumberEncoderLib.sol";

import {IGameGuildInternal} from "./IGameGuildInternal.sol";
import {ERC721BaseInternal} from "../../../lib/solidstate/token/ERC721/base/ERC721BaseInternal.sol";
import {ERC721EnumerableInternal} from "../../../lib/solidstate/token/ERC721/enumerable/ERC721EnumerableInternal.sol";

contract GameGuildInternal is IGameGuildInternal, ERC721BaseInternal, ERC721EnumerableInternal {
    function _getAndCheckOgNft(string memory code) internal view returns (uint256 sponsorOg) {
        Og721Storage.Layout storage lo = Og721Storage.layout();
        sponsorOg = NumberEncoderLib.decode(code);
        if (sponsorOg == 0) {
            revert OgNftIdError();
        }
        if (sponsorOg > lo.currentId) {
            revert OgNftIdError();
        }
        if (_ownerOf(sponsorOg) == address(0)) {
            revert OgNftIdError();
        }
    }

    function _ogBindSponsor(address account, uint256 sponsorOg) internal {
        GameGuildStorage.Layout storage lg = GameGuildStorage.layout();

        if (_balanceOf(account) == 0) {
            return;
        }

        // 检查用户是否有多个OG, 不允许有多个OG在手上
        if (_balanceOf(account) > 1) {
            revert HoldMoreThanOneOg();
        }

        uint256 ogId = _tokenOfOwnerByIndex(account, 0);
        // OG不能绑定自己
        if (ogId == sponsorOg) {
            revert OgCannotBindSelf();
        }
        // 检查OG是否已经绑定上级
        if (lg.isOgBoundSponsor[ogId]) {
            revert AlreadyBound();
        }

        lg.isOgBoundSponsor[ogId] = true;
        lg.ogSponsorOgId[ogId] = sponsorOg;

        lg.ogRecruitOgBindRecord[sponsorOg].push(
            GameGuildStorage.RecruitOgBindRecord({ogId: ogId, timestamp: block.timestamp})
        );

        emit OgBindSponsor(ogId, account, sponsorOg, _ownerOf(sponsorOg));
    }

    function _accountBindSponsor(address account, uint256 sponsorOg) internal {
        GameGuildStorage.Layout storage lg = GameGuildStorage.layout();

        if (lg.isAccountBoundSponsor[account]) {
            revert AlreadyBound();
        }

        if (lg.ogRecruitAccountBindRecord[sponsorOg].length > 200) {
            revert RecruitAccountCountExceeded();
        }

        lg.isAccountBoundSponsor[account] = true;
        lg.accountSponsorOgId[account] = sponsorOg;

        lg.ogRecruitAccountBindRecord[sponsorOg].push(
            GameGuildStorage.RecruitAccountBindRecord({account: account, timestamp: block.timestamp})
        );

        emit AccountBindSponsor(account, sponsorOg, _ownerOf(sponsorOg));
    }

    function _claimProfit(address account, uint256 ogId) internal {
        GameGuildStorage.Layout storage lg = GameGuildStorage.layout();

        if (_balanceOf(account) == 0) {
            revert OgNftNotOwner();
        }

        if (_balanceOf(account) > 1) {
            revert HoldMoreThanOneOg();
        }

        if (_tokenOfOwnerByIndex(account, 0) != ogId) {
            revert OgNftNotOwner();
        }

        if (lg.ogClaimableProfit[ogId] == 0) {
            revert NoClaimableProfit();
        }

        uint256 amount = lg.ogClaimableProfit[ogId];
        lg.ogClaimableProfit[ogId] = 0;
        lg.ogClaimProfitRecord[ogId].push(
            GameGuildStorage.OgClaimProfitRecord({amount: amount, timestamp: block.timestamp})
        );

        IUSDA(lg.config.usda()).transfer(account, amount);

        emit ClaimOgProfit(ogId, account, amount);
    }

    function _onCardDestroy(
        address losser,
        address winner,
        uint256 usdaAmount
    ) internal returns (uint256 profitAmount) {
        GameGuildStorage.Layout storage lg = GameGuildStorage.layout();

        if (msg.sender != lg.config.shop()) {
            revert OnlyShop();
        }

        if (!lg.isAccountBoundSponsor[losser]) {
            return 0;
        }

        uint256 ogId = lg.accountSponsorOgId[losser];
        address ogOwner = _ownerOf(ogId);
        if (ogOwner == address(0)) {
            return 0;
        }

        // 下级收益的组成: 基础收益是5%, 每个下级OG增加1%, 最多增加4%
        uint256 recruitProfit = 5;
        uint256 recruitMultiplier = lg.ogRecruitOgBindRecord[ogId].length;
        if (recruitMultiplier > 4) {
            recruitMultiplier = 4;
        }
        recruitProfit += recruitMultiplier;
        uint256 recruitProfitAmount = (usdaAmount * recruitProfit) / 100;

        lg.ogClaimableProfit[ogId] += recruitProfitAmount;
        lg.ogTotalRecruitBattleProfit[ogId] += recruitProfitAmount;
        profitAmount += recruitProfitAmount;

        // 上级收益的组成: 如果有上级, 则上级OG拿1%
        uint256 sponsorProfitAmount;
        address sponsorOgOwner;
        if (lg.isOgBoundSponsor[ogId]) {
            sponsorProfitAmount = (usdaAmount * 1) / 100;
            sponsorOgOwner = _ownerOf(lg.ogSponsorOgId[ogId]);
            lg.ogClaimableProfit[lg.ogSponsorOgId[ogId]] += sponsorProfitAmount;
            lg.ogTotalHorizontalProfit[lg.ogSponsorOgId[ogId]] += sponsorProfitAmount;
            profitAmount += sponsorProfitAmount;
        }

        // 记录统计数据
        lg.accountLossCount[losser]++;
        lg.accountWinCount[winner]++;
        lg.ogTeamBattleLossCount[ogId]++;
        lg.ogTeamBattleDestroyValue[ogId] += usdaAmount;

        if (lg.isAccountBoundSponsor[winner]) {
            lg.ogTeamBattleWinCount[lg.accountSponsorOgId[winner]]++;
        }

        emit OgCardDestroy(
            losser,
            winner,
            usdaAmount,
            OgCardDestroyProfitInfo({
                ogId: ogId,
                ogOwner: ogOwner,
                recruitMultiplier: recruitMultiplier,
                recruitProfitAmount: recruitProfitAmount,
                sponsorOgId: lg.ogSponsorOgId[ogId],
                sponsorOgOwner: sponsorOgOwner,
                sponsorProfitAmount: sponsorProfitAmount,
                totalProfitAmount: profitAmount
            })
        );
    }
}
