// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {IRegistry} from "./IRegistry.sol";
import {IACLManager} from "./IACLManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Registry is IRegistry {
    mapping(bytes4 service => address impl) private _impls;
    IACLManager private immutable _aclManager;
    IERC20 private immutable _athToken;

    address private _deployer;
    uint64 private _version = 0;

    modifier onlyInitializing() {
        require(_version == 0, "Registry: initialized");
        _;
    }

    constructor(IACLManager aclManager, IERC20 athToken) {
        _deployer = msg.sender;
        _aclManager = aclManager;
        _athToken = athToken;
    }

    /// @notice Initialize the registry with the given services and implementations
    /// @param services the list of service typeids
    /// @param impls the list of implementation addresses
    function initialize(bytes4[] memory services, address[] memory impls) public onlyInitializing {
        initSetup(services, impls);
        _version = 1;
        _deployer = address(0);
        emit Initialized();
    }

    /// @notice Initialize the registry with the given services and implementations
    /// @param services the list of service typeids
    /// @param impls the list of implementation addresses
    /// @dev only use this function if service list is too long for a single call,
    /// otherwise use `initialize`. This function is only callable by the deployer
    function initSetup(bytes4[] memory services, address[] memory impls) public onlyInitializing {
        require(_deployer == msg.sender, "Registry: not deployer");
        require(services.length == impls.length, "Registry: input length mismatch");
        for (uint256 i = 0; i < services.length; i++) {
            _impls[services[i]] = impls[i];
        }

        emit SetUp(services, impls);
    }

    /// @inheritdoc IRegistry
    function getACLManager() external view override returns (IACLManager) {
        return _aclManager;
    }

    /// @inheritdoc IRegistry
    function getATHToken() external view override returns (IERC20) {
        return _athToken;
    }

    /// @inheritdoc IRegistry
    function getAddress(bytes4 service) external view override returns (address) {
        return _impls[service];
    }

    /// @inheritdoc IRegistry
    /// @dev only contract deployed by deployer can self-register during initialization
    function register(bytes4 service) external override onlyInitializing {
        // solhint-disable-next-line avoid-tx-origin
        require(_deployer == tx.origin, "Registry: not deployer");
        require(_impls[service] == address(0), "Registry: service exists");
        _impls[service] = msg.sender;
        emit SetAddress(service, msg.sender);
    }

    /// @inheritdoc IRegistry
    /// @dev only migrator can set new implementation addresses
    function setAddress(bytes4 service, address impl) external override {
        _aclManager.requireMigrator(msg.sender);
        _impls[service] = impl;
        emit SetAddress(service, impl);
    }

    /// @inheritdoc IRegistry
    function getVersion() external view override returns (uint64) {
        return _version;
    }

    /// @inheritdoc IRegistry
    function setVersion(uint64 value) external override {
        require(value != 0, "Registry: invalid version");
        _aclManager.requireMigrator(msg.sender);
        _version = value;
        emit SetVersion(value);
    }
}
