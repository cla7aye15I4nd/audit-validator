// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.17;

import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./SilksERC1155Burnable.sol";
import "./SilksPausable.sol";

abstract contract ERC721 {
    function ownerOf(uint tokenId) public view virtual returns (address);
}

abstract contract ContractGlossary3 {
    function getAddress(
        string memory name
    ) public view virtual returns (address);

    function owner() public view virtual returns (address);
}

abstract contract MarketPlace {
    function extDeleteOffer(uint horseId) external virtual;

    function extDeleteMarketItem(uint horseId) external virtual;

    function extDeleteMarketItems(
        string memory tokenType,
        address account,
        uint tokenId,
        uint amount
    ) external virtual;
}

contract HorsePartnerships is SilksPausable, SilksERC1155Burnable {
    using Address for address;

    // As of right now, the horse owner is not stored as a partner.
    struct Partnership {
        address[] partners;
        uint maxPartnershipShares;
        bool isFractionalized;
    }

    event HorseFractionalized(
        address indexed operator,
        address indexed account,
        uint indexed horseId
    );

    event HorseReconstituted(
        address indexed operator,
        address indexed account,
        uint indexed horseId
    );

    string public name = "Silks - Horse Partnership";

    bool public fractionalizationPaused;
    bool public reconstitutionPaused;
    uint public partnershipCount;
    uint public maxPartnershipShares;

    address private _royaltyReceiver;
    uint96 private _royaltyRate; // 8 = 8%

    mapping(uint => Partnership) internal _partnerships;

    ContractGlossary3 internal _indexContract;

    constructor(
        string memory tokenUri,
        address indexContract,
        address royaltyReceiver,
        uint96 royaltyRate
    ) ERC1155(tokenUri) {
        partnershipCount = 0;
        maxPartnershipShares = 9; // 1 Governance (Horse Owner) + 9 Partners
        _indexContract = ContractGlossary3(indexContract);
        _royaltyReceiver = royaltyReceiver;
        _royaltyRate = royaltyRate;
    }

    modifier whenFractionalizationNotPaused() {
        require(!fractionalizationPaused, "FRACTIONALIZATION-PAUSED");
        _;
    }

    modifier whenReconstitutionNotPaused() {
        require(!reconstitutionPaused, "RECONSTITUTION-PAUSED");
        _;
    }

    // *********** Internal Functions
    function _mintPartnershipTokenType(
        address operator,
        address account,
        uint horseId,
        uint amount,
        bytes memory data
    ) internal {
        require(
            ERC721(_indexContract.getAddress("Horse")).ownerOf(horseId) ==
                account,
            "NOT-TOKEN-OWNER"
        );

        require(
            !_partnerships[horseId].isFractionalized,
            "HORSE-FRACTIONALIZED"
        );

        address[] memory addresses;
        _partnerships[horseId] = Partnership(
            addresses,
            maxPartnershipShares,
            true
        );

        MarketPlace marketPlaceContract = MarketPlace(
            _indexContract.getAddress("Marketplace")
        );
        // Delete any offers
        marketPlaceContract.extDeleteOffer(horseId);
        // Delete any listings
        marketPlaceContract.extDeleteMarketItem(horseId);

        _mint(account, horseId, amount, data);

        partnershipCount += 1;

        emit HorseFractionalized(operator, account, horseId);
    }

    function _reconstituteHorsePartnership(
        address operator,
        address account,
        uint horseId
    ) internal {
        require(
            ERC721(_indexContract.getAddress("Horse")).ownerOf(horseId) ==
                account,
            "NOT-TOKEN-OWNER"
        );

        require(
            _partnerships[horseId].isFractionalized,
            "HORSE-NOT-FRACTIONALIZED"
        );

        require(_partnerships[horseId].partners.length == 0, "HAS-PARTNERS");

        _burn(account, horseId, balanceOf(account, horseId));

        address[] memory partners;
        _partnerships[horseId] = Partnership(partners, 0, false);

        partnershipCount -= 1;

        emit HorseReconstituted(operator, account, horseId);
    }

    function _afterTokenTransfer(
        address,
        address from,
        address to,
        uint[] memory ids,
        uint[] memory amounts,
        bytes memory
    ) internal virtual override {
        for (uint i = 0; i < ids.length; i++) {
            uint id = ids[i];
            address[] memory partnerAddresses = _partnerships[id].partners;
            // Don't perform these steps if this is a mint
            if (from != address(0)) {
                if (balanceOf(from, id) <= 0) {
                    uint partnerAddressesLength = partnerAddresses.length;
                    if (partnerAddressesLength > 0) {
                        // Delete partner from partners array if the share balance after transfer is <= 0
                        for (uint j = 0; j < partnerAddressesLength; j++) {
                            if (partnerAddresses[j] == from) {
                                delete partnerAddresses[j];
                            }
                        }
                    }
                }

                address marketPlaceContractAddress = _indexContract.getAddress(
                    "Marketplace"
                );
                if (marketPlaceContractAddress != msg.sender) {
                    MarketPlace marketPlaceContract = MarketPlace(
                        marketPlaceContractAddress
                    );
                    marketPlaceContract.extDeleteMarketItems(
                        "HorseFractionalization",
                        from,
                        id,
                        amounts[i]
                    );
                }
            }

            // Don't execute when token is being burned
            if (to != address(0)) {
                // Don't execute when minting.
                if (from != address(0)) {
                    bool addressExists = false;
                    for (uint j = 0; j < partnerAddresses.length; j++) {
                        if (partnerAddresses[j] == to) {
                            addressExists = true;
                            break;
                        }
                    }

                    address owner = ERC721(_indexContract.getAddress("Horse"))
                        .ownerOf(id);

                    // Add address to partnership array if address is not already a part of it and the transfer is not
                    // to the owner
                    if (!addressExists) {
                        if (to != owner) {
                            // Extend the array.
                            uint partnerAddressesLength = partnerAddresses
                                .length;
                            address[]
                                memory newPartnerAddresses = new address[](
                                    partnerAddressesLength + 1
                                );
                            for (uint j = 0; j < partnerAddressesLength; j++) {
                                newPartnerAddresses[j] = partnerAddresses[j];
                            }
                            newPartnerAddresses[partnerAddressesLength] = to;
                            partnerAddresses = newPartnerAddresses;
                        }
                    }
                }
            }

            _partnerships[id].partners = partnerAddresses;
        }
    }

    // ************ Public Functions
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC1155) returns (bool) {
        return
            interfaceId == type(IERC2981).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    function isFractionalized(uint horseId) external view returns (bool) {
        return _partnerships[horseId].isFractionalized;
    }

    function fractionalize(
        uint horseId
    ) external whenNotPaused whenFractionalizationNotPaused {
        _mintPartnershipTokenType(
            msg.sender,
            msg.sender,
            horseId,
            maxPartnershipShares,
            ""
        );
    }

    function adminFractionalize(
        address[] memory accounts,
        uint[] memory horseIds
    ) external onlyOwner {
        require(accounts.length == horseIds.length, "ACCOUNTS-IDS-MISMATCH");

        for (uint8 i = 0; i < accounts.length; i++) {
            _mintPartnershipTokenType(
                msg.sender,
                accounts[i],
                horseIds[i],
                maxPartnershipShares,
                ""
            );
        }
    }

    function reconstitute(
        uint horseId
    ) external whenNotPaused whenReconstitutionNotPaused {
        _reconstituteHorsePartnership(msg.sender, msg.sender, horseId);
    }

    function adminReconstitute(
        address[] memory accounts,
        uint[] memory horseIds
    ) external onlyOwner {
        require(accounts.length == horseIds.length, "ACCOUNTS-IDS-MISMATCH");
        for (uint8 i = 0; i < accounts.length; i++) {
            _reconstituteHorsePartnership(msg.sender, accounts[i], horseIds[i]);
        }
    }

    function getPartnership(
        uint horseId
    ) external view returns (address[] memory, uint256[] memory) {
        Partnership storage partnership = _partnerships[horseId];
        require(partnership.isFractionalized, "HORSE-NOT-FRACTIONALIZED");

        address[] storage partners = partnership.partners;

        uint256 arrayLength = partners.length + 1;
        address[] memory partnerAddresses = new address[](arrayLength);
        uint256[] memory partnerShares = new uint256[](arrayLength);

        address ownerAddress = ERC721(_indexContract.getAddress("Horse"))
            .ownerOf(horseId);
        uint pos = 0;
        for (uint256 i = 0; i < partners.length; i++) {
            address partner = partners[i];
            if (partner != address(0)) {
                partnerAddresses[pos] = partner;
                partnerShares[pos] = balanceOf(partner, horseId);
                pos++;
            }
        }

        uint256 ownerPosition = partnerAddresses.length - 1;
        partnerAddresses[ownerPosition] = ownerAddress;
        partnerShares[ownerPosition] = balanceOf(ownerAddress, horseId) + 1;

        return (partnerAddresses, partnerShares);
    }

    function setContractPaused(bool _paused) external onlyOwner {
        super._setContractPaused(_paused);
    }

    function setFractionalizationPaused(
        bool _fractionalizationPaused
    ) external onlyOwner {
        fractionalizationPaused = _fractionalizationPaused;
    }

    function setReconstitutionPaused(
        bool _reconstitutionPaused
    ) external onlyOwner {
        reconstitutionPaused = _reconstitutionPaused;
    }

    function setMaxPartnershipShares(uint num) external onlyOwner {
        maxPartnershipShares = num;
    }

    function setContractGlossary3(
        address ContractGlossary3Address
    ) external onlyOwner {
        require(
            ContractGlossary3Address.isContract(),
            "INVALID-INDEX-CONTRACT-ADDRESS"
        );
        ContractGlossary3 newIndexContract = ContractGlossary3(
            ContractGlossary3Address
        );
        _indexContract = newIndexContract;
    }

    function royaltyInfo(
        uint horseId,
        uint salePrice
    ) external view returns (address, uint) {
        require(
            _partnerships[horseId].isFractionalized,
            "HORSE-NOT-FRACTIONALIZED"
        );
        return (_royaltyReceiver, (salePrice * _royaltyRate) / 100);
    }

    function setRoyaltyInfo(
        address royaltyReceiver,
        uint96 royaltyRate
    ) external onlyOwner {
        _royaltyReceiver = royaltyReceiver;
        _royaltyRate = royaltyRate;
    }

    function uri(uint tokenId) public view override returns (string memory) {
        return (
            string(
                abi.encodePacked(super.uri(tokenId), Strings.toString(tokenId))
            )
        );
    }
}
