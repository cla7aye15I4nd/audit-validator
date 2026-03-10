// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IConfigImpl {
    // dependency
    function baseToken() external view returns (address);
    function usda() external view returns (address);
    function vnome() external view returns (address);
    function wkToken() external view returns (address);
    function game() external view returns (address);
    function weth() external view returns (address);
    function shop() external view returns (address);
    function alloc() external view returns (address);
    function box() external view returns (address);
    function boxCert() external view returns (address);
    function uniV2Router() external view returns (address);
    function ogNFT() external view returns (address);

    // accounts
    function caller() external view returns (address);
    function treasury() external view returns (address);
    function usdaAnchorHolder() external view returns (address);
    function defaultSponsor() external view returns (address);
    function buyCardPayee() external view returns (address);
    function cardDefaultIPPayee() external view returns (address);
    function cardDestroyPayee() external view returns (address);

    // 亏损挖矿
    function bnome() external view returns (address);
    function anomeDexRouter() external view returns (address);
}
