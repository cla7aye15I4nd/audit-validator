// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";

contract Index is Ownable {
    mapping(uint256 => string) public SilksContractsIndextoName;
    mapping(string => address) public SilksContractsMapping;
    mapping(address => string) public SilksContractsbyAddress;
    uint256 public addressCount;

    constructor(string[] memory names, address[] memory addresses) {
        addressCount = 0;
        for (uint256 i = 0; i < names.length; i++) {
            _setAddress(names[i], addresses[i]);
        }
    }

    function getAddress(string memory name) public view returns (address) {
        return SilksContractsMapping[name];
    }

    function getName(address contractAddress)
        public
        view
        returns (string memory)
    {
        return SilksContractsbyAddress[contractAddress];
    }

    function setAddress(string memory name, address contractAddress)
        public
        onlyOwner
    {
        _setAddress(name, contractAddress);
    }

    function _setAddress(string memory name, address contractAddress) internal {
        if (SilksContractsMapping[name] == address(0)) {
            SilksContractsIndextoName[addressCount] = name;
            SilksContractsbyAddress[contractAddress] = name;
            addressCount++;
        }
        SilksContractsMapping[name] = contractAddress;
        SilksContractsbyAddress[contractAddress] = name;
    }
}
