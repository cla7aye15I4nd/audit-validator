# Pendle Oracle Does Not Always Return Rate Scaled By The Underlying Decimals


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🟡 Medium |
| Triage Verdict | ✅ Valid |
| Project ID | `8ab17f70-b8e3-11ef-a996-75baa03c0028` |
| Commit | `97d37973628a56f8bbd1a8c6d0b3301602fe4aae` |

## Location

- **Local path:** `./src/contracts/oracles/PendleOracle.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/8ab17f70-b8e3-11ef-a996-75baa03c0028/source?file=$/github/VenusProtocol/oracle/97d37973628a56f8bbd1a8c6d0b3301602fe4aae/contracts/oracles/PendleOracle.sol
- **Lines:** 80–85

## Description

The function `_getUnderlyingAmount()` is designed to get the `underlyingToken` amount for 1 `ptToken` scaled by the `underlyingToken` decimals. However, this function simply returns the value obtained from the `PT_ORACLE`, which does not always have this scaling and can result in an incorrect price being returned.

For example lets assume that PT pumpBTC 27MAR2025 is to be supported [0x997Ec6Bf18a30Ef01ed8D9c90718C7726a213527](https://etherscan.io/address/0x997Ec6Bf18a30Ef01ed8D9c90718C7726a213527). If one uses the `PendlePtLpOracle` at address [0x66a1096C6366b2529274dF4f5D8247827fe4CEA8](https://etherscan.io/address/0x66a1096C6366b2529274dF4f5D8247827fe4CEA8) (currently used by Venus) and fetches the rate via the pumpBTC market [0x8098b48a1c4e4080b30a43a7ebc0c87b52f17222](https://etherscan.io/address/0x8098b48a1c4e4080b30a43a7ebc0c87b52f17222), it will return a value with 18 decimals of precision, however WBTC only has 8 decimals. This would result in the wrong price being returned.

In our testing when calling `PT_ORACLE.getPtToAssetRate(0x8098b48a1c4e4080b30a43a7ebc0c87b52f17222, 900)` we got a value of `988245041751264715`, which is scaled by 1e18 as opposed to 1e8.

## Recommendation

We recommend ensuring that `_getUnderlyingAmount()` returns an amount scaled by the underlying token decimals for all Pendle oracles/markets that will be supported.

## Vulnerable Code

```
address ptOracle,
        RateKind rateKind,
        address ptToken,
        address underlyingToken,
        address resilientOracle,
        uint32 twapDuration
    ) CorrelatedTokenOracle(ptToken, underlyingToken, resilientOracle) {
        ensureNonzeroAddress(market);
        ensureNonzeroAddress(ptOracle);
        ensureNonzeroValue(twapDuration);

        MARKET = market;
        PT_ORACLE = IPendlePtOracle(ptOracle);
        RATE_KIND = rateKind;
        TWAP_DURATION = twapDuration;

        (bool increaseCardinalityRequired, , bool oldestObservationSatisfied) = PT_ORACLE.getOracleState(
            MARKET,
            TWAP_DURATION
        );
        if (increaseCardinalityRequired || !oldestObservationSatisfied) {
            revert InvalidDuration();
        }
    }

    /**
     * @notice Fetches the amount of underlying or SY token for 1 pendle token
     * @return amount The amount of underlying or SY token for pendle token
     */
    function _getUnderlyingAmount() internal view override returns (uint256) {
        if (RATE_KIND == RateKind.PT_TO_SY) {
            return PT_ORACLE.getPtToSyRate(MARKET, TWAP_DURATION);
        }
        return PT_ORACLE.getPtToAssetRate(MARKET, TWAP_DURATION);
    }
}
```
