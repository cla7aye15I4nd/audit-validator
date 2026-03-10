// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Arrays.sol";

abstract contract ContractGlossary {
    function getAddress(
        string memory name
    ) public view virtual returns (address);

    function getName(
        address contractAddress
    ) public view virtual returns (string memory);
}

abstract contract HorsePartnershiper {
    function maxPartnershipShares() external view virtual returns (uint256);
}

contract Marketplace is Ownable, Pausable, ERC165 {
    using Counters for Counters.Counter;
    using Arrays for uint256[];
    Counters.Counter private _itemIDs;
    Counters.Counter private _itemsSold;

    uint256 public marketSize;
    uint256 public fullMarketSize;
    mapping(string => uint256) public floorPrices;
    // mapping(address => string) public SilksContractsbyAddress;
    mapping(string => uint256) public fees; // fees in percent

    address public indexAddress;
    // address public LandAddress;
    // address public HorseAddress;
    // address public HorseGovAddress;
    // address public StableAddress;
    // address public FarmAddress;

    address payable public FeeAddress;

    uint256 offerTimeIncrement = (1 minutes); // 1 hour

    uint256 listingTimeIncrement = (1 minutes); // 1 day

    ContractGlossary Index;

    mapping(uint256 => MarketItem) public marketItems;
    mapping(string => mapping(uint256 => uint256[]))
        public marketIDsbyTypeandTokenID;

    mapping(address => mapping(uint256 => Offer[])) public offers;
    mapping(address => bool) public is1155;

    struct Offer {
        address user;
        uint256 price;
        uint256 quantity;
    }

    struct MarketItem {
        uint256 itemID;
        address nftContract;
        uint256 tokenID;
        address payable seller;
        address payable owner;
        uint256 price;
        bool sold;
        uint256 quantity;
        uint256 exp;
    }

    event MarketItemCreated(
        uint256 itemID,
        address nftContract,
        uint256 tokenId,
        address seller,
        address owner,
        uint256 price,
        bool sold,
        uint256 quantity,
        uint256 exp
    );

    event MarketItemSold(
        uint256 itemID,
        address nftContract,
        uint256 tokenId,
        address seller,
        address owner,
        uint256 price,
        address to,
        uint256 quantity
    );
    event OfferMade(
        uint256 indexID,
        address nftContract,
        uint256 tokenId,
        address offerer,
        address owner,
        uint256 price,
        bool sold,
        uint256 quantity
    );

    event OfferFilled(
        uint256 indexID,
        address nftContract,
        uint256 tokenId,
        address offerer,
        address owner,
        uint256 price,
        address to,
        uint256 quantity
    );

    event MarketItemDeleted(uint256 itemID);
    event OfferDeleted(address nftContract, uint256 tokenId, uint256 index);

    modifier expireListing(uint256 itemID) {
        if (block.timestamp >= marketItems[itemID].exp) {
            _deleteMarketItem(itemID, marketItems[itemID].quantity);
        }
        _;
    }

    constructor(address _indexAddress, address payable _FeeAddress) {
        indexAddress = _indexAddress;
        refreshContracts();

        is1155[Index.getAddress("HorsePartnership")] = true;

        FeeAddress = _FeeAddress;
    }

    function extDeleteOffer(uint256 horseId) external {
        require(
            msg.sender == Index.getAddress("HorseFractionalization"),
            "MUST BE CALLED FROM FRACTIONALIZATION CONTRACT"
        );
        delete offers[Index.getAddress("Horse")][horseId];
    }

    function extDeleteMarketItem(uint256 horseId) external {
        require(
            msg.sender == Index.getAddress("HorseFractionalization"),
            "MUST BE CALLED FROM FRACTIONALIZATION CONTRACT"
        );
        if (marketIDsbyTypeandTokenID["Horse"][horseId].length != 0) {
            _deleteMarketItem(
                marketIDsbyTypeandTokenID["Horse"][horseId][0],
                1
            );
        }
    }

    function extDeleteMarketItems(
        string memory contractName,
        address transferrer,
        uint256 tokenID,
        uint256 quantity
    ) external {
        require(
            msg.sender == Index.getAddress("HorseFractionalization"),
            "MUST BE CALLED FROM FRACTIONALIZATION CONTRACT"
        );
        uint256[] storage marketIDs = marketIDsbyTypeandTokenID[contractName][
            tokenID
        ];
        for (uint256 i = 0; i < marketIDs.length; i++) {
            if (marketItems[marketIDs[i]].seller == transferrer) {
                if (quantity >= marketItems[marketIDs[i]].quantity) {
                    quantity -= marketItems[marketIDs[i]].quantity;
                    _deleteMarketItem(
                        marketIDs[i],
                        marketItems[marketIDs[i]].quantity
                    );
                } else {
                    uint256 quantToDelete = marketItems[marketIDs[i]].quantity -
                        quantity;
                    marketItems[marketIDs[i]].quantity = quantToDelete;
                    break;
                }
            }
        }
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setIndexContractAddress(address _addr) public onlyOwner {
        require(_addr != address(0), "CANNOT SET TO THE NULL ADDRESS");
        indexAddress = _addr;
    }

    function changeFloorPrice(
        string memory nftType,
        uint256 price
    ) public onlyOwner {
        floorPrices[nftType] = price;
    }

    function setFee(string memory nftType, uint256 fee) public onlyOwner {
        fees[nftType] = fee;
    }

    function set1155(address _addr) public onlyOwner {
        require(_addr != address(0), "CANNOT SET TO THE NULL ADDRESS");
        is1155[_addr] = true;
    }

    function removeMarketID(
        uint256 tokenID,
        uint256 marketIDToRemove,
        uint256 quantityToRemove
    ) public {
        // Get a reference to the array of market IDs for the specified token ID
        uint256[] storage marketIDs = marketIDsbyTypeandTokenID[
            Index.getName(marketItems[marketIDToRemove].nftContract)
        ][tokenID];

        // Loop through the array to find the index of the item with the specified value
        for (uint256 i = 0; i < marketIDs.length; i++) {
            if (marketIDs[i] == marketIDToRemove) {
                // If the item is found, get a reference to the MarketItem
                MarketItem storage marketItem = marketItems[marketIDToRemove];
                // Check that the quantity of the MarketItem matches the quantityToRemove argument
                if (marketItem.quantity == quantityToRemove) {
                    // If the quantities match, delete the item
                    delete marketIDs[i];
                    // Exit the loop to stop searching for the item
                    break;
                }
            }
        }
    }

    function withdrawETH(address payable _addr) public onlyOwner {
        _addr.transfer(address(this).balance);
    }

    function createMarketItem(
        address nftContract,
        uint256 tokenID,
        uint256 price,
        uint256 quantity,
        uint256 exp
    ) public whenNotPaused {
        refreshContracts();
        require(
            (keccak256(abi.encodePacked((Index.getName(nftContract))))) !=
                (keccak256(abi.encodePacked(("")))),
            "ITEM MUST BE A SILKS NFT"
        );
        require(
            price >= floorPrices[Index.getName(nftContract)],
            "Price must be greater than floor price for it's type"
        );
        require(quantity >= 1, "QUANTITY MUST BE AT LEAST 1");
        if (is1155[nftContract] == true) {
            require(
                IERC1155(nftContract).balanceOf(msg.sender, tokenID) >=
                    quantity,
                "MUST HAVE ENOUGH OF THE 1155 ASSET"
            );
            if (
                marketIDsbyTypeandTokenID[Index.getName(nftContract)][tokenID]
                    .length != 0
            ) {
                uint256 maxPartnershipShares = HorsePartnershiper(
                    Index.getAddress("HorseFractionalization")
                ).maxPartnershipShares();
                uint256 sharesForSale = 0;
                uint256 sharesByUser = 0;
                for (
                    uint256 i = 0;
                    i <
                    marketIDsbyTypeandTokenID[Index.getName(nftContract)][
                        tokenID
                    ].length;
                    i++
                ) {
                    sharesForSale += marketItems[
                        marketIDsbyTypeandTokenID[Index.getName(nftContract)][
                            tokenID
                        ][i]
                    ].quantity;
                    if (
                        marketItems[
                            marketIDsbyTypeandTokenID[
                                Index.getName(nftContract)
                            ][tokenID][i]
                        ].seller == msg.sender
                    ) {
                        sharesByUser += marketItems[
                            marketIDsbyTypeandTokenID[
                                Index.getName(nftContract)
                            ][tokenID][i]
                        ].quantity;
                    }
                }
                require(
                    sharesForSale != maxPartnershipShares,
                    "CANNOT LIST MORE 1155 TOKENS THAN CAN EXIST"
                );
                require(
                    sharesByUser <
                        IERC1155(nftContract).balanceOf(msg.sender, tokenID),
                    "CANNOT LIST MORE 1155 TOKENS THAN YOU HAVE"
                );
            }
        } else {
            require(quantity == 1, "QUANTITY MUST BE 1 FOR 721");
            require(
                IERC721(nftContract).ownerOf(tokenID) == msg.sender,
                "MUST BE OWNER OF 721 ASSET"
            );
            if (
                marketIDsbyTypeandTokenID[Index.getName(nftContract)][tokenID]
                    .length != 0
            )
                for (
                    uint256 i = 0;
                    i <
                    marketIDsbyTypeandTokenID[Index.getName(nftContract)][
                        tokenID
                    ].length;
                    i++
                ) {
                    require(
                        marketIDsbyTypeandTokenID[Index.getName(nftContract)][
                            tokenID
                        ][i] == 0,
                        "MARKET ID'S PRESENT. CAN'T LIST ITEM THAT IS ALREADY LISTED"
                    );
                }
        }

        require(
            IERC721(nftContract).isApprovedForAll(msg.sender, address(this)),
            "CONTRACT MUST HAVE SETAPPROVALFORALL PRIVILEGES"
        );
        _itemIDs.increment();
        uint256 itemID = _itemIDs.current();
        marketItems[itemID] = MarketItem(
            itemID,
            nftContract,
            tokenID,
            payable(msg.sender),
            payable(address(0)),
            price,
            false,
            quantity,
            exp
        );
        marketIDsbyTypeandTokenID[Index.getName(nftContract)][tokenID].push(
            itemID
        );
        emit MarketItemCreated(
            itemID,
            nftContract,
            tokenID,
            msg.sender,
            address(0),
            price,
            false,
            quantity,
            exp
        );
        marketSize++;
        fullMarketSize++;
    }

    function deleteMarketItem(uint256 itemID) public {
        require(
            msg.sender == marketItems[itemID].seller,
            "MUST BE SELLER TO DELETE ITEM"
        );
        require(
            marketItems[itemID].sold == false,
            "ITEM CANNOT BE SOLD ALREADY"
        );
        uint256 quantity = marketItems[itemID].quantity;
        _deleteMarketItem(itemID, quantity);
    }

    function createMarketSale(
        uint256 itemID,
        uint256 quantity
    ) public payable whenNotPaused expireListing(itemID) {
        require(
            msg.value >= marketItems[itemID].price * quantity,
            "Please submit the asking price in order to complete the purchase"
        );
        require(
            msg.sender != marketItems[itemID].seller,
            "CANNOT BUY YOUR OWN ITEM"
        );
        require(quantity >= 1, "QUANTITY MUST BE AT LEAST 1");
        _createMarketSale(
            marketItems[itemID].nftContract,
            itemID,
            msg.sender,
            msg.value,
            quantity
        );
    }

    function makeOffer(
        address nftContract,
        uint256 tokenID,
        uint256 quantity
    ) public payable whenNotPaused {
        refreshContracts();
        require(
            (keccak256(abi.encodePacked((Index.getName(nftContract))))) !=
                (keccak256(abi.encodePacked(("")))),
            "ITEM MUST BE A SILKS - NFT"
        );
        if (is1155[nftContract] == false) {
            require(
                msg.sender != IERC721(nftContract).ownerOf(tokenID),
                "CANT MAKE OFFER ON ITEM YOU OWN"
            );
            require(quantity == 1, "QUANTITY MUST 1 for 721");
        }
        require(
            msg.value >= (floorPrices[Index.getName(nftContract)] * quantity),
            "Price must be greater than floor price for it's type"
        );
        require(quantity >= 1, "QUANTITY MUST BE AT LEAST 1");
        uint256 indexID = offers[nftContract][tokenID].length;
        offers[nftContract][tokenID].push(
            Offer(msg.sender, (msg.value / quantity), quantity)
        );
        emit OfferMade(
            indexID,
            nftContract,
            tokenID,
            msg.sender,
            address(0),
            msg.value,
            false,
            quantity
        );
    }

    function acceptOffer(
        address nftContract,
        uint256 tokenID,
        uint256 index,
        uint256 quantity
    ) public whenNotPaused {
        refreshContracts();
        require(quantity >= 1, "QUANTITY MUST BE AT LEAST 1");
        address payable newOwner = payable(
            offers[nftContract][tokenID][index].user
        );
        require(msg.sender != newOwner, "YOU CANT ACCEPT YOUR OWN OFFER");
        require(newOwner != address(0), "OFFER DOES NOT EXIST");
        uint256 price = offers[nftContract][tokenID][index].price * quantity;
        if (is1155[nftContract] == true) {
            require(
                IERC1155(nftContract).balanceOf(msg.sender, tokenID) >=
                    quantity,
                "MUST OWN AT MINIMUM THE AMOUNT YOU WANT TO SELL"
            );
            IERC1155(nftContract).safeTransferFrom(
                msg.sender,
                newOwner,
                tokenID,
                quantity,
                ""
            );
        } else {
            require(
                msg.sender == IERC721(nftContract).ownerOf(tokenID),
                "MUST BE OWNER OF ASSET TO ACCEPT OFFER"
            );
            // require(quantity == 1, "QUANTITY MUST BE 1 FOR 721");
            IERC721(nftContract).transferFrom(msg.sender, newOwner, tokenID);
        }
        payable(msg.sender).transfer(
            price - (((price * fees[Index.getName(nftContract)]) / 100))
        );
        FeeAddress.transfer((price * fees[Index.getName(nftContract)]) / 100);
        if (quantity == offers[nftContract][tokenID][index].quantity) {
            _deleteOffer(nftContract, tokenID, index);
            // delete offers[nftContract][tokenID][index];
        } else {
            offers[nftContract][tokenID][index].quantity -= quantity;
        }

        _itemIDs.increment();
        uint256 itemID = _itemIDs.current();
        marketItems[itemID] = MarketItem(
            itemID,
            nftContract,
            tokenID,
            payable(msg.sender),
            newOwner,
            price,
            true,
            quantity,
            block.timestamp + (1 * offerTimeIncrement)
        );

        emit MarketItemCreated(
            itemID,
            nftContract,
            tokenID,
            msg.sender,
            address(0),
            price,
            false,
            quantity,
            block.timestamp + (1 * offerTimeIncrement)
        );
        marketSize++;
        fullMarketSize++;
        emit MarketItemSold(
            itemID,
            nftContract,
            tokenID,
            msg.sender,
            newOwner,
            price,
            newOwner,
            quantity
        );
        emit OfferFilled(
            index,
            nftContract,
            tokenID,
            msg.sender,
            newOwner,
            price,
            newOwner,
            quantity
        );
    }

    function deleteOffer(
        address nftContract,
        uint256 tokenID,
        uint256 index
    ) public whenNotPaused {
        require(
            offers[nftContract][tokenID][index].user != address(0),
            "CANT DELETE OFFER THATS ALREADY DELETED"
        );
        if (msg.sender != offers[nftContract][tokenID][index].user) {
            require(
                is1155[nftContract] == false &&
                    IERC721(nftContract).ownerOf(tokenID) == msg.sender,
                "MUST BE OFFERER OR (OWNER OF TOKEN AND NO 1155)"
            );
        }

        // Transfer the funds back to the user
        payable(offers[nftContract][tokenID][index].user).transfer(
            offers[nftContract][tokenID][index].price
        );
        _deleteOffer(nftContract, tokenID, index);
        emit OfferDeleted(nftContract, tokenID, index);
    }

    function getOffer(
        address nftContract,
        uint256 tokenID,
        uint256 index
    ) public view returns (Offer memory) {
        return offers[nftContract][tokenID][index];
    }

    function getAllOffers(
        address nftContract,
        uint256 tokenID
    ) public view returns (Offer[] memory) {
        return offers[nftContract][tokenID];
    }

    function fetchUnsoldMarketItems()
        public
        view
        returns (MarketItem[] memory)
    {
        MarketItem[] memory items = new MarketItem[](marketSize);

        uint256 j = 0;
        for (uint256 i = 0; i < fullMarketSize; i++) {
            if (
                marketItems[i].nftContract != address(0) &&
                marketItems[i].exp > block.timestamp &&
                marketItems[i].sold == false
            ) {
                items[j] = (marketItems[i]);
                j++;
            }
        }
        MarketItem[] memory items2 = new MarketItem[](j);
        uint256 k = 0;
        for (uint256 l = 0; l < j; l++) {
            if (
                items[l].nftContract != address(0) &&
                items[l].exp > block.timestamp &&
                marketItems[l].sold == false
            ) {
                items2[k] = (items[l]);
                k++;
            }
        }

        return items2;
    }

    function fetchAllMarketItems() public view returns (MarketItem[] memory) {
        uint itemCount = 0;
        for (uint i = 1; i < fullMarketSize + 1; i++) {
            if (marketItems[i].exp > block.timestamp) {
                itemCount++;
            }
        }

        MarketItem[] memory items = new MarketItem[](itemCount);
        uint256 currentIndex = 0;
        for (uint i = 1; i < fullMarketSize + 1; i++) {
            if (marketItems[i].exp > block.timestamp) {
                items[currentIndex] = marketItems[i];
                currentIndex++;
            }
        }
        return items;
    }

    function fetchMarketItemsbyAddress(
        address nftContract
    ) public view returns (MarketItem[] memory) {
        uint itemCount = 0;
        for (uint i = 1; i < fullMarketSize + 1; i++) {
            if (
                marketItems[i].exp > block.timestamp &&
                marketItems[i].nftContract == nftContract
            ) {
                itemCount++;
            }
        }

        MarketItem[] memory items = new MarketItem[](itemCount);
        uint256 currentIndex = 0;
        for (uint i = 1; i < fullMarketSize + 1; i++) {
            if (
                marketItems[i].exp > block.timestamp &&
                marketItems[i].nftContract == nftContract
            ) {
                items[currentIndex] = marketItems[i];
                currentIndex++;
            }
        }
        return items;
    }

    function fetchMarketSizebyAddress(
        address nftContract
    ) public view returns (uint) {
        uint itemCount = 0;
        for (uint i = 1; i < fullMarketSize + 1; i++) {
            if (
                marketItems[i].exp > block.timestamp &&
                marketItems[i].nftContract == nftContract
            ) {
                itemCount++;
            }
        }
        return itemCount;
    }

    function fetchMarketItemsbyID(
        uint256 id
    ) public view returns (MarketItem memory) {
        return marketItems[id];
    }

    function refreshContracts() internal {
        Index = ContractGlossary(indexAddress);
        // AvatarAddress = Index.getAddress["Avatar"];
        // SilksContractsbyAddress[AvatarAddress] = "Avatar";
        // LandAddress = Index.getAddress("Land");
        // SilksContractsbyAddress[LandAddress] = "Land";
        // HorseAddress = Index.getAddress("Horse");
        // SilksContractsbyAddress[HorseAddress] = "Horse";
        // HorseGovAddress = Index.getAddress("HorseFractionalization");
        // SilksContractsbyAddress[HorseGovAddress] = "HorseFractionalization";
        // StableAddress = Index.getAddress("Stable");
        // SilksContractsbyAddress[StableAddress] = "Stable";
        // FarmAddress = Index.getAddress("Farm");
        // SilksContractsbyAddress[FarmAddress] = "Farm";
    }

    function _deleteMarketItem(
        uint256 itemID,
        uint256 quantity // address to
    ) internal {
        if (quantity == marketItems[itemID].quantity) {
            marketSize--;
        }
        removeMarketID(marketItems[itemID].tokenID, itemID, quantity);
        delete marketItems[itemID];
        emit MarketItemDeleted(itemID);
    }

    function _createMarketSale(
        address nftContract,
        uint256 itemID,
        address to,
        uint256 price,
        uint256 quantity
    ) internal whenNotPaused {
        refreshContracts();
        uint256 tokenID = marketItems[itemID].tokenID;
        bool sold = marketItems[itemID].sold;
        marketItems[itemID].owner = payable(msg.sender);
        require(sold != true, "This Sale has alredy finnished");
        emit MarketItemSold(
            itemID,
            marketItems[itemID].nftContract,
            marketItems[itemID].tokenID,
            marketItems[itemID].seller,
            marketItems[itemID].owner,
            price,
            to,
            quantity
        );
        uint256 quantToDelete = marketItems[itemID].quantity - quantity;
        if (quantity == marketItems[itemID].quantity) {
            marketItems[itemID].sold = true;
            removeMarketID(marketItems[itemID].tokenID, itemID, quantity);
        } else {
            marketItems[itemID].quantity = quantToDelete;
        }
        marketItems[itemID].owner = payable(to);
        _itemsSold.increment();
        uint256 fee = fees[Index.getName(nftContract)];
        marketItems[itemID].seller.transfer(price - (((price * fee) / 100)));
        FeeAddress.transfer((price * fee) / 100);
        if (is1155[nftContract] == true) {
            IERC1155(nftContract).safeTransferFrom(
                marketItems[itemID].seller,
                to,
                tokenID,
                quantity,
                ""
            );
        } else {
            IERC721(nftContract).transferFrom(
                marketItems[itemID].seller,
                to,
                tokenID
            );
        }
    }

    function _deleteOffer(
        address nftContract,
        uint256 tokenID,
        uint256 index
    ) internal {
        delete offers[nftContract][tokenID][index];
    }
}
