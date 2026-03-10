// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "../../../lib/openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../../lib/openzeppelin/token/ERC20/utils/SafeERC20.sol";

import {ShopStorage} from "../ShopStorage.sol";
import {IVnome} from "../../token/vnome/IVnome.sol";
import {IWK} from "../../token/wk/IWK.sol";
import {ShopTypes} from "../ShopTypes.sol";

import {IBattleService} from "./IBattleService.sol";
import {BattleServiceInternal} from "./BattleServiceInternal.sol";

contract BattleService is IBattleService, BattleServiceInternal {
    using SafeERC20 for IERC20;

    // ========= Write =========

    function onBattled(
        address winner,
        address loser,
        uint256 amount,
        uint256 winnerCardCost,
        uint256 loserCardCost,
        uint256 destroyValue
    )
        external
        returns (
            uint256 winnerVnomeAmount,
            uint256 loserVnomeAmount,
            uint256 winnerSponsorVnomeAmount,
            uint256 loserSponsorVnomeAmount,
            uint256 wkAmount
        )
    {
        OnBattledResult memory result = _onBattled(
            winner,
            loser,
            amount,
            winnerCardCost,
            loserCardCost,
            destroyValue
        );
        return (
            result.winnerVnomeAmount,
            result.loserVnomeAmount,
            result.winnerSponsorVnomeAmount,
            result.loserSponsorVnomeAmount,
            result.wkAmount
        );
    }

    function destroyCard(
        address account,
        address cardAddr,
        address winner,
        address loser
    ) external override returns (uint256 xnomeAmount) {
        xnomeAmount = _destroyCard(account, cardAddr, winner, loser);
    }

    // ========= Read =========

    function getAccountBattleLevel(address account) external view override returns (uint256) {
        return ShopStorage.layout().battleLevel[account];
    }

    function getAccountBattleExp(address account) external view override returns (uint256) {
        return ShopStorage.layout().battleExp[account];
    }

    function getAccountBattleRewardInfo(
        address account
    ) external view override returns (ShopTypes.BattleRewardInfo memory) {
        return
            ShopTypes.BattleRewardInfo(
                ShopStorage.layout().battleReward[account],
                ShopStorage.layout().battleLevel[account],
                ShopStorage.layout().battleExp[account]
            );
    }

    function getAccountBattleRecordLength(address account) external view override returns (uint256) {
        return ShopStorage.layout().battleRewardRecords[account].length;
    }

    function getAccountBattleRecords(
        address account,
        uint256 page,
        uint256 size
    ) external view override returns (ShopTypes.BattleRewardRecord[] memory records) {
        ShopStorage.Layout storage data = ShopStorage.layout();
        uint256 totalSize = data.battleRewardRecords[account].length;
        uint256 start = page * size;
        if (start >= totalSize) {
            return new ShopTypes.BattleRewardRecord[](0);
        }
        uint256 end = (start + size) > totalSize ? totalSize : (start + size);

        records = new ShopTypes.BattleRewardRecord[](end - start);
        for (uint256 i = 0; i < (end - start); i++) {
            records[i] = data.battleRewardRecords[account][start + i];
        }
    }
}
