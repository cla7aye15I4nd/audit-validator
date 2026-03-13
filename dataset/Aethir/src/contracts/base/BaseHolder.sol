// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {IRegistry} from "./IRegistry.sol";
import {BaseService} from "./BaseService.sol";
import {IKYCWhitelist} from "../account/IKYCWhitelist.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

abstract contract BaseHolder is BaseService {
    using SafeERC20 for IERC20;

    constructor(IRegistry registry, bytes4 interfaceId) BaseService(registry, interfaceId) {}

    /// @notice Only fund withdraw admin or default admin can withdraw tokens
    /// For admin withdrawals, the receiver address is exempt from KYC verification.
    /// @param recipient The address to receive the tokens
    /// @param amount The amount of tokens to withdraw
    function _adminWithdrawToken(address recipient, uint256 amount) internal {
        require(recipient != address(0), "Invalid recipient");
        require(amount > 0, "Invalid amount");
        _registry.getACLManager().requireFundWithdrawAdmin(msg.sender);
        _registry.getATHToken().safeTransfer(recipient, amount);
    }

    /// @notice Throw error if receiver is not approved
    function _requireKYC(address recipient) internal {
        require(recipient != address(0), "Invalid recipient");
        IKYCWhitelist whitelist = IKYCWhitelist(_registry.getAddress(type(IKYCWhitelist).interfaceId));
        require(whitelist.checkKYC(recipient), "Receiver is not approved");
    }
}
