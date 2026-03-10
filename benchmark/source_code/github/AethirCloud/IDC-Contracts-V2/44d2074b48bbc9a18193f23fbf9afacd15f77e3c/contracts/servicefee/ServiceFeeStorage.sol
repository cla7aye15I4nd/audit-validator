// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {IRegistry, IServiceFeeStorage, BaseService, SERVICE_FEE_STORAGE_ID, SERVICE_FEE_HANDLER_ID} from "../Index.sol";

/// @title ServiceFeeStorage
contract ServiceFeeStorage is IServiceFeeStorage, BaseService {
    mapping(uint256 => uint256) private _depositedAmounts;
    mapping(uint256 => uint256) private _lockedAmounts;

    /// @notice Modifier to restrict access to the current handler
    modifier onlyHandler() {
        require(_registry.getAddress(SERVICE_FEE_HANDLER_ID) == msg.sender, "ServiceFeeHandler only");
        _;
    }

    constructor(IRegistry registry) BaseService(registry, SERVICE_FEE_STORAGE_ID) {}

    function getDepositedAmount(uint256 tid) external view returns (uint256) {
        return _depositedAmounts[tid];
    }

    function getLockedAmount(uint256 tid) external view returns (uint256) {
        return _lockedAmounts[tid];
    }

    function increaseDepositedAmount(uint256 tid, uint256 amount) external override onlyHandler {
        _depositedAmounts[tid] += amount;
    }

    function increaseDepositedAmounts(
        uint256[] calldata tids,
        uint256[] calldata amounts
    ) external override onlyHandler {
        require(tids.length == amounts.length, "Invalid input length");
        for (uint256 i = 0; i < tids.length; i++) {
            require(amounts[i] > 0, "Invalid amount");
            _depositedAmounts[tids[i]] += amounts[i];
        }
    }

    function decreaseDepositedAmount(uint256 tid, uint256 amount) external override onlyHandler {
        _depositedAmounts[tid] -= amount;
    }

    function decreaseDepositedAmounts(
        uint256[] calldata tids,
        uint256[] calldata amounts
    ) external override onlyHandler {
        require(tids.length == amounts.length, "Invalid input length");
        for (uint256 i = 0; i < tids.length; i++) {
            require(amounts[i] > 0, "Invalid amount");
            _depositedAmounts[tids[i]] -= amounts[i];
        }
    }

    function increaseLockedAmount(uint256 tid, uint256 amount) external override onlyHandler {
        _lockedAmounts[tid] += amount;
    }

    function increaseLockedAmounts(uint256[] calldata tids, uint256[] calldata amounts) external override onlyHandler {
        require(tids.length == amounts.length, "Invalid input length");
        for (uint256 i = 0; i < tids.length; i++) {
            require(amounts[i] > 0, "Invalid amount");
            _lockedAmounts[tids[i]] += amounts[i];
        }
    }

    function decreaseLockedAmount(uint256 tid, uint256 amount) external override onlyHandler {
        require(amount > 0, "Invalid amount");
        _lockedAmounts[tid] -= amount;
    }

    function decreaseLockedAmounts(uint256[] calldata tids, uint256[] calldata amounts) external override onlyHandler {
        require(tids.length == amounts.length, "Invalid input length");
        for (uint256 i = 0; i < tids.length; i++) {
            require(amounts[i] > 0, "Invalid amount");
            _lockedAmounts[tids[i]] -= amounts[i];
        }
    }
}
