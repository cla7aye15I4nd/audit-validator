// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {IRegistry, IVestingConfigurator, BaseService, VESTING_CONFIGURATOR_ID} from "../Index.sol";

contract VestingConfigurator is IVestingConfigurator, BaseService {
    uint256 private _minimumClaimAmount = 0;

    constructor(IRegistry registry) BaseService(registry, VESTING_CONFIGURATOR_ID) {}

    /// @inheritdoc IVestingConfigurator
    function getMinimumClaimAmount() external view returns (uint256) {
        return _minimumClaimAmount;
    }

    /// @inheritdoc IVestingConfigurator
    function setMinimumClaimAmount(uint256 value) external {
        _registry.getACLManager().requireConfigurationAdmin(msg.sender);
        _minimumClaimAmount = value;
        emit MinimumClaimAmountChanged(value);
    }
}
