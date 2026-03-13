// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title Swap
 * @dev A simple contract to facilitate atomic swaps of an ERC1155 NFT for an ERC20 token.
 * The swap is initiated by the seller, using a signature provided by the buyer.
 * This allows for gasless "listing" by the buyer.
 */
contract Swap is EIP712, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Custom error for expired deadlines.
    error DeadlineExpired(uint256 deadline, uint256 timestamp);
    // Custom error for invalid signatures.
    error InvalidSignature();
    // Custom error for used nonce
    error NonceAlreadyUsed();
    // Custom error for invalid addresses
    error InvalidAddress(address addr);
    // Custom error for invalid amounts
    error InvalidAmount(uint256 amount);

    // Mapping to track used nonces for each account
    // Using a mapping instead of a counter allows concurrent transactions:
    // - Different buyers can use the same nonce numbers simultaneously
    // - Same buyer can submit multiple transactions with different nonces in any order
    mapping(address => mapping(uint256 => bool)) private _nonces;

    /**
     * @dev Emitted when a swap is successfully executed.
     */
    event SwapExecuted(
        address indexed seller,
        address indexed buyer,
        address indexed nft,
        address token,
        uint256 nftId,
        uint256 amount,
        uint256 tokenAmount,
        uint256 nonce
    );

    /**
     * @dev Emitted when a nonce is marked as used
     */
    event NonceUsed(address indexed user, uint256 indexed nonce);

    // The struct that contains all the data for a swap, which is signed by the buyer.
    struct SwapData {
        address token; // The ERC20 token address for payment.
        address nft; // The ERC1155 NFT contract address.
        uint256 nftId; // The ID of the NFT to be swapped.
        uint256 amount; // The amount of the NFT to be swapped.
        uint256 tokenAmount; // The amount of ERC20 token to be paid.
        address buyer; // The address of the buyer who will receive the NFT and pay the tokens.
        address seller; // The address of the seller who will receive the tokens and send the NFT.
        uint256 deadline; // The deadline for the transaction.
        uint256 nonce; // The nonce to prevent replay attacks
    }

    // The keccak256 hash of the struct type definition, used for EIP-712.
    bytes32 private constant SWAP_TYPEHASH = keccak256(
        "SwapData(address token,address nft,uint256 nftId,uint256 amount,uint256 tokenAmount,address buyer,address seller,uint256 deadline,uint256 nonce)"
    );

    /**
     * @dev Sets the EIP-712 domain separator.
     */
    constructor() EIP712("Swap", "1") {}

    /**
     * @dev Executes the swap.
     * The seller (`msg.sender`) calls this function with the swap parameters and a signature from the buyer.
     * The contract verifies the signature and then atomically transfers the NFT from the seller to the buyer,
     * and the ERC20 tokens from the buyer to the seller.
     *
     * Requirements:
     * - The seller (`msg.sender`) must have approved this contract to transfer their NFT (`IERC1155.setApprovalForAll`).
     * - The buyer must have approved this contract to spend their ERC20 tokens (`IERC20.approve`).
     *
     * @param data The struct containing all swap parameters.
     * @param signature The EIP-712 signature from the buyer.
     */
    function swap(SwapData calldata data, bytes calldata signature) external nonReentrant {
        address seller = msg.sender;

        // Check addresses
        if (data.token == address(0)) revert InvalidAddress(data.token);
        if (data.nft == address(0)) revert InvalidAddress(data.nft);
        if (data.buyer == address(0)) revert InvalidAddress(data.buyer);
        
        // Ensure only the designated seller can execute this swap
        if (seller != data.seller) revert InvalidAddress(seller);

        // Check amounts
        if (data.amount == 0) revert InvalidAmount(data.amount);
        if (data.tokenAmount == 0) revert InvalidAmount(data.tokenAmount);
        
        // Check deadline
        if (block.timestamp > data.deadline) {
            revert DeadlineExpired(data.deadline, block.timestamp);
        }
        
        // Prevent buyer and seller from being the same address
        if (data.buyer == data.seller) revert InvalidAddress(data.buyer);

        // Check nonce
        if (isNonceUsed(data.buyer, data.nonce)) {
            revert NonceAlreadyUsed();
        }

        // Verify signature
        bytes32 digest = _hash(data);
        address recoveredSigner = ECDSA.recover(digest, signature);
        if (recoveredSigner == address(0) || recoveredSigner != data.buyer) {
            revert InvalidSignature();
        }

        // Mark nonce as used
        _nonces[data.buyer][data.nonce] = true;
        emit NonceUsed(data.buyer, data.nonce);

        // Execute the atomic swap.
        // Transfer NFT from seller to buyer.
        // The seller must have called `setApprovalForAll` on the NFT contract for this contract.
        IERC1155(data.nft).safeTransferFrom(seller, data.buyer, data.nftId, data.amount, "");

        // Transfer ERC20 tokens from buyer to seller.
        // The buyer must have called `approve` on the token contract for this contract.
        IERC20(data.token).safeTransferFrom(data.buyer, seller, data.tokenAmount);

        emit SwapExecuted(
            seller, data.buyer, data.nft, data.token, data.nftId, data.amount, data.tokenAmount, data.nonce
        );
    }

    /**
     * @dev Verifies if a signature is valid for the given swap data.
     * @param data The struct containing all swap parameters.
     * @param signature The EIP-712 signature from the buyer.
     * @return A boolean indicating whether the signature is valid and matches the buyer's address.
     */
    function verifySignature(SwapData calldata data, bytes calldata signature) public view returns (bool) {
        bytes32 digest = _hash(data);
        address recoveredSigner = ECDSA.recover(digest, signature);
        return recoveredSigner != address(0) && recoveredSigner == data.buyer;
    }

    /**
     * @dev Verifies if a swap is valid.
     * @param data The struct containing all swap parameters.
     * @param signature The EIP-712 signature from the buyer.
     * @return A boolean indicating whether the swap is valid.
     */
    function verifySwap(SwapData calldata data, bytes calldata signature) public view returns (bool) {
        if (block.timestamp > data.deadline) {
            return false;
        }
        if (isNonceUsed(data.buyer, data.nonce)) {
            return false;
        }
        return verifySignature(data, signature);
    }

    /**
     * @dev Returns if a nonce has been used for an address.
     */
    function isNonceUsed(address owner, uint256 nonce) public view virtual returns (bool) {
        return _nonces[owner][nonce];
    }

    /**
     * @dev Hashes the swap data struct according to the EIP-712 standard.
     * @param data The SwapData struct to hash.
     * @return The EIP-712 digest.
     */
    function _hash(SwapData calldata data) internal view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    SWAP_TYPEHASH,
                    data.token,
                    data.nft,
                    data.nftId,
                    data.amount,
                    data.tokenAmount,
                    data.buyer,
                    data.seller,
                    data.deadline,
                    data.nonce
                )
            )
        );
    }
}
