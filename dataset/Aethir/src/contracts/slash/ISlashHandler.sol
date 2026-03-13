// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {VestingRecord} from "../vesting/IVestingHandler.sol";

/// @title ISlashHandler
/// @notice Interface for the SlashHandler contract
interface ISlashHandler {
    /**
     * @notice Processes a new penalty and stores it in the SlashStorage contract.
     * @param tid tid;
     * @param gid gid;
     * @param amount The penalty amount in wei.
     * @param container The container of the penalty.
     */
    function createTicket(uint256 tid, uint256 gid, uint256 container, uint256 amount) external;

    /**
     * @notice transferring the penalty amount to the SlashDeductionReceiver.
     * @param tid tid;
     * @param gid gid;
     * @param container The container of the penalty.
     * @param caller The original sender of the function. Should be the host.
     */
    function settlePenalty(uint256 tid, uint256 gid, uint256 container, address caller) external returns (uint256);

    /**
     * @notice Cancels amount of penalty and removes it from the SlashStorage contract.
     * @param tid tid;
     * @param gid gid;
     * @param container The container of the penalty.
     * @param amount The penalty amount in wei.
     */
    function cancelPenalty(uint256 tid, uint256 gid, uint256 container, uint256 amount) external;

    /**
     * @notice Deducts the penalty amount from alternative balances (e.g., staked tokens or rewards).
     * @param tid tid;
     * @param gid gid;
     * @param container The container of the penalty.
     * @param fees The fees to deduct.
     * @param rewards The rewards to deduct.
     */
    function deductPenalty(
        uint256 tid,
        uint256 gid,
        uint256 container,
        VestingRecord calldata fees,
        VestingRecord calldata rewards
    ) external returns (uint256 amount, uint256 slashAmount);

    /**
     * @notice Refunds tenants to the GrantPool.
     * @param tids The list of tenant IDs to refund.
     * @param amounts The list of amounts to refund.
     */
    function refundTenants(uint256[] memory tids, uint256[] memory amounts) external returns (uint256);
}
