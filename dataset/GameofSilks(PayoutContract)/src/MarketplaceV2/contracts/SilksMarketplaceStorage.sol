// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

// Constants for various roles and statuses.
bytes32 constant CONTRACT_ADMIN_ROLE = keccak256("silks.contracts.roles.ContractAdminRole");

// Custom errors for specific invalid operations.
error InvalidAddress(address _address);
error InvalidSignature(bytes _signature);
error InvalidIntValue(bytes32 _reason, uint256 _sent, uint256 _expected);
error InvalidStringValue(string _reason, string _sent, string _expected);
error ApprovalNotSetForMarketplace();
error NotTokenOwner(address _listingAddress, address _checkedAddress, uint256 tokenId);

// Library for managing the marketplace.
library SilksMarketplaceStorage {
    // Storage slot for the layout.
    bytes32 internal constant STORAGE_SLOT = keccak256('silks.contracts.storage.SilksMarketplace');
    
    // Struct for the layout of the marketplace.
    struct Layout {
        address royaltyReceiver;
        uint256 royaltyBasePoints;
    }
    
    // Function to retrieve the layout.
    function layout()
    internal
    pure
    returns (
        Layout storage _l
    ) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            _l.slot := slot
        }
    }
    
    function isValidateSignature(
        address _account,
        string memory _message,
        bytes memory _signature
    )
    internal
    view
    returns (
        bool isValidSignature
    )
    {
        bytes32 messageHash = keccak256(abi.encodePacked(_message));
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        return SignatureChecker.isValidSignatureNow(_account, ethSignedMessageHash, _signature);
    }
}
