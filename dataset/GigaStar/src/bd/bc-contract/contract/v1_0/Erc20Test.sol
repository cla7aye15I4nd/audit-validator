// SPDX-License-Identifier: UNLICENSED
// Copyright 2025, GigaStar Technologies LLC, All Rights Reserved, https://gigastar.io
pragma solidity ^0.8.29;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

import './CallTracker.sol';

/// @dev Test ERC-20 currency
/// @custom:api protected
/// @custom:deploy basic
contract Erc20Test is ERC20, CallTracker {
    // ────────────────────────────────────────────────────────────────────────────
    // Types
    // ────────────────────────────────────────────────────────────────────────────

    // ───────────────────────────────────────
    // Errors
    // ───────────────────────────────────────
    error LengthMismatch(uint a, uint b);
    error SyntheticError(uint code);

    // ────────────────────────────────────────────────────────────────────────────
    // Constants
    // ────────────────────────────────────────────────────────────────────────────
    uint constant VERSION = 10; // 123 => Major: 12, Minor: 3 (always 1 digit)

    // ────────────────────────────────────────────────────────────────────────────
    // Fields
    // ────────────────────────────────────────────────────────────────────────────
    bool _doFailApprove;
    bool _doFailXfer;
    bool _doRevertApprove;
    bool _doRevertAllowance;
    bool _doRevertXfer;
    bool _doRevertBalanceOf;

    // ────────────────────────────────────────────────────────────────────────────
    // Functions
    // ────────────────────────────────────────────────────────────────────────────

    // ───────────────────────────────────────
    // Contract Setup
    // ───────────────────────────────────────

    /// @custom:api public
    constructor(string memory symbol)
        ERC20('Test Token', symbol)
    {
        __CallTracker_init(msg.sender, UuidZero);
    }

    /// @dev Mint `qty` tokens to `addr`
    /// - For on-chain calls
    /// @custom:api private
    function mint(address addr, uint qty) external {
        _mint(addr, qty);
    }

    /// @dev Burn `qty` tokens from `addr`
    /// - For on-chain calls
    /// @custom:api private
    function burn(address addr, uint qty) external {
        _burn(addr, qty);
    }

    /// @dev Mint/create `qty` tokens to `addr`
    /// - For off-chain calls
    /// @param seqNumEx =0 for on-chain caller, else expected sequence number for determinism, etc; See `CallTracker`
    /// @param reqId Request ID, unique amongst requests across all callers
    /// @param addr Receipient of new tokens
    /// @param qty Quantity to create; Value must be scaled relative to `decimals`
    /// @custom:api public
    function mintTokens(uint40 seqNumEx, UUID reqId, address addr, uint qty) external {
        _mint(addr, qty);
        _setCallRes(msg.sender, seqNumEx, reqId, true);
    }

    /// @dev Burn/destroy `qty` tokens from `addr`
    /// - For off-chain calls
    /// @param seqNumEx =0 for on-chain caller, else expected sequence number for determinism, etc; See `CallTracker`
    /// @param reqId Request ID, unique amongst requests across all callers
    /// @param addr Owner of existing tokens
    /// @param qty Quantity to destroy; Value must be scaled relative to `decimals`
    /// @custom:api public
    function burnTokens(uint40 seqNumEx, UUID reqId, address addr, uint qty) external {
        _burn(addr, qty);
        _setCallRes(msg.sender, seqNumEx, reqId, true);
    }

    /// @dev Get the current version
    function getVersion() external pure virtual returns(uint) { return VERSION; }

    // ───────────────────────────────────────
    // IERC20
    // ───────────────────────────────────────

    /// @dev Number of decimals implied in the qty
    /// - Example: Given 6 decimals then $9.123`456 is stored as 9,123,456 (ie qty x 1,000,000 = on-chain qty)
    function decimals() public pure override returns(uint8) { return 6; }

    /// @custom:api private
    function allowance(address owner, address spender) public view override returns (uint) {
        if (_doRevertAllowance) revert SyntheticError(1);
        return ERC20.allowance(owner, spender);
    }

    /// @custom:api private
    function approve(address spender, uint value) public override returns (bool) {
        if (_doFailApprove) return false;
        if (_doRevertApprove) revert SyntheticError(2);
        return ERC20.approve(spender, value);
    }

    /// @custom:api private
    function transferFrom(address from, address to, uint value) public override returns (bool) {
        if (_doFailXfer) return false;
        if (_doRevertXfer) revert SyntheticError(3);
        // Non-standard tokens that do not return a boolean are not supported, expecting well-behaved like USDC
        return ERC20.transferFrom(from, to, value);
    }

    /// @custom:api private
    function transfer(address to, uint value) public override returns (bool) {
        if (_doFailXfer) return false;
        if (_doRevertXfer) revert SyntheticError(4);
        return ERC20.transfer(to, value);
    }

    function balanceOf(address account) public view override returns (uint256) {
        if (_doRevertBalanceOf) revert SyntheticError(5);
        return ERC20.balanceOf(account);
    }

    // ───────────────────────────────────────
    // Test Helpers
    // ───────────────────────────────────────

    /// @dev Like `approve` but allows a test to set approval rather than only from the owner
    /// @custom:api private
    function setApproval(address owner, address spender, uint256 value) public {
        _approve(owner, spender, value, true);
    }

    // Allow error simulations via return code

    /// @custom:api private
    function setFailApprove(bool enable) public { _doFailApprove = enable; }

    /// @custom:api private
    function setFailXfer(bool enable) public { _doFailXfer = enable; }

    // Allow error simulation via revert

    /// @custom:api private
    function setRevertApprove(bool enable) public { _doRevertApprove = enable; }

    /// @custom:api private
    function setRevertAllowance(bool enable) public { _doRevertAllowance = enable; }

    /// @custom:api private
    function setRevertXfer(bool enable) public { _doRevertXfer = enable; }

    /// @custom:api private
    function setRevertBalanceOf(bool enable) public { _doRevertBalanceOf = enable; }
}
