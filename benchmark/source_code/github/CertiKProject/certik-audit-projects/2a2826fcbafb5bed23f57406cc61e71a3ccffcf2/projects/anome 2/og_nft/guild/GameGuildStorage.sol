// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IConfig} from "../../config/IConfig.sol";

library GameGuildStorage {
    bytes32 internal constant STORAGE_SLOT = keccak256("anome.og.nft.guild.contracts.storage.v1");

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }

    struct Layout {
        IConfig config;
        address shop;

        mapping(uint256 => uint256) ogClaimableProfit;

        mapping(uint256 => bool) isOgBoundSponsor;
        mapping(uint256 => uint256) ogSponsorOgId;
        mapping(uint256 => RecruitOgBindRecord[]) ogRecruitOgBindRecord;

        mapping(address => bool) isAccountBoundSponsor;
        mapping(address => uint256) accountSponsorOgId;
        mapping(uint256 => RecruitAccountBindRecord[]) ogRecruitAccountBindRecord;

        mapping(address => uint256) accountLossCount;
        mapping(address => uint256) accountWinCount;
        mapping(uint256 => uint256) ogTeamBattleLossCount;
        mapping(uint256 => uint256) ogTeamBattleWinCount;
        mapping(uint256 => uint256) ogTeamBattleDestroyValue;

        mapping(uint256 => uint256) ogTotalRecruitBattleProfit;
        mapping(uint256 => uint256) ogTotalHorizontalProfit;
        mapping(uint256 => OgClaimProfitRecord[]) ogClaimProfitRecord;
    }

    struct RecruitOgBindRecord {
        uint256 ogId;
        uint256 timestamp;
    }

    struct RecruitAccountBindRecord {
        address account;
        uint256 timestamp;
    }

    struct OgClaimProfitRecord {
        uint256 amount;
        uint256 timestamp;
    }
}
