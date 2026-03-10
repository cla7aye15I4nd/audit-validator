# Vulnerability to Duplicate ID Exploitation in `withdrawByID` Function Leads To Fund Drain


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🔴 Critical |
| Triage Verdict | ✅ Valid |
| Project ID | `e8e6a7b0-9a56-11ef-8e7a-85ed0c9f95ba` |
| Commit | `69e732ace3c61a7b0ab16a3ff49a0b9ab521f5f4` |

## Location

- **Local path:** `./src/AccountManager.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/e8e6a7b0-9a56-11ef-8e7a-85ed0c9f95ba/source?file=$/github/SAFE-anwang/SAFE4-system-contract/69e732ace3c61a7b0ab16a3ff49a0b9ab521f5f4/AccountManager.sol
- **Lines:** 127–139

## Description

Repository:
- `SAFE4 System Contract`

Commit hash:
- [`69e732ace3c61a7b0ab16a3ff49a0b9ab521f5f4`](https://github.com/SAFE-anwang/SAFE4-system-contract/tree/69e732ace3c61a7b0ab16a3ff49a0b9ab521f5f4)


Files:
- `AccountManager.sol`


**`AccountManager.sol`**
```solidity=127
        uint amount;
        uint temp = balances[msg.sender];
        for(uint i; i < _ids.length; i++) {
            if(_ids[i] == 0) {
                amount += temp;
            } else {
                AccountRecord memory record = getRecordByID(_ids[i]);
                RecordUseInfo memory useinfo = id2useinfo[_ids[i]];
                if(record.addr == msg.sender && block.number >= record.unlockHeight && block.number >= useinfo.unfreezeHeight && block.number >= useinfo.releaseHeight) {
                    amount += record.amount;
                }
            }
        }
```

The `withdrawByID` function in the contract is vulnerable to a duplicate ID attack. If a user provides an array of IDs containing duplicates, the function will incorrectly calculate the withdrawal `amount` multiple times for the same record ID. However, the deletion of records only succeeds on the first occurrence, leading to potential re-exploitation of the same records and allowing a malicious actor to withdraw more funds than intended.


An attacker can exploit this vulnerability by passing duplicate IDs, leading to unauthorized withdrawals and potentially draining funds from the contract.

## Recommendation

Recommend **Implement Duplicate ID Check**: Use a mapping or a boolean array to track processed IDs and prevent duplicate processing.

## Vulnerable Code

```
}
        ids[i] = this.deposit{value: batchValue + msg.value % _times}(_addrs[i], _startDay + (i + 1) * _spaceDay);
        return ids;
    }

    // withdraw all
    function withdraw() public override noReentrant returns (uint) {
        uint amount;
        uint num;
        (amount, num) = getAvailableAmount(msg.sender);
        require(amount > 0, "insufficient amount");

        uint[] memory ids = new uint[](num);
        uint index;
        if(balances[msg.sender] != 0) {
            ids[index++] = 0;
        }
        AccountRecord[] memory records = addr2records[msg.sender];
        for(uint i; i < records.length; i++) {
            if(block.number >= records[i].unlockHeight && block.number >= id2useinfo[records[i].id].unfreezeHeight && block.number >= id2useinfo[records[i].id].releaseHeight) {
                ids[index++] = records[i].id;
            }
        }
        return withdrawByID(ids);
    }

    // withdraw by specify amount
    function withdrawByID(uint[] memory _ids) public override returns (uint) {
        require(_ids.length > 0, "invalid record ids");
        uint amount;
        uint temp = balances[msg.sender];
        for(uint i; i < _ids.length; i++) {
            if(_ids[i] == 0) {
                amount += temp;
            } else {
                AccountRecord memory record = getRecordByID(_ids[i]);
                RecordUseInfo memory useinfo = id2useinfo[_ids[i]];
                if(record.addr == msg.sender && block.number >= record.unlockHeight && block.number >= useinfo.unfreezeHeight && block.number >= useinfo.releaseHeight) {
                    amount += record.amount;
                }
            }
        }
        if(amount != 0) {
            payable(msg.sender).transfer(amount);
            for(uint i; i < _ids.length; i++) {
                if(_ids[i] != 0) {
                    AccountRecord memory record = getRecordByID(_ids[i]);
                    RecordUseInfo memory useinfo = id2useinfo[_ids[i]];
                    if(record.addr == msg.sender && block.number >= record.unlockHeight && block.number >= useinfo.unfreezeHeight && block.number >= useinfo.releaseHeight) {
                        getSNVote().removeVoteOrApproval2(msg.sender, _ids[i]);
                        if(getMasterNodeStorage().exist(useinfo.frozenAddr)) {
                            getMasterNodeLogic().removeMember(useinfo.frozenAddr, _ids[i]);
                        } else if(getSuperNodeStorage().exist(useinfo.frozenAddr)) {
                            getSuperNodeLogic().removeMember(useinfo.frozenAddr, _ids[i]);
                        }
                        delRecord(_ids[i]);
                    }
                } else {
                    balances[msg.sender] -= temp;
                }
            }
        }
        emit SafeWithdraw(msg.sender, amount, _ids);
        return amount;
    }

    function transfer(address _to, uint _amount, uint _lockDay) public override returns (uint) {
        require(_to != address(0), "transfer to the zero address");
        require(_amount > 0, "invalid amount");

        uint amount;
        uint num;
```
