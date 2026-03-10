# Sender Can Set Unbounded Condition Timelines in NFT Creation, Leading to Griefing Attack


| Field | Value |
| --- | --- |
| Type | False Positive |
| Severity | — |
| Triage Verdict | ❌ Invalid |
| Triage Reason | Security control exists |
| Source | scanner.smart_audit |
| Scan Model | gemini-2.5-pro |
| Project ID | `b619bc20-116e-11f0-85f2-afceaa02a7b6` |
| Commit | `54b12f25ff139912cbddcc316c940624a64687cf` |

## Location

- **Local path:** `./source_code/github/GLBank/Web3/54b12f25ff139912cbddcc316c940624a64687cf/GLDB Pulse Contracts/ENT&Swap/NFT.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/b619bc20-116e-11f0-85f2-afceaa02a7b6/source?file=$/github/GLBank/Web3/54b12f25ff139912cbddcc316c940624a64687cf/GLDB Pulse Contracts/ENT&Swap/NFT.sol
- **Lines:** 1–1

## Description

The `createNFTsFromTokens` function allows a `sender` to create an NFT proposal for a `receiver`. The NFT can have an `executionDate` and a set of `conditions`, each with their own date ranges. If the `executionDate` is not specified at creation (`executionDate.isTimeSet2()` is false), the NFT is created in a `WAIT_EXECUTION_DATE` state, and the `receiver` must later call `setExecutionStartTimestamp` to activate it.

The vulnerability is an incomplete validation check within `createNFTsFromTokens`. The function checks if a condition's end time exceeds the execution end time (`cond.date.endTime > executionDate.endTime`), but this check is only performed if the execution date is already set (`executionDate.isTimeSet2()` is true).

A malicious sender can exploit this by creating a proposal with an unset execution date, thereby bypassing the check. This allows the sender to include a condition with a `date` range that ends arbitrarily far in the future (e.g., years from now). The NFT is created in the `WAIT_EXECUTION_DATE` state without locking any of the sender's tokens.

When the unsuspecting receiver attempts to finalize the agreement by calling `setExecutionStartTimestamp`, that function enforces that the new `executionDate.endTime` must be greater than or equal to the maximum end time (`maxTime`) of all conditions. The receiver is now trapped: either they accept an extremely long execution timeline that was not part of the off-chain agreement, or their transaction will revert. They cannot proceed with the originally intended timeline. The sender successfully griefs the receiver, disrupting the deal at no cost to themselves.

**Exploit Demonstration**

1.  **Attacker's Goal:** To force the receiver into an unfairly long contract timeline or to make them abandon the deal.
2.  **Step 1: The Setup.** Alice (the malicious sender) and Bob (the receiver) agree off-chain to a deal where Alice will send Bob 1000 tokens, claimable within 30 days of activation. Bob's approval is required as a condition, which should also be completed within the 30-day window.
3.  **Step 2: Malicious Creation.** Alice calls `createNFTsFromTokens` with the following parameters:
    *   `receiver`: Bob's address.
    *   `amount`: 1000 tokens.
    *   `executionDate`: A `Date` struct where `day` is 30 (representing a 30-day period to be started later), and `startTime` and `endTime` are 0. This causes `executionDate.isTimeSet2()` to return `false`.
    *   `conditions`: An array with one `NFTCreateConditionParams` struct:
        *   `operator`: Bob's address.
        *   `date`: A `Date` struct where `day` is 0, `startTime` is a near-future timestamp, but `endTime` is a timestamp set 10 years in the future.
4.  **Step 3: Flaw Execution.** The `createNFTsFromTokens` function executes:
    *   Because `executionDate.isTimeSet2()` is false, the crucial check `if (executionDate.isTimeSet2() && cond.date.endTime > executionDate.endTime)` is skipped.
    *   The NFT is successfully created with status `WAIT_EXECUTION_DATE`. No tokens are transferred from Alice at this point.
5.  **Step 4: Receiver's Trap.** Bob, believing the deal is ready to be finalized, calls `setExecutionStartTimestamp` to start the agreed 30-day execution period.
    *   Inside `setExecutionStartTimestamp`, the contract retrieves `maxTime` from the conditions, which is the timestamp 10 years in the future maliciously set by Alice.
    *   The function calculates the `endTimestamp` for the execution period (e.g., `now + 30 days`).
    *   It then fails the check `if (maxTime > endTimestamp)` because `now + 10 years` is greater than `now + 30 days`.
    *   Bob's transaction reverts. He cannot set the agreed-upon 30-day timeline. His only options are to set a timeline of at least 10 years or to abandon the deal. The griefing attack is successful.

## Vulnerable Code

```
function createNFTsFromTokens(
        uint256 nftId,
        uint256 amount,
        address receiver,
        Date memory executionDate,
        LogicType logic,
        NFTCreateConditionParams[] memory conditions
    ) external checkTransfer(_msgSender(), receiver) {
        address sender = _msgSender();

        ////////////////////// CHECK PARAMETERS //////////////////////
        require(sender != receiver);
        // 0. Check logic and conditions length
        if (conditions.length > 1 && logic == LogicType.NONE) {
            revert InvalidConditionsLength();
        }
        if (conditions.length < 2 && logic != LogicType.NONE) {
            revert InvalidConditionsLength();
        }
        // 1. Check if ID is already in use
        if (nftId == 0 || _getNFTStorage().nfts[nftId].status != NFTStatus.NONE) {
            revert NFTAlreadyExists(nftId);
        }
        // 2. Check receiver address
        Helper.checkAddress(receiver);
        // 3. Check amount value
        Helper.checkValue(amount);
        // 3.1. Check Execution Date
        uint40 nowTime = uint40(block.timestamp);
        // The user creates an request off-chain.
        // The validity period is 24 hours and it becomes effective upon the other party's approval.
        // To prevent the approval from being too late and resulting in failure to pass, there is a grace period of 25 hour
        uint40 toleranceTime = nowTime - 90000; /*25Hours*/
        if (!executionDate.check(toleranceTime)) {
            revert InvalidExecutionDate();
        }
        // 4. Check conditions
        NFTStatus nftStatus = executionDate.isTimeSet2() ? NFTStatus.CREATED : NFTStatus.WAIT_EXECUTION_DATE;
        NFTMetadata storage newNFT = _getNFTStorage().nfts[nftId];
        {
            uint256 countSender;
            uint256 countReceiver;
            for (uint256 i = 0; i < conditions.length;) {
                NFTCreateConditionParams memory cond = conditions[i];
                if (
                    !cond.date.check(toleranceTime)
                        || uint8(cond.allowedAction) > uint8(AllowedAction.ApproveRejectOrNoAction)
                ) {
                    revert InvalidCondition(cond);
                }
                // If execution date is set, condition's max time cannot exceed execution time's endTime
                if (executionDate.isTimeSet2() && cond.date.endTime > executionDate.endTime) {
                    revert InvalidCondition(cond);
                }
                if (cond.operator == sender) {
                    countSender++;
                } else if (cond.operator == receiver) {
                    countReceiver++;
                } else {
                    revert InvalidCondition(cond);
                }
                if (!cond.date.isTimeSet2() && executionDate.isTimeSet2()) {
                    nftStatus = NFTStatus.WAIT_CONDITION_DATE;
                }
                newNFT.conditions.push(
                    NFTCondition({
                        operator: cond.operator,
                        date: cond.date,
                        firstActionTime: 0,
                        lastActionTime: 0,
                        isPartial: cond.isPartial,
                        allowedAction: cond.allowedAction,
                        action: Action3.None,
                        confirmedAmount: 0
                    })
                );
                unchecked {
                    i++;
                }
            }
            if (countSender > 1 || countReceiver > 1) {
                // Same person can only handle once
                revert DuplicateOperatorInConditions();
            }
        }
        // 5. Check if allowance is sufficient
        {
            uint256 allowance = IERC20(tokenAddress).allowance(sender, address(this));
            if (allowance < amount) {
                revert IERC20Errors.ERC20InsufficientAllowance(address(this), allowance, amount);
            }
        }

        newNFT.createdAt = nowTime;
        newNFT.executionDate = executionDate;
        newNFT.status = nftStatus;
        newNFT.sender = sender;
        newNFT.partyA = receiver;
        newNFT.amount = amount;
        newNFT.logic = logic;

        emit NFTInitial(nftId, sender, receiver, amount);

        if (nftStatus == NFTStatus.CREATED) {
            _createNFT(nftId, newNFT);
        }
    }
```

## Related Context

```
checkTransfer ->     modifier checkTransfer(address sender, address recipient) {
        checkWhiteBlacklist(sender, recipient);
        _;
    }

_msgSender ->     function _msgSender() internal view virtual override(Context, ContextUpgradeable) returns (address) {
        return ContextUpgradeable._msgSender();
    }

_getNFTStorage ->     function _getNFTStorage() internal pure returns (NFTStorage storage $) {
        assembly {
            $.slot := NFT_STORAGE_LOCATION
        }
    }

checkAddress ->     function checkAddress(address addr) internal pure {
        if (addr == address(0)) {
            revert ZeroAddress();
        }
    }

checkValue ->     /**
     * @notice Check if a value is greater than zero
     * @dev If value is zero, raised error
     * @param value - Value to check
     */
    function checkValue(uint256 value) internal pure {
        if (value == 0) {
            revert ZeroValue();
        }
    }

check ->     function check(Date memory date, uint40 nowTime) internal pure returns (bool) {
        if (date.day == 0) {
            // Start time must be greater than current block time
            if (date.startTime < nowTime) {
                return false;
            }
            // End time must be greater than start time
            if (date.endTime <= date.startTime) {
                return false;
            }
        } else {
            // T1: x days, date set by partyA
            // startTime and endTime is zero
            if (date.startTime != 0 || date.endTime != 0) {
                return false;
            }
        }
        return true;
    }

isTimeSet2 ->     function isTimeSet2(Date memory date) internal pure returns (bool) {
        return date.startTime != 0;
    }

_createNFT ->     function _createNFT(uint256 nftId, NFTMetadata storage nft) private {
        _changeNFTStatus(nftId, nft, NFTStatus.CREATED);
        nft.nftCreatedAt = uint40(block.timestamp);
        _swap(nft.sender, nft.partyA, nftId, nft.amount);
        _updateTotalHold(nftId, nft.partyA, nft.amount, true);
    }
```
