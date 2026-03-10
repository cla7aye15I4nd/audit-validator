// SPDX-License-Identifier: UNLICENSED
// Copyright 2025, GigaStar Technologies LLC, All Rights Reserved, https://gigastar.io
pragma solidity ^0.8.29;

import './IBox.sol';
import './IContractUser.sol';
import './LibraryTI.sol';
import './Types.sol';

/// @dev Transfer Manager for transfers and proposal management
// prettier-ignore
interface IXferMgr is IContractUser {
    // ────────────────────────────────────────────────────────────────────────────
    // Types
    // ────────────────────────────────────────────────────────────────────────────

    // ───────────────────────────────────────
    // Enums
    // ───────────────────────────────────────
    // Every first enum item must be a suitable zero-value

    /// Internally `XferStatus` behaves as as transfer result since the value is invalid until post-execution
        /// - Externally the value behaves as a transfer status since pre-executed values are masked on retrieval to
    ///   `Pending`, see see XFER_NOT_EXEC for details
    enum XferStatus { Pending, Sent, Skipped, Failed, Canceled }

    /// Values < `ProgressPartition` show progress, other values show an error
    enum AddXferRc { PartPage, FullPage, AllPages,
                    ProgressPartition, // Metadata: Preceding codes show progress
                    NoProp, ReadOnly, BadPage, BadIndex, BadTotal, BadLine, LowGas }

    /// `Ok` shows success, other values show an error
    enum AddXferLrc { Ok, LowFunds, BadEid, BadQty, SelfXfer, NativeSrc, NativeAddr, MintBurn }

    /// `Ok` shows success, other values show an error
    enum PropXferFinalRc { Ok, NoProp, PropStat }

    /// Values < `ProgressPartition` show progress, other values show an error
    enum ExecXferRc { Progress, Done,
                    ProgressPartition, // Metadata: Preceding codes show progress
                    NoProp, PartProp, PropStat }

    // ───────────────────────────────────────
    // Errors
    // ───────────────────────────────────────

    // ───────────────────────────────────────
    // Events
    // ───────────────────────────────────────
    event TokenAdminListUpdated(address token, bool admin);

    // Xfers
    event XfersUploaded(uint indexed pid, UUID indexed reqId, uint iBegin, uint uploaded);
    event XfersProcessed(uint indexed pid, UUID indexed reqId, uint iBegin, uint count, uint fails, string tokSym);
    event XfersPruned(uint indexed pid, UUID indexed reqId, uint pruned);
    event XfersDeleted(uint indexed pid, UUID indexed reqId, uint deleted, uint xfersLen);
    event XferErr(address from, address to, uint qty, bool isClaim, bool isErc20); // No index in tight-loop

    // ───────────────────────────────────────
    // Structs (See MEM_LAYOUT)
    // ───────────────────────────────────────

    /// @dev Transfer i/o
    /// - Performance: Fields are packed/reordered to optimize slot usage in a simple `abi.encode` compatible way
    /// - Upgradability skipped for performance (fast-loop storage), though not all bytes are used
    /// - NOTE: CRT qty is not scaled, USDC qty is scaled by the token's decimals(6) (qty x 1,000,000)
    struct Xfer { //            Slot, Bytes: Description
        UUID eid;               /// 0,  0-15: Transfer External ID, provides a more reliable/resilient off-chain sync
        address from;           /// 1,  0-20: Sender,    See `ExplicitMint`, `ExplicitBurn`, `ContractHeld`
        address to;             /// 2,  0-20: Recipient, See `ExplicitMint`, `ExplicitBurn`, `ContractHeld`
        uint64 tokenId;         /// 2, 21-28: Used with TI.TokenTypeErc1155, must be >0
        XferStatus status;      /// 2,    29: Set after transfer and only valid if iXfer > pageIndex
        uint qty;               /// 3,   all: Qty to transfer w/ token's scale, where: 0 < qty < balanceOf(from)
        UUID fromEid;           /// 4,  0-15: Sender External ID; For balance tracking
        UUID toEid;             /// 5, 16-31: Recipient External ID; For future use
    }

    /// @dev Lightweight subset of `Xfer` for inspecting results
    /// - Upgradability skipped as type is ephemeral
    struct XferLite { //            Slot, Bytes: Description
        UUID eid;               /// 0,  0-15: Transfer External ID, provides a more reliable/resilient off-chain sync
        XferStatus status;      /// 0,    16: Set after transfer and only valid if iXfer > pageIndex
    }

    /// @dev A simulated balance over a sequence of transfers
    /// - Upgradability skipped for performance (fast-loop storage), though not all bytes are used
    struct SimBal { //          Slot, Bytes: Description
        int balance;            /// 0,   all: Running sum; Signed integer allows for a deficit
        bool seen;              /// 1,     0: Whenter this is the first balance in a sequence
    }

    /// @dev Tracks state for a Transfer Proposal (`PropType.Xfer`)
    /// - Contains a series of transfers
    /// - Supplements `IVault.Prop` to mitigate contract size limits
    /// - Upgradability provides backwards compatibility in storage
    struct Prop {
        PropHdr hdr;                        /// Most fields (excluding dynamic fields)
        Xfer[] xfers;                       /// Transfer inputs
        mapping(UUID => SimBal) srcSimBals; /// Simulated source balances to avoid balance underflows

        // slither-disable-next-line unused-state (Space reserved for future use - upgradability)
        uint[5] __gap; // Always last field, for upgradeability, reduce size by slots used for new fields
    }

    /// @dev Tracks state for a Transfer Proposal (`PropType.Xfer`)
    /// - A separate header without dynamic fields allows a view function to easily copy it
    /// - Linked to a general Vault proposal via `pid`
    /// - Upgradability provides backwards compatibility in storage
    struct PropHdr {
        uint pid;               /// Proposal ID
        UUID eid;               /// External ID, Request ID during create, unique amongst proposals
        bool isRevDist;         /// true: simulate balances via `RevMgr` checks
        uint iXfer;             /// Next transfers index for execution
        uint uploadedAt;        /// block.timestamp when fully uploaded
        uint executedAt;        /// block.timestamp when fully executed
        TI.TokenInfo ti;        /// Token information affects required inputs and execution logic

        // slither-disable-next-line unused-state (Space reserved for future use - upgradability)
        uint[5] __gap; // Always last field, for upgradeability, reduce size by slots used for new fields
    }

    /// @dev Input to `propAddXfers`
    /// - Bundles vars to reduce stack pressure
    /// - Upgradability is not a concern for this ephemeral type
    struct PropAddXfersReq {
        uint pid;        /// Proposal ID, identifies an existing transfer proposal
        uint iAppend;    /// Proposal's transfer index to append at, helps ensure data integrity
        uint total;      /// Total transfers to be uploaded in the proposal across all pages
        Xfer[] page;     /// A non-empty page of xfers, unique accounts (coalesced). See SENTINEL_ADDRESS, PAGE_REQUESTS
    }

    // ────────────────────────────────────────────────────────────────────────────
    // Functions
    // ────────────────────────────────────────────────────────────────────────────

    // ───────────────────────────────────────
    // Setup
    // ───────────────────────────────────────

    function initialize(address creator, UUID reqId) external;

    function updateTokenAdminList(uint40 seqNumEx, UUID reqId, address tokAddr, bool add) external;

    // ───────────────────────────────────────
    // Operations: Xfer Proposal
    // ───────────────────────────────────────

    function propCreate(uint pid, UUID reqId, TI.TokenInfo memory ti, bool isRevDist) external;

    function propAddXfers(uint40 seqNumEx, UUID reqId, PropAddXfersReq calldata req) external;

    function propFinalize(uint pid) external view returns(PropXferFinalRc rc);

    function propExecute(uint pid) external returns(CallRes memory result);

    function propPruneXfers(uint40 seqNumEx, UUID reqId, uint pid, uint[] calldata skipIndexes) external;

    // ───────────────────────────────────────
    // Getters
    // ───────────────────────────────────────

    function inTokenAdminList(address tokAddr) external view returns(bool);

    function getTokenBalances(address tokAddr, TI.TokenType tokType, address[] calldata accounts)
        external view returns(uint[] memory balances);

    // ───────────────────────────────────────
    // Getters: Proposal
    // ───────────────────────────────────────

    function getPropHdr(uint pid) external view returns(PropHdr memory);

    function getXferExecIndex(uint pid) external view returns(uint);

    function getXfersLen(uint pid) external view returns(uint);

    function getXfers(uint pid, uint iBegin, uint count) external view returns(Xfer[] memory results);

    function getXferLites(uint pid, uint iBegin, uint count) external view returns(XferLite[] memory results);
}
