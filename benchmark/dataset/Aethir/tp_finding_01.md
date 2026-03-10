# Verifiable Data Hash Does Not Include Method Parameter Allowing For Unintended Method To Be Verified


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🔴 Critical |
| Triage Verdict | ✅ Valid |
| Project ID | `61c50ac0-0012-11f0-a6c7-dd487ba7c9c0` |
| Commit | `44d2074b48bbc9a18193f23fbf9afacd15f77e3c` |

## Location

- **Local path:** `./source_code/github/AethirCloud/IDC-Contracts-V2/44d2074b48bbc9a18193f23fbf9afacd15f77e3c/contracts/base/RequestVerifier.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/61c50ac0-0012-11f0-a6c7-dd487ba7c9c0/source?file=$/github/AethirCloud/IDC-Contracts-V2/44d2074b48bbc9a18193f23fbf9afacd15f77e3c/contracts/base/RequestVerifier.sol
- **Lines:** 73–88

## Description

The validators sign for the the data hash given by the function `getHash()`, which does not include the `vdata.method`. As such users can use signatures intended for verification of a certain method on another method in the same contract provided the parameters will pass any further validation done within the method, which may happen in certain cases.

## Recommendation

We recommend including the `vdata.method` in the data hash to ensure that signatures will only verify the intended method.

## Vulnerable Code

```
require(vdata.nonce > user.nonce, "NonceTooLow");
        // slither-disable-next-line timestamp
        require(vdata.lastUpdateBlock >= user.lastUpdateBlock, "DataTooOld");

        hash = getHash(vdata);
        checkValidatorSignatures(hash, vdata.proof);

        // update user data
        user.nonce = vdata.nonce;
        user.lastUpdateBlock = uint64(block.number);
        db.setUserData(vdata.sender, user);
    }

    /// @inheritdoc IRequestVerifier
    function verifyInitiator(
        VerifiableData calldata vdata,
        bytes4 method
    ) external view override returns (bytes32 hash) {
        require(vdata.target == msg.sender, "TargetMismatch");
        require(vdata.method == method, "MethodMismatch");
        require(vdata.version == _registry.getVersion(), "InvalidVersion");
        require(vdata.deadline >= block.timestamp, "DataExpired");

        hash = getHash(vdata);
        checkInitiatorSignatures(hash, vdata.proof);
    }

    /// @inheritdoc IRequestVerifier
    function getHash(VerifiableData calldata vdata) public view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    block.chainid,
                    vdata.nonce,
                    vdata.deadline,
                    vdata.lastUpdateBlock,
                    vdata.version,
                    vdata.sender,
                    vdata.target,
                    vdata.params,
                    vdata.payloads
                )
            );
    }

    function checkValidatorSignatures(bytes32 dataHash, bytes calldata signatures) public view {
        uint8 threshold = _registry.getACLManager().getRequiredSignatures();
        require(signatures.length >= (threshold * 65), "Invalid signature len");
        bytes32 hash = MessageHashUtils.toEthSignedMessageHash(dataHash);
        address[] memory signers = new address[](threshold);
        for (uint256 i = 0; i < threshold; i++) {
            signers[i] = ECDSA.recover(hash, signatures[i * 65:(i + 1) * 65]);
            _registry.getACLManager().requireValidator(signers[i]);
            for (uint256 j = 0; j < i; j++) {
                require(signers[j] != signers[i], "Duplicate signer");
            }
        }
    }

    function checkInitiatorSignatures(bytes32 dataHash, bytes calldata signatures) public view {
        uint8 threshold = _registry.getACLManager().getRequiredInitiatorSignatures();
        require(signatures.length >= (threshold * 65), "Invalid signature len");
        bytes32 hash = MessageHashUtils.toEthSignedMessageHash(dataHash);
        address[] memory signers = new address[](threshold);
        for (uint256 i = 0; i < threshold; i++) {
            signers[i] = ECDSA.recover(hash, signatures[i * 65:(i + 1) * 65]);
            _registry.getACLManager().requireInitSettlementOperator(signers[i]);
            for (uint256 j = 0; j < i; j++) {
                require(signers[j] != signers[i], "Duplicate signer");
            }
        }
    }

    /// @dev Get the emergency switch contract from the registry
```
