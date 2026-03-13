// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IWK} from "../../token/wk/IWK.sol";
import {IVnome} from "../../token/vnome/IVnome.sol";
import {IUSDA} from "../../token/usda/IUSDA.sol";

import {ShopTypes} from "../ShopTypes.sol";
import {ShopStorage} from "../ShopStorage.sol";
import {IConfig} from "../../config/IConfig.sol";
import {IOgNFT} from "../../og_nft/IOgNFT.sol";

import {CardShopPriceInternal} from "../card/CardShopPriceInternal.sol";
import {BattleMiningInternal} from "../mining/BattleMiningInternal.sol";
import {IBattleServiceInternal} from "./IBattleServiceInternal.sol";
import {ShopCommonInternal} from "../common/ShopCommonInternal.sol";

contract BattleServiceInternal is
    IBattleServiceInternal,
    CardShopPriceInternal,
    ShopCommonInternal,
    BattleMiningInternal
{
    struct OnBattledResult {
        uint256 winnerVnomeAmount;
        uint256 loserVnomeAmount;
        uint256 winnerSponsorVnomeAmount;
        uint256 loserSponsorVnomeAmount;
        uint256 wkAmount;
    }

    function _onBattled(
        address winner,
        address loser,
        uint256 amount,
        uint256 winnerCardCost,
        uint256 loserCardCost,
        uint256 destroyValue
    ) internal onlyGame returns (OnBattledResult memory result) {
        ShopStorage.Layout storage data = ShopStorage.layout();

        // 发放Vnome
        result = _processVnomeDistribution(winner, loser, amount);

        // 发放WK
        result.wkAmount = 1e18;
        IWK(data.config.wkToken()).mint(winner, result.wkAmount);

        // 记录用户对战经验和级别
        data.battleExp[winner] += 1;
        if (data.battleExp[winner] >= 3000 && data.battleLevel[winner] == 0) {
            data.battleLevel[winner] = 1;
        }

        data.battleExp[loser] += 1;
        if (data.battleExp[loser] >= 3000 && data.battleLevel[loser] == 0) {
            data.battleLevel[loser] = 1;
        }

        // 发放Bnome亏损补偿
        _setCostIncome(winner, loser, winnerCardCost, loserCardCost, destroyValue);

        return result;
    }

    function _processVnomeDistribution(
        address winner,
        address loser,
        uint256 amount
    ) internal returns (OnBattledResult memory result) {
        ShopStorage.Layout storage data = ShopStorage.layout();

        address winnerSponsor = data.accountSponsor[winner];
        address loserSponsor = data.accountSponsor[loser];

        result.winnerVnomeAmount = (amount * 10) / 100;
        result.loserVnomeAmount = (amount * 70) / 100;
        result.winnerSponsorVnomeAmount = (amount * 10) / 100;
        result.loserSponsorVnomeAmount = (amount * 10) / 100;

        _sendVnome(winner, result.winnerVnomeAmount, false);
        _sendVnome(loser, result.loserVnomeAmount, false);
        _sendVnome(winnerSponsor, result.winnerSponsorVnomeAmount, true);
        _sendVnome(loserSponsor, result.loserSponsorVnomeAmount, true);

        return result;
    }

    function _sendVnome(address account, uint256 amount, bool isReferral) internal {
        if (account == address(0)) {
            return;
        }

        ShopStorage.Layout storage data = ShopStorage.layout();
        IVnome(data.config.vnome()).mint(account, amount);

        if (isReferral) {
            emit OnReferralRewawrd(account, amount);
        } else {
            emit OnBattleRewawrd(account, amount);
        }
    }

    function _destroyCard(
        address account,
        address cardAddr,
        address winner,
        address loser
    ) internal onlyGame returns (uint256 xnomeAmount) {
        account;

        if (cardAddr == address(0)) {
            return 0;
        }

        ShopStorage.Layout storage data = ShopStorage.layout();
        uint256 index = data.cardsIndex[cardAddr];
        ShopTypes.CardPool storage pool = data.pools[index];

        if (address(data.pools[index].card) != cardAddr) {
            return 0;
        }

        // 计算销毁卡牌的价值
        // 40% 回流, 什么都不做就是回流
        uint256 releasedUsda = _priceOf(index);
        uint256 ipAmount = _destroyCardToIP(index, releasedUsda);
        uint256 treasuryAmount = _destroyCardToTreasury(index, winner, loser, releasedUsda);
        DestroyCardToSponsorResult memory sponsorResult = _destroyCardToSponsor(
            index,
            winner,
            loser,
            releasedUsda
        );

        if (ipAmount + treasuryAmount + (sponsorResult.sponsorAmount * 2) > releasedUsda) {
            revert CardDestroyedAmountExceeded();
        }

        // 收取要销毁的卡牌
        pool.card.transferFrom(msg.sender, ShopStorage.HOLE, pool.card.getUnit());
        // 发放Xnome
        xnomeAmount = _distributeXnome(loser, releasedUsda);

        emit CardDestroyed(
            index,
            address(pool.card),
            releasedUsda,
            pool.card.getIPReceiver().receiver,
            ipAmount,
            data.config.cardDestroyPayee(),
            treasuryAmount,
            sponsorResult.winnerSponsor,
            sponsorResult.sponsorAmount,
            sponsorResult.loserSponsor,
            sponsorResult.sponsorAmount
        );
    }

    function _destroyCardToIP(uint256 cardId, uint256 releasedUsda) internal returns (uint256 ipAmount) {
        ShopStorage.Layout storage data = ShopStorage.layout();
        ShopTypes.CardPool storage pool = data.pools[cardId];

        // 30% IP方
        ipAmount = (releasedUsda * pool.card.getIPReceiver().ratio) / ShopStorage.DIVIDEND;
        _transferPoolUsda(cardId, pool.card.getIPReceiver().receiver, ipAmount);
        pool.ipRevenue += ipAmount;
    }

    function _destroyCardToTreasury(
        uint256 cardId,
        address winner,
        address loser,
        uint256 releasedUsda
    ) internal returns (uint256 treasuryAmount) {
        ShopStorage.Layout storage data = ShopStorage.layout();

        // 25% 一部分是项目方分红, 一部分是OG NFT分红(最多10%), 一部分是公会分红
        uint256 ogNftAmount = IOgNFT(data.config.ogNFT()).onCardDestroy(loser, winner, releasedUsda);
        if (ogNftAmount > (releasedUsda * 10) / 100) {
            revert OgNftAmountExceeded();
        }

        treasuryAmount = (releasedUsda * data.destroyRewardRatio) / ShopStorage.DIVIDEND;
        if (ogNftAmount > treasuryAmount) {
            revert OgNftAmountExceeded();
        }

        _transferPoolUsda(cardId, data.config.ogNFT(), ogNftAmount);
        _transferPoolUsda(cardId, data.config.cardDestroyPayee(), treasuryAmount - ogNftAmount);
    }

    struct DestroyCardToSponsorResult {
        address winnerSponsor;
        address loserSponsor;
        uint256 sponsorAmount;
    }

    function _destroyCardToSponsor(
        uint256 cardId,
        address winner,
        address loser,
        uint256 releasedUsda
    ) internal returns (DestroyCardToSponsorResult memory result) {
        ShopStorage.Layout storage data = ShopStorage.layout();

        // 胜方和负方的上级各自2.5%
        uint256 sponsorAmount = (releasedUsda * data.destroyPerSponsorRatio) / ShopStorage.DIVIDEND;
        address winnerSponsor = data.accountSponsor[winner];
        address loserSponsor = data.accountSponsor[loser];

        result.winnerSponsor = winnerSponsor;
        result.loserSponsor = loserSponsor;
        result.sponsorAmount = sponsorAmount;

        if (winnerSponsor != address(0)) {
            _transferPoolUsda(cardId, winnerSponsor, sponsorAmount);
            data.battleReward[winnerSponsor] += sponsorAmount;
            data.battleRewardRecords[winnerSponsor].push(
                ShopTypes.BattleRewardRecord(winner, sponsorAmount, block.timestamp)
            );
        }
        if (loserSponsor != address(0)) {
            _transferPoolUsda(cardId, loserSponsor, sponsorAmount);
            data.battleReward[loserSponsor] += sponsorAmount;
            data.battleRewardRecords[loserSponsor].push(
                ShopTypes.BattleRewardRecord(loser, sponsorAmount, block.timestamp)
            );
        }
    }

    // 如果receiver为address(0), 则data.destroyReceiver收款
    function _transferPoolUsda(uint256 cardId, address receiver, uint256 amount) internal {
        ShopStorage.Layout storage data = ShopStorage.layout();
        ShopTypes.CardPool storage pool = data.pools[cardId];

        if (pool.usdaBalance > amount) {
            pool.usdaBalance -= amount;
        } else {
            pool.usdaBalance = 0;
        }

        if (receiver == address(0)) {
            receiver = data.config.cardDestroyPayee();
        }

        IUSDA(data.config.usda()).transfer(receiver, amount);
    }
}
