/**
 *Submitted for verification at Etherscan.io on 2024-03-04
 */

/**
 *Submitted for verification at testnet.snowtrace.io on 2023-07-20
 */

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import {SafeMathUpgradeable} from "./SafeMathUpgradeable.sol";
import {IERC20Upgradeable} from "./IERC20Upgradeable.sol";
import {Initializable} from "./initializer.sol";
import {IERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import {ContextUpgradeable} from "./ContextUpgradeable.sol";
import {VerifySignature} from "./VerifySignature.sol";

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract OwnableUpgradeable is Initializable, ContextUpgradeable {
    address private _owner;

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */

    function __Ownable_init() internal initializer {
        __Context_init_unchained();
        __Ownable_init_unchained();
    }

    function __Ownable_init_unchained() internal initializer {
        _transferOwnership(_msgSender());
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(
            newOwner != address(0),
            "Ownable: new owner is the zero address"
        );
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }

    uint256[49] private __gap;
}

interface HomecubesCollection721 {
    function mint(
        string memory ipfsmetadata,
        address to,
        uint256 royal,
        uint256 id_
    ) external;

    function getCreatorsAndRoyalty(
        uint256 tokenid
    ) external view returns (address, uint256);
    function changeCollectionOwner(address to) external;
    function setRoyaltyPERCentage(uint96 _royPer) external;
    function adminBurn(uint256 tokenId) external;
    function lazyMint(
        string[] memory ipfsmetadata,
        address from,
        address to,
        uint royal,
        uint256 id_
    ) external;
    function changeBaseUri(string memory _baseuri) external;
}

interface HomecubesCollectionDeployer {
    function createCollection(
        string memory _name,
        string memory _symbol,
        string memory base_,
        address _collectionOwner
    ) external returns (address);
}

contract HomecubesTrade is OwnableUpgradeable, VerifySignature {
    event OrderPlace(
        address indexed from,
        uint256 indexed tokenId,
        uint256 indexed value
    );
    event CancelOrder(address indexed from, uint256 indexed tokenId);
    event ColletionId(address indexed collectionAddress);
    event RoyaltyInfo(
        address indexed from,
        uint256 indexed royaltyPer,
        uint256 indexed royalty
    );
    using SafeMathUpgradeable for uint256;

    function initialize() public initializer {
        __Ownable_init();
        serviceValue = 3000000000000000000;
        sellervalue = 3000000000000000000;
        deci = 18;
        publicMint = true;
        _tid = 1;
    }

    struct Collection {
        uint256 nftPrice;
        address royaltyReceiver;
        address feeCollector;
    }

    struct Order {
        uint256 tokenId;
        uint256 price;
        address contractAddress;
    }

    mapping(address => mapping(uint256 => Order)) public order_place;
    mapping(string => address) private tokentype;
    mapping(address => bool) public collectionCheck;
    mapping(address => Collection) public collectionDetails;
    mapping(address => bool) public _subAdmin;

    uint256 private serviceValue;
    uint256 private sellervalue;
    bool public publicMint;
    uint256 deci;
    uint256 _tid;
    address public deployerAddress;

    struct BidOrder {
        uint256 tokenId;
        uint256 price;
        address collectionAddress;
        address bidder;
        bool status;
        uint256 withoutGasAmt;
        address bidTokenAddress;
    }

    mapping(uint256 => mapping(address => BidOrder)) public _bidDetails;
    address public exeAddress;

    uint256 public referralFees;

    function getServiceFee() external view returns (uint256, uint256) {
        return (serviceValue, sellervalue);
    }

    function setServiceValue(
        uint256 _serviceValue,
        uint256 sellerfee
    ) external onlyOwner {
        serviceValue = _serviceValue;
        sellervalue = sellerfee;
    }

    function getTokenAddress(
        string memory _type
    ) external view returns (address) {
        return tokentype[_type];
    }

    function addTokenType(
        string[] memory _type,
        address[] memory tokenAddress
    ) external onlyOwner {
        require(
            _type.length == tokenAddress.length,
            "Not equal for type and tokenAddress"
        );
        for (uint256 i = 0; i < _type.length; i++) {
            tokentype[_type[i]] = tokenAddress[i];
        }
    }

    function pERCent(
        uint256 value1,
        uint256 value2
    ) internal pure returns (uint256) {
        uint256 result = value1.mul(value2).div(1e20);
        return (result);
    }

    function calc(
        uint256 amount,
        uint256 royal,
        uint256 _serviceValue,
        uint256 _sellervalue
    ) internal pure returns (uint256, uint256, uint256) {
        uint256 fee = pERCent(amount, _serviceValue);
        uint256 roy = pERCent(amount, royal);
        uint256 netamount = 0;
        if (_sellervalue != 0) {
            uint256 fee1 = pERCent(amount, _sellervalue);
            fee = fee.add(fee1);
            netamount = amount.sub(fee1.add(roy));
        } else {
            netamount = amount.sub(roy);
        }
        return (fee, roy, netamount);
    }

    function orderPlace(
        uint256 tokenId,
        uint256 _price,
        address _conAddress
    ) external {
        require(_price > 0, "Price Must be greater than zero");
        Order memory order;
        order.tokenId = tokenId;
        order.price = _price;
        require(
            IERC721Upgradeable(_conAddress).ownerOf(tokenId) == _msgSender(),
            "Not a Owner"
        );

        order_place[_msgSender()][tokenId] = order;
        emit OrderPlace(_msgSender(), tokenId, _price);
    }
    function cancelOrder(uint256 tokenId) external {
        delete order_place[_msgSender()][tokenId];
        emit CancelOrder(_msgSender(), tokenId);
    }

    // ids[0] - tokenId, ids[1] - amount, ids[2] - collectionId
    function saleToken(
        address payable from,
        uint256[] memory ids,
        address _conAddr
    ) external payable {
        require(
            ids[1] == order_place[from][ids[0]].price &&
                order_place[from][ids[0]].price > 0,
            "Order Mismatch"
        );
        _saleToken(from, ids, "Coin", _conAddr);
        IERC721Upgradeable(_conAddr).safeTransferFrom(
            from,
            _msgSender(),
            ids[0]
        );
        if (order_place[from][ids[0]].price > 0) {
            delete order_place[from][ids[0]];
        }
    }

    // ids[0] - tokenId, ids[1] - amount
    //ldatas[0] = _royal, ldatas[1] = Tokendecimals, ldatas[2] = approveValue, ldatas[3] = _adminfee,
    //ldatas[4] = roy, ldatas[5] = netamount, ldatas[6] = val
    function _saleToken(
        address payable from,
        uint256[] memory ids,
        string memory bidtoken,
        address _conAddr
    ) internal {
        uint256[7] memory ldatas;
        ldatas[6] = pERCent(ids[1], serviceValue).add(ids[1]);
        address create;

        (create, ldatas[0]) = HomecubesCollection721(_conAddr)
            .getCreatorsAndRoyalty(ids[0]);

        if (
            keccak256(abi.encodePacked((bidtoken))) ==
            keccak256(abi.encodePacked(("Coin")))
        ) {
            require(msg.value == ldatas[6], "Mismatch the msg.value");
            (ldatas[3], ldatas[4], ldatas[5]) = calc(
                ids[1],
                ldatas[0],
                serviceValue,
                sellervalue
            );
            require(
                msg.value == ldatas[3].add(ldatas[4].add(ldatas[5])),
                "Missmatch the fees amount"
            );
            if (ldatas[3] != 0) {
                payable(owner()).transfer(ldatas[3]);
            }
            if (ldatas[4] != 0) {
                payable(collectionDetails[_conAddr].royaltyReceiver).transfer(
                    ldatas[4]
                );
            }
            if (ldatas[5] != 0) {
                from.transfer(ldatas[5]);
            }
        } else {
            IERC20Upgradeable t = IERC20Upgradeable(tokentype[bidtoken]);
            ldatas[1] = deci.sub(t.decimals());
            ldatas[2] = t.allowance(_msgSender(), address(this));
            (ldatas[3], ldatas[4], ldatas[5]) = calc(
                ids[1],
                ldatas[0],
                serviceValue,
                sellervalue
            );
            if (ldatas[3] != 0) {
                t.transferFrom(
                    _msgSender(),
                    owner(),
                    ldatas[3].div(10 ** ldatas[1])
                );
            }
            if (ldatas[4] != 0) {
                t.transferFrom(
                    _msgSender(),
                    collectionDetails[_conAddr].royaltyReceiver,
                    ldatas[4].div(10 ** ldatas[1])
                );
            }
            if (ldatas[5] != 0) {
                t.transferFrom(
                    _msgSender(),
                    from,
                    ldatas[5].div(10 ** ldatas[1])
                );
            }
        }
        emit RoyaltyInfo(
            collectionDetails[_conAddr].royaltyReceiver,
            ldatas[0],
            ldatas[4]
        );
    }

    // ids[0] - tokenId, ids[1] - amount
    function saleWithToken(
        string memory bidtoken,
        address payable from,
        uint256[] memory ids,
        address _conAddr
    ) external {
        require(ids[1] == order_place[from][ids[0]].price, "Order is Mismatch");
        _saleToken(from, ids, bidtoken, _conAddr);
        IERC721Upgradeable(_conAddr).safeTransferFrom(
            from,
            _msgSender(),
            ids[0]
        );

        if (order_place[from][ids[0]].price > 0) {
            delete order_place[from][ids[0]];
        }
    }

    function bidNFT(
        uint256 tokenId,
        address collectionAddress,
        string memory tokenName,
        uint256 usdtAmount
    ) external payable {
        bool coinStatus = keccak256(abi.encodePacked((tokenName))) ==
            keccak256(abi.encodePacked(("Coin")));
        require(
            _bidDetails[tokenId][collectionAddress].price < usdtAmount,
            "Bid value must be greater in previous value"
        );
        require(
            coinStatus ? usdtAmount == msg.value : true,
            "msg.value should be same"
        );
        if (_bidDetails[tokenId][collectionAddress].status) {
            coinStatus
                ? payable(_bidDetails[tokenId][collectionAddress].bidder)
                    .transfer(_bidDetails[tokenId][collectionAddress].price)
                : transferStaticTokenByAdmin(
                    _bidDetails[tokenId][collectionAddress].bidder,
                    _bidDetails[tokenId][collectionAddress].withoutGasAmt,
                    tokentype[tokenName]
                );
        }
        BidOrder memory _bidOrder;
        _bidOrder.tokenId = tokenId;
        _bidOrder.price = usdtAmount;
        _bidOrder.collectionAddress = collectionAddress;
        _bidOrder.bidder = _msgSender();
        _bidOrder.status = true;
        _bidOrder.withoutGasAmt = usdtAmount;
        _bidOrder.bidTokenAddress = tokentype[tokenName];
        _bidDetails[tokenId][collectionAddress] = _bidOrder;
        if (!coinStatus) {
            transferStaticToken(
                _msgSender(),
                usdtAmount,
                address(this),
                tokentype[tokenName]
            ); // collect bid amount
        }
    }

    function editBid(
        uint256 tokenId,
        address collectionAddress,
        string memory tokenName,
        uint256 usdtAmount
    ) external payable {
        require(
            _bidDetails[tokenId][collectionAddress].bidder == _msgSender(),
            "Not a valid Bidder"
        );
        require(
            _bidDetails[tokenId][collectionAddress].price <
                _bidDetails[tokenId][collectionAddress].price.add(usdtAmount),
            "Bid value must be greater in previous value"
        );
        bool coinStatus = keccak256(abi.encodePacked((tokenName))) ==
            keccak256(abi.encodePacked(("Coin")));
        _bidDetails[tokenId][collectionAddress].price = _bidDetails[tokenId][
            collectionAddress
        ].price.add(usdtAmount);
        _bidDetails[tokenId][collectionAddress].withoutGasAmt = _bidDetails[
            tokenId
        ][collectionAddress].price;
        if (!coinStatus) {
            transferStaticToken(
                _msgSender(),
                usdtAmount,
                address(this),
                _bidDetails[tokenId][collectionAddress].bidTokenAddress
            );
        }
    }

    function cancelBid(uint256 tokenId, address collectionAddress) external {
        require(
            _bidDetails[tokenId][collectionAddress].bidder == _msgSender(),
            "Not a valid Bidder"
        );
        bool coinStatus = _bidDetails[tokenId][collectionAddress]
            .bidTokenAddress == address(0);
        coinStatus
            ? payable(_bidDetails[tokenId][collectionAddress].bidder).transfer(
                _bidDetails[tokenId][collectionAddress].price
            )
            : transferStaticTokenByAdmin(
                _bidDetails[tokenId][collectionAddress].bidder,
                _bidDetails[tokenId][collectionAddress].withoutGasAmt,
                _bidDetails[tokenId][collectionAddress].bidTokenAddress
            );
        delete _bidDetails[tokenId][collectionAddress];
    }

    function cancelBidByExe(
        uint256 tokenId,
        address collectionAddress
    ) external {
        require(exeAddress == _msgSender(), "Not a Bidcancel Admin");
        bool coinStatus = _bidDetails[tokenId][collectionAddress]
            .bidTokenAddress == address(0);
        coinStatus
            ? payable(_bidDetails[tokenId][collectionAddress].bidder).transfer(
                _bidDetails[tokenId][collectionAddress].price
            )
            : transferStaticTokenByAdmin(
                _bidDetails[tokenId][collectionAddress].bidder,
                _bidDetails[tokenId][collectionAddress].withoutGasAmt,
                _bidDetails[tokenId][collectionAddress].bidTokenAddress
            );
        delete _bidDetails[tokenId][collectionAddress];
    }
    function cancelBidBySeller(
        uint256 tokenId,
        address collectionAddress
    ) external {
        require(
            IERC721Upgradeable(collectionAddress).ownerOf(tokenId) ==
                _msgSender(),
            "Not a Owner"
        );
        bool coinStatus = _bidDetails[tokenId][collectionAddress]
            .bidTokenAddress == address(0);
        coinStatus
            ? payable(_bidDetails[tokenId][collectionAddress].bidder).transfer(
                _bidDetails[tokenId][collectionAddress].price
            )
            : transferStaticTokenByAdmin(
                _bidDetails[tokenId][collectionAddress].bidder,
                _bidDetails[tokenId][collectionAddress].withoutGasAmt,
                _bidDetails[tokenId][collectionAddress].bidTokenAddress
            );
        delete _bidDetails[tokenId][collectionAddress];
    }

    // ids[0] - tokenId, ids[1] - amount, isd[2] - collectionId
    function acceptBId(
        string memory bidtoken,
        address bidaddr,
        uint256[] memory ids,
        address _conAddr
    ) external {
        _acceptBId(bidtoken, bidaddr, owner(), ids, _conAddr);
        IERC721Upgradeable(_conAddr).safeTransferFrom(
            _msgSender(),
            bidaddr,
            ids[0]
        );
        if (order_place[_msgSender()][ids[0]].price > 0) {
            delete order_place[_msgSender()][ids[0]];
        }
    }

    // ids[0] - tokenId, ids[1] - amount
    //ldatas[0] = _royal, ldatas[1] = Tokendecimals, ldatas[2] = approveValue, ldatas[3] = _adminfee,
    //ldatas[4] = roy, ldatas[5] = netamount, ldatas[6] = val
    function _acceptBId(
        string memory tokenAss,
        address from,
        address admin,
        uint256[] memory ids,
        address _conAddr
    ) internal {
        uint256[7] memory ldatas;
        ldatas[6] = pERCent(ids[1], serviceValue).add(ids[1]);
        address create;


            (create, ldatas[0]) = HomecubesCollection721(_conAddr)
                .getCreatorsAndRoyalty(ids[0]);
        

        if (
            keccak256(abi.encodePacked((tokenAss))) ==
            keccak256(abi.encodePacked(("Coin")))
        ) {
            require(
                _bidDetails[ids[0]][_conAddr].price == ldatas[6],
                "Mismatch the msg.value"
            );
            (ldatas[3], ldatas[4], ldatas[5]) = calc(
                ids[1],
                ldatas[0],
                serviceValue,
                sellervalue
            );
            require(
                _bidDetails[ids[0]][_conAddr].price ==
                    ldatas[3].add(ldatas[4].add(ldatas[5])),
                "Missmatch the fees amount"
            );
            if (ldatas[3] != 0) {
                payable(admin).transfer(ldatas[3]);
            }
            if (ldatas[4] != 0) {
                payable(collectionDetails[_conAddr].royaltyReceiver).transfer(
                    ldatas[4]
                );
            }
            if (ldatas[5] != 0) {
                payable(_msgSender()).transfer(ldatas[5]);
            }
        } else {
            IERC20Upgradeable t = IERC20Upgradeable(tokentype[tokenAss]);
            ldatas[1] = deci.sub(t.decimals());
            ldatas[2] = t.allowance(from, address(this));
            (ldatas[3], ldatas[4], ldatas[5]) = calc(
                ids[1],
                ldatas[0],
                serviceValue,
                sellervalue
            );
            if (ldatas[3] != 0) {
                t.transfer(admin, ldatas[3].div(10 ** ldatas[1]));
            }
            if (ldatas[4] != 0) {
                t.transfer(
                    collectionDetails[_conAddr].royaltyReceiver,
                    ldatas[4].div(10 ** ldatas[1])
                );
            }
            if (ldatas[5] != 0) {
                t.transfer(_msgSender(), ldatas[5].div(10 ** ldatas[1]));
            }
        }
        delete _bidDetails[ids[0]][_conAddr];
        emit RoyaltyInfo(
            collectionDetails[_conAddr].royaltyReceiver,
            ldatas[0],
            ldatas[4]
        );
    }
    // messages[0] - _message, messages[1] - tokentype
    // datas[0] - supply, datas[1] -  royal,  datas[2] - _nonce, datas[3] - signatureValue
    // _addr[0] - collection Address, _addr[1] - refAddress
    function lazyMinting(
        string[] memory ipfsmetadata,
        uint256[] memory datas,
        string[] memory messages,
        bytes memory signature,
        address[] memory _addr,
        uint256 totalValue
    ) external payable {
        require(
            verify(owner(), datas[3], messages[0], datas[2], signature) == true,
            "Not vaild User"
        );
        require(
            _msgSender() == owner() || publicMint == true,
            "Public Mint Not Available"
        );
        require(
            datas[3] == collectionDetails[_addr[0]].nftPrice,
            "Nft amount not correct"
        );
        _tid = _tid.add(1);
        uint256 id_ = _tid.add(block.timestamp);
        HomecubesCollection721(_addr[0]).lazyMint(
            ipfsmetadata,
            owner(),
            _msgSender(),
            datas[1],
            id_
        );
        require(
            totalValue == datas[3].mul(ipfsmetadata.length) && datas[3] != 0,
            "Mismatch the msg.value or Price Must > 0"
        );
        if (_addr.length > 1) {
            uint256 _refamount = pERCent(totalValue, referralFees);
            totalValue = totalValue.sub(_refamount);
            transferStaticToken(
                _msgSender(),
                _refamount,
                _addr[1],
                tokentype[messages[1]]
            );
        }
        if (datas[3] != 0) {
            transferStaticToken(
                _msgSender(),
                totalValue,
                collectionDetails[_addr[0]].feeCollector,
                tokentype[messages[1]]
            ); // sending mint amount to the collector
        }
    }

    function referralFeeEdit(uint256 _fees) external onlyOwner {
        referralFees = _fees;
    }
    // datas[0] - supply, datas[1] -  royal
    // _address[0] - To user, _address[1] - Collection Address
    function adminLazyMinting(
        string[] memory ipfsmetadata,
        uint256[] memory datas,
        address[] memory _address
    ) external onlyOwner {
        require(_msgSender() == owner(), "Public Mint Not Available");
        _tid = _tid.add(1);
        uint256 id_ = _tid.add(block.timestamp);
        HomecubesCollection721(_address[1]).lazyMint(
            ipfsmetadata,
            owner(),
            _address[0],
            datas[1],
            id_
        );
    }

    function enablePublicMint() external onlyOwner {
        publicMint = true;
    }

    function disablePublicMint() external onlyOwner {
        publicMint = false;
    }

    function setDeployerAddress(address _deployerAddress) external onlyOwner {
        deployerAddress = _deployerAddress;
    }

    function SetRoyalty(
        uint96 _royPer,
        address _collectionAddr
    ) external onlyOwner {
        HomecubesCollection721(_collectionAddr).setRoyaltyPERCentage(_royPer);
    }

    function changeCollectionOwner(
        address to,
        address _collectionAddr
    ) external onlyOwner {
        HomecubesCollection721(_collectionAddr).changeCollectionOwner(to);
    }

    function _adminBurn(
        uint256 tokenId,
        address _collectionAddr
    ) external onlyOwner {
        HomecubesCollection721(_collectionAddr).adminBurn(tokenId);
    }

    // owners[0] - collection Owner Address , owners[]
    // _name[0] - name, _name[1] - synbol, _name[2] - baseURI
    // feeCollector - mint fees collector
    function createCollection(
        address royalAddress,
        string[] memory _name,
        uint256 _nftPrice,
        address feeCollector
    ) external {
        require(_subAdmin[_msgSender()], "Not a valid user");
        address collectionAddr = HomecubesCollectionDeployer(deployerAddress)
            .createCollection(_name[0], _name[1], _name[2], address(this));
        collectionCheck[collectionAddr] = true;
        Collection memory _collectionDetails;
        _collectionDetails.nftPrice = _nftPrice;
        _collectionDetails.feeCollector = feeCollector;
        _collectionDetails.royaltyReceiver = royalAddress;
        collectionDetails[collectionAddr] = _collectionDetails;
        emit ColletionId(collectionAddr);
    }

    function blocklistCollection(
        address[] memory _collAddr
    ) external onlyOwner {
        for (uint256 index = 0; index < _collAddr.length; index++) {
            delete collectionCheck[_collAddr[index]];
        }
    }

    function whitelistCollection(
        address[] memory _collAddr
    ) external onlyOwner {
        for (uint256 index = 0; index < _collAddr.length; index++) {
            collectionCheck[_collAddr[index]] = true;
        }
    }

    function whitlistAdmin(address[] memory _address) external onlyOwner {
        for (uint256 index = 0; index < _address.length; index++) {
            _subAdmin[_address[index]] = true;
        }
    }

    function changeExeAddress(address _exeaddress) external onlyOwner {
        exeAddress = _exeaddress;
    }

    function blocklistAdmin(address[] memory _address) external onlyOwner {
        for (uint256 index = 0; index < _address.length; index++) {
            delete _subAdmin[_address[index]];
        }
    }
    // _Address[0] - collection Address, _Address[1] - New Receiver Address
    function changeRoyaltyReceiver(
        address[] memory _Address,
        uint256 _Price,
        string memory _baseuri
    ) external onlyOwner {
        collectionDetails[_Address[0]].royaltyReceiver = _Address[1];
        collectionDetails[_Address[0]].nftPrice = _Price;
        collectionDetails[_Address[0]].feeCollector = _Address[2];
        if (
            keccak256(abi.encodePacked((_baseuri))) !=
            keccak256(abi.encodePacked(("")))
        ) {
            HomecubesCollection721(_Address[0]).changeBaseUri(_baseuri);
        }
    }

    function transferStaticToken(
        address from,
        uint256 amount,
        address feeCollector,
        address tokenAdress
    ) internal {
        IERC20Upgradeable getToken = IERC20Upgradeable(tokenAdress);
        require(getToken.balanceOf(from) >= amount, "Not Enough Token Balance");
        require(
            from == address(this) ||
                getToken.allowance(from, address(this)) >= amount,
            "Token Allowance Not Enough"
        );
        uint256 decimal = deci.sub(getToken.decimals());
        getToken.transferFrom(from, feeCollector, amount.div(10 ** decimal));
    }

    function transferStaticTokenByAdmin(
        address to,
        uint256 amount,
        address tokenAddress
    ) internal {
        IERC20Upgradeable getToken = IERC20Upgradeable(tokenAddress);
        uint256 decimal = deci.sub(getToken.decimals());
        getToken.transfer(to, amount.div(10 ** decimal));
    }

    function withdrawAdminGasProfit(
        address tokenAdress,
        uint256 amount
    ) external onlyOwner {
        IERC20Upgradeable getToken = IERC20Upgradeable(tokenAdress);
        uint256 decimal = deci.sub(getToken.decimals());
        getToken.transfer(owner(), amount.div(10 ** decimal));
    }

    function TransferNFT(
        uint256 tokenId,
        address toAddress,
        address _conAddr
    ) external {
        IERC721Upgradeable(_conAddr).safeTransferFrom(
            _msgSender(),
            toAddress,
            tokenId
        );
    }

    receive() external payable {}
}
