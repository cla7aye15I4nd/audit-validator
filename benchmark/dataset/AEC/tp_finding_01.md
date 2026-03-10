# `transferBySig()` Allows Draining of Signer’s Balance


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🔴 Critical |
| Triage Verdict | ✅ Valid |
| Project ID | `5f0618f0-7cd8-11ef-88bc-cde2c27fc0ff` |
| Commit | `b7e6f6a3f0a65c608378c49e96cf468f077df87b` |

## Location

- **Local path:** `./src/ADC.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/5f0618f0-7cd8-11ef-88bc-cde2c27fc0ff/source?file=$/gitlab/adc-stablecoin/adc-contracts/b7e6f6a3f0a65c608378c49e96cf468f077df87b/ADC.sol
- **Lines:** 616–628

## Description

The signature mechanism in `transferBySig()` does not include the `value` or the `to` address in the hash being signed. As a result, a valid signature can be used to transfer any amount from the signer to any arbitrary recipient. This defeats the security purpose of the signature mechanism and opens up the possibility for misuse.

A malicious user could exploit this by either gaining access to a signature with the intent to transfer a specific amount and then transferring the signer’s entire balance instead, or by front-running transactions and changing the recipient address to their own, thereby redirecting funds.

## Recommendation

We recommend including the `value` (amount) and the `to` (recipient) address in the message being signed. This ensures that the signature is valid only for the specific transfer that was intended, mitigating the risk of unauthorized transfers.

## Vulnerable Code

```
address[] tos,
        uint256[] values,
        bytes32[] r,
        bytes32[] s,
        uint8[] v
    ) public whenNotPaused {
        uint256 count = spenders.length;
        require(
            tos.length == count &&
                values.length == count &&
                r.length == count &&
                s.length == count &&
                v.length == count,
            "invalid args"
        );
        for (uint256 i = 0; i < count; i++) {
            transferBySig(spenders[i], tos[i], values[i], r[i], s[i], v[i]);
        }
    }

    function transferBySig(
        address spender,
        address to,
        uint256 value,
        bytes32 r,
        bytes32 s,
        uint8 v
    ) public whenNotPaused isPermitted(spender) isPermitted(to) {
        require(deprecated == false, "inactive");
        bytes32 permitHash = keccak256(
            bytes(
                string(
                    abi.encodePacked(
                        DOMAIN_PERMIT_HASH,
                        ":",
                        nonces[spender].toString()
                    )
                )
            )
        );
        bytes memory prefix = "\x19Ethereum Signed Message:\n32";
        bytes32 ethSigHash = keccak256(abi.encodePacked(prefix, permitHash));
        require(spender == ecrecover(ethSigHash, v, r, s), "invalid signature");

        nonces[spender]++;
        super._transfer(spender, to, value);
    }

    function batchTransfer(
        address[] _targets,
        uint256[] _values
    ) public whenNotPaused isPermitted(msg.sender) {
        require(deprecated == false, "inactive");
        require(_targets.length == _values.length, "invalid args");
        for (uint256 i = 0; i < _targets.length; i++) {
            requirePermission(_targets[i]);
            super._transfer(msg.sender, _targets[i], _values[i]);
        }
    }

    // Forward ERC20 methods to upgraded contract if this one is deprecated
    function transfer(
        address _to,
        uint256 _value
    ) public whenNotPaused isPermitted(msg.sender) isPermitted(_to) {
        if (deprecated) {
            return
                UpgradedStandardToken(upgradedAddress).transferByLegacy(
                    msg.sender,
                    _to,
                    _value
                );
```
