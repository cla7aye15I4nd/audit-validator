// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity =0.7.4;

import './IERC20.sol';

interface IPair is IERC20 {
    event Mint(address indexed sender, uint256 amountEquivalent, uint256 amountToken);
    event Burn(address indexed sender, uint256 amountEquivalent, uint256 amountToken, address indexed to);
    event Swap(
        address indexed sender,
        uint256 amountEquivalentIn,
        uint256 amountTokenIn,
        uint256 amountEquivalentOut,
        uint256 amountTokenOut,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    function MINIMUM_LIQUIDITY() external pure returns (uint256);

    function factory() external view returns (address);

    function equivalent() external view returns (address);

    function token() external view returns (address);

    function taxPool() external view returns (address);

    function getReserves()
        external
        view
        returns (
            uint112 reserveEquivalent,
            uint112 reserveToken,
            uint32 blockTimestampLast
        );

    function price0CumulativeLast() external view returns (uint256);

    function price1CumulativeLast() external view returns (uint256);

    function kLast() external view returns (uint256);

    function mint(address to) external returns (uint256 liquidity);

    function burn(address to) external returns (uint256 amountEquivalent, uint256 amountToken);

    function swap(
        uint256 amountEquivalentOut,
        uint256 amountTokenOut,
        uint256 amountIn,
        address to
    ) external;

    function skim(address to) external;

    function sync() external;
}
