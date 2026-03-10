// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity =0.7.4;

interface IERC25 {
    function costOf(address _account, uint256 _amount) external view returns (uint256);

    function taxRate() external view returns (uint256);

    function equivalent() external view returns (address);

    function updateCost(
        address _account,
        uint256 _cost
    ) external returns (bool);
}
