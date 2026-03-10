// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {ShopTypes} from "../ShopTypes.sol";
import {ShopStorage} from "../ShopStorage.sol";

import {IShopReferralInternal} from "./IShopReferralInternal.sol";

contract ShopReferralInternal is IShopReferralInternal {
    // 通过是否绑定上级来确定一个用户是否被创建, 是因为保证默认上级作为最顶级上级
    // 如果一个账号可以另开邀请分支, 就会架空默认上级
    function _isAccountCreated(address account) internal view returns (bool) {
        ShopStorage.Layout storage data = ShopStorage.layout();
        return data.accountSponsor[account] != address(0) || account == data.config.defaultSponsor();
    }

    function _createCode(address account) internal {
        ShopStorage.Layout storage data = ShopStorage.layout();
        if (data.accountCode[account] != 0) revert CodeAlreadyCreated();

        _recreateCode(account);
    }

    function _recreateCode(address account) internal {
        uint256 code = _genCode();
        _setCode(account, code);
    }

    function _genCode() internal returns (uint256) {
        ShopStorage.Layout storage data = ShopStorage.layout();
        uint256 newCode = block.timestamp;

        for (uint i = 0; i < 999; i++) {
            if (data.codeStatus[newCode]) {
                newCode = newCode + 1;
            } else {
                break;
            }
        }

        data.codeStatus[newCode] = true;

        return newCode;
    }

    function _setCode(address account, uint256 code) internal {
        ShopStorage.Layout storage data = ShopStorage.layout();
        data.accountCode[account] = code;
        data.accountByCode[code] = account;
        emit CodeSet(msg.sender, account, code);
    }

    function _removeCode(address account, bool isRemoveRelation) internal {
        ShopStorage.Layout storage data = ShopStorage.layout();
        uint256 oldCode = data.accountCode[account];
        delete data.accountCode[account];
        delete data.accountByCode[oldCode];

        if (isRemoveRelation) {
            _removeSponsor(account);
            _removeAllRecruit(account);
        }

        emit CodeRemoved(msg.sender, account, oldCode);
    }

    function _bindSponsor(address account, uint256 sponsorCode) internal {
        ShopStorage.Layout storage data = ShopStorage.layout();
        if (data.accountSponsor[account] != address(0)) revert AccountAlreadyCreated();

        address sponsorAddress;
        if (sponsorCode == 0) {
            sponsorAddress = data.config.defaultSponsor();
        } else {
            sponsorAddress = data.accountByCode[sponsorCode];
        }
        _rebindSponsor(account, sponsorAddress);
    }

    function _rebindSponsor(address account, address sponsor) internal {
        ShopStorage.Layout storage data = ShopStorage.layout();
        if (sponsor == address(0)) revert InvalidAccount(sponsor);
        if (sponsor == account) revert InvalidSponsor(sponsor);
        if (data.accountSponsor[account] != address(0)) revert AccountAlreadyCreated();

        data.accountSponsor[account] = sponsor;
        data.accountRecruits[sponsor].push(ShopTypes.Recruit({account: account, timestamp: block.timestamp}));

        emit RelationBinded(msg.sender, account, sponsor);
    }

    function _changeSponsor(address account, address newSponsor) internal {
        ShopStorage.Layout storage data = ShopStorage.layout();
        address oldSponsor = data.accountSponsor[account];
        _removeRecruit(oldSponsor, account);
        _rebindSponsor(account, newSponsor);
    }

    function _removeSponsor(address account) internal {
        if (account == address(0)) {
            return;
        }

        ShopStorage.Layout storage data = ShopStorage.layout();
        delete data.accountSponsor[account];
    }

    function _removeRecruit(address account, address recruit) internal {
        if (account == address(0)) {
            return;
        }

        if (recruit == address(0)) {
            return;
        }

        ShopStorage.Layout storage data = ShopStorage.layout();
        ShopTypes.Recruit[] storage recruits = data.accountRecruits[account];
        for (uint i = 0; i < recruits.length; i++) {
            if (recruits[i].account == recruit) {
                delete recruits[i];
            }
        }

        _removeSponsor(recruit);
    }

    function _removeAllRecruit(address account) internal {
        if (account == address(0)) {
            return;
        }

        ShopStorage.Layout storage data = ShopStorage.layout();
        ShopTypes.Recruit[] memory recruits = data.accountRecruits[account];
        for (uint i = 0; i < recruits.length; i++) {
            _removeSponsor(recruits[i].account);
        }

        delete data.accountRecruits[account];
    }
}
