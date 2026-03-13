// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "./IVaultConfig.sol";

interface IVault {
    function initialize(IVaultConfig _config, address, string calldata, string calldata)
        //address _debtToken
        external;
    /// @notice Return the total ERC20 entitled to the token holders. Be careful of unaccrued interests.
    function totalToken() external view returns (uint256);

    /// @notice Add more ERC20 to the bank. Hope to get some good returns.
    function deposit(uint256 amountToken) external payable;

    /// @notice Withdraw ERC20 from the bank by burning the share tokens.
    function withdraw(uint256 share) external;

    /// @notice Request funds from user through Vault
    function requestFunds(address targetedToken, uint256 amount) external;

    /// @notice Underlying token address
    function token() external view returns (address);

    /**
     * Event
     */
    event AddDebt(uint256 indexed id, uint256 debtShare);

    event RemoveDebt(uint256 indexed id, uint256 debtShare);

    event Work(uint256 indexed id, uint256 loan);

    event Kill(
        uint256 indexed id,
        address indexed killer,
        address owner,
        uint256 posVal,
        uint256 debt,
        uint256 prize,
        uint256 left
    );

    event AddCollateral(uint256 indexed id, uint256 amount, uint256 healthBefore, uint256 healthAfter);
}
