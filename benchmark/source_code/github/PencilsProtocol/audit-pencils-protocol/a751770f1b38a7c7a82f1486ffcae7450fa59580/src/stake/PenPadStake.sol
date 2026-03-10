// SPDX-License-Identifier: GPL-3.0

pragma solidity =0.8.17;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";

interface IVault {
    function depositFromStake(address user, uint256 amountToken) external payable;
}

contract PenPadStake is
    Initializable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    AccessControlUpgradeable,
    EIP712Upgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /* Constant */
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");
    bytes32 public constant SIGNER_ROLE = keccak256("SIGNER_ROLE");
    uint256 public constant GAS_REFUND = 0.0005 ether;
    bytes32 public constant DECISION_DISAGREE = keccak256("disagree");
    bytes32 public constant DECISION_AGREE = keccak256("agree");
    bytes32 public constant DECISION_INSUFFICIENT = keccak256("insufficient");

    /* State Variables */
    uint256 public totalValueLocked; // total ETH locked
    uint256 public maxTotalValueLocked; // total ETH locked in history
    IERC20Upgradeable public penToken;

    /* For Signature */
    string private constant SIGNING_DOMAIN = "MyContractDomain";
    string private constant SIGNATURE_VERSION = "1";
    bytes32 private constant _TYPEHASH = keccak256(
        "UserAllocationData(address user,uint256 allocation,uint256 unlockAmount,uint256 expirationTime,bytes32 functionName,bytes32 activityName,bytes32 userDecision,address vaultAddress)"
    );

    struct UserAllocationData {
        address user;
        uint256 allocation; // Used for claim. @deprecated, filled with zero
        uint256 unlockAmount; // amount of eth unlockable, @backend.payload.diff
        uint256 expirationTime; // signature expiration time
        bytes32 functionName; // Determine this signature is for claim or unstake
        bytes32 activityName; // Determine this signature is for which activity
        bytes32 userDecision; // User decision 'agree'||'disagree'||' insufficient'
        address vaultAddress; // vault address
    }

    /* Parameters */
    uint256 public minStakeAmount; // minimum stake value when calling stake()
    uint256 public percentageDenominator; // calculate float number
    uint256 public stakeEndTimestamp; // timestamp that stop stake
    uint256 public unlockStartTimestamp; // timestamp that start unlock
    uint256 public stakedUserCount; // users that has staked

    /* User States */
    mapping(address => bool) public userClaimed; // user that has claimed
    mapping(address => uint256) public userStakeAmounts; // ETH that user staked in
    mapping(address => uint256) public userTotalStake; // ETH that user staked in and do not decrease
    mapping(bytes => bool) public usedSignatures; // signature that has been used

    uint256 public ownerBalance;
    mapping(address => uint256) public userRemainAmounts;
    uint256 public refundEndTimestamp; // timestamp that stop refund

    /* ========== EVENTS ========== */

    event Staked(address user, uint256 amount);
    event Unstake(address user, uint256 amount);
    event Claim(address user, uint256 allocation);
    event Withdrawn(address owner, uint256 amount);
    event ToVault(address user, bytes32 decision, uint256 amount);
    event Refund(address user, uint256 amount);
    /* ========== ERROR ========== */

    error stakeTooLow(address user, uint256 amount);
    error transferETHFailed();
    error cannotUnlockBeforeStartTime(uint256 blockTimestamp, uint256 unlockStartTimestamp);
    error stakePeriodExpired(uint256 blockTimestamp, uint256 unlockStartTimestamp);
    error signatureUsed(bytes signature);
    error invalidSigner(address signer, address recoveredSigner);
    error signatureExpired(uint256 expirationTime);
    error signerIsNotOwner(address signer);
    error userHasUnstaked(address user);
    error userHasClaimed(address user);
    error invalidSender(address sender, address user);
    error signatureFunctionError(bytes32 functionName);

    /* ========== MODIFIERS ========== */

    modifier checkUnlock() {
        if (block.timestamp < unlockStartTimestamp) {
            revert cannotUnlockBeforeStartTime(block.timestamp, unlockStartTimestamp);
        }
        _;
    }

    function initialize(
        address defaultAdmin,
        address pauser,
        address upgrader,
        address owner,
        address signer,
        uint256 _minStakeAmount,
        uint256 _percentageDenominator,
        uint256 _stakeEndTimestamp,
        uint256 _unlockStartTimestamp,
        address _penTokenAddress
    ) public initializer {
        __ReentrancyGuard_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __EIP712_init(SIGNING_DOMAIN, SIGNATURE_VERSION);

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(PAUSER_ROLE, pauser);
        _grantRole(UPGRADER_ROLE, upgrader);
        _grantRole(OWNER_ROLE, owner);
        _grantRole(SIGNER_ROLE, signer);

        minStakeAmount = _minStakeAmount;
        percentageDenominator = _percentageDenominator;
        unlockStartTimestamp = _unlockStartTimestamp;
        stakeEndTimestamp = _stakeEndTimestamp;
        penToken = IERC20Upgradeable(_penTokenAddress);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function stake() public payable nonReentrant whenNotPaused {
        if (block.timestamp >= stakeEndTimestamp) {
            revert stakePeriodExpired(block.timestamp, stakeEndTimestamp);
        }
        if (msg.value < minStakeAmount) {
            revert stakeTooLow(msg.sender, msg.value);
        }
        totalValueLocked = totalValueLocked + msg.value;
        maxTotalValueLocked = maxTotalValueLocked + msg.value;
        if (userStakeAmounts[msg.sender] == 0) {
            stakedUserCount++;
        }
        userStakeAmounts[msg.sender] = userStakeAmounts[msg.sender] + msg.value;
        userTotalStake[msg.sender] = userTotalStake[msg.sender] + msg.value;
        emit Staked(msg.sender, msg.value);
    }

    function unstake(UserAllocationData calldata data, bytes calldata signature, address signer)
        external
        nonReentrant
        checkUnlock
        whenNotPaused
    {
        verifySignature(data, signature, signer);
        uint256 stakeAmount = userStakeAmounts[data.user];
        if (stakeAmount == 0) {
            revert userHasUnstaked(msg.sender);
        }
        if (data.functionName != keccak256("unstake") || data.activityName != keccak256("season2")) {
            revert signatureFunctionError(data.functionName);
        }
        if (data.userDecision == DECISION_DISAGREE) {
            require(ownerBalance >= GAS_REFUND, "insufficient eth transfer to vault");

            // effect
            // // user stake amount
            uint256 remained = stakeAmount - data.unlockAmount;
            userStakeAmounts[data.user] = 0;
            userRemainAmounts[data.user] = remained;
            // // withdraw
            (bool success,) = data.user.call{value: data.unlockAmount}("");
            if (!success) {
                revert transferETHFailed();
            }
            // // total stake amount
            totalValueLocked -= data.unlockAmount;
            // // vault deposit
            ownerBalance -= GAS_REFUND;
            IVault(data.vaultAddress).depositFromStake{value: GAS_REFUND}(data.user, GAS_REFUND);

            // event
            emit Unstake(data.user, data.unlockAmount);
            emit ToVault(data.user, DECISION_DISAGREE, GAS_REFUND);
        } else if (data.userDecision == DECISION_AGREE) {
            require(ownerBalance >= GAS_REFUND, "insufficient eth transfer to vault");

            // effect
            // // user stake amount
            uint256 remained = stakeAmount - data.unlockAmount;
            userStakeAmounts[data.user] = 0;
            userRemainAmounts[data.user] = remained;
            // // total stake amount
            totalValueLocked -= data.unlockAmount;
            // // vault deposit
            ownerBalance -= GAS_REFUND;
            IVault(data.vaultAddress).depositFromStake{value: data.unlockAmount + GAS_REFUND}(
                data.user, data.unlockAmount + GAS_REFUND
            );

            // event
            emit Unstake(data.user, data.unlockAmount);
            emit ToVault(data.user, DECISION_AGREE, data.unlockAmount);
        } else if (data.userDecision == DECISION_INSUFFICIENT) {
            require(ownerBalance >= GAS_REFUND, "insufficient eth transfer to vault");

            // effect
            // // user stake amount
            userStakeAmounts[data.user] = 0;
            userRemainAmounts[data.user] = stakeAmount;
            // // total stake amount
            // totalValueLocked -= data.unlockAmount; // data.unlockAmount should be zero
            // // vault deposit
            ownerBalance -= GAS_REFUND;
            IVault(data.vaultAddress).depositFromStake{value: GAS_REFUND}(data.user, GAS_REFUND);
            // event
            emit ToVault(data.user, DECISION_INSUFFICIENT, GAS_REFUND);
        } else {
            revert("user decision unmatch");
        }
    }

    function refund() external nonReentrant {
        require(block.timestamp < refundEndTimestamp, "refund period end");
        uint256 remain = userRemainAmounts[msg.sender];
        userRemainAmounts[msg.sender] = 0;
        (bool success,) = payable(msg.sender).call{value: remain}("");
        if (!success) {
            revert transferETHFailed();
        }
        emit Refund(msg.sender, remain);
    }

    function verifySignature(UserAllocationData calldata data, bytes calldata signature, address signer) internal {
        if (msg.sender != data.user) {
            revert invalidSender(msg.sender, data.user);
        }

        if (usedSignatures[signature]) {
            revert signatureUsed(signature);
        }

        bytes32 digest = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    _TYPEHASH,
                    data.user,
                    data.allocation,
                    data.unlockAmount,
                    data.expirationTime,
                    data.functionName,
                    data.activityName,
                    data.userDecision,
                    data.vaultAddress
                )
            )
        );
        address recoveredSigner = ECDSAUpgradeable.recover(digest, signature);

        if (recoveredSigner != signer) {
            revert invalidSigner(signer, recoveredSigner);
        }

        if (block.timestamp >= data.expirationTime) {
            revert signatureExpired(data.expirationTime);
        }

        if (!hasRole(SIGNER_ROLE, signer)) {
            revert signerIsNotOwner(signer);
        }

        usedSignatures[signature] = true;
    }

    receive() external payable {
        stake();
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function depositByOwner() public payable onlyRole(OWNER_ROLE) {
        ownerBalance += msg.value;
    }

    function withdraw(uint256 amount) external onlyRole(OWNER_ROLE) {
        (bool success,) = msg.sender.call{value: amount}("");
        if (!success) {
            revert transferETHFailed();
        }
        emit Withdrawn(msg.sender, amount);
    }

    function setMinStakeAmount(uint256 _minStakeAmount) external onlyRole(OWNER_ROLE) {
        minStakeAmount = _minStakeAmount;
    }

    function setPercentageDenominator(uint256 _percentageDenominator) external onlyRole(OWNER_ROLE) {
        percentageDenominator = _percentageDenominator;
    }

    function setStakeEndTimestamp(uint256 _stakeEndTimestamp) external onlyRole(OWNER_ROLE) {
        stakeEndTimestamp = _stakeEndTimestamp;
    }

    function setUnlockStartTimestamp(uint256 _unlockStartTimestamp) external onlyRole(OWNER_ROLE) {
        unlockStartTimestamp = _unlockStartTimestamp;
    }

    function setPenTokenAddress(address _penTokenAddress) external onlyRole(OWNER_ROLE) {
        penToken = IERC20Upgradeable(_penTokenAddress);
    }

    function setRefundEndTimestamp(uint256 _timestamp) external onlyRole(OWNER_ROLE) {
        refundEndTimestamp = _timestamp;
    }

    /* ========== VIEWS ========== */

    // The following functions are overrides required by Solidity.

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}
}
