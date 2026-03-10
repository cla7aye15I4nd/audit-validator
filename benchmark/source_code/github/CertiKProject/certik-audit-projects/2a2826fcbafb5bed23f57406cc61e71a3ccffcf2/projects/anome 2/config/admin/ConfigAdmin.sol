// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ConfigStorage} from "../ConfigStorage.sol";

import {IConfigAdmin} from "./IConfigAdmin.sol";
import {SafeOwnableInternal} from "../../../lib/solidstate/access/ownable/SafeOwnableInternal.sol";

contract ConfigAdmin is IConfigAdmin, SafeOwnableInternal {
    function setBaseToken(address baseToken) external onlyOwner {
        ConfigStorage.layout().baseToken = baseToken;
    }

    function setUsda(address usda) external onlyOwner {
        ConfigStorage.layout().usda = usda;
    }

    function setVnome(address vnome) external onlyOwner {
        ConfigStorage.layout().vnome = vnome;
    }

    function setWkToken(address wkToken) external onlyOwner {
        ConfigStorage.layout().wkToken = wkToken;
    }

    function setGame(address game) external onlyOwner {
        ConfigStorage.layout().game = game;
    }

    function setWeth(address weth) external onlyOwner {
        ConfigStorage.layout().weth = weth;
    }

    function setShop(address shop) external onlyOwner {
        ConfigStorage.layout().shop = shop;
    }

    function setAlloc(address alloc) external onlyOwner {
        ConfigStorage.layout().alloc = alloc;
    }

    function setBox(address box) external onlyOwner {
        ConfigStorage.layout().box = box;
    }

    function setBoxCert(address boxCert) external onlyOwner {
        ConfigStorage.layout().boxCert = boxCert;
    }

    function setUniV2Router(address uniV2Router) external onlyOwner {
        ConfigStorage.layout().uniV2Router = uniV2Router;
    }

    function setOgNFT(address ogNft) external onlyOwner {
        ConfigStorage.layout().ogNft = ogNft;
    }

    function setCaller(address caller) external onlyOwner {
        ConfigStorage.layout().caller = caller;
    }

    function setTreasury(address treasury) external onlyOwner {
        ConfigStorage.layout().treasury = treasury;
    }

    function setUsdaAnchorHolder(address usdaAnchorHolder) external onlyOwner {
        ConfigStorage.layout().usdaAnchorHolder = usdaAnchorHolder;
    }

    function setDefaultSponsor(address defaultSponsor) external onlyOwner {
        ConfigStorage.layout().defaultSponsor = defaultSponsor;
    }

    function setBuyCardPayee(address buyCardPayee) external onlyOwner {
        ConfigStorage.layout().buyCardPayee = buyCardPayee;
    }

    function setCardDefaultIPPayee(address cardDefaultIPPayee) external onlyOwner {
        ConfigStorage.layout().cardDefaultIPPayee = cardDefaultIPPayee;
    }

    function setCardDestroyPayee(address cardDestroyPayee) external onlyOwner {
        ConfigStorage.layout().cardDestroyPayee = cardDestroyPayee;
    }

    function setBnome(address bnome) external onlyOwner {
        ConfigStorage.layout().bnome = bnome;
    }

    function setAnomeDexRouter(address anomeDexRouter) external onlyOwner {
        ConfigStorage.layout().anomeDexRouter = anomeDexRouter;
    }
}
