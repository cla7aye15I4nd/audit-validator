// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ConfigStorage} from "../ConfigStorage.sol";

import {IConfigImpl} from "./IConfigImpl.sol";

contract ConfigImpl is IConfigImpl {
    function baseToken() external view returns (address) {
        return ConfigStorage.layout().baseToken;
    }

    function usda() external view returns (address) {
        return ConfigStorage.layout().usda;
    }

    function vnome() external view returns (address) {
        return ConfigStorage.layout().vnome;
    }

    function wkToken() external view returns (address) {
        return ConfigStorage.layout().wkToken;
    }

    function game() external view returns (address) {
        return ConfigStorage.layout().game;
    }

    function weth() external view returns (address) {
        return ConfigStorage.layout().weth;
    }

    function shop() external view returns (address) {
        return ConfigStorage.layout().shop;
    }

    function alloc() external view returns (address) {
        return ConfigStorage.layout().alloc;
    }

    function box() external view returns (address) {
        return ConfigStorage.layout().box;
    }

    function boxCert() external view returns (address) {
        return ConfigStorage.layout().boxCert;
    }

    function uniV2Router() external view returns (address) {
        return ConfigStorage.layout().uniV2Router;
    }

    function ogNFT() external view returns (address) {
        return ConfigStorage.layout().ogNft;
    }

    function caller() external view returns (address) {
        return ConfigStorage.layout().caller;
    }

    function treasury() external view returns (address) {
        return ConfigStorage.layout().treasury;
    }

    function usdaAnchorHolder() external view returns (address) {
        return ConfigStorage.layout().usdaAnchorHolder;
    }

    function defaultSponsor() external view returns (address) {
        return ConfigStorage.layout().defaultSponsor;
    }

    function buyCardPayee() external view returns (address) {
        return ConfigStorage.layout().buyCardPayee;
    }

    function cardDefaultIPPayee() external view returns (address) {
        return ConfigStorage.layout().cardDefaultIPPayee;
    }

    function cardDestroyPayee() external view returns (address) {
        return ConfigStorage.layout().cardDestroyPayee;
    }

    function bnome() external view returns (address) {
        return ConfigStorage.layout().bnome;
    }

    function anomeDexRouter() external view returns (address) {
        return ConfigStorage.layout().anomeDexRouter;
    }
}
