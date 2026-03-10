// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

interface IEmergencySwitch {
    /**
     * @dev Emitted when the tier is changed
     * @param newTier The new tier number
     */
    event TierChanged(uint8 newTier);

    /**
     * @dev Set the tier.
     * Default = 0 : No restrictions
     * @param tier The tier number
     */
    function pause(uint8 tier) external;

    /**
     * @dev Check if a function is allowed to be called, based on the tier.
     * If tier of function is less than current tier, it is allowed to be called
     * @param functionSelector The function signature
     * @return True if the function is allowed to be called
     */
    function isAllowed(bytes4 functionSelector) external view returns (bool);
}
