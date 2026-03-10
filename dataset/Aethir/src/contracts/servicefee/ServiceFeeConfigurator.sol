// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {IRegistry, IServiceFeeConfigurator, BaseService, SERVICE_FEE_CONFIGURATOR_ID} from "../Index.sol";

/// @title ServiceFeeConfigurator
/// @notice Configures system parameters.
contract ServiceFeeConfigurator is IServiceFeeConfigurator, BaseService {
    uint16 private _commissionPercentage = 20; // 20%

    constructor(IRegistry registry) BaseService(registry, SERVICE_FEE_CONFIGURATOR_ID) {}

    /// @inheritdoc IServiceFeeConfigurator
    function getCommissionPercentage() external view override returns (uint16) {
        return _commissionPercentage;
    }

    /// @inheritdoc IServiceFeeConfigurator
    function setCommissionPercentage(uint16 commissionPercentage) external override {
        _registry.getACLManager().requireConfigurationAdmin(msg.sender);
        require(commissionPercentage <= 100, "Value exceeds maximum");
        _commissionPercentage = commissionPercentage;
        emit CommissionPercentageChanged(commissionPercentage);
    }
}
