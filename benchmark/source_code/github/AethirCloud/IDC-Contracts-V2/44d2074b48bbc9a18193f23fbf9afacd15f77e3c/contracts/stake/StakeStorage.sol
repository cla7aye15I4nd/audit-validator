// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {IRegistry, IStakeStorage, BaseService, STAKE_STORAGE_ID, STAKE_HANDLER_ID} from "../Index.sol";

contract StakeStorage is IStakeStorage, BaseService {
    mapping(uint256 tid => mapping(uint256 gid => mapping(uint256 cid => StakeData))) private _stakeData;
    mapping(uint256 tid => mapping(uint256 gid => bool)) private _groupStaked;

    mapping(uint256 cid => bool) private _staked;

    /// @notice Modifier to restrict access to the current Vesting Handler
    modifier onlyHandler() {
        require(_registry.getAddress(STAKE_HANDLER_ID) == msg.sender, "StakeStorage: handler only");
        _;
    }

    constructor(IRegistry registry) BaseService(registry, STAKE_STORAGE_ID) {}

    /// @inheritdoc IStakeStorage
    function stake(
        uint256 tid,
        uint256 gid,
        uint256[] calldata cids,
        uint256[] calldata amounts,
        address delegator
    ) external override onlyHandler returns (uint256 amount) {
        require(cids.length > 0, "StakeStorage: empty input");
        require(cids.length == amounts.length, "StakeStorage: invalid input");
        for (uint256 i = 0; i < cids.length; i++) {
            require(_stakeData[tid][gid][cids[i]].amount == 0, "StakeStorage: stake exists");
            require(amounts[i] > 0, "StakeStorage: invalid amount");
            require(_staked[cids[i]] == false, "StakeStorage: container staked");
            _staked[cids[i]] = true;
            amount += amounts[i];
            _stakeData[tid][gid][cids[i]] = StakeData(tid, gid, cids[i], amounts[i], delegator);
        }
        _groupStaked[tid][gid] = true;
    }

    /// @inheritdoc IStakeStorage
    function unstake(
        uint256 tid,
        uint256 gid,
        uint256[] calldata cids
    ) external override onlyHandler returns (uint256 totalAmount, uint256[] memory amounts) {
        require(cids.length > 0, "StakeStorage: empty input");
        amounts = new uint256[](cids.length);
        for (uint256 i = 0; i < cids.length; i++) {
            StakeData memory sd = _stakeData[tid][gid][cids[i]];
            require(sd.amount > 0, "StakeStorage: no stake");
            amounts[i] = sd.amount;
            totalAmount += sd.amount;
            delete _stakeData[tid][gid][cids[i]];
            _staked[cids[i]] = false;
        }
    }

    /// @inheritdoc IStakeStorage
    function unstakeSingleContainer(
        uint256 tid,
        uint256 gid,
        uint256 cid
    ) external override onlyHandler returns (uint256 amount) {
        StakeData memory sd = _stakeData[tid][gid][cid];
        require(sd.amount > 0, "StakeStorage: no stake");
        amount = sd.amount;
        delete _stakeData[tid][gid][cid];
        _staked[cid] = false;
    }

    /// @inheritdoc IStakeStorage
    function getStakeData(uint256 tid, uint256 gid, uint256 cid) external view override returns (StakeData memory) {
        return _stakeData[tid][gid][cid];
    }

    /// @inheritdoc IStakeStorage
    function isStaked(uint256 tid, uint256 gid) external view override returns (bool) {
        return _groupStaked[tid][gid];
    }
}
