// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "./interfaces/IVaultConfig.sol";
import "./interfaces/IVault.sol";
import "./utils/SafeToken.sol";
import "./interfaces/IWETH.sol";

interface IERC20 {
    function decimals() external view returns (uint8);
}

contract Vault is IVault, ERC20Upgradeable, ReentrancyGuardUpgradeable, OwnableUpgradeable {
    // @notice Libraries
    using SafeToken for address;

    /// @dev Flags for manage execution scope
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private constant _NO_ID = type(uint256).max;
    address private constant _NO_ADDRESS = address(1);

    /// @dev stake contract
    address public constant STAKE_CONTRACT = address(0x8F53fA7928305Fd4f78c12BA9d9DE6B2420A2188);

    /// @dev Temporay variables to manage execution scope
    uint256 public _IN_EXEC_LOCK;
    uint256 public POSITION_ID;
    address public STRATEGY;

    /// @dev Attributes for Vault
    /// token - address of the token to be deposited in this pool
    /// name - name of the ibERC20
    /// symbol - symbol of ibERC20
    /// decimals - decimals of ibERC20, this depends on the decimal of the token
    /// debtToken - just a simple ERC20 token for staking with FairLaunch
    address public override token;
    //address public debtToken;

    struct Position {
        address worker;
        address owner;
        uint256 debtShare;
    }

    IVaultConfig public config; // address(0)
    mapping(uint256 => Position) public positions;
    uint256 public nextPositionID; // 1
    //uint256 public fairLaunchPoolId;

    uint256 public vaultDebtShare; // always zero
    uint256 public vaultDebtVal; // always zero
    uint256 public lastAccrueTime; // set in init()
    uint256 public reservePool; // always zero

    /**
     * Modifier
     */

    /// @dev Ensure that the function is called with the execution scope
    modifier inExec() {
        require(POSITION_ID != _NO_ID, "not within execution scope");
        require(STRATEGY == msg.sender, "not from the strategy");
        require(_IN_EXEC_LOCK == _NOT_ENTERED, "in exec lock");
        _IN_EXEC_LOCK = _ENTERED;
        _;
        _IN_EXEC_LOCK = _NOT_ENTERED;
    }

    /// @dev Add more debt to the bank debt pool.
    modifier accrue(uint256 value) {
        if (block.timestamp > lastAccrueTime) {
            uint256 interest = pendingInterest(value);
            uint256 toReserve = interest * config.getReservePoolBps() / 10000;
            reservePool = reservePool + toReserve;
            vaultDebtVal = vaultDebtVal + interest;
            lastAccrueTime = block.timestamp;
        }
        _;
    }

    /**
     * Initialization
     */
    function initialize(IVaultConfig _config, address _token, string calldata _name, string calldata _symbol)
        //address _debtToken
        external
        initializer
    {
        OwnableUpgradeable.__Ownable_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
        ERC20Upgradeable.__ERC20_init(_name, _symbol);

        nextPositionID = 1;
        config = _config;
        lastAccrueTime = block.timestamp;
        token = _token;

        //SafeToken.safeApprove(debtToken, config.getFairLaunchAddr(), type(uint256).max);

        // free-up execution scope
        _IN_EXEC_LOCK = _NOT_ENTERED;
        POSITION_ID = _NO_ID;
        STRATEGY = _NO_ADDRESS;
    }

    /**
     * View Functions
     */

    /// @dev Return the pending interest that will be accrued in the next call.
    /// @param value Balance value to subtract off address(this).balance when called from payable functions.
    function pendingInterest(uint256 value) public view returns (uint256) {
        if (block.timestamp > lastAccrueTime) {
            uint256 timePast = block.timestamp - lastAccrueTime;
            uint256 balance = SafeToken.myBalance(token) - value;
            uint256 ratePerSec = config.getInterestRate(vaultDebtVal, balance);
            return ratePerSec * (vaultDebtVal) * (timePast) / (1e18);
        } else {
            return 0;
        }
    }

    /// @dev Return the total token entitled to the token holders. Be careful of unaccrued interests.
    function totalToken() public view override returns (uint256) {
        return SafeToken.myBalance(token) + vaultDebtVal - (reservePool);
    }

    /**
     * User-facing Functions
     */

    /// @dev deposit from staking, only accept native eth
    function depositFromStake(address user, uint256 amountToken) external payable nonReentrant {
        require(msg.sender == STAKE_CONTRACT, "only called by stake contract");
        require(msg.value == amountToken, "invalid amount");

        // calc share
        uint256 totalBefore = totalToken();
        uint256 totalSupplyBefore = totalSupply();
        uint256 share = totalBefore == 0 ? amountToken : (amountToken * totalSupplyBefore) / totalBefore;

        IWETH(token).deposit{value: msg.value}();
        _mint(user, share);
        require(totalSupply() > 10 ** (uint256(decimals()) - 1), "no tiny shares");
    }

    /// @dev Add more token to the lending pool. Hope to get some good returns.

    function deposit(uint256 amountToken) external payable nonReentrant {
        uint256 totalBefore = totalToken();
        uint256 totalSupplyBefore = totalSupply();
        uint256 share = totalBefore == 0 ? amountToken : (amountToken * totalSupplyBefore) / totalBefore;

        _safeWrap(amountToken);
        _mint(msg.sender, share);
        require(totalSupply() > 10 ** (uint256(decimals()) - 1), "no tiny shares");
    }

    /// @dev Withdraw token from the lending and burning ibToken.
    function withdraw(uint256 share) external nonReentrant {
        uint256 amount = share * (totalToken()) / (totalSupply());
        _burn(msg.sender, share);
        _safeUnwrap(msg.sender, amount);
        require(totalSupply() > 10 ** (uint256(decimals()) - 1), "no tiny shares");
    }

    /// @dev Request Funds from user through Vault
    function requestFunds(address targetedToken, uint256 amount) external override inExec {
        SafeToken.safeTransferFrom(targetedToken, positions[POSITION_ID].owner, msg.sender, amount);
    }

    /**
     * Internal Functions
     */

    /// @dev Transfer to "to". Automatically unwrap if BTOKEN is WBNB
    /// @param to The address of the receiver
    /// @param amount The amount to be withdrawn
    function _safeUnwrap(address to, uint256 amount) internal {
        if (token == address(0x5300000000000000000000000000000000000004)) {
            IWETH(token).withdraw(amount);
            SafeToken.safeTransferETH(to, amount);
        } else {
            SafeToken.safeTransfer(token, to, amount);
        }
    }

    function _safeWrap(uint256 amount) internal {
        if (token == address(0x5300000000000000000000000000000000000004)) {
            require(msg.value == amount, "msg.value not enough");
            IWETH(token).deposit();
        } else {
            require(msg.value == 0, "not zero when token is not WETH");
            SafeToken.safeTransferFrom(token, msg.sender, address(this), amount);
        }
    }

    /**
     * Admin Functions
     */

    /// @dev Update bank configuration to a new address. Must only be called by owner.
    /// @param _config The new configurator address.
    function updateConfig(IVaultConfig _config) external onlyOwner {
        config = _config;
    }

    /// @dev Withdraw BaseToken reserve for underwater positions to the given address.
    /// @param to The address to transfer BaseToken to.
    /// @param value The number of BaseToken tokens to withdraw. Must not exceed `reservePool`.
    function withdrawReserve(address to, uint256 value) external onlyOwner nonReentrant {
        reservePool = reservePool - (value);
        SafeToken.safeTransfer(token, to, value);
    }

    /// @dev Reduce BaseToken reserve, effectively giving them to the depositors.
    /// @param value The number of BaseToken reserve to reduce.
    function reduceReserve(uint256 value) external onlyOwner {
        reservePool = reservePool - (value);
    }

    function decimals() public view override returns (uint8) {
        return IERC20(token).decimals();
    }
}
