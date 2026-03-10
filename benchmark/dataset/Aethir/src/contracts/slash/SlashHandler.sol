// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {
    IRegistry,
    ISlashHandler,
    ISlashStorage,
    ISlashConfigurator,
    IVestingHandler,
    ISlashDeductionReceiver,
    IStakeHandler,
    IStakeStorage,
    VestingRecord,
    IAccountStorage,
    BaseService,
    SLASH_HANDLER_ID,
    SLASH_DEDUCTION_RECEIVER_ID,
    SLASH_STORAGE_ID,
    SLASH_CONFIGURATOR_ID,
    TICKET_MANAGER_ID,
    VESTING_HANDLER_ID,
    ACCOUNT_STORAGE_ID,
    STAKE_HANDLER_ID,
    STAKE_STORAGE_ID,
    GRANT_POOL_ID
} from "../Index.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title SlashHandler
/// @notice Executes penalty logic.
contract SlashHandler is ISlashHandler, BaseService {
    using SafeERC20 for IERC20;

    /// @notice Modifier to restrict access to the current Slash Handler
    modifier onlyTicketManager() {
        require(_registry.getAddress(TICKET_MANAGER_ID) == msg.sender, "SlashHandler: TicketManager only");
        _;
    }

    constructor(IRegistry registry) BaseService(registry, SLASH_HANDLER_ID) {}

    /// @notice Deducts penalty from the ticket.
    function createTicket(
        uint256 tid,
        uint256 gid,
        uint256 container,
        uint256 amount
    ) external override onlyTicketManager {
        require(amount > 0, "Invalid amount");
        _slashStorage().increaseTicket(tid, gid, container, amount);
    }

    /// @notice Deducts penalty from the ticket.
    function settlePenalty(
        uint256 tid,
        uint256 gid,
        uint256 container,
        address caller
    ) external override onlyTicketManager returns (uint256) {
        ISlashStorage.Penalty memory penalty = _slashStorage().getTicket(tid, gid, container);
        require(penalty.amount > 0, "Invalid amount");
        address host = _accountStorage().getWallet(tid);
        require(host == caller, "Invalid sender");
        require(host != address(0), "Invalid tid");
        _registry.getATHToken().safeTransferFrom(
            host,
            _registry.getAddress(SLASH_DEDUCTION_RECEIVER_ID),
            penalty.amount
        );

        _slashStorage().decreaseTicket(tid, gid, container, penalty.amount);

        return penalty.amount;
    }

    /// @notice Deducts penalty from the ticket.
    function cancelPenalty(
        uint256 tid,
        uint256 gid,
        uint256 container,
        uint256 amount
    ) external override onlyTicketManager {
        ISlashStorage.Penalty memory penalty = _slashStorage().getTicket(tid, gid, container);
        require(penalty.amount >= amount, "Invalid amount");

        _slashStorage().decreaseTicket(tid, gid, container, amount);
    }

    /// @notice Deducts penalty from the ticket.
    function deductPenalty(
        uint256 tid,
        uint256 gid,
        uint256 container,
        VestingRecord calldata fees,
        VestingRecord calldata rewards
    ) external override onlyTicketManager returns (uint256 amount, uint256 stakedAmount) {
        ISlashStorage.Penalty memory penalty = _slashStorage().getTicket(tid, gid, container);
        require(penalty.amount > 0, "Invalid amount");
        require(penalty.ts + _configurator().getTicketExpireTime() < block.timestamp, "Ticket is not expired");

        amount = 0;
        stakedAmount = 0;

        for (uint256 i = 0; i < fees.amounts.length; i++) {
            amount += fees.amounts[i];
        }
        for (uint256 i = 0; i < rewards.amounts.length; i++) {
            amount += rewards.amounts[i];
        }

        require(amount > 0, "Invalid amount");
        require(amount <= penalty.amount, "Deduction exceeds ticket amount");

        stakedAmount = penalty.amount - amount;

        uint256 stakedToken = _stakeStorage().getStakeData(tid, gid, container).amount;
        stakedAmount = stakedToken < stakedAmount ? stakedToken : stakedAmount;

        _vestingHandler().settleSlash(tid, gid, fees, rewards);
        _slashStorage().decreaseTicket(tid, gid, container, amount + stakedAmount);

        if (stakedAmount > 0) {
            _stakeHandler().deductStaked(tid, gid, container, stakedAmount);
        }

        return (amount, stakedAmount);
    }

    /// @notice Refunds tenants for a penalty.
    function refundTenants(
        uint256[] memory tids,
        uint256[] memory amounts
    ) external override onlyTicketManager returns (uint256 totalAmount) {
        require(tids.length > 0, "Empty input");
        require(tids.length == amounts.length, "Invalid length");
        totalAmount = 0;

        for (uint256 i = 0; i < tids.length; i++) {
            require(amounts[i] > 0, "Invalid amount");
            totalAmount += amounts[i];
        }

        _deductionReceiver().sendSlashToken(_registry.getAddress(GRANT_POOL_ID), totalAmount);
    }

    /// @notice Returns the slash deduction receiver contract.
    function _deductionReceiver() internal view returns (ISlashDeductionReceiver) {
        return ISlashDeductionReceiver(_registry.getAddress(SLASH_DEDUCTION_RECEIVER_ID));
    }

    /// @notice Returns the slash handler contract.
    function _slashStorage() internal view returns (ISlashStorage) {
        return ISlashStorage(_registry.getAddress(SLASH_STORAGE_ID));
    }

    /// @notice Returns the slash configurator contract.
    function _configurator() internal view returns (ISlashConfigurator) {
        return ISlashConfigurator(_registry.getAddress(SLASH_CONFIGURATOR_ID));
    }

    /// @notice Returns the vesting handler contract.
    function _vestingHandler() internal view returns (IVestingHandler) {
        return IVestingHandler(_registry.getAddress(VESTING_HANDLER_ID));
    }

    function _accountStorage() internal view returns (IAccountStorage) {
        return IAccountStorage(_registry.getAddress(ACCOUNT_STORAGE_ID));
    }

    function _stakeHandler() internal view returns (IStakeHandler) {
        return IStakeHandler(_registry.getAddress(STAKE_HANDLER_ID));
    }

    function _stakeStorage() internal view returns (IStakeStorage) {
        return IStakeStorage(_registry.getAddress(STAKE_STORAGE_ID));
    }
}
