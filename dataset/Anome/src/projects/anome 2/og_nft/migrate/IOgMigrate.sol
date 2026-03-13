// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IOgMigrate {
    function migrate01(address config, address shop) external;
}