// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {ERC20} from "../../../lib/openzeppelin/token/ERC20/ERC20.sol";
import {IERC20} from "../../../lib/openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "../../../lib/openzeppelin/token/ERC20/utils/SafeERC20.sol";

import {ShopTypes} from "../ShopTypes.sol";
import {ShopStorage} from "../ShopStorage.sol";
import {ICard} from "../../token/card/ICard.sol";
import {IShopReferral} from "./IShopReferral.sol";
import {ShopReferralInternal} from "./ShopReferralInternal.sol";
import {SafeOwnableInternal} from "../../../lib/solidstate/access/ownable/SafeOwnableInternal.sol";

contract ShopReferral is IShopReferral, ShopReferralInternal, SafeOwnableInternal {
    using SafeERC20 for IERC20;

    // Write

    function buyCode() external payable {
        // if (msg.value < (15 * 1e18 / 1000000)) revert Errors.InsufficientValue();
        // payable(Storage.layout().treasury).transfer(msg.value);
        _createCode(msg.sender);
    }

    function bindSponsor(uint256 code) external override {
        _bindSponsor(msg.sender, code);
    }

    function bindRecruit(address recruit, address card, uint256 amount) external override {
        ShopStorage.Layout storage data = ShopStorage.layout();
        ICard realCard = data.pools[data.cardsIndex[card]].card;
        if (realCard != ICard(card)) revert InvalidReferralCardAddress();
        if (amount < 1e17) revert InvalidReferralAmount();

        if (data.accountCode[msg.sender] == 0) revert AccountNotRegister(msg.sender);
        if (data.accountSponsor[msg.sender] == address(0)) revert AccountHasNoSponsor(msg.sender);

        realCard.transferFrom(msg.sender, recruit, amount);
        _rebindSponsor(recruit, msg.sender);
    }

    // View

    function isAccountCreated(address account) public view override returns (bool) {
        ShopStorage.Layout storage data = ShopStorage.layout();
        return data.accountSponsor[account] != address(0) || account == data.config.defaultSponsor();
    }

    function getAccountCode(address account) external view override returns (uint256) {
        ShopStorage.Layout storage data = ShopStorage.layout();
        return data.accountCode[account];
    }

    function getAccountByCode(uint256 code) external view override returns (address) {
        ShopStorage.Layout storage data = ShopStorage.layout();
        return data.accountByCode[code];
    }

    function getSponsor(address account) external view override returns (address) {
        // if (!isAccountCreated(account)) revert Errors.AccountNotRegister(account);

        return ShopStorage.layout().accountSponsor[account];
    }

    function getRecruits(address account) external view override returns (ShopTypes.Recruit[] memory) {
        // if (!isAccountCreated(account)) revert Errors.AccountNotRegister(account);

        ShopStorage.Layout storage data = ShopStorage.layout();
        ShopTypes.Recruit[] memory recruits = new ShopTypes.Recruit[](data.accountRecruits[account].length);
        for (uint256 i = 0; i < data.accountRecruits[account].length; i++) {
            recruits[i] = data.accountRecruits[account][i];
        }
        return recruits;
    }

    function getDownlines(address account) external view override returns (ShopTypes.Downline[] memory) {
        ShopStorage.Layout storage data = ShopStorage.layout();
        ShopTypes.Downline[] memory downlines = new ShopTypes.Downline[](data.accountRecruits[account].length);

        for (uint256 i = 0; i < data.accountRecruits[account].length; i++) {
            address recruit = data.accountRecruits[account][i].account;
            uint256 recruitDownlinesLength = data.accountRecruits[recruit].length;
            ShopTypes.DownlineItem[] memory recruitDownlines = new ShopTypes.DownlineItem[](
                recruitDownlinesLength
            );

            for (uint256 j = 0; j < recruitDownlinesLength; j++) {
                address recruitDownline = data.accountRecruits[recruit][j].account;
                recruitDownlines[j] = ShopTypes.DownlineItem({
                    account: recruitDownline,
                    level: data.battleLevel[recruitDownline]
                });
            }

            downlines[i] = ShopTypes.Downline({
                account: recruit,
                downlines: recruitDownlines,
                level: data.battleLevel[recruit]
            });
        }

        return downlines;
    }

    function getUplines(address account, uint256 length) external view override returns (address[] memory) {
        // if (!isAccountCreated(account)) revert Errors.AccountNotRegister(account);

        ShopStorage.Layout storage data = ShopStorage.layout();
        address[] memory uplines = new address[](length);
        for (uint256 i = 0; i < uplines.length; i++) {
            address curAccount;

            if (i == 0) {
                curAccount = account;
            } else {
                curAccount = uplines[i - 1];
            }

            address curSponsor = data.accountSponsor[curAccount];
            if (curSponsor == address(0)) {
                break;
            } else {
                uplines[i] = curSponsor;
            }
        }
        return uplines;
    }

    // Admin

    function adminCreateCode(address account) external override onlyOwner {
        ShopStorage.Layout storage data = ShopStorage.layout();
        if (data.accountCode[account] != 0) revert CodeAlreadyCreated();
        _recreateCode(account);
    }

    function adminRecreateCode(address account) external override onlyOwner {
        _recreateCode(account);
    }

    function adminSetCode(address account, uint256 code) external override onlyOwner {
        _setCode(account, code);
    }

    function adminRemoveCode(address account, bool isRemoveRelation) external override onlyOwner {
        _removeCode(account, isRemoveRelation);
    }

    function adminBindSponsor(address account, address sponsor) external override onlyOwner {
        ShopStorage.Layout storage data = ShopStorage.layout();
        if (data.accountSponsor[account] != address(0)) revert AccountAlreadyCreated();
        _rebindSponsor(account, sponsor);
    }

    function adminSetReferral(address account, address sponsor) external override onlyOwner {
        _changeSponsor(account, sponsor);
    }

    function adminRemoveRelation(address account) external override onlyOwner {
        _removeSponsor(account);
        _removeAllRecruit(account);
    }

    function callerBindSponsor(address account, uint256 sponsorCode) public override {
        ShopStorage.Layout storage data = ShopStorage.layout();
        if (msg.sender != data.config.caller()) revert OnlyCaller();
        if (data.accountSponsor[account] != address(0)) revert AccountAlreadyCreated();

        address sponsorAddress = data.accountByCode[sponsorCode];
        if (sponsorAddress == address(0)) revert InvalidSponsor(sponsorAddress);

        _rebindSponsor(account, sponsorAddress);
    }

    function callerBatchBindSponsor(address[] memory accounts, address[] memory sponsors) external override {
        ShopStorage.Layout storage data = ShopStorage.layout();
        if (msg.sender != data.config.caller()) revert OnlyCaller();
        if (accounts.length != sponsors.length) revert InvalidInput();

        for (uint256 i = 0; i < accounts.length; i++) {
            if (data.accountSponsor[accounts[i]] != address(0)) continue;
            _rebindSponsor(accounts[i], sponsors[i]);
        }
    }

    function callerSetCode(address[] memory accounts, uint256[] memory codes) external override {
        ShopStorage.Layout storage data = ShopStorage.layout();
        if (msg.sender != data.config.caller()) revert OnlyCaller();
        if (accounts.length != codes.length) revert InvalidInput();

        for (uint256 i = 0; i < accounts.length; i++) {
            // 可以重复修改Code
            // if (data.accountCode[accounts[i]] != 0) continue;

            _setCode(accounts[i], codes[i]);
        }
    }
}
