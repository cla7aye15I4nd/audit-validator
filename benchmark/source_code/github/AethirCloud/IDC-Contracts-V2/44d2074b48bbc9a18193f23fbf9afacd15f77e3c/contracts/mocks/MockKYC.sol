// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {IRegistry, IRequestVerifier, IKYCWhitelist, BaseService, KYC_WHITELIST_ID} from "../Index.sol";

contract MockKYC is IKYCWhitelist, BaseService {
    constructor(IRegistry registry) BaseService(registry, KYC_WHITELIST_ID) {}

    // @inheritdoc IKYCWhitelist
    function updateKYC(IRequestVerifier.VerifiableData calldata) external override {}

    // @inheritdoc IKYCWhitelist
    function checkKYC(address) external pure override returns (bool) {
        return true;
    }
}
