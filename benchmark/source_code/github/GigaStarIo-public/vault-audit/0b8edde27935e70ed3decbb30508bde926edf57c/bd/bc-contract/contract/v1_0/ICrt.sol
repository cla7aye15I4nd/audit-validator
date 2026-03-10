// SPDX-License-Identifier: UNLICENSED
// Copyright 2025, GigaStar Technologies LLC, All Rights Reserved, https://gigastar.io
pragma solidity ^0.8.29;

// import '@openzeppelin/contracts/interfaces/IERC1155.sol'; // Included by IERC1155MetadataURI
import '@openzeppelin/contracts/token/ERC1155/extensions/IERC1155MetadataURI.sol';
import '@openzeppelin/contracts/utils/introspection/IERC165.sol';

import './IContractUser.sol';

/// @dev Channel Revenue Token features including ERC-165, ERC-1155, and ContractUser
// prettier-ignore
interface ICrt is IERC165, IERC1155MetadataURI, IContractUser {
    // ────────────────────────────────────────────────────────────────────────────
    // Types
    // ────────────────────────────────────────────────────────────────────────────

    // ───────────────────────────────────────
    // Enums
    // ───────────────────────────────────────
    enum EventMode  { None, PerXfer, PerBatch,
                      Count // Metadata: Used for input validation; Must remain last item
                    }

    // ───────────────────────────────────────
    // Events
    // ───────────────────────────────────────
    event XferAgentUpdated(address account, bool authorized);

    event TransferMany( address operator,
        address[] froms,
        address[] tos,
        uint256[] ids,
        uint256[] values
    );

    // ───────────────────────────────────────
    // Errors
    // ───────────────────────────────────────
    error BalanceUnderflow(address from, uint balance, uint needed, uint tokenId, uint index);
    error SupplyUnderflow(address from, uint balance, uint needed, uint tokenId, uint index);

    // ────────────────────────────────────────────────────────────────────────────
    // Functions
    // ────────────────────────────────────────────────────────────────────────────
    // No `mint` or `burn` functions as these actions are integrated into the transfer features

    function setApprovalForAllEx(uint40 seqNumEx, UUID reqId, address spender, bool approved) external;

    function safeTransferFromEx(uint40 seqNumEx, UUID reqId, address from, address to, uint id, uint value) external;

    function safeBatchTransferFromEx(uint40 seqNumEx, UUID reqId, address from, address to,
        uint[] calldata ids, uint[] calldata values) external;

    function transferBatch(uint40 seqNumEx, UUID reqId, EventMode eventMode,
        address[] calldata froms,
        address[] calldata tos,
        uint[] calldata ids,
        uint[] calldata values
    ) external;

    function setUri(uint40 seqNumEx, UUID reqId, string calldata newUri) external;

    // ───────────────────────────────────────
    // Setup
    // ───────────────────────────────────────

    function initialize(address creator, UUID reqId, string memory url) external;

    // ───────────────────────────────────────
    // Getters
    // ───────────────────────────────────────

    function getTokenCount() external view returns(uint);

    function getTokenIds(uint iBegin, uint count) external view returns(uint[] memory tokenIds);

    function getTokenSupply(uint tokenId) external view returns(uint);
}
