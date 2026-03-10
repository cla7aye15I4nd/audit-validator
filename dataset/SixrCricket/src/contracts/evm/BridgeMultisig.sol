// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

interface IMintableToken {
    function mint(address to, uint256 amount) external;
}

/**
 * @title BridgeMultisig
 * @notice Enforces a 3-of-5 watcher quorum for mint execution and a 3-of-5 governance quorum
 *         for configuration changes such as key rotation or token allow-list updates.
 *         Watcher and governance signatures are verified against EIP-712 typed data payloads
 *         so that hardware wallets can participate safely.
 */
contract BridgeMultisig is EIP712 {
    using ECDSA for bytes32;

    uint8 public constant WATCHER_THRESHOLD = 3;
    uint8 public constant WATCHER_COUNT = 5;
    uint8 public constant GOVERNANCE_THRESHOLD = 3;
    uint8 public constant GOVERNANCE_COUNT = 5;

    bytes32 public constant ACTION_UPDATE_WATCHERS = keccak256("ACTION_UPDATE_WATCHERS");
    bytes32 public constant ACTION_UPDATE_GOVERNANCE = keccak256("ACTION_UPDATE_GOVERNANCE");
    bytes32 public constant ACTION_SET_TOKEN_STATUS = keccak256("ACTION_SET_TOKEN_STATUS");
    bytes32 public constant ACTION_TRANSFER_TOKEN_OWNER = keccak256("ACTION_TRANSFER_TOKEN_OWNER");
    bytes32 public constant ACTION_MAP_TOKEN = keccak256("ACTION_MAP_TOKEN");
    bytes32 public constant ACTION_SET_MINT_NONCE = keccak256("ACTION_SET_MINT_NONCE");
    bytes32 public constant ACTION_SET_FEE_RECIPIENT = keccak256("ACTION_SET_FEE_RECIPIENT");
    bytes32 public constant ACTION_SET_FEE_BASIS_POINTS = keccak256("ACTION_SET_FEE_BASIS_POINTS");

    bytes32 private constant MINT_TYPEHASH =
        keccak256("MintPayload(uint256 originChainId,address token,address recipient,uint256 amount,uint64 nonce,uint256 epoch)");
    bytes32 private constant GOVERNANCE_TYPEHASH =
        keccak256("GovernanceAction(bytes32 actionType,bytes data,uint256 nonce,uint256 epoch)");

    // Custom errors
    error InsufficientSignatures();
    error InvalidEpoch();
    error InvalidNonce();
    error TokenNotAllowed();
    error PayloadAlreadyExecuted();
    error InvalidWatcher();
    error DuplicateWatcher();
    error ThresholdNotMet();
    error InvalidGovernanceSigner();
    error DuplicateGovernanceSigner();
    error TooManySignatures();
    error InvalidWatcherLength();
    error WatcherZeroAddress();
    error DuplicateWatcherAddress();
    error InvalidGovernanceLength();
    error GovernanceZeroAddress();
    error DuplicateGovernanceAddress();
    error TokenZeroAddress();
    error NewOwnerZeroAddress();
    error TransferOwnershipFailed(string reason);
    error JettonHashZeroValue();
    error UnknownAction();
    error SetFeeRecipientFailed(string reason);
    error SetFeeBasisPointsFailed(string reason);

    struct MintPayload {
        uint256 originChainId;
        address token;
        address recipient;
        uint256 amount;
        uint64 nonce;
        uint256 epoch;
    }

    struct GovernanceAction {
        bytes32 actionType;
        bytes data;
        uint256 nonce;
        uint256 epoch;
    }

    address[] private watcherSet;
    address[] private governanceSet;
    mapping(address => uint256) private watcherIndex;
    mapping(address => uint256) private governanceIndex;

    mapping(bytes32 => bool) private consumedPayloads;
    mapping(address => bool) public allowedTokens;
    mapping(bytes32 => address) public tokenMappings; // TON jetton hash => EVM token address

    uint64 public mintNonce; // Last consumed mint nonce
    uint256 public governanceNonce;
    uint256 public governanceEpoch; // Increments on governance/watcher rotation to invalidate old signatures

    event MintExecuted(
        bytes32 indexed payloadHash,
        uint256 originChainId,
        address indexed token,
        address indexed recipient,
        uint256 amount,
        uint64 nonce
    );
    event WatcherSetUpdated(address[WATCHER_COUNT] watchers);
    event GovernanceSetUpdated(address[GOVERNANCE_COUNT] governance);
    event TokenStatusUpdated(address indexed token, bool allowed);
    event TokenOwnershipTransferred(address indexed token, address indexed oldOwner, address indexed newOwner);
    event TokenMapped(bytes32 indexed tonJettonHash, address indexed evmToken);
    event MintNonceSet(uint64 indexed oldMintNonce, uint64 indexed newMintNonce);
    event GovernanceEpochUpdated(uint256 indexed newEpoch);
    event GovernanceActionExecuted(bytes32 indexed actionType, uint256 indexed nonce, bytes data);
    event FeeRecipientSet(address indexed token, address indexed feeRecipient);
    event FeeBasisPointsSet(address indexed token, uint256 feeBasisPoints);

    constructor(
        address[] memory initialWatchers,
        address[] memory initialGovernance,
        address[] memory initialAllowedTokens
    ) EIP712("BridgeMultisig", "1") {
        _setWatchers(initialWatchers);
        _setGovernance(initialGovernance);
        for (uint256 i = 0; i < initialAllowedTokens.length; ++i) {
            _setTokenStatus(initialAllowedTokens[i], true);
        }
    }

    function getWatchers() external view returns (address[] memory) {
        return watcherSet;
    }

    function getGovernance() external view returns (address[] memory) {
        return governanceSet;
    }

    function hasConsumedPayload(bytes32 payloadHash) external view returns (bool) {
        return consumedPayloads[payloadHash];
    }

    function hashMintPayload(MintPayload calldata payload) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                MINT_TYPEHASH,
                payload.originChainId,
                payload.token,
                payload.recipient,
                payload.amount,
                payload.nonce,
                payload.epoch
            )
        );
    }

    function mintDigest(MintPayload calldata payload) external view returns (bytes32) {
        return _hashTypedDataV4(hashMintPayload(payload));
    }

    function hashGovernanceAction(GovernanceAction calldata action) public pure returns (bytes32) {
        return keccak256(abi.encode(GOVERNANCE_TYPEHASH, action.actionType, keccak256(action.data), action.nonce, action.epoch));
    }

    function governanceDigest(GovernanceAction calldata action) external view returns (bytes32) {
        return _hashTypedDataV4(hashGovernanceAction(action));
    }

    function executeMint(MintPayload calldata payload, bytes[] calldata signatures) external {
        if (signatures.length < WATCHER_THRESHOLD) revert InsufficientSignatures();
        if (payload.epoch != governanceEpoch) revert InvalidEpoch();
        if (!allowedTokens[payload.token]) revert TokenNotAllowed();

        bytes32 payloadHash = hashMintPayload(payload);
        if (consumedPayloads[payloadHash]) revert PayloadAlreadyExecuted();

        bytes32 digest = _hashTypedDataV4(payloadHash);
        _validateWatcherSignatures(digest, signatures);

        consumedPayloads[payloadHash] = true;
        IMintableToken(payload.token).mint(payload.recipient, payload.amount);

        emit MintExecuted(
            payloadHash,
            payload.originChainId,
            payload.token,
            payload.recipient,
            payload.amount,
            payload.nonce
        );
    }

    function executeGovernanceAction(GovernanceAction calldata action, bytes[] calldata signatures) external {
        if (signatures.length < GOVERNANCE_THRESHOLD) revert InsufficientSignatures();
        if (action.epoch != governanceEpoch) revert InvalidEpoch();
        if (action.nonce != governanceNonce + 1) revert InvalidNonce();

        bytes32 actionHash = hashGovernanceAction(action);
        bytes32 digest = _hashTypedDataV4(actionHash);
        _validateGovernanceSignatures(digest, signatures);

        governanceNonce = action.nonce;
        if (action.actionType == ACTION_UPDATE_WATCHERS) {
            address[] memory newWatchers = abi.decode(action.data, (address[]));
            _setWatchers(newWatchers);
            _incrementGovernanceEpoch();
        } else if (action.actionType == ACTION_UPDATE_GOVERNANCE) {
            address[] memory newGovernance = abi.decode(action.data, (address[]));
            _setGovernance(newGovernance);
            _incrementGovernanceEpoch();
        } else if (action.actionType == ACTION_SET_TOKEN_STATUS) {
            (address token, bool allowed) = abi.decode(action.data, (address, bool));
            _setTokenStatus(token, allowed);
        } else if (action.actionType == ACTION_TRANSFER_TOKEN_OWNER) {
            (address token, address newOwner) = abi.decode(action.data, (address, address));
            _transferTokenOwnership(token, newOwner);
        } else if (action.actionType == ACTION_MAP_TOKEN) {
            (bytes32 tonJettonHash, address evmToken) = abi.decode(action.data, (bytes32, address));
            _mapToken(tonJettonHash, evmToken);
        } else if (action.actionType == ACTION_SET_MINT_NONCE) {
            uint64 newMintNonce = abi.decode(action.data, (uint64));
            _setMintNonce(newMintNonce);
        } else if (action.actionType == ACTION_SET_FEE_RECIPIENT) {
            (address token, address feeRecipient) = abi.decode(action.data, (address, address));
            _setFeeRecipient(token, feeRecipient);
        } else if (action.actionType == ACTION_SET_FEE_BASIS_POINTS) {
            (address token, uint256 feeBasisPoints) = abi.decode(action.data, (address, uint256));
            _setFeeBasisPoints(token, feeBasisPoints);
        } else {
            revert UnknownAction();
        }

        emit GovernanceActionExecuted(action.actionType, action.nonce, action.data);
    }

    function _validateWatcherSignatures(bytes32 digest, bytes[] calldata signatures) internal view {
        if (signatures.length > WATCHER_COUNT) revert TooManySignatures();
        uint256 seen = 0;
        uint256 unique = 0;
        for (uint256 i = 0; i < signatures.length; ++i) {
            address signer = digest.recover(signatures[i]);
            uint256 index = watcherIndex[signer];
            if (index == 0) revert InvalidWatcher();
            uint256 mask = 1 << (index - 1);
            if ((seen & mask) != 0) revert DuplicateWatcher();
            seen |= mask;
            ++unique;
        }
        if (unique < WATCHER_THRESHOLD) revert ThresholdNotMet();
    }

    function _validateGovernanceSignatures(bytes32 digest, bytes[] calldata signatures) internal view {
        if (signatures.length > GOVERNANCE_COUNT) revert TooManySignatures();
        uint256 seen = 0;
        uint256 unique = 0;
        for (uint256 i = 0; i < signatures.length; ++i) {
            address signer = digest.recover(signatures[i]);
            uint256 index = governanceIndex[signer];
            if (index == 0) revert InvalidGovernanceSigner();
            uint256 mask = 1 << (index - 1);
            if ((seen & mask) != 0) revert DuplicateGovernanceSigner();
            seen |= mask;
            ++unique;
        }
        if (unique < GOVERNANCE_THRESHOLD) revert ThresholdNotMet();
    }

    function _setWatchers(address[] memory newWatchers) internal {
        if (newWatchers.length != WATCHER_COUNT) revert InvalidWatcherLength();
        for (uint256 i = 0; i < watcherSet.length; ++i) {
            watcherIndex[watcherSet[i]] = 0;
        }
        delete watcherSet;

        address[WATCHER_COUNT] memory packed;
        for (uint256 i = 0; i < WATCHER_COUNT; ++i) {
            address watcher = newWatchers[i];
            if (watcher == address(0)) revert WatcherZeroAddress();
            for (uint256 j = 0; j < i; ++j) {
                if (newWatchers[j] == watcher) revert DuplicateWatcherAddress();
            }
            watcherSet.push(watcher);
            watcherIndex[watcher] = i + 1;
            packed[i] = watcher;
        }

        emit WatcherSetUpdated(packed);
    }

    function _setGovernance(address[] memory newGovernance) internal {
        if (newGovernance.length != GOVERNANCE_COUNT) revert InvalidGovernanceLength();
        for (uint256 i = 0; i < governanceSet.length; ++i) {
            governanceIndex[governanceSet[i]] = 0;
        }
        delete governanceSet;

        address[GOVERNANCE_COUNT] memory packed;
        for (uint256 i = 0; i < GOVERNANCE_COUNT; ++i) {
            address signer = newGovernance[i];
            if (signer == address(0)) revert GovernanceZeroAddress();
            for (uint256 j = 0; j < i; ++j) {
                if (newGovernance[j] == signer) revert DuplicateGovernanceAddress();
            }
            governanceSet.push(signer);
            governanceIndex[signer] = i + 1;
            packed[i] = signer;
        }

        emit GovernanceSetUpdated(packed);
    }

    function _setTokenStatus(address token, bool allowed) internal {
        if (token == address(0)) revert TokenZeroAddress();
        if (allowedTokens[token] == allowed) return; // Skip if no change
        allowedTokens[token] = allowed;
        emit TokenStatusUpdated(token, allowed);
    }

    /**
     * @notice Transfers ownership of a token contract to a new owner address.
     * @dev This function is used to facilitate token ownership migration during contract upgrades
     *      or bridge redeployments. It can be executed via governance action (3-of-5 threshold).
     * @param token The address of the token contract whose ownership will be transferred
     * @param newOwner The address of the new owner (must not be zero address)
     */
    function _transferTokenOwnership(address token, address newOwner) internal {
        if (token == address(0)) revert TokenZeroAddress();
        if (newOwner == address(0)) revert NewOwnerZeroAddress();

        // Get current owner before transfer
        (bool ownerOk, bytes memory ownerRes) = token.staticcall(
            abi.encodeWithSignature("owner()")
        );
        address oldOwner = ownerOk && ownerRes.length >= 32 ? abi.decode(ownerRes, (address)) : address(0);

        (bool ok, bytes memory res) = token.call(
            abi.encodeWithSignature("transferOwnership(address)", newOwner)
        );
        if (!ok) revert TransferOwnershipFailed(_bubbleRevert(res, "BridgeMultisig: transferOwnership failed"));

        emit TokenOwnershipTransferred(token, oldOwner, newOwner);
    }

    /**
     * @notice Maps a TON jetton to an EVM token address for bridge operations.
     * @dev This function is used to establish cross-chain token mappings (TON->EVM burn direction).
     *      Can only be executed via governance action (3-of-5 threshold).
     * @param tonJettonHash The keccak256 hash of the TON jetton root address
     * @param evmToken The EVM token contract address to map to
     */
    function _mapToken(bytes32 tonJettonHash, address evmToken) internal {
        if (tonJettonHash == bytes32(0)) revert JettonHashZeroValue();
        if (evmToken == address(0)) revert TokenZeroAddress();
        if (tokenMappings[tonJettonHash] == evmToken) return; // Skip if no change
        tokenMappings[tonJettonHash] = evmToken;
        emit TokenMapped(tonJettonHash, evmToken);
    }

    /**
     * @notice Sets the mint nonce to a specific value.
     * @dev This function allows governance to reset or update the mint nonce for recovery scenarios.
     *      Can only be executed via governance action (3-of-5 threshold).
     * @param newMintNonce The new mint nonce value
     */
    function _setMintNonce(uint64 newMintNonce) internal {
        uint64 oldMintNonce = mintNonce;
        if (oldMintNonce == newMintNonce) return; // Skip if no change
        mintNonce = newMintNonce;
        emit MintNonceSet(oldMintNonce, newMintNonce);
    }

    /**
     * @notice Sets the fee recipient address for a token contract.
     * @dev This function allows governance to update the fee recipient address for BridgedSIXR tokens.
     *      Can only be executed via governance action (3-of-5 threshold).
     * @param token The address of the token contract
     * @param feeRecipient The new fee recipient address
     */
    function _setFeeRecipient(address token, address feeRecipient) internal {
        if (token == address(0)) revert TokenZeroAddress();

        (bool ok, bytes memory res) = token.call(
            abi.encodeWithSignature("setFeeRecipient(address)", feeRecipient)
        );
        if (!ok) revert SetFeeRecipientFailed(_bubbleRevert(res, "BridgeMultisig: setFeeRecipient failed"));

        emit FeeRecipientSet(token, feeRecipient);
    }

    /**
     * @notice Sets the fee basis points for a token contract.
     * @dev This function allows governance to update the fee basis points for BridgedSIXR tokens.
     *      Can only be executed via governance action (3-of-5 threshold).
     * @param token The address of the token contract
     * @param feeBasisPoints The new fee basis points (100 = 1%, max 1000 = 10%)
     */
    function _setFeeBasisPoints(address token, uint256 feeBasisPoints) internal {
        if (token == address(0)) revert TokenZeroAddress();

        (bool ok, bytes memory res) = token.call(
            abi.encodeWithSignature("setFeeBasisPoints(uint256)", feeBasisPoints)
        );
        if (!ok) revert SetFeeBasisPointsFailed(_bubbleRevert(res, "BridgeMultisig: setFeeBasisPoints failed"));

        emit FeeBasisPointsSet(token, feeBasisPoints);
    }

    /**
     * @notice Increments the governance epoch to invalidate signatures from previous governance/watcher sets.
     * @dev Called automatically when watchers or governance members are rotated.
     *      This prevents replay of signatures collected before the rotation.
     */
    function _incrementGovernanceEpoch() internal {
        ++governanceEpoch;
        emit GovernanceEpochUpdated(governanceEpoch);
    }

    /**
     * @notice Helper function to extract revert reason from failed external call.
     * @dev If the returned data contains a revert reason, it extracts and returns it.
     *      Otherwise, returns the provided fallback message.
     * @param returnData The bytes data returned from the failed call
     * @param fallbackMessage The message to return if no revert reason is found
     * @return A string containing either the extracted revert reason or the fallback message
     */
    function _bubbleRevert(bytes memory returnData, string memory fallbackMessage) internal pure returns (string memory) {
        if (returnData.length == 0) {
            return fallbackMessage;
        }

        // Check if the return data is a standard revert string (Error(string))
        // The signature of Error(string) is 0x08c379a0
        if (returnData.length >= 68 && bytes4(returnData) == 0x08c379a0) {
            assembly {
                // Skip the first 4 bytes (function selector) and decode the string
                returnData := add(returnData, 0x04)
            }
            return abi.decode(returnData, (string));
        }

        return fallbackMessage;
    }

    /**
     * @notice Gets the EVM token address mapped to a TON jetton hash.
     * @param tonJettonHash The keccak256 hash of the TON jetton root address
     * @return address The mapped EVM token address (zero address if not mapped)
     */
    function getTokenMapping(bytes32 tonJettonHash) external view returns (address) {
        return tokenMappings[tonJettonHash];
    }
}
