// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

interface IMWXStaking {
    function rewardToken() external view returns (address);
}

contract RewardVault is Initializable, UUPSUpgradeable, AccessControlUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20Metadata;

    /**
     * @notice Staking contract
     */
    IMWXStaking public staking;

    /**
     * @notice Staking address set
     */
    event StakingAddressSet(address indexed stakingAddress);

    /**
     * @notice Unauthorized caller
     */
    error UnAuthorizedCaller();

    /**
     * @notice Invalid address
     */
    error InvalidAddress();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Receive function to receive native tokens
     */
    receive() external virtual payable {}

    /**
     * @dev Authorize upgrade
     * @param newImplementation New implementation address
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    /**
     * @dev Initialize the contract
     */
    /// @custom:oz-upgrades-validate-as-initializer
    function initialize() public initializer {
        __UUPSUpgradeable_init();
        __AccessControl_init();
        __ReentrancyGuard_init();

        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    /**
     * @dev Approve to staking contract
     */
    function approve() external virtual {
        if (!hasRole(DEFAULT_ADMIN_ROLE, _msgSender()) && address(staking) != _msgSender()) revert UnAuthorizedCaller();

        IERC20Metadata(staking.rewardToken()).approve(address(staking), type(uint256).max);
    }

    /**
     * @dev Set staking address
     * @param _staking Staking contract
     */
    function setStakingAddress(IMWXStaking _staking) external virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        if (address(_staking) == address(0)) revert InvalidAddress();
        
        staking = _staking;

        emit StakingAddressSet(address(_staking));
    }
}