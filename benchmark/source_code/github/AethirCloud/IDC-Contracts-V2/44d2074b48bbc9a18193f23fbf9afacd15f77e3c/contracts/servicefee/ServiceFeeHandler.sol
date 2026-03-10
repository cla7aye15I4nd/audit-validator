// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {
    IRegistry,
    IRequestVerifier,
    IAccountStorage,
    IServiceFeeHandler,
    IServiceFeeStorage,
    IServiceFeeFundHolder,
    IGrantPool,
    IVestingHandler,
    VestingType,
    VestingRecord,
    IServiceFeeConfigurator,
    BaseService,
    ACCOUNT_STORAGE_ID,
    VESTING_HANDLER_ID,
    SERVICE_FEE_STORAGE_ID,
    SERVICE_FEE_HANDLER_ID,
    SERVICE_FEE_FUND_HOLDER_ID,
    SERVICE_FEE_CONFIGURATOR_ID,
    GRANT_POOL_ID
} from "../Index.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract ServiceFeeHandler is IServiceFeeHandler, BaseService {
    using SafeERC20 for IERC20;

    constructor(IRegistry registry) BaseService(registry, SERVICE_FEE_HANDLER_ID) {}

    /// @inheritdoc IServiceFeeHandler
    function depositServiceFee(uint256 tid, uint256 amount) external override {
        _verifier().checkRisk(this.depositServiceFee.selector, msg.sender);
        require(amount > 0, "Invalid amount");
        address host = _accountStorage().getWallet(tid);
        require(host != address(0), "Invalid tid");
        require(host == msg.sender, "Host only");
        _storage().increaseDepositedAmount(tid, amount);
        _registry.getATHToken().safeTransferFrom(msg.sender, address(_fundHolder()), amount);
        emit ServiceFeeDeposited(msg.sender, tid, amount);
    }

    /// @inheritdoc IServiceFeeHandler
    function withdrawServiceFee(uint256 tid, uint256 amount) external override {
        _verifier().checkRisk(this.withdrawServiceFee.selector, msg.sender);
        require(amount > 0, "Invalid amount");
        address host = _accountStorage().getWallet(tid);
        require(host != address(0), "Invalid tid");
        require(host == msg.sender, "Host only");
        _storage().decreaseDepositedAmount(tid, amount);
        _fundHolder().sendServiceFeeToken(host, amount);
        emit ServiceFeeWithdrawn(msg.sender, tid, amount);
    }

    /// @inheritdoc IServiceFeeHandler
    function lockServiceFee(IRequestVerifier.VerifiableData calldata vdata) external override {
        bytes32 vhash = _verifier().verify(vdata, msg.sender, this.lockServiceFee.selector);
        (uint256[] memory tids, uint256[] memory amounts) = abi.decode(vdata.params, (uint256[], uint256[]));
        require(tids.length > 0, "Empty input");
        require(tids.length == amounts.length, "Invalid input length");
        _storage().decreaseDepositedAmounts(tids, amounts);
        _storage().increaseLockedAmounts(tids, amounts);
        emit ServiceFeeLocked(tids, amounts, vdata.nonce, vhash);
    }

    /// @inheritdoc IServiceFeeHandler
    function unlockServiceFee(IRequestVerifier.VerifiableData calldata vdata) external override {
        bytes32 vhash = _verifier().verify(vdata, msg.sender, this.unlockServiceFee.selector);
        (uint256[] memory tids, uint256[] memory amounts) = abi.decode(vdata.params, (uint256[], uint256[]));
        require(tids.length > 0, "Empty input");
        require(tids.length == amounts.length, "Invalid input length");
        _storage().decreaseLockedAmounts(tids, amounts);
        _storage().increaseDepositedAmounts(tids, amounts);
        emit ServiceFeeUnlocked(tids, amounts, vdata.nonce, vhash);
    }

    /// @inheritdoc IServiceFeeHandler
    function settleServiceFee(IRequestVerifier.VerifiableData calldata vdata) external override {
        bytes32 vhash = _verifier().verify(vdata, msg.sender, this.settleServiceFee.selector);

        ServiceFeeSettleParams memory params = abi.decode(vdata.params, (ServiceFeeSettleParams));
        _processSettleServiceFee(params);
        emit ServiceFeeSettled(params, vdata.nonce, vhash);
    }

    /// @inheritdoc IServiceFeeHandler
    function initialSettleServiceFee(IRequestVerifier.VerifiableData calldata vdata) external override {
        bytes32 vhash = _verifier().verifyInitiator(vdata, this.initialSettleServiceFee.selector);
        (uint256[] memory tids, uint256[] memory gids, VestingRecord[] memory records) = abi.decode(
            vdata.params,
            (uint256[], uint256[], VestingRecord[])
        );

        require(tids.length > 0, "Empty input");
        require(tids.length == gids.length && gids.length == records.length, "Invalid input length");

        for (uint256 i = 0; i < tids.length; i++) {
            _vestingHandler().initialVesting(VestingType.ServiceFee, tids[i], gids[i], records[i]);
        }
        emit ServiceFeeInitialSettled(tids, gids, records, vdata.nonce, vhash);
    }

    /// @inheritdoc IServiceFeeHandler
    function initialTenantsServiceFee(IRequestVerifier.VerifiableData calldata vdata) external override {
        bytes32 vhash = _verifier().verifyInitiator(vdata, this.initialTenantsServiceFee.selector);
        (uint256[] memory tids, uint256[] memory amounts) = abi.decode(vdata.params, (uint256[], uint256[]));
        require(tids.length > 0, "Empty input");
        require(tids.length == amounts.length, "Invalid input length");
        _storage().increaseDepositedAmounts(tids, amounts);
        emit ServiceFeeInitialDeposited(tids, amounts, vdata.nonce, vhash);
    }

    function _processSettleServiceFee(ServiceFeeSettleParams memory params) private {
        require(params.tenants.length == params.tenantAmounts.length, "Invalid tenant amount length");
        require(params.hosts.length == params.groups.length, "Invalid group length");
        require(params.hosts.length == params.hostGroupAmounts.length, "Invalid host group amount length");

        // Verifies the total deductions and the total increments are equal
        uint256 totalDeductions = params.grantAmount;
        for (uint256 i = 0; i < params.tenantAmounts.length; i++) {
            totalDeductions += params.tenantAmounts[i];
        }
        uint256 totalIncrements = params.slashAmount;
        for (uint256 i = 0; i < params.hostGroupAmounts.length; i++) {
            totalIncrements += params.hostGroupAmounts[i];
        }
        require(totalDeductions == totalIncrements, "Total deductions != increments");

        // Deducts the service fee from the tenants and the grant pool
        _storage().decreaseLockedAmounts(params.tenants, params.tenantAmounts);
        if (params.grantAmount > 0) {
            _grantPool().spendGrantFund(params.grantAmount);
        }

        // Distributes the service fee to the service fee receiver, the commission receiver, and the vesting fund holder
        uint16 commissionPercentage = _config().getCommissionPercentage();
        uint256 commissionAmount = (totalDeductions * commissionPercentage) / 100;
        uint256 netSlashAmount = (params.slashAmount * (100 - commissionPercentage)) / 100;
        uint256 receiverAmount = totalDeductions - commissionAmount - netSlashAmount;

        if (netSlashAmount > 0) {
            _fundHolder().sendSlashedToken(netSlashAmount);
        }
        if (commissionAmount > 0) {
            _fundHolder().sendCommissionToken(commissionAmount);
        }
        if (receiverAmount > 0) {
            _fundHolder().sendVestingToken(receiverAmount);
        }

        // Create vesting record
        IVestingHandler vestingHandler = _vestingHandler();
        for (uint256 i = 0; i < params.hostGroupAmounts.length; i++) {
            vestingHandler.createVesting(
                VestingType.ServiceFee,
                params.hosts[i],
                params.groups[i],
                (params.hostGroupAmounts[i] * (100 - commissionPercentage)) / 100
            );
        }
    }

    /// @notice Returns the service fee storage contract.
    function _storage() private view returns (IServiceFeeStorage) {
        return IServiceFeeStorage(_registry.getAddress(SERVICE_FEE_STORAGE_ID));
    }

    /// @notice returns the address of the fund holder
    function _fundHolder() private view returns (IServiceFeeFundHolder) {
        return IServiceFeeFundHolder(_registry.getAddress(SERVICE_FEE_FUND_HOLDER_ID));
    }

    /// @notice Returns the account handler contract.
    function _accountStorage() private view returns (IAccountStorage) {
        return IAccountStorage(_registry.getAddress(ACCOUNT_STORAGE_ID));
    }

    /// @notice Returns the vesting handler contract.
    function _vestingHandler() private view returns (IVestingHandler) {
        return IVestingHandler(_registry.getAddress(VESTING_HANDLER_ID));
    }

    /// @notice Returns the service fee configurator contract.
    function _config() private view returns (IServiceFeeConfigurator) {
        return IServiceFeeConfigurator(_registry.getAddress(SERVICE_FEE_CONFIGURATOR_ID));
    }

    /// @notice Returns the grant pool contract.
    function _grantPool() private view returns (IGrantPool) {
        return IGrantPool(_registry.getAddress(GRANT_POOL_ID));
    }
}
