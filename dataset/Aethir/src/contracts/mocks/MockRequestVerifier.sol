// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {IRegistry, IRequestVerifier, BaseService, REQUEST_VERIFIER_ID} from "../Index.sol";

contract MockRequestVerifier is IRequestVerifier, BaseService {
    constructor(IRegistry registry) BaseService(registry, REQUEST_VERIFIER_ID) {}

    function checkRisk(bytes4, address) external pure override {}

    function verify(VerifiableData calldata, address, bytes4) external returns (bytes32 hash) {}

    function verifyInitiator(VerifiableData calldata, bytes4) external returns (bytes32 hash) {}

    function getHash(VerifiableData calldata) external view returns (bytes32) {}
}
