// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IConfigAdmin {
    // dependency
    function setBaseToken(address baseToken) external;
    function setUsda(address usda) external;
    function setVnome(address vnome) external;
    function setWkToken(address wkToken) external;
    function setGame(address game) external;
    function setWeth(address weth) external;
    function setShop(address shop) external;
    function setAlloc(address alloc) external;
    function setBox(address box) external;
    function setBoxCert(address boxCert) external;
    function setUniV2Router(address uniV2Router) external;
    function setOgNFT(address ogNft) external;

    // accounts
    function setCaller(address caller) external;
    function setTreasury(address treasury) external;
    function setUsdaAnchorHolder(address usdaAnchorHolder) external;
    function setDefaultSponsor(address defaultSponsor) external;
    function setBuyCardPayee(address buyCardPayee) external;
    function setCardDefaultIPPayee(address cardDefaultIPPayee) external;
    function setCardDestroyPayee(address cardDestroyPayee) external;

    // 亏损挖矿
    function setBnome(address bnome) external;
    function setAnomeDexRouter(address anomeDexRouter) external;
}
