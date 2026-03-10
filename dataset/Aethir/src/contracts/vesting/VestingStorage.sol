// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {
    IRegistry,
    IVestingStorage,
    VestingType,
    VestingRecord,
    BaseService,
    VESTING_HANDLER_ID,
    VESTING_STORAGE_ID
} from "../Index.sol";

contract VestingStorage is IVestingStorage, BaseService {
    struct Record {
        mapping(uint32 => uint256) amounts;
        uint32 firstDay;
        uint32 lastDay;
    }
    struct Table {
        mapping(uint256 tid => mapping(uint256 gid => mapping(address => Record))) records;
    }

    mapping(VestingType => Table) private _tables;

    /// @notice Modifier to restrict access to the current Vesting Handler
    modifier onlyHandler() {
        require(_registry.getAddress(VESTING_HANDLER_ID) == msg.sender, "VestingStorage: handler only");
        _;
    }

    constructor(IRegistry registry) BaseService(registry, VESTING_STORAGE_ID) {}

    /// @inheritdoc IVestingStorage
    function increaseVestingAmounts(
        VestingType vestingType,
        uint256 tid,
        uint256 gid,
        address account,
        VestingRecord calldata record
    ) external override onlyHandler returns (uint256 totalAmount) {
        require(record.amounts.length > 0, "VestingStorage: empty input");
        require(record.amounts.length == record.vestingDays.length, "VestingStorage: length mismatch");
        if (record.vestingDays.length == 0) return 0;
        Record storage _record = _tables[vestingType].records[tid][gid][account];
        uint32 firstDay = _record.firstDay;
        uint32 lastDay = _record.lastDay;
        for (uint256 i = 0; i < record.amounts.length; i++) {
            if (record.amounts[i] == 0) continue;
            if (record.vestingDays[i] < firstDay || firstDay == 0) {
                firstDay = record.vestingDays[i];
            }
            if (record.vestingDays[i] > lastDay) {
                lastDay = record.vestingDays[i];
            }
            _record.amounts[record.vestingDays[i]] += record.amounts[i];
            totalAmount += record.amounts[i];
        }
        _record.firstDay = firstDay;
        _record.lastDay = lastDay;
    }

    /// @inheritdoc IVestingStorage
    function decreaseVestingAmounts(
        VestingType vestingType,
        uint256 tid,
        uint256 gid,
        address account,
        VestingRecord calldata record
    ) external override onlyHandler returns (uint256 totalAmount) {
        require(record.amounts.length > 0, "VestingStorage: empty input");
        require(record.amounts.length == record.vestingDays.length, "VestingStorage: length mismatch");
        if (record.vestingDays.length == 0) return 0;
        Record storage _record = _tables[vestingType].records[tid][gid][account];
        for (uint256 i = 0; i < record.amounts.length; i++) {
            if (record.amounts[i] == 0) continue;
            uint256 currentAmount = _record.amounts[record.vestingDays[i]];
            require(currentAmount >= record.amounts[i], "VestingStorage: insufficient");
            _record.amounts[record.vestingDays[i]] = currentAmount - record.amounts[i];
            totalAmount += record.amounts[i];
        }
    }

    /// @inheritdoc IVestingStorage
    function getVestingAmounts(
        VestingType vestingType,
        uint256 tid,
        uint256 gid,
        address account,
        uint32[] calldata vestingDays
    ) external view override returns (uint256[] memory amounts) {
        require(vestingDays.length > 0, "VestingStorage: empty input");
        for (uint256 i = 1; i < vestingDays.length; i++) {
            require(vestingDays[i] > vestingDays[i - 1], "VestingStorage: vesting days must be strictly increasing");
        }
        amounts = new uint256[](vestingDays.length);
        Record storage _record = _tables[vestingType].records[tid][gid][account];
        for (uint256 i = 0; i < vestingDays.length; i++) {
            amounts[i] = _record.amounts[vestingDays[i]];
        }
    }

    /// @inheritdoc IVestingStorage
    function getRange(
        VestingType vestingType,
        uint256 tid,
        uint256 gid,
        address account
    ) external view override returns (uint32, uint32) {
        Record storage _record = _tables[vestingType].records[tid][gid][account];
        return (_record.firstDay, _record.lastDay);
    }

    /// @inheritdoc IVestingStorage
    function batchGetVestingAmounts(
        VestingType[] calldata vestingTypes,
        uint256[] calldata tids,
        uint256[] calldata gids,
        address[] calldata accounts,
        uint32[][] calldata vestingDays
    ) external view override returns (uint256[][] memory amounts) {
        uint256 len = vestingTypes.length;
        require(
            len == tids.length &&
                len == gids.length &&
                len == accounts.length &&
                len == vestingDays.length &&
                len == vestingDays.length,
            "Invalid length"
        );
        amounts = new uint256[][](len);
        for (uint256 i = 0; i < len; i++) {
            amounts[i] = this.getVestingAmounts(vestingTypes[i], tids[i], gids[i], accounts[i], vestingDays[i]);
        }
    }

    /// @inheritdoc IVestingStorage
    function batchGetRange(
        VestingType[] calldata vestingTypes,
        uint256[] calldata tids,
        uint256[] calldata gids,
        address[] calldata accounts
    ) external view override returns (uint32[] memory firstDays, uint32[] memory lastDays) {
        uint256 len = vestingTypes.length;
        require(len == tids.length && len == gids.length && len == accounts.length, "Invalid length");
        firstDays = new uint32[](len);
        lastDays = new uint32[](len);
        for (uint256 i = 0; i < len; i++) {
            Record storage _record = _tables[vestingTypes[i]].records[tids[i]][gids[i]][accounts[i]];
            firstDays[i] = _record.firstDay;
            lastDays[i] = _record.lastDay;
        }
    }

    /// @inheritdoc IVestingStorage
    function getVestedRecord(
        VestingType vestingType,
        uint256 tid,
        uint256 gid,
        address account,
        uint32 today
    ) external view returns (VestingRecord memory record) {
        Record storage _record = _tables[vestingType].records[tid][gid][account];
        uint256 len = 0;
        for (uint32 i = _record.firstDay; i <= today && i <= _record.lastDay; i++) {
            if (_record.amounts[i] > 0) {
                len++;
            }
        }
        record = VestingRecord(new uint256[](len), new uint32[](len));
        uint256 index = 0;
        for (uint32 i = _record.firstDay; i <= today && i <= _record.lastDay; i++) {
            if (_record.amounts[i] > 0) {
                record.amounts[index] = _record.amounts[i];
                record.vestingDays[index] = i;
                index++;
            }
        }
    }

    /// @inheritdoc IVestingStorage
    function getVestingRecord(
        VestingType vestingType,
        uint256 tid,
        uint256 gid,
        address account,
        uint32 today
    ) external view returns (VestingRecord memory record) {
        Record storage _record = _tables[vestingType].records[tid][gid][account];
        uint256 len = 0;
        for (uint32 i = today + 1; i <= _record.lastDay; i++) {
            if (_record.amounts[i] > 0) {
                len++;
            }
        }
        record = VestingRecord(new uint256[](len), new uint32[](len));
        uint256 index = 0;
        for (uint32 i = today + 1; i <= _record.lastDay; i++) {
            if (_record.amounts[i] > 0) {
                record.amounts[index] = _record.amounts[i];
                record.vestingDays[index] = i;
                index++;
            }
        }
    }
}
