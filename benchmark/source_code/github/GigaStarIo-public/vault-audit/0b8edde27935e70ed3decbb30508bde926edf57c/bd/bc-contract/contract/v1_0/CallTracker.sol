// SPDX-License-Identifier: UNLICENSED
// Copyright 2025, GigaStar Technologies LLC, All Rights Reserved, https://gigastar.io
pragma solidity ^0.8.29;

import './ICallTracker.sol';

// slither-disable-start dead-code (Functions are optimized away where unused though all used somewhere)

/// @notice A call tracker for write functions to resolve the 'Uncertain outcome problem' where an off-chain
/// request is made and a failure can occur at any time/location such that the client cannot easily know the
/// outcome of the call. A call may be lost, dropped, in-flight, reverted, completed, duplicated, reorg, etc.
/// @dev Allows a write function result to be persisted to provide off-chain client call certainty at the
///   application level. In the most simple case, a client makes a call that is executed on-chain but the client
///   was disconnected before getting a tx hash or receipt. The client needs to be able to determine both whether
///   the call was executed and the outcome. A simplification to the client experience is idempotency such that
///   in-flight and duplicate calls can be ignored by resubmitting the call with assurance that calls with lower
///   sequence numbers will be ignored. This monotonically increasing sequence number can also detect block reorgs
///   which could erase the history of completed txs. Recovery from such a situation is context specific but the
///   role of this contract is to detect such an event to maintain data consistency.
/// - These mechanisms also provide context where each is lacking in isolation but more effective together:
///     - View functions: Show if/how state was updated such as calling `getCallRes` or similar persisted effects
///     - Events: Complicated by search/parse/topic/arg issues and connection flaps
/// @custom:api private
/// @custom:deploy none
abstract contract CallTracker is ICallTracker {
    // ────────────────────────────────────────────────────────────────────────────
    // Fields
    // ────────────────────────────────────────────────────────────────────────────
    mapping(address => mapping(uint40 => CallRes)) _crBySeqNum; // Key: caller, seqNum; idempotent CallResult
    mapping(address => uint40) _seqNums; // Key: caller; Montonotically increasing sequence number per caller
    mapping(UUID => CallRes) _crByReqId; // Key: Request ID; Ensures idempotency per request ID and allows replay

    // slither-disable-next-line unused-state (Space reserved for future use - upgradability)
    uint[10] __gapCallTracker; // Always last field, for upgradeability, reduce size by slots used for new fields

    // ────────────────────────────────────────────────────────────────────────────
    // Functions
    // ────────────────────────────────────────────────────────────────────────────

    /// @dev Initializes contract
    /// @param creator Account that created this contract
    /// @param reqId Request ID, unique amongst requests across all callers
    function __CallTracker_init(address creator, UUID reqId) internal {
        _setCallRes(creator, 1, reqId, true); // For off-chain sequencing
    }

    // ───────────────────────────────────────
    // Getters
    // ───────────────────────────────────────

    /// @dev Get next expected seq num for the given account address
    /// @param account Address to lookup
    /// @return seqNumEx Next expected seq num to be passed to a write function call from `account`
    function getSeqNum(address account) external view override returns(uint40 seqNumEx) {
        seqNumEx = _seqNums[account];
        return seqNumEx > 0 ? seqNumEx : 1;
    }

    /// @dev Get a result for a prior write function call invoked from off-chain by this caller
    /// - Subject to storage lag when retrieved off-chain shortly after write, prefer the `ReqAck` event in that case
    /// @param seqNum Sequence number of a prior call by this caller
    /// @return cr See `CallRes`
    /// @custom:api public
    function getCallResBySeqNum(uint40 seqNum) external view override returns(CallRes memory cr) {
        if (seqNum == 0) {
            seqNum = _seqNums[msg.sender]; // Get next expected seq num
            if (seqNum > 0) --seqNum;      // Get prev seq num
        }
        return _crBySeqNum[msg.sender][seqNum];
    }

    /// @dev Get a result for a prior write function call invoked from off-chain by this caller
    /// - Subject to storage lag when retrieved off-chain shortly after write, prefer the `ReqAck` event in that case
    /// @param reqId Request ID of a prior call
    /// @return cr See `CallRes`
    /// @custom:api public
    function getCallResByReqId(UUID reqId) external view override returns(CallRes memory cr) {
        return _crByReqId[reqId];
    }

    // ───────────────────────────────────────
    // Sequence number management
    // ───────────────────────────────────────

    /// @dev Provides reliability and idempotency, see RELIABLE_IDEMPOTENT
    /// - There are 2 seq num expectations here: 1) off-chain: `seqNum`, 2) on-chain: `_seqNums[caller]`
    /// - Replays `ReqAck` event if necessary
    /// - Each path has a case from the RELIABLE_IDEMPOTENT table
    /// - Tracking is per contract - no protection is offered when reusing a `reqId` across contracts
    /// @param caller External caller
    /// @param seqNum 0: On-chain caller; >0: Expected seq num for ordering, 1:1 request/response, reorg detection
    /// @param reqId Request ID, unique amongst requests across all callers
    /// @return Whether the request is a replay: (seqNum < expected) AND (caller,seqNum,reqId) same as original call
    function _isReqReplay(address caller, uint40 seqNum, UUID reqId) internal returns(bool) {
        if (seqNum == 0) return false; // Hot path for on-chain calls; No tracking (reliability guaranteed)

        uint40 nextExpected = _seqNums[caller];  // Get next expected seqNum
        bool isNewReqId = _crByReqId[reqId].blockNum == 0;
        // Check if `reqId` has been used by any caller
        if (isNewReqId) { // then new `reqId`
            // Compare `seqNum` vs next expected
            if (nextExpected == 0) nextExpected = 1; // First call by `caller`
            if (nextExpected == seqNum) {            // Received matched expected
                _seqNums[caller] = seqNum + 1;       // Accept request, advance expected seq num
                return false;                        // Case 0100; Hot path for off-chain calls
            }

            if (seqNum > nextExpected) { // then client out-of-sync, possibly client problem or block reorg
                revert SeqNumGap(nextExpected, seqNum, caller); // Case 0200
            }
            // Case 0000; `seqNum` < expected with a different `reqId` => error
        } else {
            // Check if replay allowed
            CallRes memory cr = _crBySeqNum[caller][seqNum];
            if (UUID.unwrap(cr.reqId) == UUID.unwrap(reqId)) {
                // Replay cached result with same (caller,seqNum,reqId) as a prior call
                // - Flag indicates replay; `reqId` can be used to recover related events
                emit ReqAck(reqId, caller, seqNum, cr, true);
                return true; // Case 0011
            }
            // Cases 0012, 0112, 0212;
            // - Different (caller,seqNum) than original `reqId` usage
            // - Case not allowed to ensure idempotency and when the full key does not match then assumed that there
            //   could be a problem with the input and/or order changing, both of which could invalidate the result
            // - For simplicity `reqId` identifies the request inputs but hashing would be another or supplemental
            //   approach though it would significantly increase SIZE as the hash would occur per external call
            // - Original caller cannot be easily known here but can be found by searching for `ReqAck` by `reqId`
        }

        // Client issue, see the cases above that can lead here and x-ref with the RELIABLE_IDEMPOTENT table
        UUID oldReqId = _crBySeqNum[caller][seqNum].reqId;
        revert RequestKeyConflict(isNewReqId, nextExpected, seqNum, oldReqId, reqId);
    }

    /// @dev Store call result, increment sequence number, and emit a `ReqAck` event
    function _setCallRes(address caller, uint40 seqNum, UUID reqId, CallRes memory cr) internal {
        if (seqNum == 0) return;
        _setCallRes(caller, seqNum, reqId, cr.rc, cr.lrc, cr.count);
    }

    /// @dev Store call result, increment sequence number, and emit a `ReqAck` event
    /// - Simplifies caller by handling `CallRes` creation for a general boolean case
    function _setCallRes(address caller, uint40 seqNum, UUID reqId, bool ok) internal {
        if (seqNum == 0) return;
        return _setCallRes(caller, seqNum, reqId, ok ? 1 : 0, 0, 0);
    }

    /// @dev Store call result, increment sequence number, and emit a `ReqAck` event
    /// - Simplifies caller by handling `CallRes` creation yet provides control of all inputs
    function _setCallRes(address caller, uint40 seqNum, UUID reqId, uint16 rc, uint16 lrc, uint16 count) internal {
        if (seqNum == 0) return;

        CallRes memory cr = CallRes({
            reqId: reqId,
            rc: rc,
            lrc: lrc,
            count: count,
            blockNum: uint40(block.number),
            reserved: 0
        });

        // Track result via event (in tx receipt) and storage (easier to lookup by seqNum after storage lag)
        // - See `ReqAck` definition for more
        emit ReqAck(reqId, caller, seqNum, cr, false);
        _crBySeqNum[caller][seqNum] = cr;
        _crByReqId[reqId] = cr;
    }
}

// slither-disable-end dead-code
