// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {
    IRegistry,
    ITicketManager,
    IRequestVerifier,
    ISlashHandler,
    VestingRecord,
    BaseService,
    TICKET_MANAGER_ID,
    SLASH_HANDLER_ID
} from "../Index.sol";

/// @title TicketManager
/// @notice Manages the creation and tracking of tickets for penalties.
contract TicketManager is ITicketManager, BaseService {
    constructor(IRegistry registry) BaseService(registry, TICKET_MANAGER_ID) {}

    /// @inheritdoc ITicketManager
    function addPenalty(IRequestVerifier.VerifiableData calldata vdata) external override {
        bytes32 vhash = _verifier().verify(vdata, msg.sender, this.addPenalty.selector);
        (uint256 tid, uint256 gid, uint256 amount, uint256 container) = abi.decode(
            vdata.params,
            (uint256, uint256, uint256, uint256)
        );

        _slashHandler().createTicket(tid, gid, container, amount);
        emit TicketCreated(tid, gid, container, amount, vdata.nonce, vhash);
    }

    /// @inheritdoc ITicketManager
    // pay penalty
    function settlePenalty(IRequestVerifier.VerifiableData calldata vdata) external override {
        bytes32 vhash = _verifier().verify(vdata, msg.sender, this.settlePenalty.selector);
        (uint256 tid, uint256 gid, uint256 container) = abi.decode(vdata.params, (uint256, uint256, uint256));

        uint256 amount = _slashHandler().settlePenalty(tid, gid, container, msg.sender);
        emit TicketSettled(tid, gid, container, amount, vdata.nonce, vhash);
    }

    /// @inheritdoc ITicketManager
    function deductPenalty(IRequestVerifier.VerifiableData calldata vdata) external override {
        bytes32 vhash = _verifier().verify(vdata, msg.sender, this.deductPenalty.selector);
        (uint256 tid, uint256 gid, uint256 container, VestingRecord memory fees, VestingRecord memory rewards) = abi
            .decode(vdata.params, (uint256, uint256, uint256, VestingRecord, VestingRecord));

        (uint256 amount, uint256 stakedAmount) = _slashHandler().deductPenalty(tid, gid, container, fees, rewards);
        emit TicketDeducted(tid, gid, container, amount, stakedAmount, vdata.nonce, vhash);
    }

    /// @inheritdoc ITicketManager
    function cancelPenalty(IRequestVerifier.VerifiableData calldata vdata) external override {
        bytes32 vhash = _verifier().verify(vdata, msg.sender, this.cancelPenalty.selector);
        (uint256 tid, uint256 gid, uint256 container, uint256 amount) = abi.decode(
            vdata.params,
            (uint256, uint256, uint256, uint256)
        );

        _slashHandler().cancelPenalty(tid, gid, container, amount);
        emit TicketCancelled(tid, gid, container, amount, vdata.nonce, vhash);
    }

    /// @inheritdoc ITicketManager
    function refundTenants(IRequestVerifier.VerifiableData calldata vdata) external override {
        bytes32 vhash = _verifier().verify(vdata, msg.sender, this.refundTenants.selector);
        (uint256[] memory tids, uint256[] memory amounts) = abi.decode(vdata.params, (uint256[], uint256[]));

        uint256 totalAmount = _slashHandler().refundTenants(tids, amounts);

        emit TenantRefunded(tids, amounts, totalAmount, vdata.nonce, vhash);
    }

    /// @notice Returns the slash handler contract.
    function _slashHandler() private view returns (ISlashHandler) {
        return ISlashHandler(_registry.getAddress(SLASH_HANDLER_ID));
    }
}
