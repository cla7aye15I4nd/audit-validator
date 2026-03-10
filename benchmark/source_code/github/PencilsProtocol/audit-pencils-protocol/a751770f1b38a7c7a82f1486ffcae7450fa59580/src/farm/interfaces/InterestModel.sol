// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

interface InterestModel {
    /// @dev Return the interest rate per second, using 1e18 as denom.
    function getInterestRate(uint256 debt, uint256 floating) external view returns (uint256);
}
