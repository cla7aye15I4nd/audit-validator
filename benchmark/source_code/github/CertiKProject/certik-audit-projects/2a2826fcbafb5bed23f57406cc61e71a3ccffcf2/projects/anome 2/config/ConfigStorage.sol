// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.10;

import {IERC20} from "../../lib/openzeppelin/token/ERC20/IERC20.sol";

import {ShopTypes} from "../shop/ShopTypes.sol";
import {IVnome} from "../token/vnome/IVnome.sol";
import {IUSDA} from "../token/usda/IUSDA.sol";
import {IWK} from "../token/wk/IWK.sol";

library ConfigStorage {
    // Config中只保存依赖和账号
    struct Layout {
        // dependency
        address baseToken;
        address usda;
        address vnome;
        address wkToken;
        address game;
        address weth;
        address shop;
        address alloc;
        address box;
        address boxCert;
        address uniV2Router;

        // accounts
        address caller;
        address treasury;
        address usdaAnchorHolder;
        address defaultSponsor;
        address buyCardPayee;
        address cardDefaultIPPayee;
        address cardDestroyPayee;

        // 亏损挖矿
        address bnome;
        address anomeDexRouter;

        // Og Nft
        address ogNft;
    }

    bytes32 internal constant STORAGE_SLOT = keccak256("anome.config.storage.v1");
    uint256 constant DIVIDEND = 10000;
    address constant HOLE = address(0xdead);

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}
