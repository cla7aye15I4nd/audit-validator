// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

library RoleConstants {
    
    /// @notice Role identifier for Margin Trading Facet
    bytes32 public constant MARGIN_TRADING_FACET_ROLE = keccak256("MARGIN_TRADING_FACET_ROLE");
    
    /// @notice Role identifier for Platform Contract
    bytes32 public constant PLATFORM_CONTRACT_ROLE = keccak256("PLATFORM_CONTRACT_ROLE");
    
    /// @notice Role identifier for Parameter Manager
    bytes32 public constant PARAMETER_MANAGER_ROLE = keccak256("PARAMETER_MANAGER_ROLE");
    
    /// @notice Role identifier for Margin Trader
    bytes32 public constant MARGIN_TRADER_ROLE = keccak256("MARGIN_TRADER_ROLE");
    
    /// @notice Role identifier for Staked Trader
    bytes32 public constant STAKED_TRADER_ROLE = keccak256("STAKED_TRADER_ROLE");
    
    /// @notice Role identifier for Token Admin
    bytes32 public constant TOKEN_ADMIN_ROLE = keccak256("TOKEN_ADMIN_ROLE");
    
    /// @notice Role identifier for Liquidator
    bytes32 public constant LIQUIDATOR_ROLE = keccak256("LIQUIDATOR_ROLE");

    /// @notice Role indetifier for OOO Router
    bytes32 public constant OOO_ROUTER_ROLE = keccak256("OOO_ROUTER_ROLE");
    
    /// @notice Role identifier for Price Manager
    bytes32 public constant PRICE_MANAGER = keccak256("PRICE_MANAGER");
    
    /// @notice Role identifier for Admin
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
}