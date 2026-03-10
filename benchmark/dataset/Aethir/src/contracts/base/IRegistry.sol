// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {IACLManager} from "./IACLManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IRegistry
 * @notice Defines the basic interface for the Service Registry
 */
interface IRegistry {
    /// @notice emitted when the registry is initialized
    event Initialized();

    /// @notice emitted when the registry is set up
    event SetUp(bytes4[] service, address[] impl);

    /// @notice emitted when a new service is registered
    event SetAddress(bytes4 service, address impl);

    /// @notice emitted when the system version is updated
    event SetVersion(uint64 value);

    /// @notice returns the ACL Manager
    function getACLManager() external view returns (IACLManager);

    /// @notice returns the ATH token
    function getATHToken() external view returns (IERC20);

    /// @notice get current implementation address for a service
    /// @param service the service typeid
    /// @return the address of the implementation
    function getAddress(bytes4 service) external view returns (address);

    /// @notice register the caller as a new service
    /// @param service the service typeid
    function register(bytes4 service) external;

    /// @notice set new implementation address for a service
    /// @param service the service typeid
    /// @param impl the address of the implementation
    function setAddress(bytes4 service, address impl) external;

    /// @notice returns the current system version
    function getVersion() external view returns (uint64);

    /// @notice registers new system version
    /// @param value: new version
    function setVersion(uint64 value) external;
}
