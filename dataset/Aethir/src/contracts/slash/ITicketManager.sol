// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {IRequestVerifier} from "../base/IRequestVerifier.sol";

/// @title ITicketManager
/// @notice Interface for the TicketManager contract.
interface ITicketManager {
    event TicketCreated(uint256 tid, uint256 gid, uint256 container, uint256 amount, uint64 nonce, bytes32 vdata);
    event TicketSettled(uint256 tid, uint256 gid, uint256 container, uint256 amount, uint64 nonce, bytes32 vdata);
    event TicketDeducted(
        uint256 tid,
        uint256 gid,
        uint256 container,
        uint256 amount,
        uint256 stakedAmount,
        uint64 nonce,
        bytes32 vdata
    );
    event TicketCancelled(uint256 tid, uint256 gid, uint256 container, uint256 amount, uint64 nonce, bytes32 vdata);
    event TenantRefunded(uint256[] tid, uint256[] amounts, uint256 totalAmount, uint64 nonce, bytes32 vdata);

    /**
     * @notice Creates a new ticket for a penalty.
     */
    function addPenalty(IRequestVerifier.VerifiableData calldata vdata) external;

    /**
     * @notice Settles a penalty by transferring the penalty amount from the host
     */
    function settlePenalty(IRequestVerifier.VerifiableData calldata vdata) external;

    /**
     * @notice Deducts a penalty from the host's balance.
     */

    function deductPenalty(IRequestVerifier.VerifiableData calldata vdata) external;

    /**
     * @notice Cancels a ticket, removing it from storage.
     */
    function cancelPenalty(IRequestVerifier.VerifiableData calldata vdata) external;

    /**
     * @notice Refunds tenants to the GrantPool.
     */
    function refundTenants(IRequestVerifier.VerifiableData calldata vdata) external;
}
