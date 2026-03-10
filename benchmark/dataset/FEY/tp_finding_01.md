# `closeGhostStake()` Cannot Close Users Stakes


| Field | Value |
| --- | --- |
| Type | True Positive |
| Severity | 🟠 Major |
| Triage Verdict | ✅ Valid |
| Project ID | `ecefe950-a048-11ef-badd-73246e4a2372` |
| Commit | `a3fd8f96d8002f7ef619ad01810426568a59c1bf` |

## Location

- **Local path:** `./src/contracts/FEYToken.sol`
- **ACC link:** https://acc.audit.certikpowered.info/project/ecefe950-a048-11ef-badd-73246e4a2372/source?file=$/github/FEYToken/Feyorra-FEY-/a3fd8f96d8002f7ef619ad01810426568a59c1bf/contracts/FEYToken.sol
- **Lines:** 154–154

## Description

`closeGhostStake()` is intended to be able to close the users stake that corresponds to the input `_stakingId` after all seconds of the users last day have passed. However, it does this by calling `closeStake(_stakingId)`, which makes the following check:

```solidity
  require(
            _stakeElement.userAddress == msg.sender,
            'FEYToken: wrong stake owner'
        );
```

`closeGhostStake()` can only be called if the `msg.sender` is the owner and `closeStake()` can only be called if the `_stakeElement.userAddress == msg.sender`, so that `closeGhostStake()` can only be called on the owners stakes and cannot be used to close other users stakes.

## Recommendation

We recommend refactoring the code to ensure that `closeGhostStake()` can successfully close a users stake after all seconds of the users last day have passed.

## Vulnerable Code

```
yearFullAmount,
            31556952,
            0
        );

        durationInterestAmt = dailyInterestAmt
            .mul(_seconds)
            .div(100);
    }

   /**
        * @notice admin function to close a matured stake OBO the staker
        * @param _stakingId ID of the stake, used as the Key from the stakeList mapping
        * @dev can only close after all of the seconds of the last day have passed
     */
    function closeGhostStake(
        uint256 _stakingId
    )
        external
        onlyOwner
    {
        (uint256 daysOld, uint256 secondsOld) = getStakeAge(_stakingId);

        require(
            daysOld == MAX_STAKE_DAYS &&
            secondsOld == SECONDS_IN_DAY,
            'FEYToken: not old enough'
        );

        closeStake(_stakingId);

        emit ClosedGhostStake(
            daysOld,
            secondsOld,
            _stakingId
        );
    }

    /**
        * @notice calculates number of days and remaining seconds on current day that a stake is open
        * @param _stakingId ID of the stake, used as the Key from the stakeList mapping
        * @return daysTotal -- number of complete days that the stake has been open
        * @return secondsToday -- number of seconds the stake has been open on the current day
     */
    function getStakeAge(
        uint256 _stakingId
    )
        public
        view
        returns (
            uint256 daysTotal,
            uint256 secondsToday
        )
    {
        StakeElement memory _stakeElement = stakeList[_stakingId];

        uint256 secondsTotal = getNow()
            .sub(_stakeElement.stakedAt);

        daysTotal = secondsTotal
```
