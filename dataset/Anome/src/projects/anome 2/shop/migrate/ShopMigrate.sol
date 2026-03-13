// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IConfig} from "../../config/IConfig.sol";
import {ShopStorage} from "../ShopStorage.sol";

import {IShopMigrate} from "./IShopMigrate.sol";
import {SafeOwnableInternal} from "../../../lib/solidstate/access/ownable/SafeOwnableInternal.sol";
import {ShopReferralInternal} from "../referral/ShopReferralInternal.sol";

contract ShopMigrate is IShopMigrate, SafeOwnableInternal, ShopReferralInternal {
    function migrate01(address config) external override onlyOwner {
        ShopStorage.Layout storage data = ShopStorage.layout();
        // config
        data.config = IConfig(config);
        // default sponsor
        _recreateCode(data.config.defaultSponsor());
        // destroy params
        data.destroyRewardRatio = 2000;
        data.destroyPerSponsorRatio = 500;
        // borrow params
        data.borrowLtv = 3000;
        data.borrowIndex = 1e27;
        data.borrowRate = 8e25;
        data.borrowIndexLastUpdateTimestamp = uint40(block.timestamp);
        // wk params
        data.wkRankLength = 3;
    }

    function migrate02() external override onlyOwner {
        ShopStorage.Layout storage data = ShopStorage.layout();
        // 调整对战卡牌销毁比例
        // 胜方和负方的上级各自2.5%
        // 40%回流
        // 30% IP方
        // 25% 游戏代理分红
        data.destroyRewardRatio = 2500;
        data.destroyPerSponsorRatio = 250;
    }

    function migrate03() external override onlyOwner {
        ShopStorage.Layout storage data = ShopStorage.layout();
        // 初始化Xnome挖矿参数
        data.initialBnomeDistribution = 555555 * 1e18;
        data.bnomeDistributionStartTime = block.timestamp;
    }

    function migrate04() external override onlyOwner {
        ShopStorage.Layout storage data = ShopStorage.layout();
        data.highBorrowLTV = 9500;
    }

    function migrate05() external override onlyOwner {
        ShopStorage.Layout storage data = ShopStorage.layout();
        data.isAccountBanned[0xDC577C0d4D3DeF4BbBE3Ab4A993DDe8840c80e95] = true;

        // 17 69501 - 69500
        // 28 59020 - 59000
        // 87 37043 - 37000
        // 37 5046 - 5000
        // 169 4513 - 4500

        // if (data.pools[17].cardDecreaseVirtualBalance > 69500) {
        //     data.pools[17].cardDecreaseVirtualBalance -= 69500;
        // }
        // if (data.pools[28].cardDecreaseVirtualBalance > 59000) {
        //     data.pools[28].cardDecreaseVirtualBalance -= 59000;
        // }
        // if (data.pools[87].cardDecreaseVirtualBalance > 37000) {
        //     data.pools[87].cardDecreaseVirtualBalance -= 37000;
        // }
        // if (data.pools[37].cardDecreaseVirtualBalance > 5000) {
        //     data.pools[37].cardDecreaseVirtualBalance -= 5000;
        // }
        // if (data.pools[169].cardDecreaseVirtualBalance > 4500) {
        //     data.pools[169].cardDecreaseVirtualBalance -= 4500;
        // }
    }

    function migrate06() external override onlyOwner {
        ShopStorage.Layout storage data = ShopStorage.layout();
        data.isShopPaused = false;
        data.hasPausePermission[0xc958682886513C48A8D50e212b6D2CD510B5F39A] = true;
        data.hasPausePermission[0x7629fAc34Cc0ddBCc89f5B29395bC6e6028ed19a] = true;
        data.hasPausePermission[_owner()] = true;
        data.hasPausePermission[data.config.caller()] = true;

        data.isNoContractWhitelist[0xB7F5c23bb2e627391a18919bBD57C67fa94a5d59] = true;
        data.isAccountBanned[0x735D6Db96f26300867E680aAaB844Ba44c7c341f] = true;
        data.isAccountBanned[0x6CE7ebf20C543D620c2f77494DfDb45fC22AC2d9] = true;
    }

    function migrate07() external override onlyOwner {
        ShopStorage.Layout storage data = ShopStorage.layout();
        data.xnomeProductionCutStartAt = block.timestamp / 1 days;
        data.xnomeProductionCutRatioPerDay = 200;
        data.minXnomeRatio = 5000;
    }
}
