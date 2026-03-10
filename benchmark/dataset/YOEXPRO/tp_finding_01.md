# Incorrect Bond Accounting Leads to Potential Vault Insolvency


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🟠 Major |
| Triage Verdict | ✅ Valid |
| Project ID | `9779da50-371d-11f0-b142-2bda881cf922` |
| Commit | `0x26c98b27ab51af12c616d2d2eb99909b6bde6dde` |

## Location

- **Local path:** `./source_code/bsc/mainnet/0x31569a2d8333554bb0d8bd6deeb425682bb3d082/YoExBond.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/9779da50-371d-11f0-b142-2bda881cf922/source?file=$/bsc/mainnet/0x31569a2d8333554bb0d8bd6deeb425682bb3d082/YoExBond.sol
- **Lines:** 83–83

## Description

The `bond()` function swaps `USDT` for a fee-on-transfer YOEX token that burns 1% on each transfer. It uses `router.getAmountsOut(amount, path)` to estimate the YOEX output, then performs the swap. Because YOEX burns 1% on transfer, the actual tokens received (`yoexReceived`) are only 99% of the estimated amount. The contract then calculates `burnedTokens = estimatedYoex - yoexReceived` and **adds this difference back into the user’s bond (`totalBondAmount`)**. 

However, these burned YOEX tokens never reached the contract. As a consequence, users are credited for tokens that never reach the contract, leading to vault insolvency, failed withdrawals, and potential loss of funds for other users.

## Recommendation

We recommend accounting in the user`s bond only the actual tokens received by the vault contract (taking into account the burn fee) or clarify the intended behavior.

## Vulnerable Code

```
address indexed user,
        uint256 indexed index,
        uint256 indexed usdtAmount,
        uint256 yoexAmount,
        uint256 bonusAmount,
        uint256 lockDays,
        uint256 unlockTime
    );

    event BondUnstaked(
        address indexed user,
        uint256 indexed index,
        uint256 indexed totalWithdrawn,
        uint256 principal,
        uint256 bonus
    );

    event VaultUpdated(address oldVault, address newVault);
    event RouterUpdated(address oldRouter, address newRouter);
    event SlippageUpdated(uint256 oldSlippage, uint256 newSlippage);

    constructor(address _usdt, address _yoex, address _router, address _vault) {
        owner = msg.sender;
        usdt = IERC20(_usdt);
        yoex = IERC20(_yoex);
        router = IPancakeRouter(_router);
        vault = IYoexVault(_vault);
    }

    function bond(uint256 amount, uint256 lockDays) external {
        require(amount >= minBond, "Minimum bond is 1 USDT");
        require(lockDays != 0, "0 days lock not allowed");

        uint256 bonusPercent = getBonusPercent(lockDays);
        require(bonusPercent > 0, "Invalid bond duration");

        require(usdt.transferFrom(msg.sender, address(this), amount), "USDT transfer failed");
        require(usdt.approve(address(router), amount), "USDT approve failed");

        path[0] = address(usdt);
        path[1] = address(yoex);

        uint256 estimatedYoex = router.getAmountsOut(amount, path)[1];
        uint256 minYoex = (estimatedYoex * (10000 - slippageBPS)) / 10000;

        uint256 yoexReceived = router.swapExactTokensForTokens(
            amount,
            minYoex,
            path,
            address(this),
            block.timestamp + 600
        )[1];
        require(yoexReceived > 0, "Swap failed");

        uint256 burnedTokens = 0;
        if (estimatedYoex > yoexReceived) {
            burnedTokens = estimatedYoex - yoexReceived;
        }

        uint256 totalBondAmount = yoexReceived + burnedTokens;
```
