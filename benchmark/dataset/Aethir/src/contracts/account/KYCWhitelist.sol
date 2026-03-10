// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {IRegistry, IRequestVerifier, IKYCWhitelist, BaseService, KYC_WHITELIST_ID} from "../Index.sol";

contract KYCWhitelist is IKYCWhitelist, BaseService {
    mapping(address wallet => bool) private _verified;

    constructor(IRegistry registry) BaseService(registry, KYC_WHITELIST_ID) {}

    // @inheritdoc IKYCWhitelist
    function updateKYC(IRequestVerifier.VerifiableData calldata vdata) external override {
        bytes32 vhash = _verifier().verify(vdata, msg.sender, this.updateKYC.selector);
        (address[] memory wallets, bool[] memory verified) = abi.decode(vdata.params, (address[], bool[]));
        require(wallets.length == verified.length, "lengths mismatch");
        for (uint256 i = 0; i < wallets.length; i++) {
            _verified[wallets[i]] = verified[i];
        }
        emit KYCUpdated(wallets, verified, vdata.nonce, vhash);
    }

    // @inheritdoc IKYCWhitelist
    function checkKYC(address receiver) external view override returns (bool) {
        return _verified[receiver];
    }
}
