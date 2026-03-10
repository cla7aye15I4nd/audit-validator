// SPDX-License-Identifier: UNLICENSED
// Copyright 2025, GigaStar Technologies LLC, All Rights Reserved, https://gigastar.io
pragma solidity ^0.8.29;

import './Types.sol';

/// @dev Call result and account sequence number tracking
///
/// ## Reliability and Idempotency (RELIABLE_IDEMPOTENT)
///
/// To safeguard against subtle off-chain call issues, contracts enforce reliability and idempotency
/// via these design principles
///
/// **1. FIFO and dependency handling**
/// - Off-chain producers ensure requests are executed in FIFO order
///   - Implies each proposal should only be voted on after prior ones are approved or final
///   - Exceptions may exist for unrelated proposals, but uniform FIFO simplifies correctness
/// - Each off-chain queue produces requests with a UUID (`reqId`) used as the proposal ID
///   - Every contract write call in that sequence is a deterministic descendant of the `reqId`
/// - Each queue should be serviced by exactly one on/off-chain agent to preserve FIFO
///   - Throughput can be increased by segmenting unrelated requests into separate queues
///   - More than one agent per queue risks race conditions and replay errors
///   - A single agent can manage multiple queues, but debugging complexity increases
///
/// **2. Sequence tracking**
/// - Each contract tracks a monotonically increasing sequence number (`seqNum`) per caller
/// - `seqNum` is incremented after each accepted state-changing call
/// - It enforces FIFO ordering for each caller
///
/// **3. Request identity tracking**
/// - Each request has a unique `reqId`, globally unique across all callers
///   - Tracking is per contract - no protection is offered when reusing a `reqId` across contracts
/// - If `(caller, seqNum, reqId)` matches a prior call:
///   - The duplicate is idempotent so no state changes occur
///   - The previous `CallRes` is replayed (may be a summary, can be used to recover prior events)
/// - If two agents share a queue: (don't do it)
///   - *Independent agents*: race may occur; first call succeeds, second reverts
///   - *Coordinated agents*: even with exclusive access to each `reqId`, complexities may still exist
///      related to both dependencies: a) between requests and b) between calls for the same request
///
/// ---
///
/// ### Request Outcome Matrix
///
/// ```
/// +-----------------------------------------------------------------------------------------+
/// |------|   Request Input Factors   |       Outcome                                        |
/// +------+-----------+-------+-------+---------+--------------------------------------------+
/// | Case |  SeqNum   | ReqId | Allow | Action  | Description                                |
/// +------+-----------+-------+-------+---------+--------------------------------------------+
/// | 0000 |  < expect | New   | N/A   | REJECT  | Stale seqNum with new reqId (invalid)      |
/// | 0011 |  < expect | Reuse | Yes   | REPLAY  | Replay prior req, same (caller, seqNum)    |
/// | 0012 |  < expect | Reuse | No    | REJECT  | Invalid replay, different (caller, seqNum) |
/// | 0100 | == expect | New   | N/A   | ACCEPT  | Valid next FIFO request, state change      |
/// | 0111 | == expect | Reuse | Yes   | INVALID | Unreachable (curr seq can’t match prior)   |
/// | 0112 | == expect | Reuse | No    | REJECT  | Invalid replay, mismatched seqNum          |
/// | 0200 |  > expect | New   | N/A   | REJECT  | Future seqNum (FIFO violation)             |
/// | 0211 |  > expect | Reuse | Yes   | INVALID | Unreachable (future seq can’t match prior) |
/// | 0212 |  > expect | Reuse | No    | REJECT  | Future seqNum (FIFO violation)             |
/// +------+-----------+-------+-------+---------+--------------------------------------------+
/// ```
///
/// **Rules**
/// - `Allow` (Allow `reqId` reuse), `Yes`: prior call had *same* (caller,seqNum,reqId); `No`: `reqId` must be new
/// - `seqNum` must increase monotonically per caller (FIFO) for a write to occur; else a replay or error
/// - Each `(caller, seqNum)` uniquely maps to one `reqId`
/// - Each `(caller, reqId)` uniquely maps to one `seqNum`
/// - Reuse never advances `seqNum`; it is always either idempotent (replay) or an error
///
interface ICallTracker {
    // ────────────────────────────────────────────────────────────────────────────
    // Types
    // ────────────────────────────────────────────────────────────────────────────

    // ───────────────────────────────────────
    // Events
    // ───────────────────────────────────────

    /// @dev A Request Acknowledgement Event occurs at the end of each request (if no revert) and bridges the gaps
    /// between data sources, clients, lossy/unreliable protocols/providers/neworks, and the on-chain call outcome
    /// - Captures 3 categories of data for off-chain calls:
    ///     - Key inputs (indexed params) allow a tx search via either:
    ///         - PK1: reqId: Allows a tx search on a single field such as to fill a gap on replay
    ///         - PK2: (caller,seqNum): Allows a tx search to audit a sequence for a caller
    ///     - Context: `replay` and `callRes.blockNum` provide context on when/where this happened
    ///     - Output: `callRes` provides fields (rc, lrc, count) for either a simple result or summary
    ///         - Additional results can be found in the tx receipt logs from prior events in the same tx
    /// @param reqId From CallRes: Request ID, allows for gap-fill on replay
    /// @param caller Account initiating the tx
    /// @param seqNum From CallRes: Caller's sequence number incremented monotonically
    /// @param callRes See `CallRes`; `reqId` and `ReqAck` are separate params for indexes
    /// @param replay false for an original event, true when `reqId` was already processed
    event ReqAck(UUID indexed reqId, address indexed caller, uint40 indexed seqNum, CallRes callRes, bool replay);

    // ───────────────────────────────────────
    // Errors
    // ───────────────────────────────────────

    /// @dev Occurs when seq num `rcvd` > `expect`, possible causes: error from network/provider/client/reorg
    ///     - Invariant: `seqNum` must increment monotonically for a write call, see table above
    /// @param seqNumExp Expected sequence number
    /// @param seqNumAct Received sequence number
    /// @param caller Caller's address
    error SeqNumGap(uint40 seqNumExp, uint40 seqNumAct, address caller);

    /// @dev Occurs during a request where (`reqId` is reused and/or `seqNum` < expected) and the prior call had
    /// a different key (caller,seqNum,reqId) so replay does not occur as it otherwise could
    /// @param isNewReqId true: `reqIdAct` is new; false: value was reused with a different (caller,seqNum)
    /// @param seqNumExp Expected sequence number based upon caller
    /// @param seqNumAct Actual sequence number received
    /// @param reqIdExp Expected request id, based upon cache lookup by (caller,seqNum); Zero-value if !`isNewReqId`
    /// @param reqIdAct Actual request id received
    error RequestKeyConflict(bool isNewReqId, uint40 seqNumExp, uint40 seqNumAct, UUID reqIdExp, UUID reqIdAct);

    // ───────────────────────────────────────
    // Structs (See MEM_LAYOUT)
    // ───────────────────────────────────────

    /// @dev An off-chain write function call result summary (possibly a full result for simple return values)
    /// - Optimized for load/store via field packing into 1 slot
    /// - Integrated with `ReqAck` event for a call result per tx receipt to avoid node storage store/load lag
    /// - Seq nums are tracked separately as they are per caller whereas results are per request ID (all callers)
    /// - More on fields:
    ///     - Tracking a seq num (8 B) would also require a caller address (20 B) - bloating this struct to 2 slots
    ///     - (rc, lrc, count) are call specific (eg may have enums to decode meaning or used as bools)
    ///     - Block number allows a single block get to replay tx events rather than O(N) on (caller,seqNum)
    ///     - Request ID is generated off-chain, links request/response, provides idempotency beyond seqNums
    struct CallRes { //  Slot, Bytes: Range,       Description
        UUID   reqId;    // 0,  0-15: See UUIDv7,  Request ID for idempotency and off-chain seqNum gap recover
        uint16 rc;       // 0, 16-17: Max: 65,535, Call return code: Often relates to call status/progress
        uint16 lrc;      // 0, 18-19: Max: 65,535, Line return code: Often relates to a line/item
        uint16 count;    // 0, 20-21: Max: 65,535, Item count: Often relates to items processed
        uint40 blockNum; // 0, 22-26: Max: ~1.1T,  From `block.blockNumber` for replay to find original tx
        uint40 reserved; // 0, 27-31:              Reserved
    }

    // ────────────────────────────────────────────────────────────────────────────
    // Functions
    // ────────────────────────────────────────────────────────────────────────────

    // ───────────────────────────────────────
    // Getters
    // ───────────────────────────────────────

    function getSeqNum(address account) external view returns(uint40);

    function getCallResBySeqNum(uint40 seqNum) external view returns(CallRes memory);

    function getCallResByReqId(UUID reqId) external view returns(CallRes memory cr);
}
