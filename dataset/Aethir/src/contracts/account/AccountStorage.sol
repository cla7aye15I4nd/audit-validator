// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {
    IRegistry,
    IAccountHandler,
    IAccountStorage,
    BaseService,
    ACCOUNT_HANDLER_ID,
    ACCOUNT_STORAGE_ID
} from "../Index.sol";

contract AccountStorage is IAccountStorage, BaseService {
    mapping(address wallet => uint256 tid) private _wallet2tid;
    mapping(uint256 tid => address wallet) private _tid2wallet;
    mapping(uint256 tid => mapping(uint256 gid => IAccountHandler.Group)) private _groups;

    /// @notice Modifier to restrict access to the current Vesting Handler
    modifier onlyHandler() {
        require(_registry.getAddress(ACCOUNT_HANDLER_ID) == msg.sender, "AccountStorage: handler only");
        _;
    }

    constructor(IRegistry registry) BaseService(registry, ACCOUNT_STORAGE_ID) {}

    /// @inheritdoc IAccountStorage
    function bindWallet(uint256 tid, address wallet) external override onlyHandler {
        require(wallet != address(0), "Invalid wallet address");
        require(_wallet2tid[wallet] == 0, "Wallet already bound");
        if (_tid2wallet[tid] != address(0)) {
            delete _wallet2tid[_tid2wallet[tid]];
        }
        _wallet2tid[wallet] = tid;
        _tid2wallet[tid] = wallet;
    }

    /// @inheritdoc IAccountStorage
    function getWallet(uint256 tid) external view override returns (address wallet) {
        wallet = _tid2wallet[tid];
    }

    /// @inheritdoc IAccountStorage
    function getTid(address wallet) external view override returns (uint256 tid) {
        tid = _wallet2tid[wallet];
    }

    /// @inheritdoc IAccountStorage
    function setGroup(IAccountHandler.Group memory group) external override onlyHandler {
        _groups[group.tid][group.gid] = group;
    }

    /// @inheritdoc IAccountStorage
    function getGroup(uint256 tid, uint256 gid) external view override returns (IAccountHandler.Group memory group) {
        group = _groups[tid][gid];
        require(group.tid == tid && group.gid == gid, "Group not found");
    }

    /// @inheritdoc IAccountStorage
    function isGroupExist(uint256 tid, uint256 gid) external view override returns (bool) {
        return _groups[tid][gid].tid == tid && _groups[tid][gid].gid == gid;
    }
}
