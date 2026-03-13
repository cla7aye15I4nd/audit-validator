// SPDX-License-Identifier: UNLICENSED
// Copyright 2025, GigaStar Technologies LLC, All Rights Reserved, https://gigastar.io
pragma solidity ^0.8.29;

import './IBox.sol';
import './IBoxMgr.sol';
import './IContractUser.sol';
import './LibraryOI.sol';
import './Types.sol';

/// @dev Instrument revenue tracking and proposal management
// prettier-ignore
interface IRevMgr is IContractUser {
    // ────────────────────────────────────────────────────────────────────────────
    // Types
    // ────────────────────────────────────────────────────────────────────────────

    // ───────────────────────────────────────
    // Enums
    // ───────────────────────────────────────
    // Every first enum item must be a suitable zero-value

    enum AddOwnRc { PartPage, FullPage, AllPages,
                    ProgressPartition, // Metadata: Preceding codes show progress
                    NoProp, ReadOnly, NoInstRev, Exists, NotFound, BadPage, BadIndex, BadTotal, BadLine, LowGas }

    enum PropRevFinalRc { Ok, NoProp, DiffLens, NoInstRev, PartOwners, AllocFixes }

    enum ExecRevRc { Progress, Done,
                     ProgressPartition, // Metadata: Preceding codes show progress
                     NoProp, PartProp, LowFunds, NoOwners, NoInstRev, PropStat }

    enum PruneRevRc { Done, NoProp, PropStat, NoInst, LastInst, MidBal }

    // ───────────────────────────────────────
    // Events
    // ───────────────────────────────────────

    event OwnersUploaded(uint pid, string instName, uint earnDate, uint count);

    event AllOwnersUploaded(uint pid, string instName, uint earnDate, uint snapshotsLen);

    event PropPruned(uint pid, string instName, uint earnDate);

    event RevenueAllocated(uint pid, string instName, uint earnDate,
        uint owners, uint totalQty, uint totalRev, uint unitRev);

    // ───────────────────────────────────────
    // Errors
    // ───────────────────────────────────────
    error RevDiff(uint pid, string instName, uint earnDate, uint ownerRev, uint instRev);

    // ───────────────────────────────────────
    // Structs (See MEM_LAYOUT)
    // ───────────────────────────────────────

    /// @dev Tracks state for an Instrument Revenue Proposal (`PropType.InstRev`)
    /// - Contains a series of ownership snapshots
    /// - Supplements `IVault.Prop` and `IInstRevMgr.Prop` to mitigate contract size limits
    /// - Upgradability provides backwards compatibility in storage
    struct Prop {
        PropHdr hdr;            /// Most fields (excluding dynamic fields)
        OI.Emap ownSnaps;       /// Key: InstName, EarnDate, [ownerEid]; Owner's qty and revenue

        // slither-disable-next-line unused-state (Space reserved for future use - upgradability)
        uint[5] __gap; // Always last field, for upgradeability, reduce size by slots used for new fields
    }

    /// @dev Tracks state for an Instrument Revenue Proposal (`PropType.InstRev`)
    /// - A separate header without dynamic fields allows a view function to easily copy it
    /// - Linked to a general Vault proposal via `pid`
    /// - Upgradability provides backwards compatibility in storage
    struct PropHdr {
        uint pid;               /// Proposal ID
        uint totalRevenue;      /// Total revenue in proposal
        uint iInst;             /// Instrument cursor used during execution
        uint iOwner;            /// Owner cursor used during execution
        uint iRevFix;           /// `revFixes` cursor used during execution
        uint uploadedAt;        /// block.timestamp when proposal is fully uploaded
        uint executedAt;        /// block.timestamp when proposal is fully executed
        UUID eid;               /// External ID, Request ID during create, unique amongst proposals
        bool correction;        /// Whether the proposal is a correction

        // slither-disable-next-line unused-state (Space reserved for future use - upgradability)
        uint[5] __gap; // Always last field, for upgradeability, reduce size by slots used for new fields
    }

    /// @dev Input to `propAddOwners`
    /// - Bundles vars to reduce stack pressure
    /// - Upgradability is not a concern for this ephemeral type
    struct AddOwnersReq {
        uint pid;               /// Proposal ID
        uint iAppend;           /// Related to `getOwnInfosLen`
        uint total;             /// Count of owners across pages to be uploaded for a key=(instName,earnDate)
        string instName;        /// Instrument name, string version of `instNameKey`, max len 32 chars
        uint earnDate;          /// Earn date
        OI.OwnInfo[] page;      /// A page of items to upload; Excludes prior successfully uploaded items
    }

    // ────────────────────────────────────────────────────────────────────────────
    // Functions
    // ────────────────────────────────────────────────────────────────────────────

    // ───────────────────────────────────────
    // Setup
    // ───────────────────────────────────────

    function initialize(address creator, UUID reqId) external;

    // ───────────────────────────────────────
    // Operations: Instrument Revenue Proposal
    // ───────────────────────────────────────

    function propCreate(uint pid, UUID reqId, address ccyAddr, bool correction) external;

    // For `propAddInstRev` and `propAddInstRevAdj` see InstRevMgr

    function propAddOwners(uint40 seqNumEx, UUID reqId, AddOwnersReq calldata req) external;

    function propFinalize(uint pid) external returns(PropRevFinalRc rc);

    function propExecute(uint pid) external returns(CallRes memory result);

    function pruneProp(uint pid, string calldata instName, uint earnDate) external returns(PruneRevRc rc);

    // ───────────────────────────────────────
    // Getters: Proposal
    // ───────────────────────────────────────

    function getPropHdr(uint pid) external view returns(PropHdr memory);

    // ───────────────────────────────────────
    // Getters: Instrument Revenue - See InstRevMgr
    // ───────────────────────────────────────

    // ───────────────────────────────────────
    // Getters: Owner Information (Proposal or Executed)
    // ───────────────────────────────────────

    function getOwnInfo(uint pid, string calldata instName, uint earnDate, UUID ownerEid) external view
        returns(uint revenue, uint qty);

    // `function getOwnInfos(uint pid)` does not exist as it's not worth the extra size, and it would require
    // iterating over 2 dimensions (snapshots and owners for each). A caller can call with instName and earnDate via
    // known inputs or `EarnDateMgr` enumerations if pid=0 (executed state) or via `getInstRevs` with pid=0 or >0

    function getOwnInfosLen(uint pid, string calldata instName, uint earnDate) external view
        returns(uint len, uint uploadedAt, uint executedAt);

    function getOwnInfos(uint pid, string calldata instName, uint earnDate, uint iBegin, uint count) external view
        returns(OI.OwnInfo[] memory ownInfos);
}
