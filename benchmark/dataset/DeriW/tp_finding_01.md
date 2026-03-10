# Collected Fees Can Be Stolen From Router


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🟠 Major |
| Triage Verdict | ✅ Valid |
| Project ID | `d0c1c3e0-0ebe-11f0-bb28-b1ecc4c0c646` |
| Commit | `5074e14f897f25fd93d122e0dbbc5b39c676cc85` |

## Location

- **Local path:** `./source_code/github/deriwfi/deriw-contracts/5074e14f897f25fd93d122e0dbbc5b39c676cc85/contracts/chain/UserL3ToL2Router.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/d0c1c3e0-0ebe-11f0-bb28-b1ecc4c0c646/source?file=$/github/deriwfi/deriw-contracts/5074e14f897f25fd93d122e0dbbc5b39c676cc85/contracts/chain/UserL3ToL2Router.sol
- **Lines:** 145–145

## Description

The `UserL3ToL2Router` contract facilitates cross-chain transfers and charges fees for these operations. Fees are collected in the `UserL3ToL2Router` contract itself. While the contract includes a `claimFee()` function, which is restricted to the `gov` role for withdrawing these collected fees, the design choice to hold fees within the router contract creates an attack surface.

The `outboundTransfer()` function is responsible for initiating the ERC20 bridging process. It takes `_token` (the token being transferred from L3), `_l2Token` (the token to be received on L2), `_to`, `_amount`, and other parameters. The critical flaw is that the call to `gatewayRouter.outboundTransfer()` uses `_l2Token` as the token to be bridged on the L2 side, but the `IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount)` call transfers `_token` to the router on the L3 side. If `_l2Token` happens to be the same underlying asset as a token for which fees have been collected and are stored in the router, an attacker can effectively bridge the collected fees by supplying a different `_token` that is whitelisted and has sufficient balance.

No token approval is needed before calling `gatewayRouter.outboundTransfer()` because the bridge directly burns tokens from the sender, as seen [here](https://github.com/OffchainLabs/token-bridge-contracts/blob/5bdf33259d2d9ae52ddc69bc5a9cbc558c4c40c7/contracts/tokenbridge/arbitrum/gateway/L2ArbitrumGateway.sol#L201), which enables this attack.

## Recommendation

The collected fees should not remain in the `UserL3ToL2Router` contract where they can be inadvertently or maliciously transferred. Instead, fees should be immediately transferred to a designated, secure treasury or multi-signature wallet upon collection.

## Vulnerable Code

```
address _l3Usdt,
        address _arbSys,
        address[] memory tokens,
        MinTokenFee[] memory _mFee,
        MinTokenFee[] memory _mRate,
        uint8 _cType
    ) external {
        require(!initialized, "has initialized");

        initialized = true;
        gatewayRouter = IL1GatewayRouter(_l3GatewayRouter);
        gov = msg.sender;
        l3Usdt = _l3Usdt;
        arbSys = IArbSys(_arbSys);
        chainType = _cType;

        addOremoveWhitelist(tokens, true);

        if(chainType == 1) {
            if(_mFee.length > 0) {
                setMinTokenFee(_mFee);
            }

            if(_mRate.length > 0) {
                setTokenRate(_mRate);
            }
        }
    }

    function outboundTransfer(
        address _token,
        address _l2Token,
        address _to,
        uint256 _amount,
        bytes calldata _data,
        EIP712Domain memory domain,
        Message memory message,
        bytes memory signature
    ) external payable {
        require(whitelistToken.contains(_token), "token err");
        require(block.timestamp <= message.deadline, "time err");

        (address user, bytes32 digest) = getSignatureUser(domain, message, signature);
        require(msg.sender == user && !isHashUse[digest], "signature err");
        isHashUse[digest] = true;

        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        uint256 _fee;

        (_fee, _amount) = _addFee(_token, _amount);

        IERC20(_token).approve(address(gatewayRouter), _amount);
        gatewayRouter.outboundTransfer{ value: msg.value }(
                _l2Token,
                _to,
                _amount,
                _data
        );
        _outboundTransfer(_token, _l2Token, _to, _amount, _fee);
```
