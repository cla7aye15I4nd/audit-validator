# Signature Replay in `claimReward()` allows draining of rewards


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🔴 Critical |
| Triage Verdict | ✅ Valid |
| Project ID | `340b4e30-9034-11ef-b974-6b5926513cff` |
| Commit | `43b4aad87e5381d861a2c93e006213843a0e75ca` |

## Location

- **Local path:** `./source_code/github/homecub/Smart-Contracts/43b4aad87e5381d861a2c93e006213843a0e75ca/contracts/homecubesStake.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/340b4e30-9034-11ef-b974-6b5926513cff/source?file=$/github/homecub/Smart-Contracts/43b4aad87e5381d861a2c93e006213843a0e75ca/contracts/homecubesStake.sol
- **Lines:** 829–829

## Description

The `MaticzHomeCubeStaking::claimReward()` function accepts a signed signature from the contract's owner to authorize reward claims. However, it does not check if the nonce value has already been consumed during a previous reward claim. As a result, once a signature is generated, it can be replayed by malicious actors, allowing them to repeatedly call `claimReward()` and drain the staking pool. 

The root cause of the issue is the lack of nonce tracking. The nonce should be incremented with each reward claim to ensure that each signature can only be used once.

## Recommendation

The `MaticzHomeCubeStaking` contract should store the nonce value and ensure it is incremented each time a reward claim is made.

## Vulnerable Code

```
_msgSender(),
            "NFT withdraw NOT Available for This Address"
        );
        require(emergencynftwithdraw == true, "NFT withdraw Not Available");
        IERC721Upgradeable(_collectionAddress).safeTransferFrom(
            address(this),
            _msgSender(),
            tokenId
        );
        delete stackitem[_poolId][_collectionAddress][tokenId];
        delete stackStaus[_collectionAddress][tokenId];
        totalstakeusers = totalstakeusers.sub(1);
        totalusersperpool[_poolId] = totalusersperpool[_poolId].sub(1);
    }
    function emergencyTokenWithdraw(
        uint256 amount
    ) external onlyOwner {
        require(
            IERC20Upgradeable(rewardAddress).balanceOf(
                address(this)
            ) >= amount,
            "Not Enought Token Balance"
        );
        IERC20Upgradeable(rewardAddress).transfer(
            _msgSender(),
            amount
        );
    }

    function claimReward(
        uint256 reward,
        uint _nonce,
        bytes memory signature
    ) external {
        require(bytes(message).length > 0, "Message is not set.");
        verify(owner(), reward, message, _nonce, signature);
        uint tdeci = deci.sub(IERC20Upgradeable(rewardAddress).decimals());
        IERC20Upgradeable(rewardAddress).transfer(
            _msgSender(),
            reward.div(10 ** tdeci)
        );
    }
    function addRewardToken(address _rewardAddr) external onlyOwner {
        rewardAddress = _rewardAddr;
    }
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IERC721ReceiverUpgradeable.onERC721Received.selector;
    }

    function editTradeAddress(address tradeAdd) external onlyOwner {
        tradeAddress = tradeAdd;
    }

    function setMessage(string memory _msg) external onlyOwner {
        message = _msg;
```
