// SPDX-License-Identifier: MIT
pragma solidity ~0.8.20;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import {ERC20BurnableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {ERC20CappedUpgradeable} from "./extensions/ERC20CappedUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Helper} from "./lib/Helper.sol";
import {IWhitelistToggleExtension, IWhitelistCore} from "./interfaces/IWhitelistable.sol";
import {IBlacklistToggleExtension, IBlacklistCore} from "./interfaces/IBlacklistable.sol";
import {CommonErrors} from "./lib/AddressList.sol";
import {BaseToggleWhitelistable} from "./extensions/BaseToggleWhitelistable.sol";
import {BaseToggleBlacklistable} from "./extensions/BaseToggleBlacklistable.sol";
import {IExternalWhitelistImpl, IExternalBlacklistImpl} from "./interfaces/ExternalImpl.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {MulticallUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/MulticallUpgradeable.sol";
import {ERC20PermitUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";

error InvalidDecimals(uint8 decimals);
error MintingNotEnabled();
error BurningNotEnabled();
error PausingNotEnabled();
error AddrBalanceExceedsMaxAllowed(address addr, uint256 amount);
error RecipientBlacklisted(address addr);
error RecipientNotWhitelisted(address addr);
error MaxTokenAmountNotAllowed();

error TransferFromSenderNotWhitelisted(address sender);
error TransferFromSenderBlacklisted(address sender);

error InvalidRecipientAndAmount();
error UnAuthorisedSender();
error AuthorisedSenderEnabled();

error InvalidTaxBPS(uint256 taxBPS);
error InvalidDeflationBPS(uint256 deflationBPS);
error TokenIsNotTaxable();
error TokenIsNotDeflationary();

contract GLDBToken is
    Initializable,
    MulticallUpgradeable,
    ERC20Upgradeable,
    ERC20PausableUpgradeable,
    ERC20BurnableUpgradeable,
    ERC20CappedUpgradeable,
    ERC20PermitUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    BaseToggleWhitelistable,
    BaseToggleBlacklistable,
    IExternalWhitelistImpl,
    IExternalBlacklistImpl,
    IERC165
{
    /// @dev Emit when new document uri set
    event DocumentUriSet(string documentUri);
    event MaxTokenAmountPerSet(uint256 maxTokenAmount);

    event TaxConfigSet(address addr, uint256 taxBPS);
    event DeflationConfigSet(uint256 deflationBPS);

    event WhitelistImplSet(address indexed whitelistImpl);
    event BlacklistImplSet(address indexed blacklistImpl);

    event AuthorisedSenderSet(address indexed account, bool authorised);

    /// @dev MaxBPSAmount 10_000=100%
    uint256 private constant MAX_BPS_AMOUNT = 10_000;
    string public constant identifier = "GLDBToken";

    struct ConstructorParams {
        uint256 maxTokenAmountPerAddress;
        string metadata;
        string documentUri;
        /// tax config
        /// @dev Tax fee recipient address
        address taxAddress;
        /// @dev Tax fee BPS(100bps=1%)
        uint256 taxBPS;
        /// @dev Burn fee BPS(100bps=1%)
        uint256 deflationBPS;
        /// flags
        bool isBurnable;
        bool isMintable;
        bool isPausable;
        bool isBlacklistEnabled;
        bool isWhitelistEnabled;
        bool isMaxAmountPerAddressSet;
        bool isForceTransferAllowed;
        bool isTaxable;
        bool isDeflationary;
        bool authorisedSenderEnabled;
        /// whitelist implementation
        IWhitelistCore whitelistImpl;
        /// blacklist implementation
        IBlacklistCore blacklistImpl;
    }

    // Storage structures for ERC-7201 named storage pattern

    /// @dev Token features struct
    struct TokenFeatures {
        bool isBurnable;
        bool isMintable;
        bool isPausable;
        bool isMaxAmountPerAddressSet;
        bool isForceTransferAllowed;
        bool isTaxable;
        bool isDeflationary;
        bool authorisedSenderEnabled;
    }

    /// @custom:storage-location erc7201:eth.storage.Version
    struct VersionStorage {
        uint256 versionNumber;
        string version;
    }

    /// @custom:storage-location erc7201:eth.storage.TokenConfig
    struct TokenStorage {
        /// @dev Decimals of token
        uint8 decimals;
        /// @dev Initial supply of token will be mint during init
        uint256 initialSupply;
        /// @dev Max amount of token allowed per address
        uint256 maxTokenAmountPerAddress;
        /// @dev Metadata JSON
        string metadata;
        /// @dev Documentation of the security token
        string documentUri;
        /// @dev Token configuration
        TokenFeatures features;
    }

    /// @custom:storage-location erc7201:eth.storage.Tax
    struct TaxStorage {
        /// @dev Tax fee recipient address
        address taxAddress;
        /// @dev Tax fee BPS(100bps=1%)
        uint256 taxBPS;
        /// @dev Burn fee BPS(100bps=1%)
        uint256 deflationBPS;
    }

    /// @custom:storage-location erc7201:eth.storage.Auth
    struct AuthStorage {
        bool authorisedSenderEnabled;
        /// @dev Address who can send transaction
        mapping(address => bool) authorisedSender;
    }

    /// @custom:storage-location erc7201:eth.storage.WhiteBlackList
    struct WhiteBlackListStorage {
        IWhitelistCore whitelistImpl;
        IBlacklistCore blacklistImpl;
    }

    /**
     * @dev Modifier to check sender and recipient when transfer
     * @param sender - Transfer sender
     * @param recipient - Transfer recipient
     */
    modifier checkTransfer(address sender, address recipient) {
        _checkTransfer(sender, recipient);
        _;
    }

    /// @dev Modifier to check if the token is burnable
    modifier whenBurnable() {
        if (!isBurnable()) {
            revert BurningNotEnabled();
        }
        _;
    }

    /// @dev Modifier to check if the token is mintable
    modifier whenMintable() {
        if (!isMintable()) {
            revert MintingNotEnabled();
        }
        _;
    }

    function _checkTransfer(address sender, address recipient) private view {
        address msgSender = _msgSender();
        bool isOwner = msgSender == owner();

        // When the current caller is the contract owner and the contract permits forced transfers,
        // all transfer requests are released without any whitelist or blacklist checks.
        if (isForceTransferAllowed() && isOwner) {
            return;
        }

        if (isBlacklistEnabled()) {
            if (_isBlacklisted(sender)) {
                revert TransferFromSenderBlacklisted(sender);
            }
            if (_isBlacklisted(recipient)) {
                revert RecipientBlacklisted(recipient);
            }

            if (sender != msgSender && !isOwner && _isBlacklisted(msgSender)) {
                revert TransferFromSenderBlacklisted(msgSender);
            }
        }

        if (isWhitelistEnabled()) {
            if (!_isWhitelisted(sender)) {
                revert TransferFromSenderNotWhitelisted(sender);
            }
            if (!_isWhitelisted(recipient)) {
                revert RecipientNotWhitelisted(recipient);
            }

            if (sender != msgSender && !isOwner && !_isWhitelisted(msgSender)) {
                revert TransferFromSenderNotWhitelisted(msgSender);
            }
        }
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @dev Initializes the contract
    function initialize(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint256 maxSupply_,
        uint256 initialSupply_,
        address tokenOwner,
        ConstructorParams memory params
    ) public initializer {
        if (decimals_ > 18) {
            revert InvalidDecimals(decimals_);
        }
        __Multicall_init();
        __ERC20_init(name_, symbol_);
        __ERC20Pausable_init();
        __ERC20Burnable_init();
        __ERC20Capped_init(maxSupply_);
        __ERC20Permit_init(name_);
        __Ownable_init(tokenOwner);
        __UUPSUpgradeable_init();

        if (params.isWhitelistEnabled) {
            _setWhitelistImpl(params.whitelistImpl);
        }
        if (params.isBlacklistEnabled) {
            _setBlacklistImpl(params.blacklistImpl);
        }
        _setBlacklistEnabled(params.isBlacklistEnabled);
        _setWhitelistEnabled(params.isWhitelistEnabled);

        _setVersion("1.0.0", 1);

        TaxStorage storage taxStorage = _getTaxStorage();
        if (params.isTaxable) {
            if (params.taxBPS > MAX_BPS_AMOUNT) {
                revert InvalidTaxBPS(params.taxBPS);
            }
            Helper.checkAddress(params.taxAddress);
            taxStorage.taxAddress = params.taxAddress;
            taxStorage.taxBPS = params.taxBPS;
        }
        if (params.isDeflationary) {
            if (params.deflationBPS > MAX_BPS_AMOUNT) {
                revert InvalidDeflationBPS(params.deflationBPS);
            }
            taxStorage.deflationBPS = params.deflationBPS;
        }

        if (params.authorisedSenderEnabled) {
            AuthStorage storage authStorage = _getAuthStorage();
            authStorage.authorisedSenderEnabled = params.authorisedSenderEnabled;
            authStorage.authorisedSender[tokenOwner] = true;
        }

        TokenStorage storage tokenStorage = _getTokenStorage();
        tokenStorage.decimals = decimals_;
        tokenStorage.initialSupply = initialSupply_;
        tokenStorage.maxTokenAmountPerAddress = params.maxTokenAmountPerAddress;
        tokenStorage.metadata = params.metadata;
        tokenStorage.documentUri = params.documentUri;
        tokenStorage.features = TokenFeatures({
            isBurnable: params.isBurnable,
            isMintable: params.isMintable,
            isPausable: params.isPausable,
            isMaxAmountPerAddressSet: params.isMaxAmountPerAddressSet,
            isForceTransferAllowed: params.isForceTransferAllowed,
            isTaxable: params.isTaxable,
            isDeflationary: params.isDeflationary,
            authorisedSenderEnabled: params.authorisedSenderEnabled
        });

        if (initialSupply_ > 0) {
            super._mint(tokenOwner, initialSupply_);
        }
    }

    /// @dev Required override for UUPSUpgradeable to authorize upgrades
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner whenNotPaused {
        // Authorization logic is just requiring the owner
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IExternalWhitelistImpl).interfaceId
            || interfaceId == type(IExternalBlacklistImpl).interfaceId
            || interfaceId == type(IWhitelistToggleExtension).interfaceId
            || interfaceId == type(IBlacklistToggleExtension).interfaceId;
    }

    function version() public view returns (string memory) {
        return _getVersionStorage().version;
    }

    function versionNumber() public view returns (uint256) {
        return _getVersionStorage().versionNumber;
    }

    function getWhitelistImpl() external view returns (address) {
        return address(_getWhiteBlackListImplStorage().whitelistImpl);
    }

    function getBlacklistImpl() external view returns (address) {
        return address(_getWhiteBlackListImplStorage().blacklistImpl);
    }

    /// @notice Set the whitelist implementation
    function setWhitelistImpl(IWhitelistCore whitelistImpl_) public onlyOwner {
        _setWhitelistImpl(whitelistImpl_);
    }

    /// @notice Set the blacklist implementation
    function setBlacklistImpl(IBlacklistCore blacklistImpl_) public onlyOwner {
        _setBlacklistImpl(blacklistImpl_);
    }

    function _setWhitelistImpl(IWhitelistCore whitelistImpl_) internal {
        Helper.checkAddress(address(whitelistImpl_));
        _getWhiteBlackListImplStorage().whitelistImpl = whitelistImpl_;
        emit WhitelistImplSet(address(whitelistImpl_));
    }

    function _setBlacklistImpl(IBlacklistCore blacklistImpl_) internal {
        Helper.checkAddress(address(blacklistImpl_));
        _getWhiteBlackListImplStorage().blacklistImpl = blacklistImpl_;
        emit BlacklistImplSet(address(blacklistImpl_));
    }

    /**
     * @dev Return the metadata associated with the contract.
     */
    function metadata() public view virtual returns (string memory) {
        return _getTokenStorage().metadata;
    }

    /**
     * @dev Sets the metadata associated with the contract.
     */
    function setMetadata(string calldata metadata_) public onlyOwner {
        _getTokenStorage().metadata = metadata_;
    }

    /// @dev Return token decimals
    function decimals() public view virtual override returns (uint8) {
        return _getTokenStorage().decimals;
    }

    /// @dev Return if the token is burnable
    function isBurnable() public view returns (bool) {
        return _getTokenStorage().features.isBurnable;
    }

    /// @dev Return if the token is mintable
    function isMintable() public view returns (bool) {
        return _getTokenStorage().features.isMintable;
    }

    /// @dev Return if the token is pausable
    function isPausable() public view returns (bool) {
        return _getTokenStorage().features.isPausable;
    }

    /// @dev Return if the token is maxAmountPerAddressSet
    function isMaxAmountPerAddressSet() public view returns (bool) {
        return _getTokenStorage().features.isMaxAmountPerAddressSet;
    }

    /// @dev Return if the token is forceTransferAllowed
    function isForceTransferAllowed() public view returns (bool) {
        return _getTokenStorage().features.isForceTransferAllowed;
    }

    /// @dev Return if the token is taxable
    function isTaxable() public view returns (bool) {
        return _getTokenStorage().features.isTaxable;
    }

    /// @dev Return if the token is deflationary
    function isDeflationary() public view returns (bool) {
        return _getTokenStorage().features.isDeflationary;
    }

    /// @dev Return document URI
    function documentUri() public view returns (string memory) {
        return _getTokenStorage().documentUri;
    }

    /// @dev Return initial supply
    function initialSupply() public view returns (uint256) {
        return _getTokenStorage().initialSupply;
    }

    /// @dev Return max token amount per address
    function maxTokenAmountPerAddress() public view returns (uint256) {
        return _getTokenStorage().maxTokenAmountPerAddress;
    }

    /// @dev Return tax address
    function taxAddress() public view returns (address) {
        return _getTaxStorage().taxAddress;
    }

    /// @dev Return tax BPS
    function taxBPS() public view returns (uint256) {
        return _getTaxStorage().taxBPS;
    }

    /// @dev Return deflation BPS
    function deflationBPS() public view returns (uint256) {
        return _getTaxStorage().deflationBPS;
    }

    /// @dev Return authorised sender enabled
    function authorisedSenderEnabled() public view returns (bool) {
        return _getAuthStorage().authorisedSenderEnabled;
    }

    /// @dev Return if an address is an authorised sender
    function authorisedSender(address account) public view returns (bool) {
        return _getAuthStorage().authorisedSender[account];
    }

    /**
     * @dev Authorize the account eligible to send a transaction
     * @notice Only the owner can call this function.
     * @notice The functions of mint,burn,transfer and transferFrom are all under control.
     * @notice Only the owner can call this function.
     *
     * @param account The target account
     * @param authorised The value to authorize or cancel the authorization
     */
    function setAuthorisedSender(address account, bool authorised) public onlyOwner {
        _getAuthStorage().authorisedSender[account] = authorised;
        emit AuthorisedSenderSet(account, authorised);
    }

    /**
     * @dev Allow to mint specific token to an address
     * @param to - Address to mint
     * @param amount - Amount to mint
     * @dev Call onlyOwner & whenNotPaused
     */
    function mint(address to, uint256 amount) external onlyOwner whenNotPaused whenMintable {
        // Check
        _checkMaxAmountPerAddress(to, amount);
        // Interactions
        super._mint(to, amount);
        // Effects
        if (isBlacklistEnabled() && _isBlacklisted(to)) {
            revert RecipientBlacklisted(to);
        }
        if (isWhitelistEnabled() && !_isWhitelisted(to)) {
            revert RecipientNotWhitelisted(to);
        }
    }

    /// @inheritdoc ERC20BurnableUpgradeable
    function burn(uint256 amount) public override onlyOwner whenNotPaused whenBurnable {
        super.burn(amount);
    }

    /// @inheritdoc ERC20BurnableUpgradeable
    function burnFrom(address from, uint256 amount) public override onlyOwner whenNotPaused whenBurnable {
        super.burnFrom(from, amount);
    }

    /// @inheritdoc OwnableUpgradeable
    function transferOwnership(address newOwner) public override onlyOwner whenNotPaused {
        AuthStorage storage authStorage = _getAuthStorage();
        authStorage.authorisedSender[super.owner()] = false;
        super.transferOwnership(newOwner);
        authStorage.authorisedSender[newOwner] = true;
    }

    /// @inheritdoc OwnableUpgradeable
    function renounceOwnership() public override onlyOwner whenNotPaused {
        _getAuthStorage().authorisedSender[super.owner()] = false;
        super.renounceOwnership();
    }

    /// @dev Pause the token
    /// @dev Call onlyOwner
    function pause() external onlyOwner {
        if (!isPausable()) {
            revert PausingNotEnabled();
        }
        super._pause();
    }

    /// @dev Unpause the token
    /// @dev Call onlyOwner
    function unpause() external onlyOwner {
        if (!isPausable()) {
            revert PausingNotEnabled();
        }
        super._unpause();
    }

    /**
     * @dev Set new taxAddress and taxBPS
     * @param taxAddress_ - New tax address
     * @param taxBPS_  - New tax BPS
     * @dev Call onlyOwner & whenNotPaused
     */
    function setTaxConfig(address taxAddress_, uint256 taxBPS_) external onlyOwner whenNotPaused {
        if (!isTaxable()) {
            revert TokenIsNotTaxable();
        }
        if (taxBPS_ > MAX_BPS_AMOUNT) {
            revert InvalidTaxBPS(taxBPS_);
        }
        Helper.checkAddress(taxAddress_);
        TaxStorage storage taxStorage = _getTaxStorage();
        taxStorage.taxAddress = taxAddress_;
        taxStorage.taxBPS = taxBPS_;
        emit TaxConfigSet(taxStorage.taxAddress, taxStorage.taxBPS);
    }

    /**
     * @dev Set new deflation BPS
     * @param deflationBPS_ - New deflation BPS
     * @dev Call onlyOwner & whenNotPaused
     */
    function setDeflationConfig(uint256 deflationBPS_) external onlyOwner whenNotPaused {
        if (!isDeflationary()) {
            revert TokenIsNotDeflationary();
        }
        if (deflationBPS_ > MAX_BPS_AMOUNT) {
            revert InvalidDeflationBPS(deflationBPS_);
        }
        _getTaxStorage().deflationBPS = deflationBPS_;
        emit DeflationConfigSet(deflationBPS_);
    }

    /**
     * @dev Owner set new document uri
     * @param newDocumentUri - New document uri
     * @dev Call onlyOwner & whenNotPaused
     */
    function setDocumentUri(string memory newDocumentUri) external onlyOwner whenNotPaused {
        _getTokenStorage().documentUri = newDocumentUri;
        emit DocumentUriSet(newDocumentUri);
    }

    /**
     * @dev Set max token amount per address can hold
     * @param newMaxTokenAmountPerAddr - Max token amount per address
     * @dev Call onlyOwner & whenNotPaused
     */
    function setMaxTokenAmountPerAddress(uint256 newMaxTokenAmountPerAddr) external onlyOwner whenNotPaused {
        if (!isMaxAmountPerAddressSet()) {
            revert MaxTokenAmountNotAllowed();
        }
        _getTokenStorage().maxTokenAmountPerAddress = newMaxTokenAmountPerAddr;
        emit MaxTokenAmountPerSet(newMaxTokenAmountPerAddr);
    }

    /**
     * @dev Transfer specific amount token to address
     * @param to - Address to transfer
     * @param amount - Transfer amount
     */
    function transfer(address to, uint256 amount)
        public
        virtual
        override
        whenNotPaused
        checkTransfer(_msgSender(), to)
        returns (bool)
    {
        uint256 amountToTransfer = _payFeeWhenTransfer(_msgSender(), to, amount);
        return super.transfer(to, amountToTransfer);
    }

    /**
     * @dev Transfer specific amount of token from specific address to another address
     * @param from - Transfer sender
     * @param to - Transfer recipient
     * @param amount - Transfer amount
     */
    function transferFrom(address from, address to, uint256 amount)
        public
        virtual
        override
        whenNotPaused
        checkTransfer(from, to)
        returns (bool)
    {
        uint256 amountToTransfer = _payFeeWhenTransfer(from, to, amount);

        // Force transfer
        if (isForceTransferAllowed() && _msgSender() == owner()) {
            super._transfer(from, to, amountToTransfer);
            return true;
        }
        // Normal transfer
        return super.transferFrom(from, to, amountToTransfer);
    }

    /**
     * @dev Batch transfer token to other addresses
     * @param toList - Transfer recipient address list
     * @param amountList - Transfer amount list
     * @dev ToList length must equal to AmountList length
     */
    function batchTransfer(address[] memory toList, uint256[] memory amountList) external whenNotPaused {
        uint256 len = toList.length;
        if (len != amountList.length) {
            revert InvalidRecipientAndAmount();
        }
        for (uint256 i = 0; i < len;) {
            transfer(toList[i], amountList[i]);
            unchecked {
                i++;
            }
        }
    }

    /**
     * @dev Calculate tax amount during a transfer
     * @param sender - Transfer sender
     * @param amount - Transfer amount
     * @dev If sender is tax address, tax fee is 0
     */
    function _taxAmount(TaxStorage memory taxStorage, address sender, uint256 amount) internal pure returns (uint256 taxAmount) {
        if (taxStorage.taxBPS > 0 && taxStorage.taxAddress != sender) {
            return (amount * taxStorage.taxBPS) / MAX_BPS_AMOUNT;
        }
        return 0;
    }

    /**
     * @dev Calculate deflation amount during a transfer
     * @param amount - Transfer amount
     */
    function _deflationAmount(TaxStorage memory taxStorage,uint256 amount) internal pure returns (uint256 deflationAmount) {
        uint256 deflationBps = taxStorage.deflationBPS;
        if (deflationBps > 0) {
            return (amount * deflationBps) / MAX_BPS_AMOUNT;
        }
        return 0;
    }

    /**
     * @dev See {ERC20-_update}.
     *
     * Requirements:
     *
     * - the contract must not be paused.
     */
    function _update(address from, address to, uint256 value)
        internal
        virtual
        override(ERC20Upgradeable, ERC20PausableUpgradeable, ERC20CappedUpgradeable)
    {
        AuthStorage storage authStorage = _getAuthStorage();
        if (authStorage.authorisedSenderEnabled && !authStorage.authorisedSender[msg.sender]) {
            revert UnAuthorisedSender();
        }
        super._update(from, to, value);
    }

    function _payFeeWhenTransfer(address from, address to, uint256 amount) internal returns (uint256) {
        address spender = _msgSender();
        // transfer fee
        TaxStorage memory taxStorage = _getTaxStorage();
        uint256 taxAmount = _taxAmount(taxStorage, from, amount);
        uint256 deflationAmount = _deflationAmount(taxStorage, amount);
        uint256 totalFee = taxAmount + deflationAmount;
        uint256 amountToTransfer = amount - totalFee;

        // check max amount per address
        _checkMaxAmountPerAddress(to, amountToTransfer);

        // consume allowance
        if (spender != from && totalFee > 0) {
            if (spender == owner() && isForceTransferAllowed()) {
                // the owner can transfer without consuming allowance
            } else {
                // consume allowance
                super._spendAllowance(from, spender, totalFee);
            }
        }
        if (taxAmount > 0) {
            super._transfer(from, taxStorage.taxAddress, taxAmount);
        }
        if (deflationAmount > 0) {
            super._burn(from, deflationAmount);
        }

        return amountToTransfer;
    }

    function _checkMaxAmountPerAddress(address to, uint256 amount) private view {
        if (!isMaxAmountPerAddressSet()) {
            return;
        }
        uint256 newAmount = balanceOf(to) + amount;
        if (newAmount > _getTokenStorage().maxTokenAmountPerAddress) {
            revert AddrBalanceExceedsMaxAllowed(to, newAmount);
        }
    }

    function _setVersion(string memory _version, uint256 _versionNumber) internal {
        VersionStorage storage versionStorage = _getVersionStorage();
        versionStorage.version = _version;
        versionStorage.versionNumber = _versionNumber;
    }

    function _isBlacklisted(address account) internal view virtual returns (bool) {
        return _getWhiteBlackListImplStorage().blacklistImpl.isBlacklisted(account);
    }

    function _isWhitelisted(address account) internal view virtual returns (bool) {
        return _getWhiteBlackListImplStorage().whitelistImpl.isWhitelisted(account);
    }

    // keccak256(abi.encode(uint256(keccak256("eth.storage.TokenConfig")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant TOKEN_STORAGE_LOCATION = 0x991d6ea3473fe20e877a241113b2bce49c7e025de5dbfb0e3d00b028b2393300;

    // keccak256(abi.encode(uint256(keccak256("eth.storage.Tax")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant TAX_STORAGE_LOCATION = 0xed0de5778b259e2ad13f1d53573886a54e2f55f2ff8fab9b01c423473e35eb00;

    // keccak256(abi.encode(uint256(keccak256("eth.storage.Auth")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant AUTH_STORAGE_LOCATION = 0x6254167639327698ff0392879fa34e9dff2989d4d94472ebecc5f9bd4f18e100;

    // keccak256(abi.encode(uint256(keccak256("eth.storage.Version")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant VERSION_STORAGE_LOCATION =
        0x5b6c8744113e961e644258515e7c2428983fc9a9e82560c5677b16c450267b00;

    // keccak256(abi.encode(uint256(keccak256("eth.storage.WhitelistToggle")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant WHITELIST_TOGGLE_STORAGE_LOCATION =
        0x4f1ed6cd17d17a8946879cb81c313524571ec7e8cb7243a13f809e8359599400;

    // keccak256(abi.encode(uint256(keccak256("eth.storage.BlacklistToggle")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant BLACKLIST_TOGGLE_STORAGE_LOCATION =
        0x778e05615efcdbad2facfd2b7feee531e044d5c545ff533a78db22beb989bf00;

    // keccak256(abi.encode(uint256(keccak256("eth.storage.WhiteBlackListImpl")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant WHITE_BLACK_LIST_IMPL_STORAGE_LOCATION =
        0xdbc323087f5f9655ab28eebc9cfc3f6f6fcbcb06a62b34b1f948e358e6a04e00;

    /**
     * @dev Get the whitelist toggle storage.
     * @return $ The whitelist toggle storage.
     * @notice This function is an override of the BaseToggleWhitelistable contract.
     */
    function _getWhitelistToggleStorage() internal view virtual override returns (WhitelistToggleStorage storage $) {
        assembly {
            $.slot := WHITELIST_TOGGLE_STORAGE_LOCATION
        }
    }

    /**
     * @dev Get the blacklist toggle storage.
     * @return $ The blacklist toggle storage.
     * @notice This function is an override of the BaseToggleBlacklistable contract.
     */
    function _getBlacklistToggleStorage() internal view virtual override returns (BlacklistToggleStorage storage $) {
        assembly {
            $.slot := BLACKLIST_TOGGLE_STORAGE_LOCATION
        }
    }

    /**
     * @dev Get the token storage.
     * @return $ The token storage.
     */
    function _getTokenStorage() internal pure returns (TokenStorage storage $) {
        assembly {
            $.slot := TOKEN_STORAGE_LOCATION
        }
    }

    /**
     * @dev Get the tax storage.
     * @return $ The tax storage.
     */
    function _getTaxStorage() internal pure returns (TaxStorage storage $) {
        assembly {
            $.slot := TAX_STORAGE_LOCATION
        }
    }

    /**
     * @dev Get the auth storage.
     * @return $ The auth storage.
     */
    function _getAuthStorage() internal pure returns (AuthStorage storage $) {
        assembly {
            $.slot := AUTH_STORAGE_LOCATION
        }
    }

    /**
     * @dev Get the version storage.
     * @return $ The version storage.
     */
    function _getVersionStorage() internal pure returns (VersionStorage storage $) {
        assembly {
            $.slot := VERSION_STORAGE_LOCATION
        }
    }

    /**
     * @dev Get the white/blacklist implementation storage.
     * @return $ The white/blacklist implementation storage.
     */
    function _getWhiteBlackListImplStorage() internal pure returns (WhiteBlackListStorage storage $) {
        assembly {
            $.slot := WHITE_BLACK_LIST_IMPL_STORAGE_LOCATION
        }
    }
}
