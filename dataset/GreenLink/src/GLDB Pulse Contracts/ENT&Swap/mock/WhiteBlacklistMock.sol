// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IWhitelistCore} from "../interfaces/IWhitelistable.sol";
import {IBlacklistCore} from "../interfaces/IBlacklistable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

contract WhiteBlacklistMock is 
    Ownable,
    IWhitelistCore, 
    IBlacklistCore,
    IERC165 
{
    mapping(address => bool) private _whitelist;
    mapping(address => bool) private _blacklist;

    constructor(address owner) Ownable(owner) {}

    function isWhitelisted(address account) public view override returns (bool) {
        return _whitelist[account];
    }

    function areWhitelisted(address[] calldata addresses) external view override returns (bool[] memory) {
        bool[] memory results = new bool[](addresses.length);
        for (uint256 i = 0; i < addresses.length; i++) {
            results[i] = isWhitelisted(addresses[i]);
        }
        return results;
    }

    function addToWhitelist(address account) external onlyOwner {
        if (!_whitelist[account]) {
            _whitelist[account] = true;
            emit Whitelisted(account);
        }
    }

    function batchAddToWhitelist(address[] calldata addresses) external override onlyOwner {
        for (uint256 i = 0; i < addresses.length; i++) {
            if (!_whitelist[addresses[i]]) {
                _whitelist[addresses[i]] = true;
                emit Whitelisted(addresses[i]);
            }
        }
    }

    function removeFromWhitelist(address account) external override onlyOwner {
        if (_whitelist[account]) {
            _whitelist[account] = false;
            emit UnWhitelisted(account);
        }
    }

    function batchRemoveFromWhitelist(address[] calldata addresses) external override onlyOwner {
        for (uint256 i = 0; i < addresses.length; i++) {
            if (_whitelist[addresses[i]]) {
                _whitelist[addresses[i]] = false;
                emit UnWhitelisted(addresses[i]);
            }
        }
    }

    function updateWhitelist(
        address[] calldata addressesToAdd,
        address[] calldata addressesToRemove
    ) external override onlyOwner {
        for (uint256 i = 0; i < addressesToAdd.length; i++) {
            if (!_whitelist[addressesToAdd[i]]) {
                _whitelist[addressesToAdd[i]] = true;
                emit Whitelisted(addressesToAdd[i]);
            }
        }
        
        for (uint256 i = 0; i < addressesToRemove.length; i++) {
            if (_whitelist[addressesToRemove[i]]) {
                _whitelist[addressesToRemove[i]] = false;
                emit UnWhitelisted(addressesToRemove[i]);
            }
        }
    }

    function isBlacklisted(address account) public view override returns (bool) {
        return _blacklist[account];
    }

    function areBlacklisted(address[] calldata addresses) external view override returns (bool[] memory) {
        bool[] memory results = new bool[](addresses.length);
        for (uint256 i = 0; i < addresses.length; i++) {
            results[i] = isBlacklisted(addresses[i]);
        }
        return results;
    }

    function addToBlacklist(address account) external override onlyOwner {
        if (!_blacklist[account]) {
            _blacklist[account] = true;
            emit Blacklisted(account);
        }
    }

    function batchAddToBlacklist(address[] calldata addresses) external override onlyOwner {
        for (uint256 i = 0; i < addresses.length; i++) {
            if (!_blacklist[addresses[i]]) {
                _blacklist[addresses[i]] = true;
                emit Blacklisted(addresses[i]);
            }
        }
    }

    function removeFromBlacklist(address account) external override onlyOwner {
        if (_blacklist[account]) {
            _blacklist[account] = false;
            emit UnBlacklisted(account);
        }
    }

    function batchRemoveFromBlacklist(address[] calldata addresses) external override onlyOwner {
        for (uint256 i = 0; i < addresses.length; i++) {
            if (_blacklist[addresses[i]]) {
                _blacklist[addresses[i]] = false;
                emit UnBlacklisted(addresses[i]);
            }
        }
    }

    function updateBlacklist(
        address[] calldata addressesToAdd,
        address[] calldata addressesToRemove
    ) external override onlyOwner {
        for (uint256 i = 0; i < addressesToAdd.length; i++) {
            if (!_blacklist[addressesToAdd[i]]) {
                _blacklist[addressesToAdd[i]] = true;
                emit Blacklisted(addressesToAdd[i]);
            }
        }
        
        for (uint256 i = 0; i < addressesToRemove.length; i++) {
            if (_blacklist[addressesToRemove[i]]) {
                _blacklist[addressesToRemove[i]] = false;
                emit UnBlacklisted(addressesToRemove[i]);
            }
        }
    }

    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return interfaceId == type(IWhitelistCore).interfaceId ||
               interfaceId == type(IBlacklistCore).interfaceId ||
               interfaceId == type(IERC165).interfaceId;
    }

}
