// SPDX-License-Identifier: UNLICENSED
// Copyright 2025, GigaStar Technologies LLC, All Rights Reserved, https://gigastar.io
pragma solidity ^0.8.29;

import './IBox.sol';
import './IContractUser.sol';
import './IRevMgr.sol';
import './LibraryIR.sol';
import './Types.sol';

/// @dev Instrument revenue tracking and proposal management
// prettier-ignore
interface IInstRevMgr is IContractUser {
    // ────────────────────────────────────────────────────────────────────────────
    // Types
    // ────────────────────────────────────────────────────────────────────────────

    // ───────────────────────────────────────
    // Enums
    // ───────────────────────────────────────
    // Every first enum item must be a suitable zero-value

    enum AddInstRc { PartPage, FullPage, AllPages,
                     ProgressPartition, // Metadata: Preceding codes show progress
                     NoProp, ReadOnly, BadPage, BadIndex, BadTotal, BadLine, LowFunds, LowGas }

    enum AddInstLineRc { Ok, InstName, TotalQty, EarnDate, QtyDec, RevRemain, SubtotalRev, TotalRev, LowFunds,
                         PropHas2, Exists }

    // ───────────────────────────────────────
    // Events
    // ───────────────────────────────────────
    event InstAllocFixUploaded(uint pid, string instName, uint earnDate, uint uploaded, uint total);

    event InstRevUploaded(uint pid, string instName, uint earnDate,
        uint totalQty, uint totalRev, uint unitRev, bool correction);

    event AllInstRevUploaded(uint pid, uint total);

    event LowFundsErr(uint pid, string instName, uint earnDate, address ccyAddr, address from,
        uint balance, uint required);

    event RevenueXfer(uint pid, string instName, uint earnDate, bool success, bool correction,
        address ccyAddr, address from, address to, uint qty);

    // ───────────────────────────────────────
    // Structs (See MEM_LAYOUT)
    // ───────────────────────────────────────

    /// @dev Tracks state for an Instrument Revenue Proposal (`PropType.InstRev`)
    /// - Contains a series of instrument revenue and a series of ownership snapshots
    /// - Supplements `IVault.Prop` and `IRevMgr.Prop` to mitigate contract size limits
    /// - Upgradability provides backwards compatibility in storage
    struct Prop {
        PropHdr hdr;
        IR.Emap instRevs;                       /// Key: InstName, EarnDate; Instrument revenue
        mapping(bytes32 => uint) instRevSums;   /// Key: InstName; Sum revenue per instrument (across earn dates)
        mapping(bytes32 => mapping(uint =>
            InstAllocFix)) allocFixes;          /// Key: InstName, EarnDate; Inst allocation fixes

        // slither-disable-next-line unused-state (Space reserved for future use - upgradability)
        uint[5] __gap; // Always last field, for upgradeability, reduce size by slots used for new fields
    }

    /// @dev Tracks state for an Instrument Revenue Proposal (`PropType.InstRev`)
    /// - A separate header without dynamic fields allows a view function to easily copy it
    /// - Linked to a general Vault proposal via `pid`
    /// - Upgradability provides backwards compatibility in storage
    struct PropHdr {
        uint pid;               /// Proposal ID
        UUID eid;               /// External ID, Request ID during create, unique amongst proposals
        bool correction;        /// Whether the proposal is a correction
        uint fixInstRevCount;   /// Number of InstRevs to change
        uint fixCount;          /// Number of changes in proposal
        uint uploadedAt;        /// block.timestamp when fully uploaded
        uint executedAt;        /// block.timestamp when fully executed
        address ccyAddr;        /// Revenue currency address

        // slither-disable-next-line unused-state (Space reserved for future use - upgradability)
        uint[5] __gap; // Always last field, for upgradeability, reduce size by slots used for new fields
    }

    /// @dev A revenue allocation adjustment for a single owner
    /// - Performance is a minor concern as usage would be unusual
    /// - Upgradability provides backwards compatibility in storage
    struct AllocFix {
        int revenue;            /// Revenue adjustments to existing balance
        UUID ownerEid;          /// Owner external id; Owner to adjust

        // slither-disable-next-line unused-state (Space reserved for future use - upgradability)
        uint[5] __gap; // Always last field, for upgradeability, reduce size by slots used for new fields
    }

    /// @dev `propAddInstRevAdj` input
    /// when `PropHdr.correction` is true, used to adjust/fix a previous proposal
    /// - Upgradability provides backwards compatibility in storage
    struct InstAllocFix {
        uint uploadedAt;        /// block.timestamp when fully uploaded
        int requiredFunds;      /// Funds required for all the corrections (+ or -); May direct funds to/from Vault
        AllocFix[] revFixes;    /// List of relative adjustments, set when `PropHdr.correction`

        // slither-disable-next-line unused-state (Space reserved for future use - upgradability)
        uint[5] __gap; // Always last field, for upgradeability, reduce size by slots used for new fields
    }

    /// @dev `propAddInstRev` input
    /// - Bundles vars to reduce stack pressure
    /// - Upgradability is not a concern for this ephemeral type
    struct PropAddInstRevReq {
        uint pid;           /// Proposal ID
        uint iAppend;       /// Related to `getInstRevsLen`
        uint total;         /// Number of items to be uploaded in total
        IR.InstRev[] page;  /// Page of InstRevs to be uploaded in a call
    }

    /// @dev `propAddInstRevAdj` input
    /// when `PropHdr.correction` is true, used to adjust/fix a previous proposal
    /// - Bundles vars to reduce stack pressure
    /// - Performance is a minor concern as usage would be unusual
    /// - Upgradability is not a concern for this ephemeral type
    struct AddInstRevAdjReq {
        uint pid;           /// Proposal ID
        uint iAppend;       /// Related to `getAllocFixesLen`
        uint total;         /// Number of items to be uploaded in total
        string instName;    /// Instrument name, string version of `instNameKey`, max len 32 chars
        uint earnDate;      /// key: Earn date
        int requiredFunds;  /// Revenue required for the transfer; <0 = from vault else from inst drop box
        AllocFix[] page;    /// Page of fixes to be uploaded in a call
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

    function propAddInstRev(uint40 seqNumEx, UUID reqId, PropAddInstRevReq calldata req) external;

    function propAddInstRevAdj(uint40 seqNumEx, UUID reqId, AddInstRevAdjReq calldata req) external;

    function propFinalize(uint pid) external view returns(bool);

    function propExecInstRev(uint pid, uint iInstRev) external returns(IRevMgr.ExecRevRc rc);

    function propExecuted(uint pid) external;

    function pruneProp(uint pid, string calldata instName, uint earnDate) external
        returns(IRevMgr.PruneRevRc rc, uint totalRev);

    // ───────────────────────────────────────
    // Getters: Proposal
    // ───────────────────────────────────────

    function getPropHdr(uint pid) external view returns(PropHdr memory);

    function getAllocFixesLen(uint pid, string calldata instName, uint earnDate) external view returns(uint);

    function getAllocFixesLenByKey(uint pid, bytes32 instNameKey, uint earnDate) external view returns(uint);

    function getAllocFix(uint pid, string calldata instName, uint earnDate, uint iAllocFix) external view
        returns(int revenue, UUID ownerEid);

    function getAllocFixByKey(uint pid, bytes32 instNameKey, uint earnDate, uint iAllocFix) external view
        returns(int revenue, UUID ownerEid);

    function validateInstRev(uint pid, IR.InstRev calldata instRev, bool correction) external view
        returns(AddInstLineRc rc);

    // ───────────────────────────────────────
    // Getters: Instrument Revenue (Proposal or Executed)
    // ───────────────────────────────────────

    function getInstRevsLen(uint pid, string calldata instName, uint earnDate) external view returns(uint);

    function getInstRevs(uint pid, string calldata instName, uint earnDate, uint iBegin, uint count)
        external view returns(IR.InstRev[] memory results);

    function getInstRev(uint pid, uint iInst) external view returns(IR.InstRev memory);

    function getInstRevForInstDate(uint pid, string calldata instName, uint earnDate) external view
        returns(IR.InstRev memory);
}
