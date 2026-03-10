// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {IRegistry, IUserStorage, BaseService, REQUEST_VERIFIER_ID, USER_STORAGE_ID} from "../Index.sol";

/// @title UserStorage
/// @notice A contract to store user data
contract UserStorage is IUserStorage, BaseService {
    mapping(address account => UserData data) private _users;

    /// @notice Modifier to restrict access to the current Request Verifier
    modifier onlyVerifier() {
        require(_registry.getAddress(REQUEST_VERIFIER_ID) == msg.sender, "UserStorage: verifier only");
        _;
    }

    constructor(IRegistry registry) BaseService(registry, USER_STORAGE_ID) {}

    /// @inheritdoc IUserStorage
    function getUserData(address account) external view returns (UserData memory) {
        return _users[account];
    }

    /// @inheritdoc IUserStorage
    function setUserData(address account, UserData memory data) external onlyVerifier {
        _users[account] = data;
    }
}
