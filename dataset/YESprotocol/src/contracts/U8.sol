// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "./Base.sol";
import "./interfaces/IPool.sol";

contract U8 is Base, ERC20Burnable {
    constructor() Ownable(msg.sender) ERC20("U8", "U8") {
        _mint(msg.sender, 100_000_000_000 ether);
    }

    function _update(address from, address to, uint256 amount) internal override {
        if (from == pair) {
            // buy or remove liquidity
            if (_isRemoveLiquidity()) {
                super._update(from, to, amount);
            } else {
                // buy
                require(pool != address(0), "Pool not set");
                super._update(from, pool, amount);
                uint256 usdtAmount = getTokenDelta(USDT);
                IPool(pool).processBuy(from, to, amount, usdtAmount);
            }
        } else if (to == pair) {
            // sell or add liquidity
            if (_isAddLiquidity()) {
                super._update(from, to, amount);
            } else {
                // sell
                uint256 fee = (amount * sellFeeRate) / 1000;
                super._update(from, to, amount - fee);
                if (fee > 0) {
                    super._update(from, pool, fee);
                    IPool(pool).processSellFee(from, to, fee);
                }
            }
        } else {
            super._update(from, to, amount);
        }
    }
}
