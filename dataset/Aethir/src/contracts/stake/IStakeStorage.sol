// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

interface IStakeStorage {
    struct StakeData {
        uint256 tid;
        uint256 gid;
        uint256 cid;
        uint256 amount;
        address delegator;
    }

    /// @notice standard stake
    /// @param tid the account tid
    /// @param gid the group id
    /// @param cids the container ids
    /// @param amounts the amounts to stake
    /// @param delegator the delegator address
    /// @return totalAmount amount staked
    function stake(
        uint256 tid,
        uint256 gid,
        uint256[] calldata cids,
        uint256[] calldata amounts,
        address delegator
    ) external returns (uint256 totalAmount);

    /// @notice standard unstake
    /// @param tid the account tid
    /// @param gid the group id
    /// @param cids the container ids
    /// @return totalAmount total amount unstaked
    /// @return amounts the array of amounts unstaked corresponding to cids
    function unstake(
        uint256 tid,
        uint256 gid,
        uint256[] calldata cids
    ) external returns (uint256 totalAmount, uint256[] memory amounts);

    /// @notice unstake a single container
    /// @param tid the account tid
    /// @param gid the group id
    /// @param cid the container id
    /// @return totalAmount total amount unstaked
    function unstakeSingleContainer(uint256 tid, uint256 gid, uint256 cid) external returns (uint256 totalAmount);

    /// @notice get stake data
    /// @param tid the account tid
    /// @param gid the group id
    /// @param cid the container id
    function getStakeData(uint256 tid, uint256 gid, uint256 cid) external view returns (StakeData memory);

    /// @notice check if the group is staked
    /// @param tid the account tid
    /// @param gid the group id
    function isStaked(uint256 tid, uint256 gid) external view returns (bool);
}
