// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title DynamicPayout
 * @dev A contract for managing dynamic payouts to multiple addresses. Inherits from OpenZeppelin's AccessControl
 * and allows for an Admin to grant/revoke wallets with access to the payout function.
 */
contract DynamicPayout is AccessControl {
    bytes32 public constant PAYER_ROLE = keccak256("contracts.roles.ContractPayerRole");

    /**
     * @dev Struct to hold payment details.
     * @param payee The address to which payment will be sent.
     * @param amount The amount of ether (in Wei) to be paid.
     */
    struct Payment {
        address payable payee;
        uint amount;
    }

    event PaymentSent(address indexed payee, uint amount);
    event PayoutCompleted(uint totalPayout);
    event RefundSent(address indexed sender, uint amount);

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAYER_ROLE, msg.sender);
    }

    /**
     * @dev Executes a batch payout to multiple addresses.
     * Requires that the total amount of the payments not exceed the value sent with the transaction.
     * Emits a PaymentSent event for each payment and a PayoutCompleted event after all payments are processed.
     * Any excess ether sent with the transaction is refunded to the contract msg.sender.
     * @param payments An array of Payment structs containing payee addresses and amounts.
     */
    function payout(Payment[] memory payments) external payable onlyRole(PAYER_ROLE) {
        uint totalPayout = 0;

        for (uint i = 0; i < payments.length; i++) {
            totalPayout += payments[i].amount;
        }

        require(msg.value >= totalPayout, "Insufficient funds for payout");

        for (uint i = 0; i < payments.length; i++) {
            payments[i].payee.transfer(payments[i].amount);
            emit PaymentSent(payments[i].payee, payments[i].amount);
        }

        emit PayoutCompleted(totalPayout);

        // Refund any excess amount to the msg.sender
        uint balanceAfterPayout = address(this).balance;
        if (balanceAfterPayout > 0) {
            payable(msg.sender).transfer(balanceAfterPayout);
            emit RefundSent(msg.sender, balanceAfterPayout);
        }
    }

    /**
     * @dev Allows an admin to grant the payer role to an address.
     * @param account The address to be granted the payer role.
     */
    function grantPayerRole(address account) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(PAYER_ROLE, account);
    }

    /**
     * @dev Allows an admin to revoke the payer role from an address.
     * @param account The address to be revoked the payer role.
     */
    function revokePayerRole(address account) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(PAYER_ROLE, account);
    }

    /**
     * @dev Transfers the admin role to a new account. Can only be called by an account with the admin role.
     * @param newAdmin The address to be granted the admin role.
     */
    function transferAdminRole(address newAdmin) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newAdmin != address(0), "New admin cannot be the zero address");

        // Grant the new admin the DEFAULT_ADMIN_ROLE
        _grantRole(DEFAULT_ADMIN_ROLE, newAdmin);

        // Revoke the DEFAULT_ADMIN_ROLE from the message sender
        _revokeRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }
}
