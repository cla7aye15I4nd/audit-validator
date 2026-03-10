// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title BridgedSIXR
 * @notice ERC-20 representation of SIXR jetton bridged from TON
 *
 * This contract implements:
 * - Standard ERC-20 functionality
 * - TON bridge integration via redeemToTon() with configurable fee
 * - Owner-controlled minting (BridgeMultisig mints on TON→EVM bridge)
 *
 * Fee mechanism:
 * - EVM → TON: Fee stays on EVM (transferred to feeRecipient), rest is burned
 * - TON → EVM: BridgeMultisig mints tokens to recipient (no fee on this direction)
 */
contract BridgedSIXR is ERC20, Ownable {
    /// @notice Emitted when tokens are redeemed to TON (EVM→TON bridge)
    /// @param from Address that burned tokens on EVM
    /// @param tonRecipient TON address that will receive minted jettons
    /// @param amount Amount after fee deduction (18 decimals)
    /// @param fee Fee amount kept on EVM (18 decimals)
    event RedeemToTon(
        address indexed from,
        string tonRecipient,
        uint256 amount,
        uint256 fee
    );

    /// @notice Emitted when fee recipient is updated
    /// @param oldRecipient Previous fee recipient
    /// @param newRecipient New fee recipient
    event FeeRecipientUpdated(
        address indexed oldRecipient,
        address indexed newRecipient
    );

    /// @notice Emitted when fee basis points are updated
    /// @param oldFeeBps Previous fee basis points
    /// @param newFeeBps New fee basis points
    event FeeBasisPointsUpdated(uint256 oldFeeBps, uint256 newFeeBps);

    /// @notice Address that receives accumulated fees
    address public feeRecipient;

    /// @notice Fee in basis points (100 = 1%, 10000 = 100%)
    uint256 public feeBasisPoints;

    /// @notice Maximum allowed fee (10% = 1000 basis points)
    uint256 public constant MAX_FEE_BPS = 1000;

    /// @notice Basis points denominator
    uint256 private constant BPS_DENOMINATOR = 10000;

    constructor(
        string memory _name,
        string memory _symbol,
        address _owner,
        address _feeRecipient,
        uint256 _feeBasisPoints
    ) ERC20(_name, _symbol) Ownable(_owner) {
        require(_feeRecipient != address(0), "BridgedSIXR: fee recipient is zero address");
        require(_feeBasisPoints <= MAX_FEE_BPS, "BridgedSIXR: fee too high");

        feeRecipient = _feeRecipient;
        feeBasisPoints = _feeBasisPoints;
    }

    /**
     * @notice Redeems tokens to TON blockchain with fee
     * @dev Burns user's tokens, keeps fee on EVM, emits event for bridge watcher
     *
     * Flow:
     * 1. Calculate fee amount
     * 2. Transfer fee to feeRecipient
     * 3. Burn remaining amount
     * 4. Emit RedeemToTon event with net amount for bridge
     *
     * @param tonRecipient TON address in user-friendly format (EQ... or UQ...)
     * @param amount Amount to redeem in 18 decimals (before fee)
     */
    function redeemToTon(string calldata tonRecipient, uint256 amount) external {
        require(amount > 0, "BridgedSIXR: amount is zero");
        require(bytes(tonRecipient).length > 0, "BridgedSIXR: recipient is empty");

        // Calculate fee
        uint256 fee = (amount * feeBasisPoints) / BPS_DENOMINATOR;
        uint256 amountAfterFee = amount - fee;

        require(amountAfterFee > 0, "BridgedSIXR: amount after fee is zero");

        // Transfer fee to recipient (if fee > 0)
        if (fee > 0) {
            _transfer(msg.sender, feeRecipient, fee);
        }

        // Burn the amount after fee
        _burn(msg.sender, amountAfterFee);

        // Emit event for bridge watcher
        emit RedeemToTon(msg.sender, tonRecipient, amountAfterFee, fee);
    }

    /**
     * @notice Updates the fee recipient address
     * @dev Only callable by contract owner
     * @param newRecipient New fee recipient address
     */
    function setFeeRecipient(address newRecipient) external onlyOwner {
        require(newRecipient != address(0), "BridgedSIXR: fee recipient is zero address");

        address oldRecipient = feeRecipient;
        feeRecipient = newRecipient;

        emit FeeRecipientUpdated(oldRecipient, newRecipient);
    }

    /**
     * @notice Updates the fee basis points
     * @dev Only callable by contract owner
     * @param newFeeBps New fee in basis points (100 = 1%)
     */
    function setFeeBasisPoints(uint256 newFeeBps) external onlyOwner {
        require(newFeeBps <= MAX_FEE_BPS, "BridgedSIXR: fee too high");

        uint256 oldFeeBps = feeBasisPoints;
        feeBasisPoints = newFeeBps;

        emit FeeBasisPointsUpdated(oldFeeBps, newFeeBps);
    }

    /**
     * @notice Mints tokens to an address
     * @dev Only callable by contract owner (bridge multisig)
     * Used when bridging from TON to EVM
     * @param to Recipient address
     * @param amount Amount to mint (18 decimals)
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /**
     * @notice Calculates fee for a given amount
     * @param amount Amount in 18 decimals
     * @return fee Fee amount in 18 decimals
     */
    function calculateFee(uint256 amount) external view returns (uint256 fee) {
        return (amount * feeBasisPoints) / BPS_DENOMINATOR;
    }

    /**
     * @notice Calculates amount after fee deduction
     * @param amount Amount in 18 decimals (before fee)
     * @return amountAfterFee Amount after fee in 18 decimals
     */
    function calculateAmountAfterFee(uint256 amount) external view returns (uint256 amountAfterFee) {
        uint256 fee = (amount * feeBasisPoints) / BPS_DENOMINATOR;
        return amount - fee;
    }
}
