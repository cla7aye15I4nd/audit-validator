# Swap Trusts ERC20 Transfer Without Verification, Allowing Free NFT Theft


| Field | Value |
| --- | --- |
| Type | False Positive |
| Severity | — |
| Triage Verdict | ❌ Invalid |
| Triage Reason | Security control exists |
| Source | scanner.smart_audit |
| Scan Model | o4-mini |
| Project ID | `b619bc20-116e-11f0-85f2-afceaa02a7b6` |
| Commit | `54b12f25ff139912cbddcc316c940624a64687cf` |

## Location

- **Local path:** `./source_code/github/GLBank/Web3/54b12f25ff139912cbddcc316c940624a64687cf/GLDB Pulse Contracts/ENT&Swap/Swap.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/b619bc20-116e-11f0-85f2-afceaa02a7b6/source?file=$/github/GLBank/Web3/54b12f25ff139912cbddcc316c940624a64687cf/GLDB Pulse Contracts/ENT&Swap/Swap.sol
- **Lines:** 1–1

## Description

The swap() logic transfers the seller’s ERC-1155 NFT first, then calls SafeERC20.safeTransferFrom for the payment token but never confirms that any tokens actually moved. SafeERC20 only checks that the token contract call doesn’t revert and that returned data (if any) isn’t false—it does not inspect balances. A malicious ERC20 implementation can exploit this by always returning success on transferFrom without transferring tokens, causing the seller to lose their NFT for no payment.

Exploit steps:
1. Attacker deploys a MaliciousToken contract implementing ERC20.transferFrom such that it always (a) returns no data or returns true, and (b) never deducts from the buyer’s balance.
2. Buyer (attacker) calls MaliciousToken.approve(swapContract, MAX_UINT) to grant the Swap contract allowance.
3. Buyer constructs SwapData:
   • token = address(MaliciousToken)
   • nft = address(VictimNFT)
   • nftId, amount = the victim’s NFT details
   • tokenAmount = any positive amount (e.g. 1)
   • buyer = attacker address
   • seller = victim address
   • deadline, nonce = valid values
   Buyer signs this struct off-chain (EIP-712) and sends (data, signature) to the victim.
4. Victim (seller) calls swap(data, signature). Checks pass (token ≠ 0, nft ≠ 0, seller==msg.sender, buyer≠seller, nonce unused, valid signature).
5. swap() marks the nonce and executes:
     a. IERC1155(nft).safeTransferFrom(seller, buyer, nftId, amount, "");  ← NFT moves to attacker.
     b. IERC20(token).safeTransferFrom(buyer, seller, tokenAmount);        ← MaliciousToken.transferFrom returns success but doesn’t transfer anything.
6. swap() emits SwapExecuted and returns. Victim’s NFT is gone; no tokens were received.

Because swap() never verifies buyer balances or checks post-transfer token balances, a fake-always-succeeding ERC20 can drain NFTs without payment.

## Vulnerable Code

```
function swap(SwapData calldata data, bytes calldata signature) external nonReentrant {
        address seller = msg.sender;

        // Check addresses
        if (data.token == address(0)) revert InvalidAddress(data.token);
        if (data.nft == address(0)) revert InvalidAddress(data.nft);
        if (data.buyer == address(0)) revert InvalidAddress(data.buyer);
        
        // Ensure only the designated seller can execute this swap
        if (seller != data.seller) revert InvalidAddress(seller);

        // Check amounts
        if (data.amount == 0) revert InvalidAmount(data.amount);
        if (data.tokenAmount == 0) revert InvalidAmount(data.tokenAmount);
        
        // Check deadline
        if (block.timestamp > data.deadline) {
            revert DeadlineExpired(data.deadline, block.timestamp);
        }
        
        // Prevent buyer and seller from being the same address
        if (data.buyer == data.seller) revert InvalidAddress(data.buyer);

        // Check nonce
        if (isNonceUsed(data.buyer, data.nonce)) {
            revert NonceAlreadyUsed();
        }

        // Verify signature
        bytes32 digest = _hash(data);
        address recoveredSigner = ECDSA.recover(digest, signature);
        if (recoveredSigner == address(0) || recoveredSigner != data.buyer) {
            revert InvalidSignature();
        }

        // Mark nonce as used
        _nonces[data.buyer][data.nonce] = true;
        emit NonceUsed(data.buyer, data.nonce);

        // Execute the atomic swap.
        // Transfer NFT from seller to buyer.
        // The seller must have called `setApprovalForAll` on the NFT contract for this contract.
        IERC1155(data.nft).safeTransferFrom(seller, data.buyer, data.nftId, data.amount, "");

        // Transfer ERC20 tokens from buyer to seller.
        // The buyer must have called `approve` on the token contract for this contract.
        IERC20(data.token).safeTransferFrom(data.buyer, seller, data.tokenAmount);

        emit SwapExecuted(
            seller, data.buyer, data.nft, data.token, data.nftId, data.amount, data.tokenAmount, data.nonce
        );
    }
```

## Related Context

```
isNonceUsed -> function isNonceUsed(address owner, uint256 nonce) public view virtual returns (bool) {
        return _nonces[owner][nonce];
    }

_hash ->     /**
     * @dev Hashes the swap data struct according to the EIP-712 standard.
     * @param data The SwapData struct to hash.
     * @return The EIP-712 digest.
     */
    function _hash(SwapData calldata data) internal view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    SWAP_TYPEHASH,
                    data.token,
                    data.nft,
                    data.nftId,
                    data.amount,
                    data.tokenAmount,
                    data.buyer,
                    data.seller,
                    data.deadline,
                    data.nonce
                )
            )
        );
    }
```
