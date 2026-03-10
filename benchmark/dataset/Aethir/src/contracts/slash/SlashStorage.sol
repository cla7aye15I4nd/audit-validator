// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {IRegistry, ISlashStorage, BaseService, SLASH_STORAGE_ID, SLASH_HANDLER_ID} from "../Index.sol";

/// @title SlashStorage
/// @notice Stores penalty records.
contract SlashStorage is ISlashStorage, BaseService {
    mapping(uint256 tid => mapping(uint256 gid => mapping(uint256 container => Penalty))) private _penalties;
    mapping(uint256 tid => uint256 totalAmount) private _totalAmounts;

    /// @notice Modifier to restrict access to the current Slash Handler
    modifier onlyHandler() {
        require(_registry.getAddress(SLASH_HANDLER_ID) == msg.sender, "SlashStorage: handler only");
        _;
    }

    constructor(IRegistry registry) BaseService(registry, SLASH_STORAGE_ID) {}

    /// @inheritdoc ISlashStorage
    function increaseTicket(uint256 tid, uint256 gid, uint256 container, uint256 amount) external override onlyHandler {
        require(amount > 0, "Invalid amount");
        Penalty storage penalty = _penalties[tid][gid][container];
        if (penalty.amount == 0) {
            penalty.ts = block.timestamp;
        }
        penalty.amount += amount;
        _totalAmounts[tid] += amount;
    }

    /// @inheritdoc ISlashStorage
    function decreaseTicket(uint256 tid, uint256 gid, uint256 container, uint256 amount) external override onlyHandler {
        require(amount > 0, "Invalid amount");
        Penalty storage penalty = _penalties[tid][gid][container];
        penalty.amount -= amount;
        _totalAmounts[tid] -= amount;
    }

    /// @inheritdoc ISlashStorage
    function deleteTicket(uint256 tid, uint256 gid, uint256 container) external override onlyHandler {
        _totalAmounts[tid] -= _penalties[tid][gid][container].amount;
        delete _penalties[tid][gid][container];
    }

    /// @inheritdoc ISlashStorage
    function getTicket(uint256 tid, uint256 gid, uint256 container) external view override returns (Penalty memory) {
        return _penalties[tid][gid][container];
    }

    /// @inheritdoc ISlashStorage
    function totalPenalty(uint256 tid) external view override returns (uint256) {
        return _totalAmounts[tid];
    }
}
