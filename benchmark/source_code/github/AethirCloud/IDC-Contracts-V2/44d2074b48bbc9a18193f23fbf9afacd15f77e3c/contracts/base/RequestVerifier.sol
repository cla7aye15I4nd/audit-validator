// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {
    IRegistry,
    IRequestVerifier,
    IEmergencySwitch,
    IBlackListManager,
    IUserStorage,
    BaseService,
    REQUEST_VERIFIER_ID,
    EMERGENCY_SWITCH_ID,
    BLACKLIST_MANAGER_ID,
    USER_STORAGE_ID
} from "../Index.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract RequestVerifier is IRequestVerifier, BaseService {
    constructor(IRegistry registry) BaseService(registry, REQUEST_VERIFIER_ID) {}

    /// @inheritdoc IRequestVerifier
    function checkRisk(bytes4 method, address sender) public view override {
        require(_emegencySwitch().isAllowed(method), "EmergencyPaused");
        require(_blackList().isAllowed(sender, method), "BlackListed");
    }

    /// @inheritdoc IRequestVerifier
    function verify(
        VerifiableData calldata vdata,
        address caller,
        bytes4 method
    ) external override returns (bytes32 hash) {
        require(vdata.sender == caller, "SenderMismatch");
        require(vdata.target == msg.sender, "TargetMismatch");
        require(vdata.method == method, "MethodMismatch");
        require(vdata.version == _registry.getVersion(), "InvalidVersion");
        require(vdata.deadline >= block.timestamp, "DataExpired");

        checkRisk(method, vdata.sender);

        IUserStorage db = IUserStorage(_registry.getAddress(USER_STORAGE_ID));
        IUserStorage.UserData memory user = db.getUserData(vdata.sender);

        require(vdata.nonce > user.nonce, "NonceTooLow");
        // slither-disable-next-line timestamp
        require(vdata.lastUpdateBlock >= user.lastUpdateBlock, "DataTooOld");

        hash = getHash(vdata);
        checkValidatorSignatures(hash, vdata.proof);

        // update user data
        user.nonce = vdata.nonce;
        user.lastUpdateBlock = uint64(block.number);
        db.setUserData(vdata.sender, user);
    }

    /// @inheritdoc IRequestVerifier
    function verifyInitiator(
        VerifiableData calldata vdata,
        bytes4 method
    ) external view override returns (bytes32 hash) {
        require(vdata.target == msg.sender, "TargetMismatch");
        require(vdata.method == method, "MethodMismatch");
        require(vdata.version == _registry.getVersion(), "InvalidVersion");
        require(vdata.deadline >= block.timestamp, "DataExpired");

        hash = getHash(vdata);
        checkInitiatorSignatures(hash, vdata.proof);
    }

    /// @inheritdoc IRequestVerifier
    function getHash(VerifiableData calldata vdata) public view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    block.chainid,
                    vdata.nonce,
                    vdata.deadline,
                    vdata.lastUpdateBlock,
                    vdata.version,
                    vdata.sender,
                    vdata.target,
                    vdata.params,
                    vdata.payloads
                )
            );
    }

    function checkValidatorSignatures(bytes32 dataHash, bytes calldata signatures) public view {
        uint8 threshold = _registry.getACLManager().getRequiredSignatures();
        require(signatures.length >= (threshold * 65), "Invalid signature len");
        bytes32 hash = MessageHashUtils.toEthSignedMessageHash(dataHash);
        address[] memory signers = new address[](threshold);
        for (uint256 i = 0; i < threshold; i++) {
            signers[i] = ECDSA.recover(hash, signatures[i * 65:(i + 1) * 65]);
            _registry.getACLManager().requireValidator(signers[i]);
            for (uint256 j = 0; j < i; j++) {
                require(signers[j] != signers[i], "Duplicate signer");
            }
        }
    }

    function checkInitiatorSignatures(bytes32 dataHash, bytes calldata signatures) public view {
        uint8 threshold = _registry.getACLManager().getRequiredInitiatorSignatures();
        require(signatures.length >= (threshold * 65), "Invalid signature len");
        bytes32 hash = MessageHashUtils.toEthSignedMessageHash(dataHash);
        address[] memory signers = new address[](threshold);
        for (uint256 i = 0; i < threshold; i++) {
            signers[i] = ECDSA.recover(hash, signatures[i * 65:(i + 1) * 65]);
            _registry.getACLManager().requireInitSettlementOperator(signers[i]);
            for (uint256 j = 0; j < i; j++) {
                require(signers[j] != signers[i], "Duplicate signer");
            }
        }
    }

    /// @dev Get the emergency switch contract from the registry
    function _emegencySwitch() private view returns (IEmergencySwitch) {
        return IEmergencySwitch(_registry.getAddress(EMERGENCY_SWITCH_ID));
    }

    /// @dev Get the black list contract from the registry
    function _blackList() private view returns (IBlackListManager) {
        return IBlackListManager(_registry.getAddress(BLACKLIST_MANAGER_ID));
    }
}
