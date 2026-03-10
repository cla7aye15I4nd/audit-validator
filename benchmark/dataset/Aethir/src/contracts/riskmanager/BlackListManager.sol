// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {
    IRegistry,
    IBlackListManager,
    ITierController,
    BaseService,
    BLACKLIST_MANAGER_ID,
    TIER_CONTROLLER_ID
} from "../Index.sol";

contract BlackListManager is IBlackListManager, BaseService {
    // Tracks if an address is blacklisted for specific tiers
    mapping(address => uint8) private _userBlackListedTier;

    constructor(IRegistry registry) BaseService(registry, BLACKLIST_MANAGER_ID) {}

    function setBlackListed(address account, uint8 tier) external override {
        _registry.getACLManager().requireConfigurationAdmin(msg.sender);
        _userBlackListedTier[account] = tier;
        emit BlackListed(account, tier);
    }

    function isAllowed(address account, bytes4 functionSelector) external view override returns (bool) {
        ITierController tierController = ITierController(_registry.getAddress(TIER_CONTROLLER_ID));
        uint8 functionTier = tierController.getTier(functionSelector);
        return functionTier > _userBlackListedTier[account];
    }
}
