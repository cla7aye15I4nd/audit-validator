// SPDX-License-Identifier: MIT
pragma solidity ~0.8.20;

import {WhitelistableV1Upgradeable} from "./extensions/WhitelistableV1Upgradeable.sol";
import {BlacklistableV1Upgradeable} from "./extensions/BlacklistableV1Upgradeable.sol";
import {AccessControlUpgradeable} from "./acl/AccessControlUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {MulticallUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/MulticallUpgradeable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IWhitelistCore, IWhitelistQueryExtension} from "./interfaces/IWhitelistable.sol";
import {IBlacklistCore, IBlacklistQueryExtension} from "./interfaces/IBlacklistable.sol";

contract WhiteBlackList is
    MulticallUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    WhitelistableV1Upgradeable,
    BlacklistableV1Upgradeable,
    AccessControlUpgradeable,
    IERC165
{
    /// @dev allow to manage whitelist and blacklist
    bytes32 public constant BLACKWHITELIST_ROLE = keccak256("BLACKWHITELIST_ROLE");

    // keccak256(abi.encode(uint256(keccak256("eth.storage.Version")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant VERSION_STORAGE_LOCATION =
        0x5b6c8744113e961e644258515e7c2428983fc9a9e82560c5677b16c450267b00;

    /// @custom:storage-location erc7201:eth.storage.Version
    struct VersionStorage {
        uint256 versionNumber;
        string version;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address owner) public initializer {
        __Multicall_init();
        __Ownable_init(owner);
        __UUPSUpgradeable_init();
        __WhitelistableV1_init();
        __BlacklistableV1_init();
        __AccessControl_init();

        _setVersion("1.0.0", 1);
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IWhitelistCore).interfaceId
            || interfaceId == type(IBlacklistCore).interfaceId || interfaceId == type(IWhitelistQueryExtension).interfaceId
            || interfaceId == type(IBlacklistQueryExtension).interfaceId;
    }

    /// @dev Required override for UUPSUpgradeable to authorize upgrades
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function _validateWhitelistController() internal view virtual override onlyRole(BLACKWHITELIST_ROLE) {}

    function _validateBlacklistController() internal view virtual override onlyRole(BLACKWHITELIST_ROLE) {}

    function _isOwner(address account) internal view virtual override returns (bool) {
        return account == owner();
    }

    function version() public view returns (string memory) {
        return _getVersionStorage().version;
    }

    function versionNumber() public view returns (uint256) {
        return _getVersionStorage().versionNumber;
    }

    function _msgSender() internal view virtual override(ContextUpgradeable, Context) returns (address) {
        return ContextUpgradeable._msgSender();
    }

    function _msgData() internal view virtual override(ContextUpgradeable, Context) returns (bytes calldata) {
        return ContextUpgradeable._msgData();
    }

    function _contextSuffixLength() internal view virtual override(ContextUpgradeable, Context) returns (uint256) {
        return ContextUpgradeable._contextSuffixLength();
    }

    function _getVersionStorage() internal pure returns (VersionStorage storage $) {
        assembly {
            $.slot := VERSION_STORAGE_LOCATION
        }
    }

    function _setVersion(string memory _version, uint256 _versionNumber) internal {
        VersionStorage storage versionStorage = _getVersionStorage();
        versionStorage.version = _version;
        versionStorage.versionNumber = _versionNumber;
    }
}
