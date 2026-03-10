// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

interface IBlackListManager {
    /**
     * @dev Emitted when an account is blacklisted
     * @param account The account address
     * @param tier Tier of functionality to blacklist/whitelist
     */
    event BlackListed(address indexed account, uint8 tier);

    /**
     * @dev Check if an account is blacklisted
     * @param account The account address
     * @param functionSelector The function signature
     * @return True if the account is blacklisted
     */

    function isAllowed(address account, bytes4 functionSelector) external view returns (bool);

    /**
     * @dev Set the blacklisted status of an account
     * @param account The account address
     * @param tier The blacklisted status
     */
    function setBlackListed(address account, uint8 tier) external;
}
