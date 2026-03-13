// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {
    IRegistry,
    IRequestVerifier,
    IAccountHandler,
    IAccountStorage,
    IStakeStorage,
    BaseService,
    ACCOUNT_HANDLER_ID,
    ACCOUNT_STORAGE_ID,
    STAKE_STORAGE_ID
} from "../Index.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract AccountHandler is IAccountHandler, BaseService {
    constructor(IRegistry registry) BaseService(registry, ACCOUNT_HANDLER_ID) {}

    // @inheritdoc IAccountHandler
    function createAccount(IRequestVerifier.VerifiableData calldata vdata) external override {
        bytes32 vhash = _verifier().verify(vdata, msg.sender, this.createAccount.selector);
        (address wallet, uint256 tid, Group memory initialGroup) = abi.decode(vdata.params, (address, uint256, Group));
        _createAccount(wallet, tid, initialGroup);

        emit AccountCreated(wallet, tid, initialGroup, vdata.nonce, vhash);
    }

    // @inheritdoc IAccountHandler
    function initialAccountsMigration(IRequestVerifier.VerifiableData calldata vdata) external override {
        bytes32 vhash = _verifier().verifyInitiator(vdata, this.initialAccountsMigration.selector);
        (address[] memory wallets, uint256[] memory tids, Group[] memory initialGroups) = abi.decode(
            vdata.params,
            (address[], uint256[], Group[])
        );
        require(wallets.length == tids.length && wallets.length == initialGroups.length, "lengths mismatch");
        for (uint256 i = 0; i < wallets.length; i++) {
            _createAccount(wallets[i], tids[i], initialGroups[i]);
        }

        emit AccountMigrationCompleted(wallets, tids, initialGroups, vdata.nonce, vhash);
    }

    function _createAccount(address wallet, uint256 tid, Group memory initialGroup) internal {
        require(tid > 0, "Invalid tid");
        require(wallet != address(0), "Invalid wallet");
        IAccountStorage db = _db();
        require(db.getWallet(tid) == address(0), "Account already exists");
        require(db.getTid(wallet) == 0, "Wallet already bound");
        db.bindWallet(tid, wallet);

        if (initialGroup.gid > 0) {
            require(initialGroup.tid == tid, "Invalid initial group");
            _createGroup(initialGroup);
        }
    }

    // @inheritdoc IAccountHandler
    function rebindWallet(IRequestVerifier.VerifiableData calldata vdata) external override {
        bytes32 vhash = _verifier().verify(vdata, msg.sender, this.rebindWallet.selector);
        (address newWallet, uint256 tid, bytes memory oldWalletSig) = abi.decode(
            vdata.params,
            (address, uint256, bytes)
        );
        IAccountStorage db = _db();

        require(tid > 0, "Invalid tid");
        address oldWallet = db.getWallet(tid);
        require(newWallet == msg.sender, "Permission denied");
        require(newWallet != oldWallet, "Invalid new wallet");
        require(db.getTid(newWallet) == 0, "Wallet already bound");

        require(oldWalletSig.length == 65, "Invalid old wallet signature len");
        bytes32 dataHash = keccak256(abi.encode(block.chainid, address(this), vdata.nonce, oldWallet, newWallet, tid));
        bytes32 hash = MessageHashUtils.toEthSignedMessageHash(dataHash);
        require(ECDSA.recover(hash, oldWalletSig) == oldWallet, "Invalid old wallet signature");

        emit WalletRebound(newWallet, tid, vdata.nonce, vhash);
        db.bindWallet(tid, newWallet);
    }

    // @inheritdoc IAccountHandler
    function createGroup(IRequestVerifier.VerifiableData calldata vdata) external override {
        bytes32 vhash = _verifier().verify(vdata, msg.sender, this.createGroup.selector);
        Group memory group = abi.decode(vdata.params, (Group));
        _createGroup(group);

        emit GroupCreated(group.tid, group.gid, vdata.nonce, vhash);
    }

    function _createGroup(Group memory group) internal {
        require(!_db().isGroupExist(group.tid, group.gid), "Group already exists");
        _validateAndSetGroup(group);
    }

    // @inheritdoc IAccountHandler
    function assignDelegator(IRequestVerifier.VerifiableData calldata vdata) external override {
        bytes32 vhash = _verifier().verify(vdata, msg.sender, this.assignDelegator.selector);
        (uint256 tid, uint256 gid, address delegator) = abi.decode(vdata.params, (uint256, uint256, address));
        _requireNeverStaked(tid, gid);
        require(delegator != address(0), "Invalid delegator");
        IAccountStorage db = _db();
        require(db.getWallet(tid) == msg.sender, "Permission denied");
        Group memory group = db.getGroup(tid, gid);
        group.delegator = delegator;
        emit DelegatorAssigned(delegator, tid, gid, vdata.nonce, vhash);
        db.setGroup(group);
    }

    // @inheritdoc IAccountHandler
    function revokeDelegator(IRequestVerifier.VerifiableData calldata vdata) external override {
        bytes32 vhash = _verifier().verify(vdata, msg.sender, this.revokeDelegator.selector);
        (uint256 tid, uint256 gid) = abi.decode(vdata.params, (uint256, uint256));
        _requireNeverStaked(tid, gid);
        IAccountStorage db = _db();
        require(db.getWallet(tid) == msg.sender, "Permission denied");
        Group memory group = db.getGroup(tid, gid);
        group.delegator = address(0);
        group.delegatorSetFeeReceiver = false;
        group.delegatorSetRewardReceiver = false;
        emit DelegatorRevoked(tid, gid, vdata.nonce, vhash);
        db.setGroup(group);
    }

    // @inheritdoc IAccountHandler
    function setFeeReceiver(IRequestVerifier.VerifiableData calldata vdata) external override {
        bytes32 vhash = _verifier().verify(vdata, msg.sender, this.setFeeReceiver.selector);
        (uint256 tid, uint256 gid, address feeReceiver) = abi.decode(vdata.params, (uint256, uint256, address));
        require(tid > 0, "Invalid tid");
        require(gid > 0, "Invalid gid");
        require(feeReceiver != address(0), "Invalid feeReceiver");
        IAccountStorage db = _db();
        Group memory group = db.getGroup(tid, gid);
        require(
            (!group.delegatorSetFeeReceiver && db.getWallet(tid) == msg.sender) ||
                (group.delegatorSetFeeReceiver && group.delegator == msg.sender),
            "Permission denied"
        );
        group.feeReceiver = feeReceiver;
        emit FeeReceiverSet(feeReceiver, tid, gid, vdata.nonce, vhash);
        db.setGroup(group);
    }

    // @inheritdoc IAccountHandler
    function revokeFeeReceiver(IRequestVerifier.VerifiableData calldata vdata) external override {
        bytes32 vhash = _verifier().verify(vdata, msg.sender, this.revokeFeeReceiver.selector);
        (uint256 tid, uint256 gid) = abi.decode(vdata.params, (uint256, uint256));
        require(tid > 0, "Invalid tid");
        require(gid > 0, "Invalid gid");
        IAccountStorage db = _db();
        Group memory group = db.getGroup(tid, gid);
        require(
            (!group.delegatorSetFeeReceiver && db.getWallet(tid) == msg.sender) ||
                (group.delegatorSetFeeReceiver && group.delegator == msg.sender),
            "Permission denied"
        );
        group.feeReceiver = address(0);
        emit FeeReceiverRevoked(tid, gid, vdata.nonce, vhash);
        db.setGroup(group);
    }

    // @inheritdoc IAccountHandler
    function setRewardReceiver(IRequestVerifier.VerifiableData calldata vdata) external override {
        bytes32 vhash = _verifier().verify(vdata, msg.sender, this.setRewardReceiver.selector);
        (uint256 tid, uint256 gid, address rewardReceiver) = abi.decode(vdata.params, (uint256, uint256, address));
        require(tid > 0, "Invalid tid");
        require(gid > 0, "Invalid gid");
        require(rewardReceiver != address(0), "Invalid rewardReceiver");
        IAccountStorage db = _db();
        Group memory group = db.getGroup(tid, gid);
        require(
            (!group.delegatorSetRewardReceiver && db.getWallet(tid) == msg.sender) ||
                (group.delegatorSetRewardReceiver && group.delegator == msg.sender),
            "Permission denied"
        );
        group.rewardReceiver = rewardReceiver;
        emit RewardReceiverSet(rewardReceiver, tid, gid, vdata.nonce, vhash);
        db.setGroup(group);
    }

    // @inheritdoc IAccountHandler
    function revokeRewardReceiver(IRequestVerifier.VerifiableData calldata vdata) external override {
        bytes32 vhash = _verifier().verify(vdata, msg.sender, this.revokeRewardReceiver.selector);
        (uint256 tid, uint256 gid) = abi.decode(vdata.params, (uint256, uint256));
        require(tid > 0, "Invalid tid");
        require(gid > 0, "Invalid gid");
        IAccountStorage db = _db();
        Group memory group = db.getGroup(tid, gid);
        require(
            (!group.delegatorSetRewardReceiver && db.getWallet(tid) == msg.sender) ||
                (group.delegatorSetRewardReceiver && group.delegator == msg.sender),
            "Permission denied"
        );
        group.rewardReceiver = address(0);
        emit RewardReceiverRevoked(tid, gid, vdata.nonce, vhash);
        db.setGroup(group);
    }

    // @inheritdoc IAccountHandler
    function updatePolicy(
        uint256 tid,
        uint256 gid,
        bool delegatorSetFeeReceiver,
        bool delegatorSetRewardReceiver
    ) external override {
        _verifier().checkRisk(this.updatePolicy.selector, msg.sender);
        _requireNeverStaked(tid, gid);
        IAccountStorage db = _db();
        require(db.getWallet(tid) == msg.sender, "Permission denied");
        Group memory group = db.getGroup(tid, gid);
        if (delegatorSetFeeReceiver || delegatorSetRewardReceiver) {
            require(group.delegator != address(0), "Delegator not set");
        }
        group.delegatorSetFeeReceiver = delegatorSetFeeReceiver;
        group.delegatorSetRewardReceiver = delegatorSetRewardReceiver;
        emit PolicyUpdated(tid, gid, delegatorSetFeeReceiver, delegatorSetRewardReceiver);
        db.setGroup(group);
    }

    function batchUpdateGroupSettings(IRequestVerifier.VerifiableData calldata vdata) external override {
        bytes32 vhash = _verifier().verify(vdata, msg.sender, this.batchUpdateGroupSettings.selector);
        Group[] memory groups = abi.decode(vdata.params, (Group[]));
        require(groups.length > 0, "Empty input");

        IAccountStorage db = _db();
        for (uint256 i = 0; i < groups.length; i++) {
            require(db.getWallet(groups[i].tid) == msg.sender, "Permission denied");
            require(db.isGroupExist(groups[i].tid, groups[i].gid), "Group not exists");
            _requireNeverStaked(groups[i].tid, groups[i].gid);
            _validateAndSetGroup(groups[i]);
        }
        emit GroupsUpdated(groups, vdata.nonce, vhash);
    }

    function batchSetReceivers(IRequestVerifier.VerifiableData calldata vdata) external override {
        bytes32 vhash = _verifier().verify(vdata, msg.sender, this.batchSetReceivers.selector);
        (
            uint256[] memory tids,
            uint256[] memory gids,
            address[] memory feeReceivers,
            address[] memory rewardReceivers
        ) = abi.decode(vdata.params, (uint256[], uint256[], address[], address[]));
        uint256 length = tids.length;
        require(length > 0, "Empty input");
        require(
            gids.length == length && feeReceivers.length == length && rewardReceivers.length == length,
            "lengths mismatch"
        );

        IAccountStorage db = _db();

        Receiver[] memory receivers = new Receiver[](length);

        for (uint256 i = 0; i < length; i++) {
            require(tids[i] > 0, "Invalid tid");
            require(gids[i] > 0, "Invalid gid");
            Group memory group = db.getGroup(tids[i], gids[i]);
            bool isHost = db.getWallet(tids[i]) == msg.sender;
            bool isDelegator = group.delegator == msg.sender;
            bool canSetFee = (group.delegatorSetFeeReceiver && isDelegator) ||
                (isHost && !group.delegatorSetFeeReceiver);
            bool canSetReward = (group.delegatorSetRewardReceiver && isDelegator) ||
                (isHost && !group.delegatorSetRewardReceiver);
            require(canSetFee || canSetReward, "Lacks permission");

            receivers[i] = Receiver({
                feeReceiver: address(0),
                rewardReceiver: address(0),
                tid: tids[i],
                gid: gids[i],
                setFeeReceiver: false,
                setRewardReceiver: false
            });

            if (canSetFee) {
                group.feeReceiver = feeReceivers[i];

                receivers[i].feeReceiver = feeReceivers[i];
                receivers[i].setFeeReceiver = true;
            } else {
                require(feeReceivers[i] == address(0), "Permission denied");
            }

            if (canSetReward) {
                group.rewardReceiver = rewardReceivers[i];

                receivers[i].rewardReceiver = rewardReceivers[i];
                receivers[i].setRewardReceiver = true;
            } else {
                require(rewardReceivers[i] == address(0), "Permission denied");
            }

            db.setGroup(group);
        }

        emit ReceiversSet(receivers, vdata.nonce, vhash);
    }

    function _validateAndSetGroup(Group memory group) internal {
        require(group.tid > 0, "Invalid tid");
        require(group.gid > 0, "Invalid gid");
        if (group.delegator != address(0)) {
            require(!group.delegatorSetFeeReceiver || group.feeReceiver == address(0), "Logical conflict");
            require(!group.delegatorSetRewardReceiver || group.rewardReceiver == address(0), "Logical conflict");
        } else {
            require(!group.delegatorSetFeeReceiver && !group.delegatorSetRewardReceiver, "Delegator not set");
        }
        _db().setGroup(group);
    }

    /// @notice Returns the group information.
    function getGroup(uint256 tid, uint256 gid) external view override returns (Group memory) {
        return _db().getGroup(tid, gid);
    }

    /// @notice returns the address of the account storage
    function _db() private view returns (IAccountStorage) {
        return IAccountStorage(_registry.getAddress(ACCOUNT_STORAGE_ID));
    }

    /// @notice Once active staking has occurred within a group, neither the delegator settings nor the group configurations can be modified.
    function _requireNeverStaked(uint256 tid, uint256 gid) private view {
        require(tid > 0, "Invalid tid");
        require(gid > 0, "Invalid gid");
        IStakeStorage staking = IStakeStorage(_registry.getAddress(STAKE_STORAGE_ID));
        require(!staking.isStaked(tid, gid), "Group is staked before");
    }
}
