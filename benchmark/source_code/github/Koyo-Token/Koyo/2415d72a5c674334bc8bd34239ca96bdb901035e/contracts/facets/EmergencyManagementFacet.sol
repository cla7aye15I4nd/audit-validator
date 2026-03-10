// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "./FacetBase.sol";
import "./ReentrancyGuardBase.sol";
import "../libraries/LibDiamond.sol";
import "../libraries/RoleConstants.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title EmergencyManagementFacet
 * @dev Manages emergency operations and circuit breakers for the protocol
 * @notice This contract implements emergency controls with proper timelocks and access controls
 * @custom:security-contact security@koyodex.com
 */
contract EmergencyManagementFacet is FacetBase, ReentrancyGuardBase {
    using SafeERC20 for IERC20;

    uint256 private constant EMERGENCY_DELAY = 6 hours;
    uint256 private constant CIRCUIT_BREAKER_DELAY = 1 hours;
    uint256 private constant MAX_EMERGENCY_ACTIONS = 10;

    /**
     * @dev Emitted when the protocol is paused
     * @param admin Address of the admin who paused the protocol
     * @param timestamp Time when the protocol was paused
     */
    event ProtocolPaused(
        address indexed admin,
        uint256 timestamp
    );

    /**
     * @dev Emitted when the protocol is unpaused
     * @param admin Address of the admin who unpaused the protocol
     * @param timestamp Time when the protocol was unpaused
     */
    event ProtocolUnpaused(
        address indexed admin,
        uint256 timestamp
    );

    /**
     * @dev Emitted when an emergency withdrawal is scheduled
     * @param token Address of the token to be withdrawn
     * @param recipient Address that will receive the withdrawn tokens
     * @param amount Amount of tokens to be withdrawn
     * @param effectiveTime Time when the withdrawal can be executed
     */
    event EmergencyWithdrawalScheduled(
        address indexed token,
        address indexed recipient,
        uint256 amount,
        uint256 effectiveTime
    );

    /**
     * @dev Emitted when an emergency withdrawal is executed
     * @param token Address of the withdrawn token
     * @param recipient Address that received the withdrawn tokens
     * @param amount Amount of tokens withdrawn
     * @param timestamp Time when the withdrawal was executed
     */
    event EmergencyWithdrawalExecuted(
        address indexed token,
        address indexed recipient,
        uint256 amount,
        uint256 timestamp
    );

    /**
     * @dev Emitted when a circuit breaker is triggered
     * @param breaker Identifier of the triggered circuit breaker
     * @param timestamp Time when the circuit breaker was triggered
     * @param recoveryTime Time when the circuit breaker can be reset
     */
    event CircuitBreakerTriggered(
        bytes32 indexed breaker,
        uint256 timestamp,
        uint256 recoveryTime
    );

    /**
     * @dev Emitted when a circuit breaker is reset
     * @param breaker Identifier of the reset circuit breaker
     * @param timestamp Time when the circuit breaker was reset
     */
    event CircuitBreakerReset(
        bytes32 indexed breaker,
        uint256 timestamp
    );

    /**
     * @dev Modifier that checks if the caller has the specified role
     * @param role The role required to execute the function
     */
    modifier onlyRole(bytes32 role) {
        require(LibDiamond.diamondStorage().roles[role][msg.sender], "Must have required role");
        _;
    }

    /**
     * @dev Modifier to check if emergency action is allowed
     */
    modifier whenEmergencyAllowed() {
        require(!isCircuitBreakerActive("EMERGENCY"), "Emergency circuit breaker active");
        _;
    }

    /**
     * @notice Initializes the emergency management system
     * @dev Can only be called by admin and only once
     */
    function initializeEmergencySystem() external onlyRole(RoleConstants.ADMIN_ROLE) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        require(!ds.initialized, "Already initialized");
        ds.initialized = true;
    }

    /**
     * @notice Pauses the protocol
     * @dev Can only be called by admin and when emergency circuit breaker is not active
     */
    function pauseProtocol() external nonReentrant onlyRole(RoleConstants.ADMIN_ROLE) whenEmergencyAllowed {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        require(!ds.paused, "Protocol already paused");
        ds.paused = true;
        
        emit ProtocolPaused(msg.sender, block.timestamp);
    }

    /**
     * @notice Unpauses the protocol
     * @dev Can only be called by admin
     */
    function unpauseProtocol() external nonReentrant onlyRole(RoleConstants.ADMIN_ROLE) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        require(ds.paused, "Protocol not paused");
        ds.paused = false;
        
        emit ProtocolUnpaused(msg.sender, block.timestamp);
    }

    /**
     * @notice Schedules an emergency withdrawal
     * @dev Can only be called by admin when protocol is paused
     * @param token Address of the token to withdraw
     * @param recipient Address to receive the withdrawn tokens
     * @param amount Amount of tokens to withdraw
     */
    function scheduleEmergencyWithdrawal(
        address token,
        address recipient,
        uint256 amount
    ) external nonReentrant onlyRole(RoleConstants.ADMIN_ROLE) whenEmergencyAllowed {
        require(token != address(0), "Invalid token");
        require(recipient != address(0), "Invalid recipient");
        require(amount > 0, "Invalid amount");

        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        require(ds.paused, "Protocol must be paused");

        bytes32 withdrawalId = keccak256(abi.encodePacked(token, recipient, amount, block.timestamp));
        
        LibDiamond.EmergencyWithdrawal memory withdrawal = LibDiamond.EmergencyWithdrawal({
            token: token,
            recipient: recipient,
            amount: amount,
            scheduledTime: block.timestamp + EMERGENCY_DELAY,
            executed: false
        });

        ds.emergencyWithdrawals[withdrawalId] = withdrawal;

        emit EmergencyWithdrawalScheduled(token, recipient, amount, withdrawal.scheduledTime);
    }

    /**
     * @notice Executes a scheduled emergency withdrawal
     * @dev Can only be called by admin after timelock period
     * @param withdrawalId The ID of the withdrawal to execute
     */
    function executeEmergencyWithdrawal(
        bytes32 withdrawalId
    ) external nonReentrant onlyRole(RoleConstants.ADMIN_ROLE) whenEmergencyAllowed {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        LibDiamond.EmergencyWithdrawal storage withdrawal = ds.emergencyWithdrawals[withdrawalId];

        require(withdrawal.scheduledTime > 0, "Withdrawal not scheduled");
        require(!withdrawal.executed, "Withdrawal already executed");
        require(block.timestamp >= withdrawal.scheduledTime, "Time lock not expired");
        require(ds.paused, "Protocol must be paused");

        withdrawal.executed = true;

        IERC20(withdrawal.token).safeTransfer(withdrawal.recipient, withdrawal.amount);

        emit EmergencyWithdrawalExecuted(
            withdrawal.token,
            withdrawal.recipient,
            withdrawal.amount,
            block.timestamp
        );
    }

    /**
     * @notice Triggers a circuit breaker
     * @dev Can only be called by admin
     * @param breakerId The ID of the circuit breaker to trigger
     */
    function triggerCircuitBreaker(
        bytes32 breakerId
    ) external nonReentrant onlyRole(RoleConstants.ADMIN_ROLE) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        LibDiamond.CircuitBreaker storage breaker = ds.circuitBreakers[breakerId];

        require(!breaker.triggered, "Circuit breaker already triggered");
        require(breaker.triggerCount < MAX_EMERGENCY_ACTIONS, "Max triggers reached");

        breaker.triggered = true;
        breaker.triggerTime = block.timestamp;
        breaker.recoveryTime = block.timestamp + CIRCUIT_BREAKER_DELAY;
        breaker.triggerCount++;

        emit CircuitBreakerTriggered(breakerId, block.timestamp, breaker.recoveryTime);
    }

    /**
     * @notice Resets a circuit breaker
     * @dev Can only be called by admin after recovery time
     * @param breakerId The ID of the circuit breaker to reset
     */
    function resetCircuitBreaker(
        bytes32 breakerId
    ) external nonReentrant onlyRole(RoleConstants.ADMIN_ROLE) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        LibDiamond.CircuitBreaker storage breaker = ds.circuitBreakers[breakerId];

        require(breaker.triggered, "Circuit breaker not triggered");
        require(block.timestamp >= breaker.recoveryTime, "Recovery time not reached");

        breaker.triggered = false;
        breaker.triggerTime = 0;
        breaker.recoveryTime = 0;

        emit CircuitBreakerReset(breakerId, block.timestamp);
    }

    /**
     * @notice Checks if a circuit breaker is active
     * @param breakerId The ID of the circuit breaker to check
     * @return bool Whether the circuit breaker is active
     */
    function isCircuitBreakerActive(
        bytes32 breakerId
    ) public view returns (bool) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        LibDiamond.CircuitBreaker storage breaker = ds.circuitBreakers[breakerId];
        
        return breaker.triggered && block.timestamp < breaker.recoveryTime;
    }

    /**
     * @notice Gets information about a circuit breaker
     * @param breakerId The ID of the circuit breaker
     * @return triggered Whether the breaker is triggered
     * @return triggerTime When the breaker was triggered
     * @return recoveryTime When the breaker can be reset
     * @return triggerCount How many times the breaker has been triggered
     */
    function getCircuitBreakerInfo(
        bytes32 breakerId
    ) external view returns (
        bool triggered,
        uint256 triggerTime,
        uint256 recoveryTime,
        uint256 triggerCount
    ) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        LibDiamond.CircuitBreaker storage breaker = ds.circuitBreakers[breakerId];
        
        return (
            breaker.triggered,
            breaker.triggerTime,
            breaker.recoveryTime,
            breaker.triggerCount
        );
    }

    /**
     * @notice Returns the function selectors supported by this facet
     * @return selectors Array of function selectors
     */
    function getEmergencyFacetSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](9);
        selectors[0] = this.initializeEmergencySystem.selector;
        selectors[1] = this.pauseProtocol.selector;
        selectors[2] = this.unpauseProtocol.selector;
        selectors[3] = this.scheduleEmergencyWithdrawal.selector;
        selectors[4] = this.executeEmergencyWithdrawal.selector;
        selectors[5] = this.triggerCircuitBreaker.selector;
        selectors[6] = this.resetCircuitBreaker.selector;
        selectors[7] = this.isCircuitBreakerActive.selector;
        selectors[8] = this.getCircuitBreakerInfo.selector;
        return selectors;
    }
}