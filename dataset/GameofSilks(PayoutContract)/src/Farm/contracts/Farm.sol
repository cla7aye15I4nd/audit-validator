// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.9;

import "@openzeppelin/contracts/finance/PaymentSplitter.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "./ERC721AWithRoyalties.sol";

abstract contract ContractGlossary {
    function getAddress(string memory name)
        public
        view
        virtual
        returns (address);
}

abstract contract ERC1155 {
    function balanceOf(address, uint256) public view virtual returns (uint256);

    function getAmountMinted() public view virtual returns (uint256);
}

abstract contract CLClient {
    function checkcontiguity(
        address to,
        uint256[] memory ids,
        uint256 tokenCount,
        string memory farmName,
        bool upgrade
    ) public virtual returns (bytes32);

    function volume() public virtual returns (string memory volume);

    function manfulfill(address from) public virtual;
}

abstract contract Lander {
    function ownerOf(uint256 tokenId) public view virtual returns (address);

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external virtual;

    function landTypes(uint256 landID)
        public
        view
        virtual
        returns (string memory);

    function farmConditionVerifier(
        uint256[] memory ids,
        address to,
        uint256[5] memory nums
    ) external virtual returns (bool);

    function FreeStable(uint256 landID) public view virtual returns (bool);
}

abstract contract Horser {
    function ownerOf(uint256 tokenId) public view virtual returns (address);

    function checkStable(uint256 horseID) public view virtual returns (uint256);

    function checkStableExp(uint256 horseID)
        public
        view
        virtual
        returns (uint256);

    function setStable(
        uint256 horseID,
        uint256 farmID,
        uint256 stableTerm
    ) external virtual;

    function exists(uint256 horseID) external virtual returns (bool);
}

abstract contract Stabler {
    function ownerOf(uint256 tokenId) public view virtual returns (address);

    function openStalls(uint256 farmID) public view virtual returns (uint256);

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external virtual;

    function stablingVerifier(
        uint256 horseID,
        uint256 stableTerm,
        uint256[4] memory minMaxes,
        uint256[] memory farms,
        uint256[] memory horses,
        address to,
        uint256 farmID
    ) external virtual returns (uint256);

    function requestVerifier(
        uint256 farmID,
        uint256 horseID,
        uint256 farmLength,
        uint256 horseLength,
        address requester,
        uint256 publicNumber,
        address to
    ) external virtual;

    function destablingVerifier(
        uint256 farmID,
        uint256 horseID,
        address to,
        uint256 val,
        uint256 destablingFee
    ) external virtual returns (address payable);

    function requestRemovalVerifier(
        address to,
        uint256 farmID,
        uint256 horseID
    ) external virtual;
}

contract Farm is ERC721A, Ownable, Pausable {
    uint256 _tokenIdCounter;
    address public LandAddress;
    address public APIConsAddress;
    address public HorseAddress;
    address public StableAddress;
    string public _baseTokenURI;

    uint256 public publicNumber;
    uint256 public minStableTerm;
    uint256 public maxStableTerm;
    uint256 public maxFarmSize;
    uint256 public minDestablingFee;
    uint256 public maxOwnerFee;

    ContractGlossary Index;

    struct FarmRequest {
        uint256[] land_ids;
        bool upgrade;
        string name;
        uint256 farmID;
    }

    struct StableRequest {
        uint256 horseID;
        uint256 farmID;
        address requester;
        uint256 stableTerm;
    }
    struct FarmStruct {
        uint256 minTerm;
        uint256 maxTerm;
        uint256 ownerFee;
        uint256 destablingFee;
        bool openFarm;
        uint256 stableID;
    }

    mapping(address => FarmRequest) public _requests;
    mapping(uint256 => uint256[]) public farms;
    mapping(uint256 => uint256[]) public horses;
    mapping(uint256 => FarmStruct) public farmParams;
    mapping(uint256 => StableRequest[]) public stableRequests;
    mapping(uint256 => uint256[]) public stableRequestsByHorse;
    mapping(address => FarmStruct) public farmRequestParams;
    mapping(string => uint256) public minFarmSizeByType;

    event FarmMinted(uint256 tokenCount, uint256[] land_ids, string name);

    event FarmUnwrapped(uint256 farmID);

    event FarmUpgraded(uint256 farmID, uint256[] land_ids);

    event HorseStableChange(
        uint256 horseID,
        uint256 farmID,
        uint256 oldFarmID,
        uint256 exp
    );

    modifier expireHorse(uint256 farmID, uint256 horseID) {
        refreshContracts();
        Horser HorseContract = Horser(HorseAddress);
        if (block.timestamp >= HorseContract.checkStableExp(horseID)) {
            _destable(HorseContract.checkStable(horseID), horseID);
        }
        for (uint256 i = 0; i < horses[farmID].length; i++) {
            if (
                block.timestamp >=
                HorseContract.checkStableExp(horses[farmID][i])
            ) {
                _destable(farmID, horses[farmID][i]);
            }
        }
        _;
    }

    constructor(
        string memory name,
        string memory symbol,
        string memory baseTokenURI,
        uint256 maxSupply,
        address[] memory payees,
        uint256[] memory shares,
        address royaltyRecipient,
        uint256 royaltyAmount,
        address indexContract
    ) ERC721A(name, symbol, maxSupply) {
        _baseTokenURI = baseTokenURI;
        _tokenIdCounter = 0;
        publicNumber = 10;
        maxFarmSize = 10;
        maxStableTerm = 24;
        minStableTerm = 3;
        minFarmSizeByType["SkyFalls"] = 1;
        minDestablingFee = 100000000000000;
        maxOwnerFee = 10;

        Index = ContractGlossary(indexContract);
    }

    function refreshContracts() internal {
        LandAddress = Index.getAddress("Land");
        APIConsAddress = Index.getAddress("APIConsumerFarm");
        HorseAddress = Index.getAddress("Horse");
        StableAddress = Index.getAddress("Stable");
    }

    function checkStableRequests(uint256 farmID)
        public
        view
        returns (StableRequest[] memory)
    {
        return stableRequests[farmID];
    }

    function checkLandPieces(uint256 farmID)
        public
        view
        returns (uint256[] memory)
    {
        return farms[farmID];
    }

    function checkHorsesOnFarm(uint256 farmID)
        public
        view
        returns (uint256[] memory)
    {
        return horses[farmID];
    }

    function changeGlobalParams(
        uint256 _publicNumber,
        uint256 _maxStableTerm,
        uint256 _minStableTerm,
        uint256 _maxFarmSize,
        uint256 _minDestablingFee,
        uint256 _maxOwnerFee
    ) public onlyOwner {
        publicNumber = publicNumber;
        maxStableTerm = _maxStableTerm;
        minStableTerm = _minStableTerm;
        maxFarmSize = _maxFarmSize;
        minDestablingFee = _minDestablingFee;
        maxOwnerFee = _maxOwnerFee;
    }

    function updateMinFarmSizeByType(
        string memory landType,
        uint256 minFarmSize
    ) public onlyOwner {
        minFarmSizeByType[landType] = minFarmSize;
    }

    function _farmGen(
        uint256 tokenID,
        address to,
        uint256 farmID,
        bool upgrade,
        uint256[] memory ids,
        string memory farmName,
        uint256 minTerm,
        uint256 maxTerm,
        uint256 destablingFee,
        uint256 ownerFee,
        bool openFarm,
        uint256 stableID
    ) internal {
        refreshContracts();
        Lander LandContract = Lander(LandAddress);
        if (
            LandContract.farmConditionVerifier(
                ids,
                to,
                [minTerm, maxTerm, destablingFee, ownerFee, stableID]
            )
        ) {
            Stabler(StableAddress).transferFrom(to, address(this), stableID);
        }
        CLClient(APIConsAddress).checkcontiguity(
            to,
            ids,
            _tokenIdCounter,
            farmName,
            upgrade
        );
        _requests[to] = FarmRequest(ids, upgrade, farmName, tokenID);
        farmRequestParams[to] = FarmStruct(
            minTerm,
            maxTerm,
            ownerFee,
            destablingFee,
            openFarm,
            stableID
        );
    }

    function wrapLandtoFarmReq(
        uint256[] memory ids,
        string memory farmName,
        uint256 minTerm,
        uint256 maxTerm,
        uint256 destablingFee,
        uint256 ownerFee,
        bool openFarm,
        uint256 stableID
    ) external {
        _farmGen(
            _tokenIdCounter,
            msg.sender,
            0,
            false,
            ids,
            farmName,
            minTerm,
            maxTerm,
            destablingFee,
            ownerFee,
            openFarm,
            stableID
        );
    }

    function upgradeFarmReq(
        uint256 farmID,
        uint256[] memory land_ids,
        uint256 stableID
    ) external {
        refreshContracts();
        Lander LandContract = Lander(LandAddress);
        require(ownerOf(farmID) == msg.sender, "MUST OWN FARM");
        uint256[] memory old_ids = checkLandPieces(farmID);
        for (uint256 i = 0; i < old_ids.length; i++) {
            land_ids[land_ids.length + i] = old_ids[i];
        }
        _farmGen(
            farmID,
            msg.sender,
            farmID,
            true,
            land_ids,
            "U",
            farmParams[farmID].minTerm,
            farmParams[farmID].maxTerm,
            farmParams[farmID].destablingFee,
            farmParams[farmID].ownerFee,
            farmParams[farmID].openFarm,
            stableID
        );
        // CLClient(APIConsAddress).checkcontiguity(
        //     msg.sender,
        //     land_ids,
        //     _tokenIdCounter,
        //     "U",
        //     true
        // );
        // _requests[msg.sender] = FarmRequest(land_ids, true, "U", farmID);
    }

    function wrapLandtoFarmFul(address to) external {
        require(msg.sender == APIConsAddress, "APICONS");
        Lander LandContract = Lander(LandAddress);
        uint256[] memory ids = _requests[to].land_ids;
        for (uint256 j = 0; j < ids.length; j++) {
            LandContract.transferFrom(to, address(this), ids[j]);
        }
        if (_requests[to].upgrade == false) {
            _safeMint(to, 1);
            _tokenIdCounter += 1;
            farmParams[_tokenIdCounter] = farmRequestParams[to];
            farms[_tokenIdCounter] = ids;
            emit FarmMinted(
                _tokenIdCounter,
                _requests[to].land_ids,
                _requests[to].name
            );
            delete _requests[to];
        } else if (_requests[to].upgrade == true) {
            for (uint256 i = 0; i < ids.length; i++) {
                farms[_requests[to].farmID].push(ids[i]);
            }
            emit FarmUpgraded(_requests[to].farmID, ids);
        }
    }

    function manualfulfill() public {
        CLClient(APIConsAddress).manfulfill(msg.sender);
    }

    function unwrapFarmtoLand(uint256 farmID) external {
        refreshContracts();
        Stabler StableContract = Stabler(StableAddress);
        uint256 horseID;
        if (StableContract.openStalls(farmID) == farms[farmID].length) {
            horseID = 1;
        } else {
            horseID = checkHorsesOnFarm(farmID)[0];
        }
        _unwrap(farmID, horseID, msg.sender);
    }

    function _unwrap(
        uint256 farmID,
        uint256 horseID,
        address to
    ) internal expireHorse(farmID, horseID) {
        require(ownerOf(farmID) == msg.sender, "MUST OWN FARM");
        require(horses[farmID].length == 0, "DEL HORSES ICI");
        transferFrom(to, address(this), farmID);
        Lander LandContract = Lander(LandAddress);
        uint256[] memory ids = farms[farmID];
        for (uint256 j = 0; j < ids.length; j++) {
            LandContract.transferFrom(address(this), to, ids[j]);
        }
        if (farmParams[farmID].stableID != 0) {
            Stabler StableContract = Stabler(StableAddress);
            StableContract.transferFrom(
                address(this),
                to,
                farmParams[farmID].stableID
            );
        }
        delete farmParams[farmID];
        delete farms[farmID];
        emit FarmUnwrapped(farmID);
    }

    function adminStableHorse(
        uint256 horseID,
        uint256 farmID,
        uint256 stableTerm
    ) public onlyOwner {
        _stableHorse(horseID, farmID, stableTerm);
    }

    function _stableHorse(
        uint256 horseID,
        uint256 farmID,
        uint256 stableTerm
    ) internal {
        horses[farmID].push(horseID);
        // Change 1 minute to 30 days
        uint256 blockExp = (block.timestamp + (stableTerm * 1 hours));
        Horser HorseContract = Horser(HorseAddress);
        emit HorseStableChange(
            horseID,
            farmID,
            HorseContract.checkStable(horseID),
            blockExp
        );
        HorseContract.setStable(horseID, farmID, blockExp);
    }

    function _stableRequest(
        uint256 horseID,
        uint256 farmID,
        uint256 stableTerm
    ) internal {
        // 1 min->30 days
        stableRequests[farmID].push(
            StableRequest(horseID, farmID, msg.sender, stableTerm)
        );
        stableRequestsByHorse[horseID].push(farmID);
    }

    function stableHorse(
        uint256 horseID,
        uint256 farmID,
        uint256 stableTerm
    ) public payable expireHorse(farmID, horseID) {
        refreshContracts();
        require(ownerOf(farmID) != address(this), "FARM DNE");
        Stabler(StableAddress).stablingVerifier(
            horseID,
            stableTerm,
            [
                minStableTerm,
                maxStableTerm,
                farmParams[farmID].minTerm,
                farmParams[farmID].maxTerm
            ],
            farms[farmID],
            horses[farmID],
            msg.sender,
            farmID
        );
        if (
            farms[farmID].length < publicNumber || ownerOf(farmID) == msg.sender
        ) {
            //Private/Open, No need Approval
            require(ownerOf(farmID) == msg.sender, "MUST OWN P FARM");
            _stableHorse(horseID, farmID, stableTerm);
        } else {
            //Public
            if (farmParams[farmID].openFarm == true) {
                _stableHorse(horseID, farmID, stableTerm);
            } else {
                _stableRequest(horseID, farmID, stableTerm);
            }
        }
    }

    function destable(uint256 horseID) public payable {
        refreshContracts();
        Horser HorseContract = Horser(HorseAddress);
        Stabler StableContract = Stabler(StableAddress);
        uint256 farmID = HorseContract.checkStable(horseID);
        address payable _addr = StableContract.destablingVerifier(
            farmID,
            horseID,
            msg.sender,
            msg.value,
            farmParams[farmID].destablingFee
        );
        if (_addr != payable(address(0))) {
            _addr.transfer(msg.value);
        }
        _destable(farmID, horseID);
    }

    function _destable(uint256 farmID, uint256 horseID) internal {
        for (uint256 i = 0; i < horses[farmID].length; i++) {
            if (horses[farmID][i] == horseID) {
                if (horses[farmID].length > 1) {
                    horses[farmID][i] = horses[farmID][
                        horses[farmID].length - 1
                    ];
                }
                horses[farmID].pop();
                break;
            }
        }
        Horser HorseContract = Horser(HorseAddress);
        emit HorseStableChange(
            horseID,
            0,
            HorseContract.checkStable(horseID),
            0
        );
        HorseContract.setStable(horseID, 0, 0);
    }

    function changeFarmParams(
        uint256 farmID,
        uint256 minTerm,
        uint256 maxTerm,
        uint256 destablingFee,
        uint256 ownerFee,
        bool openFarm
    ) public {
        require(ownerOf(farmID) == msg.sender, "DOESNT OWN FARM");
        require(horses[farmID].length == 0, "MUST DESTABLE HORSES");
        farmParams[farmID] = FarmStruct(
            minTerm,
            maxTerm,
            ownerFee,
            destablingFee,
            openFarm,
            farmParams[farmID].stableID
        );
    }

    function _removeRequest(
        uint256 horseID,
        uint256 farmID,
        uint256 reqnum
    ) internal {
        stableRequests[farmID][reqnum] = stableRequests[farmID][
            stableRequests[farmID].length - 1
        ];
        stableRequests[farmID].pop();
        for (uint256 i = 0; i < stableRequestsByHorse[horseID].length; i++) {
            uint256 itFarm = stableRequestsByHorse[horseID][i];
            if (itFarm == farmID) {
                delete stableRequestsByHorse[horseID][i];
            }
        }
    }

    function approveRequest(uint256 farmID, uint256 reqnum)
        public
        expireHorse(farmID, stableRequests[farmID][reqnum].horseID)
    {
        refreshContracts();
        uint256 horseID = stableRequests[farmID][reqnum].horseID;
        Stabler(StableAddress).requestVerifier(
            farmID,
            horseID,
            farms[farmID].length,
            horses[farmID].length,
            stableRequests[farmID][reqnum].requester,
            publicNumber,
            msg.sender
        );
        _stableHorse(
            horseID,
            farmID,
            stableRequests[farmID][reqnum].stableTerm
        );
        _removeRequest(horseID, farmID, reqnum);
        for (uint256 i; i < stableRequestsByHorse[horseID].length; i++) {
            uint256 _farmID = stableRequestsByHorse[horseID][i];
            for (uint256 j; j < stableRequests[_farmID].length; j++) {
                if (stableRequests[_farmID][j].horseID == horseID) {
                    stableRequests[_farmID][j] = stableRequests[_farmID][
                        stableRequests[_farmID].length - 1
                    ];
                    stableRequests[_farmID].pop();
                }
            }
        }
        delete stableRequestsByHorse[horseID];
    }

    function removeRequest(uint256 farmID, uint256 reqnum) public {
        refreshContracts();
        Stabler StableContract = Stabler(StableAddress);
        uint256 horseID = stableRequests[farmID][reqnum].horseID;
        StableContract.requestRemovalVerifier(msg.sender, farmID, horseID);
        _removeRequest(horseID, farmID, reqnum);
    }

    function setBaseUri(string memory baseUri) external onlyOwner {
        _baseTokenURI = baseUri;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return string(abi.encodePacked(_baseTokenURI));
    }
}
