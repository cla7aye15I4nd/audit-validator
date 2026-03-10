// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IGameGuildInternal {
    error OgNftIdError();
    error AlreadyBound();
    error OgNftNotOwner();
    error HoldMoreThanOneOg();
    error NoClaimableProfit();
    error RecruitAccountCountExceeded();
    error OgCannotBindSelf();
    error OnlyShop();

    struct OgCardDestroyProfitInfo {
        uint256 ogId; // 销毁时得到收益的OG
        address ogOwner; // 销毁时得到收益的OG的owner
        uint256 recruitMultiplier; // 销毁时得到收益的OG的下级收益倍数
        uint256 recruitProfitAmount; // 销毁时得到收益的OG的下级收益金额
        uint256 sponsorOgId; // 销毁时得到收益的OG的上级OG
        address sponsorOgOwner; // 销毁时得到收益的OG的上级OG的owner
        uint256 sponsorProfitAmount; // 销毁时得到收益的OG的上级OG的收益金额
        uint256 totalProfitAmount; // 销毁时分发的收益总数, 包含OG和OG上级OG
    }

    event OgBindSponsor(
        uint256 indexed ogId,
        address indexed ogOwner,
        uint256 indexed sponsorOg,
        address sponsorOgOwner
    );
    event AccountBindSponsor(address indexed account, uint256 indexed sponsorOg, address sponsorOgOwner);
    event ClaimOgProfit(uint256 indexed ogId, address indexed account, uint256 amount);
    event OgCardDestroy(
        address indexed losser,
        address indexed winner,
        uint256 usdaAmount,
        OgCardDestroyProfitInfo ogCardDestroyProfitInfo
    );
}
