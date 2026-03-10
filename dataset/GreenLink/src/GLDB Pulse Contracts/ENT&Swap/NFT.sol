// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC1155Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ERC1155BurnableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155BurnableUpgradeable.sol";
import {IWhitelistCore} from "./interfaces/IWhitelistable.sol";
import {IBlacklistCore} from "./interfaces/IBlacklistable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {Helper} from "./lib/Helper.sol";
import {IExternalWhitelistImpl, IExternalBlacklistImpl} from "./interfaces/ExternalImpl.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AccessControlUpgradeable} from "./acl/AccessControlUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {MulticallUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/MulticallUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./lib/Types.sol";

/**
 * @title NFT
 * @dev Upgradeable ERC1155 NFT contract with additional features
 */
contract NFT is
    Initializable,
    IERC165,
    ERC1155Upgradeable,
    OwnableUpgradeable,
    ERC1155BurnableUpgradeable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    MulticallUpgradeable,
    IExternalWhitelistImpl,
    IExternalBlacklistImpl
{
    using RangeDateLib for Date;
    using NFTConditionSliceLib for NFTCondition[];
    using NFTConditionLib for NFTCondition;
    using NFTMetadataLib for NFTMetadata;
    using SafeERC20 for IERC20;

    /// @dev allow to automate trigger the NFT
    bytes32 public constant EXECUTE_ROLE = keccak256("EXECUTE_ROLE");
    uint256 public constant MAX_TRANSFER_HISTORY_LENGTH = 500;

    // Token address
    address public tokenAddress;

    error NFTAlreadyExists(uint256 nftId);
    error NFTInvalidState(uint256 nftId, NFTStatus requiredStatus, NFTStatus currentStatus);
    error AddressBlacklisted(address account);
    error AddressNotWhitelisted(address account);
    error InvalidCondition(NFTCreateConditionParams cond);
    error InvalidExecutionDate();
    error DuplicateOperatorInConditions();
    error InvalidConditionsLength();
    error InvalidParameter();
    error Unauthorized();
    error ConditionNotInTimeRange();
    error ConditionDateExpired();
    error TransferNotAllowed();
    error InvalidStartTime(uint40 provided, uint40 minimum);
    error InvalidEndTime(uint40 provided, uint40 minimum);
    error InvalidConditionIndex(uint8 index, uint256 length);
    error ConditionAlreadySetTime();
    error ConditionEndTimeOutOfRange(uint40 endTime, uint40 executionEndTime);
    error RequireZeroAmount();
    error ActionAlreadyTaken();
    error RequireNonZeroAmount();
    error ExceedMaxAmount(uint256 current, uint256 add, uint256 max);
    error TriggerBeforeEndTime(uint40 currentTime, uint40 endTime);
    error MaxTransferExceed(uint256 nftId);

    /// @notice Emitted when an NFT record is created
    event NFTInitial(uint256 indexed nftId, address indexed sender, address indexed receiver, uint256 amount);
    /// @notice Emitted when an NFT is minted
    event NFTMinted(uint256 indexed nftId, address indexed sender, address indexed receiver, uint256 amount);
    /// @notice Emitted when tokens are refunded to the sender
    event NFTRefunded(uint256 indexed nftId, address indexed sender, uint256 amount);
    /// @notice Emitted when the start timestamp for the execution phase is set
    event SetExecutionStartTimestamp(uint256 indexed nftId, uint40 startTimestamp, uint40 endTimestamp);
    /// @notice Emitted when the start timestamp for a condition is set
    event SetConditionStartTimestamp(uint256 indexed nftId, uint8 indexed index, uint40 startTimestamp);
    /// @notice Emitted when an NFT changes status
    event NFTStatusChanged(uint256 indexed nftId, NFTStatus indexed toStatus, NFTStatus fromStatus);
    /// @notice Emitted when a condition is processed
    event ProcessCondition(
        uint256 indexed nftId, uint8 indexed index, uint256 externalId, bool approved, uint256 amount
    );
    /**
     * @dev Emitted when an NFT is realized (settled) for tokens
     * @param nftId The ID of the NFT
     * @param account The address that realized the NFT
     * @param amount The amount realized
     */
    event NFTRealized(uint256 indexed nftId, address indexed account, uint256 amount);

    /// @dev Enum to represent different types of NFT activity tracking
    /// TOTAL_HOLD - Tracks the current amount of NFTs held by an address
    /// REALIZED - Tracks the amount of NFTs that have been settled/redeemed for tokens
    enum NFTStatisticsType {
        TOTAL_HOLD,
        REALIZED
    }

    struct LedgerItem {
        address account;
        uint256 totalHold;
        uint256 realized;
        uint256 committed;
        uint256 balance;
    }

    modifier checkTransfer(address sender, address recipient) {
        checkWhiteBlacklist(sender, recipient);
        _;
    }

    function checkWhiteBlacklist(address sender, address recipient) private view {
        if (_isBlacklisted(sender)) revert AddressBlacklisted(sender);
        if (!_isWhitelisted(sender)) revert AddressNotWhitelisted(sender);

        if (_isBlacklisted(recipient)) revert AddressBlacklisted(recipient);
        if (!_isWhitelisted(recipient)) revert AddressNotWhitelisted(recipient);
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract with initial values
     * @param owner The owner of the contract
     */
    function initialize(address owner, address _tokenAddress, IWhitelistCore whitelist, IBlacklistCore blacklist)
        public
        initializer
    {
        __ERC1155_init("");
        __Ownable_init(owner);
        __ERC1155Burnable_init();
        __UUPSUpgradeable_init();
        __AccessControl_init();
        __Multicall_init();
        _setWhitelistImpl(whitelist);
        _setBlacklistImpl(blacklist);

        _setTokenAddress(_tokenAddress);
        _setVersion("1.0.0", 1);
    }

    function uri(uint256) public view virtual override returns (string memory) {
        return "";
    }

    /**
     * @dev Authorizes an upgrade to a new implementation
     * @param newImplementation Address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

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

    /// @notice Sets the start timestamp for the execution phase when execution date type is T1
    /// @dev When an NFT is created, if the day is not 0, it indicates the date type is T1
    /// @dev This method is called by PartyA to set when the execution period starts
    function setExecutionStartTimestamp(uint256 nftId, uint40 timestamp) public {
        NFTMetadata storage nft = _getNFTStorage().nfts[nftId];
        // Check NFT status
        if (nft.status != NFTStatus.WAIT_EXECUTION_DATE) {
            revert NFTInvalidState(nftId, NFTStatus.WAIT_EXECUTION_DATE, nft.status);
        }
        // Check operator identity
        if (nft.partyA != _msgSender()) {
            revert Unauthorized();
        }
        // Validate start time range
        if (timestamp < nft.createdAt) {
            revert InvalidStartTime(timestamp, nft.createdAt);
        }
        // Get the maximum time from Conditions with time already set
        (uint40 maxTime, bool needSetConditionDate) = nft.conditions.getMaxTime();

        Date storage executionDate = nft.executionDate;
        uint40 startTimestamp = timestamp + 86400 * executionDate.day;
        uint40 endTimestamp = startTimestamp + 86400; /*1day*/
        // Require endTimestamp to be greater than or equal to the maximum time in conditions
        if (maxTime > endTimestamp) {
            revert InvalidEndTime(endTimestamp, maxTime);
        }
        executionDate.setTime(startTimestamp, endTimestamp);

        // If need to set time in Conditions, change the status
        if (needSetConditionDate) {
            _changeNFTStatus(nftId, nft, NFTStatus.WAIT_CONDITION_DATE);
        } else {
            // Otherwise create NFT directly
            _createNFT(nftId, nft);
        }

        emit SetExecutionStartTimestamp(nftId, startTimestamp, endTimestamp);
    }

    /// @notice Sets the start timestamp for a specific condition
    /// @dev This can only be called when NFT is in WAIT_CONDITION_DATE status
    /// @dev Only PartyA can set condition start times
    /// @dev The condition end time must fall within the execution time range
    /// @param nftId The ID of the NFT
    /// @param index The index of the condition in the conditions array
    /// @param startTimestamp The timestamp when condition period starts
    function setConditionStartTimestamp(uint256 nftId, uint8 index, uint40 startTimestamp) public {
        NFTMetadata storage nft = _getNFTStorage().nfts[nftId];
        // Validate NFT status
        if (nft.status != NFTStatus.WAIT_CONDITION_DATE) {
            revert NFTInvalidState(nftId, NFTStatus.WAIT_CONDITION_DATE, nft.status);
        }
        // Validate operator identity
        if (nft.partyA != _msgSender()) {
            revert Unauthorized();
        }
        // Validate start time range
        if (startTimestamp < nft.createdAt) {
            revert InvalidStartTime(startTimestamp, nft.createdAt);
        }
        // Validate if index is correct
        NFTCondition[] storage conditions = nft.conditions;
        if (index >= conditions.length) {
            revert InvalidConditionIndex(index, conditions.length);
        }
        // Validate if already set, don't allow to set again
        Date storage conditionDate = conditions[index].date;
        if (conditionDate.isTimeSet()) {
            revert ConditionAlreadySetTime();
        }
        // Validate condition end time <= execution time end
        Date storage executionDate = nft.executionDate;
        uint40 endTimestamp = startTimestamp + 86400 * conditionDate.day;
        if (endTimestamp > executionDate.endTime) {
            revert ConditionEndTimeOutOfRange(endTimestamp, executionDate.endTime);
        }

        conditionDate.setTime(startTimestamp, endTimestamp);
        emit SetConditionStartTimestamp(nftId, index, startTimestamp);

        if (conditions.isAllConditionTimeSet()) {
            _createNFT(nftId, nft);
        }
    }

    /**
     * Process a condition for an NFT
     *
     * For non-partial conditions:
     * - amount must be 0
     * - can only be processed once (action must be None)
     *
     * For partial conditions:
     * - amount can be 0
     * - if amount > 0, approved must be true
     * - if amount > 0, confirmedAmount + amount must not exceed nft.amount
     * - once approved is set to true, subsequent calls will ignore the approved parameter
     */
    function processCondition(uint256 nftId, uint64 externalId, uint8 index, bool approved, uint256 amount) external {
        address operator = _msgSender();
        (NFTMetadata storage nft, NFTCondition storage condition) = _getNFTAndCondition(nftId, index, NFTStatus.CREATED);
        // Validate operator identity
        if (condition.operator != operator) {
            revert Unauthorized();
        }

        bool skipActionUpdate;
        Action3 action = condition.action;

        if (!condition.isPartial) {
            if (amount > 0) revert RequireZeroAmount();
            if (action != Action3.None) revert ActionAlreadyTaken();
        } else {
            if (amount > 0) {
                if (!approved) revert RequireNonZeroAmount();
                if (condition.confirmedAmount + amount > nft.amount) {
                    revert ExceedMaxAmount(condition.confirmedAmount, amount, nft.amount);
                }
            }
            if (action == Action3.Approve) {
                skipActionUpdate = true; // No need to update
            } else if (action != Action3.None) {
                revert ActionAlreadyTaken();
            }
        }

        NFTCondition storage condStorage = _getNFTStorage().nfts[nftId].conditions[index];
        condStorage.setActionTime(uint40(block.timestamp));
        condStorage.setAction(approved, skipActionUpdate);
        if (amount > 0) {
            condition.confirmedAmount += amount;
        }

        emit ProcessCondition(nftId, index, externalId, approved, amount);

        _triggerPay(nftId, nft);
    }

    function trigger(uint256 nftId) public onlyRole(EXECUTE_ROLE) {
        NFTMetadata storage nft = _getNFTStorage().nfts[nftId];
        NFTStatus requiredStatus = NFTStatus.CREATED;
        // Check if NFT status is CREATED
        if (nft.status != requiredStatus) {
            revert NFTInvalidState(nftId, requiredStatus, nft.status);
        }
        uint40 maxTime = _triggerTime(nft);
        if (uint40(block.timestamp) < maxTime) {
            revert TriggerBeforeEndTime(uint40(block.timestamp), maxTime);
        }
        _triggerPay(nftId, nft);
    }

    function _triggerPay(uint256 nftId, NFTMetadata storage nft) private {
        if (_isNFTFinished(nft)) {
            return;
        }

        // Completely rejected, unable to meet conditions, direct refund
        if (nft.isConditionsUnreachable()) {
            IERC20(tokenAddress).safeTransfer(nft.sender, nft.amount);
            emit NFTRefunded(nftId, nft.sender, nft.amount);
            _changeNFTStatus(nftId, nft, NFTStatus.NOT_SATISFIED_FINISH);
            return;
        }

        uint40 nowTime = uint40(block.timestamp);
        if (nowTime < nft.executionDate.startTime) {
            return;
        }

        (bool isMet, uint256 maximumBenefit) = nft.isMet(nowTime);
        uint256 paidAmount = nft.paidAmount;

        if (isMet && maximumBenefit > paidAmount) {
            uint256 diff = maximumBenefit - paidAmount;
            nft.paidAmount += diff;
            if (paidAmount + diff == nft.amount) {
                _changeNFTStatus(nftId, nft, NFTStatus.FINISH);
            }
            // Payment
            address[] storage history = _getNFTStorage().nftTransferHistory[nftId];
            uint256 historyLength = history.length;
            for (uint256 i = 0; i < historyLength + 1;) {
                address to = i == historyLength ? nft.partyA : history[i];
                uint256 balance = minUint256(diff, super.balanceOf(to, nftId));
                if (balance > 0) {
                    _settle(nftId, to, balance);
                    diff -= balance;
                }
                if (diff == 0) {
                    break;
                }
                unchecked {
                    i++;
                }
            }
        }

        //////////////// Refund to sender ////////////////////
        // Liquidation, return unused tokens to the original sender
        if (nowTime >= _triggerTime(nft)) {
            uint256 diff = nft.amount - nft.paidAmount;
            if (diff > 0) {
                // Refund
                _refund(nftId, nft.sender, diff);
                _changeNFTStatus(nftId, nft, NFTStatus.PART_REFUND_FINISH);
            }
        }
    }

    function getHistoryLength(uint256 id) public view returns (uint256) {
        return _getNFTStorage().nftTransferHistory[id].length;
    }

    /**
     * @dev Returns ledger information for accounts that have interacted with a specific NFT
     * @param id The NFT ID to query
     * @param start Starting index in the transfer history (plus partyA at the end)
     * @param limit Maximum number of records to return
     * @return Array of LedgerItem structs containing account activity data:
     *         - totalHold: Total amount held by the account
     *         - realized: Amount already redeemed/settled
     *         - committed: Potential amount that could be claimed based on current conditions
     *
     * Note: The 'committed' values are calculated in order of the transfer history.
     * Earlier recipients will receive their commitments before later ones if the
     * available amount is limited.
     */
    function getLedgerList(uint256 id, uint256 start, uint256 limit) public view returns (LedgerItem[] memory) {
        (uint256 unpaidAmount, address nftPartyA) = calculateUnpaidAmount(id);
        if (nftPartyA == address(0)) {
            return new LedgerItem[](0);
        }
        address[] storage history = _getNFTStorage().nftTransferHistory[id];
        uint256 historyLength = history.length;
        if (start >= historyLength + 1) { // +1 for partyA
            return new LedgerItem[](0);
        }
        // avoid stack too deep
        return getLedgerListInner(
            id, start, minUint256(start + limit, historyLength + 1), unpaidAmount, nftPartyA, history
        );
    }

    function getLedgerListInner(
        uint256 id,
        uint256 start,
        uint256 end,
        uint256 unpaidAmount,
        address nftPartyA,
        address[] storage history
    ) private view returns (LedgerItem[] memory) {
        uint256 historyLength = history.length;
        LedgerItem[] memory result = new LedgerItem[](end - start);
        for (uint256 i = 0; i < end;) {
            address account = i == historyLength ? nftPartyA : history[i];
            uint256 committed = minUint256(unpaidAmount, super.balanceOf(account, id));
            if (i >= start) {
                result[i - start] = _createLedgerItem(account, id, committed);
            }
            unpaidAmount -= committed;
            unchecked {
                i++;
            }
        }
        return result;
    }

    event NFTTransferred(address indexed operator, address indexed from, address indexed to, uint256 id, uint256 value);
    event BatchNFTTransferred(
        address indexed operator, address indexed from, address indexed to, uint256[] ids, uint256[] values
    );

    /**
     * @dev See {IERC1155-safeTransferFrom}.
     */
    function safeTransferFrom(address from, address to, uint256 id, uint256 value, bytes memory data)
        public
        virtual
        override
    {
        address operator = _msgSender();
        NFTMetadata storage mt = _getNFTStorage().nfts[id];
        address nftPartyA = mt.partyA;
        if (nftPartyA != from || to == nftPartyA) {
            revert TransferNotAllowed();
        }
        uint40 nowTime = uint40(block.timestamp);
        // Only before the execution date can it be transferred.
        if (mt.status != NFTStatus.CREATED || nowTime > mt.executionDate.startTime) {
            revert TransferNotAllowed();
        }
        if (_getNFTStorage().nftTransferHistory[id].length > MAX_TRANSFER_HISTORY_LENGTH) {
            revert MaxTransferExceed(id);
        }
        _updateTotalHold(id, to, value, true);
        _updateTotalHold(id, from, value, false);
        _getNFTStorage().nftTransferHistory[id].push(to);
        super.safeTransferFrom(from, to, id, value, data);
        emit NFTTransferred(operator, from, to, id, value);
    }

    /**
     * @dev See {IERC1155-safeBatchTransferFrom}.
     */
    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values,
        bytes memory data
    ) public virtual override {
        address operator = _msgSender();
        uint256 historyLength = _getNFTStorage().nftTransferHistory[ids[0]].length;
        uint40 nowTime = uint40(block.timestamp);
        for (uint256 i = 0; i < ids.length;) {
            uint256 id = ids[i];
            NFTMetadata storage mt = _getNFTStorage().nfts[id];
            address nftPartyA = mt.partyA;
            if (nftPartyA != from || to == nftPartyA) {
                revert TransferNotAllowed();
            }
            // Only before the execution date can it be transferred.
            if (mt.status != NFTStatus.CREATED || nowTime > mt.executionDate.startTime) {
                revert TransferNotAllowed();
            }
            if (historyLength > MAX_TRANSFER_HISTORY_LENGTH) {
                revert MaxTransferExceed(id);
            }
            _updateTotalHold(id, to, values[i], true);
            _updateTotalHold(id, from, values[i], false);
            _getNFTStorage().nftTransferHistory[id].push(to);
            historyLength++;
            unchecked {
                i++;
            }
        }
        super.safeBatchTransferFrom(from, to, ids, values, data);
        emit BatchNFTTransferred(operator, from, to, ids, values);
    }

    function getNFT(uint256 nftId) external view returns (NFTMetadata memory) {
        return _getNFTStorage().nfts[nftId];
    }

    function balanceOf(address account, uint256 id) public view virtual override returns (uint256) {
        if (_isNFTFinished(_getNFTStorage().nfts[id])) {
            return 0;
        }
        return super.balanceOf(account, id);
    }

    function _getNFTAndCondition(uint256 nftId, uint8 index, NFTStatus requiredStatus)
        private
        view
        returns (NFTMetadata storage, NFTCondition storage)
    {
        NFTMetadata storage cond = _getNFTStorage().nfts[nftId];
        // Check if NFT status is CREATED
        if (cond.status != requiredStatus) {
            revert NFTInvalidState(nftId, requiredStatus, cond.status);
        }
        // Check if TA index is within valid range
        if (index >= uint8(cond.conditions.length)) {
            revert InvalidConditionIndex(index, cond.conditions.length);
        }
        // Check if in condition processing time
        NFTCondition storage condition = cond.conditions[index];
        if (!condition.date.isInRange(uint40(block.timestamp))) {
            revert ConditionNotInTimeRange();
        }
        return (cond, condition);
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view override(ERC1155Upgradeable, IERC165) returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IExternalWhitelistImpl).interfaceId
            || interfaceId == type(IExternalBlacklistImpl).interfaceId || ERC1155Upgradeable.supportsInterface(interfaceId);
    }

    event WhitelistImplSet(address indexed whitelistImpl);
    event BlacklistImplSet(address indexed blacklistImpl);

    function version() public view returns (string memory) {
        return _getVersionStorage().version;
    }

    function versionNumber() public view returns (uint256) {
        return _getVersionStorage().versionNumber;
    }

    function setTokenAddress(address _tokenAddress) public onlyOwner {
        _setTokenAddress(_tokenAddress);
    }

    function getWhitelistImpl() external view returns (address) {
        return address(_getWhiteBlackListImplStorage().whitelistImpl);
    }

    function getBlacklistImpl() external view returns (address) {
        return address(_getWhiteBlackListImplStorage().blacklistImpl);
    }

    /// @notice Set the whitelist implementation
    function setWhitelistImpl(IWhitelistCore whitelistImpl_) public onlyOwner {
        _setWhitelistImpl(whitelistImpl_);
    }

    /// @notice Set the blacklist implementation
    function setBlacklistImpl(IBlacklistCore blacklistImpl_) public onlyOwner {
        _setBlacklistImpl(blacklistImpl_);
    }

    function _setTokenAddress(address _tokenAddress) private {
        Helper.checkAddress(_tokenAddress);
        tokenAddress = _tokenAddress;
    }

    function _setWhitelistImpl(IWhitelistCore whitelistImpl_) internal {
        Helper.checkAddress(address(whitelistImpl_));
        _getWhiteBlackListImplStorage().whitelistImpl = whitelistImpl_;
        emit WhitelistImplSet(address(whitelistImpl_));
    }

    function _setBlacklistImpl(IBlacklistCore blacklistImpl_) internal {
        Helper.checkAddress(address(blacklistImpl_));
        _getWhiteBlackListImplStorage().blacklistImpl = blacklistImpl_;
        emit BlacklistImplSet(address(blacklistImpl_));
    }

    function _isBlacklisted(address account) internal view virtual returns (bool) {
        return _getWhiteBlackListImplStorage().blacklistImpl.isBlacklisted(account);
    }

    function _isWhitelisted(address account) internal view virtual returns (bool) {
        return _getWhiteBlackListImplStorage().whitelistImpl.isWhitelisted(account);
    }

    function _setVersion(string memory _version, uint256 _versionNumber) internal {
        VersionStorage storage versionStorage = _getVersionStorage();
        versionStorage.version = _version;
        versionStorage.versionNumber = _versionNumber;
    }

    function _msgSender() internal view virtual override(Context, ContextUpgradeable) returns (address) {
        return ContextUpgradeable._msgSender();
    }

    function _msgData() internal view virtual override(Context, ContextUpgradeable) returns (bytes calldata) {
        return ContextUpgradeable._msgData();
    }

    function _contextSuffixLength() internal view virtual override(Context, ContextUpgradeable) returns (uint256) {
        return ContextUpgradeable._contextSuffixLength();
    }

    function _isOwner(address account) internal view virtual override returns (bool) {
        return account == owner();
    }

    function _createLedgerItem(address account, uint256 id, uint256 committed)
        private
        view
        returns (LedgerItem memory)
    {
        mapping(address => mapping(NFTStatisticsType => uint256)) storage nftLedger =
            _getNFTStorage().nftActivityLedger[id];
        return LedgerItem({
            account: account,
            totalHold: nftLedger[account][NFTStatisticsType.TOTAL_HOLD],
            realized: nftLedger[account][NFTStatisticsType.REALIZED],
            committed: committed,
            balance: balanceOf(account, id)
        });
    }

    function calculateUnpaidAmount(uint256 id) public view returns (uint256 unpaidAmount, address nftPartyA) {
        NFTMetadata storage nft = _getNFTStorage().nfts[id];
        if (nft.status == NFTStatus.NONE) {
            return (0, address(0));
        }
        nftPartyA = nft.partyA;
        uint40 nowTime = uint40(block.timestamp);
        if (!_isNFTFinished(nft)) {
            (bool isMet, uint256 maximumBenefit) = nft.isMet(nowTime);
            if (isMet) {
                uint256 paidAmount = nft.paidAmount;
                unpaidAmount = maximumBenefit > paidAmount ? maximumBenefit - paidAmount : 0;
            }
        }
    }

    function _isNFTFinished(NFTMetadata storage nft) private view returns (bool) {
        return nft.status == NFTStatus.FINISH || nft.status == NFTStatus.PART_REFUND_FINISH
            || nft.status == NFTStatus.NOT_SATISFIED_FINISH;
    }

    function _maxTime(uint40 a, uint40 b) private pure returns (uint40) {
        return a > b ? a : b;
    }

    function _triggerTime(NFTMetadata storage nft) private view returns (uint40) {
        (uint40 maxTime,) = nft.conditions.getMaxTime();
        maxTime = _maxTime(maxTime, nft.executionDate.startTime);
        return maxTime;
    }

    /// @dev Internal function to settle an NFT - burns the NFT and transfers tokens to the account
    /// Also updates the activity ledger to record the realized amount
    /// @param nftId The ID of the NFT to settle
    /// @param account The address receiving the settlement
    /// @param amount The amount to settle
    function _settle(uint256 nftId, address account, uint256 amount) internal {
        _burn(account, nftId, amount);
        IERC20(tokenAddress).safeTransfer(account, amount);
        _getNFTStorage().nftActivityLedger[nftId][account][NFTStatisticsType.REALIZED] += amount;
        emit NFTRealized(nftId, account, amount);
    }

    /// @notice Internal function to refund tokens to an account
    function _refund(uint256 nftId, address account, uint256 amount) internal {
        IERC20(tokenAddress).safeTransfer(account, amount);
        emit NFTRefunded(nftId, account, amount);
    }

    function _changeNFTStatus(uint256 nftId, NFTMetadata storage nft, NFTStatus status) private {
        NFTStatus preStatus = nft.status;
        if (preStatus == status) {
            return;
        }
        nft.status = status;
        emit NFTStatusChanged(nftId, status, preStatus);
    }

    function _createNFT(uint256 nftId, NFTMetadata storage nft) private {
        _changeNFTStatus(nftId, nft, NFTStatus.CREATED);
        nft.nftCreatedAt = uint40(block.timestamp);
        _swap(nft.sender, nft.partyA, nftId, nft.amount);
        _updateTotalHold(nftId, nft.partyA, nft.amount, true);
    }

    function _swap(address from, address to, uint256 nftId, uint256 amount) internal {
        IERC20(tokenAddress).safeTransferFrom(from, address(this), amount);
        super._mint(to, nftId, amount, "");
        emit NFTMinted(nftId, from, to, amount);
    }

    function _updateTotalHold(uint256 nftId, address account, uint256 amount, bool increase) internal {
        mapping(NFTStatisticsType => uint256) storage r = _getNFTStorage().nftActivityLedger[nftId][account];
        if (increase) {
            r[NFTStatisticsType.TOTAL_HOLD] += amount;
        } else {
            r[NFTStatisticsType.TOTAL_HOLD] -= amount;
        }
    }

    function minUint256(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }

    /// @custom:storage-location erc7201:eth.storage.WhiteBlackList
    struct WhiteBlackListStorage {
        IWhitelistCore whitelistImpl;
        IBlacklistCore blacklistImpl;
    }

    /// @custom:storage-location erc7201:eth.storage.Version
    struct VersionStorage {
        uint256 versionNumber;
        string version;
    }

    /// @custom:storage-location erc7201:eth.storage.NFT
    struct NFTStorage {
        // Mapping to store NFT conditions
        mapping(uint256 => NFTMetadata) nfts;
        /**
         * @dev Mapping to track the complete lifecycle of NFTs
         * First key: NFT ID
         * Second key: User address
         * Third key: Activity type (total received or realized)
         * Value: Amount of tokens
         */
        mapping(uint256 => mapping(address => mapping(NFTStatisticsType => uint256))) nftActivityLedger;
        // address[] Max size: 500
        mapping(uint256 => address[]) nftTransferHistory;
    }

    // keccak256(abi.encode(uint256(keccak256("eth.storage.WhiteBlackListImpl")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant WHITE_BLACK_LIST_IMPL_STORAGE_LOCATION =
        0xdbc323087f5f9655ab28eebc9cfc3f6f6fcbcb06a62b34b1f948e358e6a04e00;

    // keccak256(abi.encode(uint256(keccak256("eth.storage.Version")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant VERSION_STORAGE_LOCATION =
        0x5b6c8744113e961e644258515e7c2428983fc9a9e82560c5677b16c450267b00;

    // keccak256(abi.encode(uint256(keccak256("eth.storage.NFT")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant NFT_STORAGE_LOCATION = 0x82269115cbdd975aafcb824aa071b2f8557d58f91a502e06c86f21382dc58200;

    function _getWhiteBlackListImplStorage() internal pure returns (WhiteBlackListStorage storage $) {
        assembly {
            $.slot := WHITE_BLACK_LIST_IMPL_STORAGE_LOCATION
        }
    }

    function _getVersionStorage() internal pure returns (VersionStorage storage $) {
        assembly {
            $.slot := VERSION_STORAGE_LOCATION
        }
    }

    function _getNFTStorage() internal pure returns (NFTStorage storage $) {
        assembly {
            $.slot := NFT_STORAGE_LOCATION
        }
    }
}
