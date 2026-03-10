# IDO Can Not Be Ended Successfully


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🔴 Critical |
| Triage Verdict | ✅ Valid |
| Project ID | `c08d7760-3cf7-11ef-be39-7174154c7792` |
| Commit | `588179c50968aa6da0ddbd4d04cd0c4ef80a58d9` |

## Location

- **Local path:** `./src/contracts/swap/Starter.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/c08d7760-3cf7-11ef-be39-7174154c7792/source?file=$/github/xxb-chain/safepump-contract/588179c50968aa6da0ddbd4d04cd0c4ef80a58d9/contracts/swap/Starter.sol
- **Lines:** 151–154

## Description

The `settle()` function allows the owner to set a proposal's status to `ended`,  indicating that the IDO has successfully concluded. The function checks if the contract's quote token balance is sufficient. 
```solidity
   require(
            IERC20(proposal.quoteToken).balanceOf(address(this)) >= proposal.goalAmount.mul(proposal.price),
            'Starter: balance not enough'
        );
```
However, the require check in lines 151-154 is incorrect. On the right side of the boolean expression, proposal.goalAmount represents the amount of base tokens, and proposal.price indicates how many base tokens are needed to buy one quote token. Therefore, the required amount of quote tokens should be calculated by division, not multiplication. 

Note that after changing the `require` condition to `quoteToken.balanceOf(this) >= goalAmount / price`, this condition is true if and only if `soldAmount >= goalAmount`. If that is the intention of the `require` condition, it is recommended to use this simpler form.

## Recommendation

Recommend redesigning the criteria for determining whether the IDO can end successfully.

## Vulnerable Code

```
emit Purchase(_pid, proposal.baseToken, msg.sender, _amount);
    }

    function purchaseByETH(uint256 _pid) external payable canPurchase(_pid) {
        Proposal storage proposal = proposals[_pid];
        require(address(proposal.baseToken) == address(0), 'Starter: should call purchase instead');
        uint256 amount = msg.value;

        users[msg.sender][_pid].purchasedAmount = users[msg.sender][_pid].purchasedAmount.add(amount);
        proposal.soldAmount = proposal.soldAmount.add(amount);
        emit Purchase(_pid, proposal.baseToken, msg.sender, amount);
    }

    function settle(uint256 _pid) public onlyOwner {
        Proposal storage proposal = proposals[_pid];
        require(proposal.status == STATUS_DEFAULT, 'Starter: already settled');

        // can be settled in fixed price proposal before end block
        if (!proposal.isFixedPrice) {
            require(block.number >= proposal.endBlock, 'Starter: not ended yet');
        }

        if (!proposal.isFixedPrice) {
            IERC20 quoteToken = IERC20(proposal.quoteToken);
            proposal.price = proposal.soldAmount.mul(10**quoteToken.decimals()).div(
                quoteToken.balanceOf(address(this))
            );
        }
        require(
            IERC20(proposal.quoteToken).balanceOf(address(this)) >= proposal.goalAmount.mul(proposal.price),
            'Starter: balance not enough'
        );
        proposal.status = Status.ended;

        emit Settle(_pid, proposal.status);
    }

    // used by ido investor
    function withdraw(uint256 _pid) external {
        Proposal storage proposal = proposals[_pid];
        require(proposal.status == Status.ended || proposal.status == Status.rejected, 'Starter: proposal in progress');
        uint256 amount = getPendingAmount(_pid, msg.sender);
        if (proposal.status == Status.ended) {
            IERC20(proposal.quoteToken).safeTransfer(msg.sender, amount);
            users[msg.sender][_pid].claimedAmount = users[msg.sender][_pid].claimedAmount.add(amount);
        }
        if (proposal.status == Status.rejected) {
            if (proposal.baseToken == address(0)) {
                msg.sender.transfer(amount);
            }
            IERC20(proposal.baseToken).safeTransfer(msg.sender, amount);
        }
        users[msg.sender][_pid].isClaimed = true;
        emit Withdraw(_pid, proposal.quoteToken, msg.sender, amount);
    }

    // withdraw base token to beneficiary
    function withdrawToken(uint256 _pid) external {
        Proposal storage proposal = proposals[_pid];
        require(msg.sender == proposal.beneficiary, 'Starter: only beneficiary');

        if (proposal.baseToken == address(0)) {
```
