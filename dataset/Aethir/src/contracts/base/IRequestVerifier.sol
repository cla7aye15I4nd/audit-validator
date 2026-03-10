// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

/**
 * @title IRequestVerifier
 * @notice Defines the basic interface for the Request Verifier
 */
interface IRequestVerifier {
    /// @notice verifiable off-chain data
    /// @param nonce: off-chain request id
    /// @param deadline: deadline timestamp as seconds since Unix epoch
    /// @param lastUpdateBlock: last indexed event blocknumber
    /// @param version: system version
    /// @param sender: sender address
    /// @param target: target contract address
    /// @param method: target function selector
    /// @param params: request parameters (format according to system version)
    /// @param payloads: data payloads (format according to system version)
    /// @param proof: data proof (Validator Signature or Merkle Proof)
    struct VerifiableData {
        uint64 nonce;
        uint64 deadline;
        uint64 lastUpdateBlock;
        uint64 version;
        address sender;
        address target;
        bytes4 method;
        bytes params;
        bytes payloads;
        bytes proof;
    }

    /// @notice check risk of the request
    /// @param method: target function selector
    /// @param sender: sender address
    function checkRisk(bytes4 method, address sender) external;

    /// @notice verify verifiable data with operator signatures
    /// @param vdata: verifiable data
    /// @param method: target function selector
    function verify(VerifiableData calldata vdata, address caller, bytes4 method) external returns (bytes32 hash);

    /// @notice verify verifiable data with initiator signatures
    /// @param vdata: verifiable data
    /// @param method: target function selector
    function verifyInitiator(VerifiableData calldata vdata, bytes4 method) external returns (bytes32 hash);

    function getHash(VerifiableData calldata vdata) external view returns (bytes32);
}
