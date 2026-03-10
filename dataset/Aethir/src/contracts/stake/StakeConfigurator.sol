// SPDX-License-Identifier: MIT

pragma solidity =0.8.27;

import {IRegistry, IStakeConfigurator, BaseService, STAKE_CONFIGURATOR_ID} from "../Index.sol";

contract StakeConfigurator is IStakeConfigurator, BaseService {
    uint16 private _restakingTransactionFeePercentage = 20; // 20%

    constructor(IRegistry registry) BaseService(registry, STAKE_CONFIGURATOR_ID) {}

    /// @inheritdoc IStakeConfigurator
    function getRestakingTransactionFeePercentage() external view override returns (uint16) {
        return _restakingTransactionFeePercentage;
    }

    /// @inheritdoc IStakeConfigurator
    function setRestakingTransactionFeePercentage(uint16 value) external {
        _registry.getACLManager().requireConfigurationAdmin(msg.sender);
        require(value <= 100, "Value exceeds maximum");
        _restakingTransactionFeePercentage = value;
        emit RestakingTransactionFeePercentageChanged(value);
    }
}
