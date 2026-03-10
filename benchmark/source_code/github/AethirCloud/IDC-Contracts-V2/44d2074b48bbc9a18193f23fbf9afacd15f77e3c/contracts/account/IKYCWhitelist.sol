// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {IRequestVerifier} from "../base/IRequestVerifier.sol";

/// @title the interface for kyc whitelist
interface IKYCWhitelist {
    /// @notice Emitted when a kyc whitelist updated
    event KYCUpdated(address[] wallets, bool[] verified, uint64 nonce, bytes32 vhash);

    /// @notice update kyc whitelist
    /// @param vdata the verifiable data
    function updateKYC(IRequestVerifier.VerifiableData calldata vdata) external;

    /// @notice check receiver is verified against the KYC whitelist
    /// @param receiver the token receiver's wallet address
    /// @return verified true if the wallet is verified
    function checkKYC(address receiver) external returns (bool verified);
}
