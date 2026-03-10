// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {IRegistry} from "./IRegistry.sol";
import {IRequestVerifier} from "./IRequestVerifier.sol";

abstract contract BaseService {
    IRegistry public immutable _registry;
    bytes4 private immutable _interfaceId;

    constructor(IRegistry registry, bytes4 interfaceId) {
        _registry = registry;
        _interfaceId = interfaceId;
        _registry.register(interfaceId);
    }

    function getServiceId() external view returns (bytes4) {
        return _interfaceId;
    }

    /// @notice Returns the verifier contract.
    function _verifier() internal view returns (IRequestVerifier) {
        return IRequestVerifier(_registry.getAddress(type(IRequestVerifier).interfaceId));
    }
}
