// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {IRegistry, ISlashConfigurator, BaseService, SLASH_CONFIGURATOR_ID} from "../Index.sol";

/// @title SlashConfigurator
/// @notice Configures system parameters.
contract SlashConfigurator is ISlashConfigurator, BaseService {
    uint256 private _expireTime = 30 days;

    constructor(IRegistry registry) BaseService(registry, SLASH_CONFIGURATOR_ID) {}

    function getTicketExpireTime() external view override returns (uint256) {
        return _expireTime;
    }

    function setTicketExpireTime(uint256 expireTime) external override {
        _registry.getACLManager().requireConfigurationAdmin(msg.sender);
        _expireTime = expireTime;
        emit TicketExpireTimeSet(expireTime);
    }
}
