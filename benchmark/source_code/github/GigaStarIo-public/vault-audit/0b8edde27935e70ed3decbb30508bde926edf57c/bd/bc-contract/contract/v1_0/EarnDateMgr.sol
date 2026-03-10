// SPDX-License-Identifier: UNLICENSED
// Copyright 2025, GigaStar Technologies LLC, All Rights Reserved, https://gigastar.io
pragma solidity ^0.8.29;

import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';

import './ContractUser.sol';
import './IEarnDateMgr.sol';
import './LibraryAC.sol';
import './LibraryEMAP.sol';
import './LibraryCU.sol';
import './LibraryString.sol';

/// @title EarnDateMgr: An instrument name and earn date manager
/// @author Jason Aubrey, GigaStar
/// @notice Allows a caller to enumerate instruments, earn dates, and combinations of each
/// @dev Insulates RevMgr from bytecode size
/// - Upgradeable via UUPS. See PROXY_OPTIONS for more.
/// @custom:api public
/// @custom:deploy uups
// prettier-ignore
contract EarnDateMgr is Initializable, UUPSUpgradeable, IEarnDateMgr, ContractUser {
    // ────────────────────────────────────────────────────────────────────────────
    // Constants
    // ────────────────────────────────────────────────────────────────────────────
    uint constant VERSION = 10; // 123 => Major: 12, Minor: 3 (always 1 digit)

    // ────────────────────────────────────────────────────────────────────────────
    // Fields (See MEM_LAYOUT), default visibility is 'internal'
    // ────────────────────────────────────────────────────────────────────────────
    mapping(bytes32 => EMAP.UintUint) _instToDates;     // Key: InstName => EarnDates; earnDate for each instName
    mapping(uint => EMAP.Bytes32Bytes32) _dateToInsts;  // Key: EarnDate => InstNames; instName for each earnDate
    EMAP.Bytes32Bytes32 _instNames;                     // An enumerable set of instNames  (a map used as a set)
    EMAP.UintUint _earnDates;                           // An enumerable set of earn dates (a map used as a set)

    // New fields should be inserted immediately above this line to preserve layout

    // slither-disable-next-line unused-state (Space reserved for future use - upgradability)
    uint[20] __gap; // Always last field, for upgradeability, reduce size by slots used for new fields

    // ────────────────────────────────────────────────────────────────────────────
    // Functions
    // ────────────────────────────────────────────────────────────────────────────

    // ───────────────────────────────────────
    // Access control
    // ───────────────────────────────────────

    /// @notice Access control; allow RevMgr or Creator
    function _requireRevMgrOrCreator(address caller) private view {
        if (caller == _contracts[CU.RevMgr] || caller == _contracts[CU.Creator]) return;
        revert AC.AccessDenied(caller);
    }

    // ───────────────────────────────────────
    // Setup
    // ───────────────────────────────────────

    /// @dev Ensures the logic contract cannot be hijacked before the `initializer` runs
    /// - Sets version to `type(uint64).max` + `emit Initialized(version)` to prevent future initialization
    /// - `initialize` is where the business logic is initialized on proxies
    /// - For more info see comments in 'Initializable.sol'
    /// @custom:api private
    constructor() { _disableInitializers(); } // Do not add code to cstr

    /// @dev Basically replaces the constructor in a proxy oriented contract
    /// - `initializer` modifier ensures this function can only be called once during deploy
    /// - See UUPS_UPGRADE_SEQ for details on how to upgrade this contract
    /// @param creator Creator's address for access control during setup
    /// @param reqId Request ID, unique amongst requests across all callers
    /// @custom:api protected
    function initialize(address creator, UUID reqId) external override initializer {
        __ContractUser_init(creator, reqId);
        EMAP.Bytes32Bytes32_init(_instNames);
        EMAP.UintUint_init(_earnDates);
    }

    /// @dev Upgrade hook to enforce permissions
    /// - Ensure `preUpgrade` is called before this function to stage required params
    function _authorizeUpgrade(address newImpl) internal override(UUPSUpgradeable) {
        _authorizeUpgradeImpl(msg.sender, newImpl);
    }

    /// @dev Get the current version
    function getVersion() external pure override virtual returns(uint) { return VERSION; }

    // ───────────────────────────────────────
    // Operations
    // ───────────────────────────────────────

    /// @dev Add an instrument earn date to each map, duplicates ignored
    /// @param seqNumEx =0 for on-chain caller, else expected sequence number for determinism, etc; See `CallTracker`
    /// @param reqId Request ID, unique amongst requests across all callers
    /// @param instName Instrument name
    /// @param earnDate Instrument earn date
    /// @custom:api public
    function addInstEarnDate(uint40 seqNumEx, UUID reqId, string calldata instName, uint earnDate) external override {
        address caller = msg.sender;
        _requireRevMgrOrCreator(caller); // Access control

        // If using sequence number protocol (off-chain caller) then enforce idempotency
        if (_isReqReplay(caller, seqNumEx, reqId)) return;

        // Add an earnDate for this instName
        bytes32 instNameKey = String.toBytes32(instName);
        EMAP.UintUint storage dateEmap = _instToDates[instNameKey];
        if (!EMAP.initialized(dateEmap)) EMAP.UintUint_init(dateEmap);
        EMAP.addIfNew(dateEmap, earnDate, earnDate);

        // Add an instName for this earnDate
        EMAP.Bytes32Bytes32 storage nameEmap = _dateToInsts[earnDate];
        if (!EMAP.initialized(nameEmap)) EMAP.Bytes32Bytes32_init(nameEmap);
        EMAP.addIfNew(nameEmap, instNameKey, instNameKey);

        // Add an instName
        EMAP.addIfNew(_instNames, instNameKey, instNameKey);

        // Add an earnDate
        EMAP.addIfNew(_earnDates, earnDate, earnDate);

        _setCallRes(caller, seqNumEx, reqId, true);
    }

    /// @dev Remove an instrument earn date from relevant maps, ignores unknown
    /// @param seqNumEx =0 for on-chain caller, else expected sequence number for determinism, etc; See `CallTracker`
    /// @param reqId Request ID, unique amongst requests across all callers
    /// @param instName Instrument name
    /// @param earnDate Instrument earn date
    /// @custom:api public
    function removeInstEarnDate(uint40 seqNumEx, UUID reqId, string calldata instName, uint earnDate) external override {
        address caller = msg.sender;
        _requireRevMgrOrCreator(msg.sender); // Access control

        // If using sequence number protocol (off-chain caller) then enforce idempotency
        if (_isReqReplay(caller, seqNumEx, reqId)) return;

        // Remove an earnDate for this instName
        bytes32 instNameKey = String.toBytes32(instName);
        EMAP.UintUint storage dateEmap = _instToDates[instNameKey];
        uint dateEmapLen = dateEmap.values.length;
        if (dateEmapLen >= EMAP.FIRST_INDEX) {
            EMAP.remove(dateEmap, earnDate);
            --dateEmapLen;
            if (dateEmapLen == EMAP.FIRST_INDEX) {       // then that was the last value, only sentinel item remains
                dateEmap.values.pop();                  // Remove last item, sentinel value
                // slither-disable-next-line mapping-deletion (ok since map in item to delete is empty)
                delete _instToDates[instNameKey];       // Remove empty value

                // Remove an instName
                EMAP.remove(_instNames, instNameKey);
            }
        }

        // Remove an instName for this earnDate
        EMAP.Bytes32Bytes32 storage instEmap = _dateToInsts[earnDate];
        uint instEmapLen = instEmap.inner.values.length;
        if (instEmapLen >= EMAP.FIRST_INDEX) { // then only sentinel item exists
            EMAP.remove(instEmap, instNameKey);
            --instEmapLen;
            if (instEmapLen == EMAP.FIRST_INDEX) {       // then that was the last value, only sentinel item remains
                instEmap.inner.values.pop();            // Remove last item, sentinel value
                // slither-disable-next-line mapping-deletion (ok since map in item to delete is empty)
                delete _dateToInsts[earnDate];          // Remove empty value

                // Remove an earnDate
                EMAP.remove(_earnDates, earnDate);
            }
        }

        _setCallRes(caller, seqNumEx, reqId, true);
    }

    // ───────────────────────────────────────
    // Getters: Instrument Names
    // ───────────────────────────────────────

    /// @dev Get count of all instrument names
    function getInstNamesLen() external view override returns(uint) {
        return EMAP.length(_instNames);
    }

    /// @dev Get all instrument names
    /// - GET_INST_NAME_GAS: Storage is optimized at the expense of retrieval conversion but seems sufficient at
    ///   ~6.27K with count=200 using a solidity string conversion (vs assembly).
    /// @param iBegin Index in the array to begin processing
    /// @param count Items to get, 0 = [iBegin:] (may exceed gas), See `getInstNamesLen()` and PAGE_REQUESTS.
    /// @return results requested range of items
    function getInstNames(uint iBegin, uint count) external view override returns(string[] memory results)
    { unchecked {
        EMAP.UintUintValue[] storage values = _instNames.inner.values;

        // Calculate results length
        iBegin += EMAP.FIRST_INDEX; // to ignore sentinel value
        uint resultsLen = Util.getRangeLen(values.length, iBegin, count);
        if (resultsLen == 0) return results;

        // Get results slice; convert names from bytes32 to string
        results = new string[](resultsLen);
        for (uint i = 0; i < resultsLen; ++i) { // Ubound: Caller must page
            results[i] = String.toString(bytes32(values[iBegin + i].key));
        }
    } }

    /// @dev Get count of instrument names for an earn date
    /// @param earnDate Earn date for revenue
    function getInstNamesForDateLen(uint earnDate) external view override returns(uint) {
        return EMAP.length(_dateToInsts[earnDate]);
    }

    /// @dev Get instrument names for an earn date, see GET_INST_NAME_GAS
    /// @param earnDate Earn date for revenue
    /// @param iBegin Index in the array to begin processing
    /// @param count Items to get, 0 = [iBegin:] (may exceed gas), See `getInstNamesForDateLen(earnDate)` and PAGE_REQUESTS.
    /// @return results requested range of items
    function getInstNamesForDate(uint earnDate, uint iBegin, uint count) external view override
        returns(string[] memory results)
    { unchecked {
        EMAP.Bytes32Bytes32 storage emap = _dateToInsts[earnDate];

        // Calculate results length
        iBegin += EMAP.FIRST_INDEX; // to ignore sentinel value
        uint resultsLen = Util.getRangeLen(emap.inner.values.length, iBegin, count);
        if (resultsLen == 0) return results;

        // Get results slice; convert names from bytes32 to string
        results = new string[](resultsLen);
        for (uint i = 0; i < resultsLen; ++i) { // Ubound: Caller must page
            results[i] = String.toString(EMAP.getByIndex(emap, iBegin + i));
        }
    } }

    // ───────────────────────────────────────
    // Getters: Earn Dates
    // ───────────────────────────────────────

    /// @dev Get count of all earn dates
    function getEarnDatesLen() external view override returns(uint) {
        return EMAP.length(_earnDates);
    }

    /// @dev Get all earn dates
    /// @param iBegin Index in the array to begin processing
    /// @param count Items to get, 0 = [iBegin:] (may exceed gas), See `getEarnDatesLen()` and PAGE_REQUESTS.
    /// @return results requested range of items
    function getEarnDates(uint iBegin, uint count) external view override
        returns(uint[] memory results)
    { unchecked {
        EMAP.UintUintValue[] storage values = _earnDates.values;

        // Calculate results length
        iBegin += EMAP.FIRST_INDEX; // to ignore sentinel value
        uint resultsLen = Util.getRangeLen(values.length, iBegin, count);
        if (resultsLen == 0) return results;

        // Get results slice
        results = new uint[](resultsLen);
        for (uint i = 0; i < resultsLen; ++i) { // Ubound: Caller must page
            results[i] = values[iBegin + i].value;
        }
    } }

    /// @dev Get count of instrument's earn dates
    function getEarnDatesForInstLen(string calldata instName) external view override returns(uint) {
        bytes32 instNameKey = String.toBytes32(instName);
        return EMAP.length(_instToDates[instNameKey]);
    }

    /// @dev Get instrument's earn dates
    /// @param iBegin Index in the array to begin processing
    /// @param count Items to get, 0 = [iBegin:] (may exceed gas), See `getEarnDatesForInstLen(instName)` and PAGE_REQUESTS.
    /// @return results requested range of items
    function getEarnDatesForInst(string calldata instName, uint iBegin, uint count) external view override
        returns(uint[] memory results)
    { unchecked {
        bytes32 instNameKey = String.toBytes32(instName);
        EMAP.UintUint storage emap = _instToDates[instNameKey];

        // Calculate results length
        iBegin += EMAP.FIRST_INDEX; // to ignore sentinel value
        uint resultsLen = Util.getRangeLen(emap.values.length, iBegin, count);
        if (resultsLen == 0) return results;

        // Get results slice
        results = new uint[](resultsLen);
        for (uint i = 0; i < resultsLen; ++i) { // Ubound: Caller must page
            results[i] = EMAP.getByIndex(emap, iBegin + i);
        }
    } }
}
