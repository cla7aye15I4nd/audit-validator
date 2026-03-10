// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

interface ITierController {
    /**
     * @dev Emitted when the tier of a function is changed
     * @param functionSelector The function signature
     * @param newTier The new tier number of the function
     */
    event TierChanged(bytes4 functionSelector, uint8 newTier);

    /**
     * @dev Emitted when the default tier is changed
     * @param newTier The new default tier number
     */
    event DefaultTierChanged(uint8 newTier);

    /**
     * @dev Set the tier of a function
     * @param functionSelector The function signature
     * @param tier The tier number of the function
     */
    function setFunctionTier(bytes4 functionSelector, uint8 tier) external;
    /**
     * @dev Get the tier of a function
     * @param functionSelector The function signature
     * @return The tier of the function
     */
    function getTier(bytes4 functionSelector) external view returns (uint8);

    /**
     * @dev Set the default tier
     * @param tier The default tier number
     */
    function setDefaultTier(uint8 tier) external;

    /**
     * @dev Get the default tier
     * @return The default tier number
     */
    function getDefaultTier() external view returns (uint8);
}
