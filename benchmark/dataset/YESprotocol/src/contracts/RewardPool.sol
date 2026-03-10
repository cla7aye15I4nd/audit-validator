// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract RewardPool is Initializable, AccessControlUpgradeable, UUPSUpgradeable {
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    address public signer;
    mapping(uint256 => bool) public orderIds;

    event SignerUpdate(address oldSigner, address newSigner);
    event Withdraw(address indexed member, uint256 orderId, uint256 amount, uint256 timestamp);

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    function initialize(address _signer) public initializer {
        __UUPSUpgradeable_init();
        __AccessControl_init();

        require(_signer != address(0), "Invalid signer address");
        signer = _signer;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
    }

    function setSigner(address _signer) external onlyRole(OPERATOR_ROLE) {
        require(_signer != address(0), "Invalid signer address");
        address oldSigner = signer;
        signer = _signer;
        emit SignerUpdate(oldSigner, _signer);
    }

    function checkSignature(bytes calldata signature, bytes32 hash) internal view returns (bool) {
        bytes32 messageHash = MessageHashUtils.toEthSignedMessageHash(hash);
        address _signer = ECDSA.recover(messageHash, signature);
        return signer == _signer;
    }

    function withdraw(bytes calldata signature, address _token, address to, uint256 amount, uint256 orderId, uint256 deadline) external {
        require(!orderIds[orderId], "duplicate withdraw");
        orderIds[orderId] = true;
        require(block.timestamp < deadline, "deadline limited");

        bytes32 hash = keccak256(abi.encode("withdraw", _token, to, amount, orderId, deadline));
        require(checkSignature(signature, hash), "invalid signatures");

        IERC20(_token).transfer(to, amount);
        emit Withdraw(msg.sender, orderId, amount, block.timestamp);
    }
}
