# Vault

## token integration

- WETH: `scroll:0x5300000000000000000000000000000000000004`
- USDT: `scroll:0xf55BEC9cafDbE8730f096Aa55dad6D22d44099Df`
- USDC: `scroll:0x06eFdBFf2a14a7c8E15944D1F4A48F9F95F663A4`
- STONE: `scroll:0x80137510979822322193FC997d400D5A6C747bf7`
- PufETH: `scroll:0xc4d46E8402F476F269c379677C99F18E22Ea030e`
- wrsETH: `scroll:0xa25b25548B4C98B0c7d3d27dcA5D5ca743d68b7F`

## contracts

- Pencils Wrapped Ether: `scroll:0x88844c8f2b895792532AaE2a0F877208248F3585`
- Pencils Tether USD: `scroll:0xC72a7a21e3E12594c75Bc6418224E812e16a027E`
- Pencils USD Coin: `scroll:0xDc1FCFe40A5Cf9745cef0B75428eE28E81D7cC56`
- Pencils StakeStone Ether: `scroll:0x20DE0435e5674Ef15E78adA570159984524B9E8F`
- Pencils PufferVault: `scroll:0x0C530882C0900b13FC6E8312B52c26e7a5b8e505`
- Pencils rsETHWrapper: `scroll:0x27D2B6cEcd759D289B0227966cC6Fe69Cc2b0424`

## known issue

- Share's decimal is equal to underlying token
  - The codebase is forked from Alpaca Finance. Since USDC, USDT in BSC were deployed by Binance, which decimal are 18. Therefore, vault contract from Alpaca Finance can ignore the decimal's effect on exchange rate.
- Share doesn't have interest yet
