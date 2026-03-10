// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

interface IShopReferralInternal {
    error CodeAlreadyCreated();
    error AccountAlreadyCreated();
    error InvalidAccount(address account);
    error InvalidSponsor(address account);
    error AccountNotRegister(address account);
    error AccountHasNoSponsor(address account);
    error CodeAlreadySetError(uint256 code);
    error InsufficientValue();
    error OnlyCaller();
    error InvalidReferralCardAddress();
    error InvalidReferralAmount();
    error InvalidInput();

    event CodeSet(address indexed caller, address indexed account, uint256 indexed code);
    event CodeRemoved(address indexed caller, address indexed account, uint256 indexed code);
    event RelationBinded(address indexed caller, address indexed account, address indexed sponsor);
}
