// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/finance/PaymentSplitter.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "./ERC721AWithRoyalties.sol";

abstract contract ContractGlossary {
    function getAddress(string memory name)
        public
        view
        virtual
        returns (address);
}

abstract contract Farmer {
    struct StableRequest {
        uint256 horseID;
        uint256 farmID;
        address requester;
        uint256 stableTerm;
    }

    function ownerOf(uint256 tokenId) public view virtual returns (address);

    function minFarmSizeByType(string memory name)
        public
        view
        virtual
        returns (uint256);

    function checkStableRequests(uint256 farmID)
        public
        view
        virtual
        returns (StableRequest[] memory);

    function checkLandPieces(uint256 farmID)
        public
        view
        virtual
        returns (uint256[] memory);

    function checkHorsesOnFarm(uint256 farmID)
        public
        view
        virtual
        returns (uint256[] memory);
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

contract Stable is Ownable, ERC721AWithRoyalties, Pausable, PaymentSplitter {
    uint256 _tokenIdCounter;
    address public skyFallsPyramidAddress;
    address private extMintAddress;
    address public LandAddress;
    address public APIConsAddress;
    address public HorseAddress;
    address public HorseGovAddress;
    address public StableAddress;
    address public FarmAddress;

    string public _baseTokenURI;
    uint256 private _maxSupply;

    mapping(uint256 => string) public StableTypes;
    mapping(uint256 => bool) public FreeStable;

    struct FarmStruct {
        uint256 minTerm;
        uint256 maxTerm;
        uint256 ownerFee;
        uint256 destablingFee;
        bool openFarm;
        uint256 stableID;
    }
    struct StableRequest {
        uint256 horseID;
        uint256 farmID;
        address requester;
        uint256 stableTerm;
        uint256 _stableReqCounter;
    }

    ContractGlossary Index;

    event StableMinted(
        uint256 amount_req,
        uint256 _tokenIdCounter,
        string StableType
    );

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
    )
        ERC721AWithRoyalties(
            name,
            symbol,
            maxSupply,
            royaltyRecipient,
            royaltyAmount
        )
        PaymentSplitter(payees, shares)
    {
        _baseTokenURI = baseTokenURI;
        _tokenIdCounter = 0;
        _maxSupply = maxSupply;
        Index = ContractGlossary(indexContract);
    }

    function setExtMintAddress(address contractAddress) public onlyOwner {
        extMintAddress = contractAddress;
    }

    function setBaseUri(string memory baseUri) external onlyOwner {
        _baseTokenURI = baseUri;
    }

    function refreshContracts() internal {
        LandAddress = Index.getAddress("Land");
        APIConsAddress = Index.getAddress("APIConsumerFarm");
        HorseAddress = Index.getAddress("Horse");
        HorseGovAddress = Index.getAddress("HorseGovernance");
        StableAddress = Index.getAddress("Stable");
        FarmAddress = Index.getAddress("Farm");
    }

    function _mint(
        address to,
        uint256 count,
        string memory StableType
    ) internal {
        ensureMintConditions(count);
        emit StableMinted(count, _tokenIdCounter, StableType);
        _safeMint(to, count);
        for (uint256 i = 0; i < count; i++) {
            StableTypes[_tokenIdCounter + 1 + i] = StableType;
        }
        _tokenIdCounter += count;
    }

    function mint(
        address to,
        uint256 count,
        string memory StableType
    ) external payable onlyOwner {
        _mint(to, count, StableType);
    }

    function extMintPay(
        address to,
        uint256 count,
        string memory StableType
    ) external payable whenNotPaused {
        require(msg.sender == extMintAddress);
        _mint(to, count, StableType);
    }

    function extMintFree(
        address to,
        uint256 count,
        string memory StableType
    ) external whenNotPaused {
        require(
            msg.sender == extMintAddress,
            "MUST BE CALLED BY SPECIFIED EXTERNAL MINT ADDRESS"
        );
        _mint(to, count, StableType);
    }

    function openStalls(uint256 farmID) public view returns (uint256) {
        Farmer FarmContract = Farmer(FarmAddress);
        Horser HorseContract = Horser(HorseAddress);
        uint256 farmlength = FarmContract.checkLandPieces(farmID).length;
        uint256[] memory horses = FarmContract.checkHorsesOnFarm(farmID);
        for (uint256 i = 0; i < horses.length; i++) {
            if (HorseContract.checkStableExp(horses[i]) > block.timestamp) {
                farmlength -= 1;
            }
        }
        return farmlength;
    }

    function stablingVerifier(
        uint256 horseID,
        uint256 stableTerm,
        uint256[4] memory minMaxes,
        uint256[] memory farms,
        uint256[] memory horses,
        address to,
        uint256 farmID
    ) external returns (uint256 farmExpDate) {
        refreshContracts();
        uint256 minStableTerm = minMaxes[0];
        uint256 maxStableTerm = minMaxes[1];
        uint256 minTerm = minMaxes[2];
        uint256 maxTerm = minMaxes[3];
        refreshContracts();
        require(
            msg.sender == Index.getAddress("Farm"),
            "MUST BE CALLED FROM FARM CONTRACT"
        );
        require(
            stableTerm >= minStableTerm && stableTerm <= maxStableTerm,
            "STABLE TERM MUST BE BETWEEN MIN & MAX STABLE TERM"
        );
        require(
            stableTerm >= minTerm && stableTerm <= maxTerm,
            "STABLE TERM MUST BE WITHIN STABLE OWNER'S PARAMETERS"
        );
        require(farms.length > 0, "FARM MUST BE >0");
        require(
            (farms.length - horses.length) > 0,
            "FARM MUST HAVE ENOUGH SLOTS"
        );
        Horser HorseContract = Horser(HorseAddress);
        Horser HorseGovContract = Horser(HorseGovAddress);
        Farmer FarmContract = Farmer(FarmAddress);
        uint256 horse = horseID;
        if (to != HorseContract.ownerOf(horse)) {
            require(
                HorseContract.ownerOf(horse) == to ||
                    HorseGovContract.ownerOf(horse) == to,
                "MUST OWN HORSE OR HORSE GOVERNANCE TOKEN"
            );
        }

        require(
            HorseContract.checkStable(horse) == 0,
            "HORSE MUST BE DESTABLED FIRST"
        );
        for (uint256 i = 0; i < horses.length; i++) {
            require(
                horses[i] != horse,
                "HORSE MUST NOT ALREADY BE STABLED IN THIS FARM"
            );
        }
        Farmer.StableRequest[] memory requests = FarmContract
            .checkStableRequests(farmID);
        for (uint256 i = 0; i < requests.length; i++) {
            require(
                requests[i].horseID != horse,
                "CANNOT SEND DUPLICATE REQUEST TO THIS FARM"
            );
        }
        return HorseContract.checkStableExp(horse);
    }

    function requestVerifier(
        uint256 farmID,
        uint256 horseID,
        uint256 farmLength,
        uint256 horseLength,
        address requester,
        uint256 publicNumber,
        address to
    ) external {
        refreshContracts();
        require(
            msg.sender == Index.getAddress("Farm"),
            "MUST BE CALLED FROM FARM CONTRACT"
        );
        require(farmLength > 0, "FARM MUST BE >0");
        require(farmLength >= publicNumber, "FARM MUST BE PUBLIC");
        require((farmLength - horseLength) > 0, "FARM MUST HAVE ENOUGH SLOTS");
        Horser HorseContract = Horser(HorseAddress);

        require(
            Farmer(Index.getAddress("Farm")).ownerOf(farmID) == to,
            "MUST OWN FARM TO APPROVE REQUESTS"
        );
        Horser HorseGovContract = Horser(HorseGovAddress);
        require(
            HorseContract.ownerOf(horseID) == requester ||
                HorseGovContract.ownerOf(horseID) == requester,
            "REQUESTER NO LONGER OWNER OF HORSE OR HORSE GOVERNANCE TOKEN"
        );
    }

    function destablingVerifier(
        uint256 farmID,
        uint256 horseID,
        address to,
        uint256 val,
        uint256 destablingFee
    ) external returns (address payable) {
        refreshContracts();
        require(msg.sender == FarmAddress, "MUST BE CALLED FROM FARM CONTRACT");
        require(
            farmID != 0,
            "CANNOT DESTABLE A HORSE THAT IS ALREADY DESTABLED"
        );
        Horser HorseContract = Horser(HorseAddress);
        Horser HorseGovContract = Horser(HorseGovAddress);
        Farmer FarmContract = Farmer(FarmAddress);
        Horser HorseTestContract;
        address payable _addr;

        if (
            HorseContract.ownerOf(horseID) ==
            Index.getAddress("HorsePartnership")
        ) {
            HorseTestContract = Horser(HorseGovAddress);
        } else {
            HorseTestContract = Horser(HorseAddress);
        }

        if (
            to == HorseTestContract.ownerOf(horseID) &&
            to == FarmContract.ownerOf(farmID)
        ) {
            _addr = payable(address(0));
        } else if (to == HorseTestContract.ownerOf(horseID)) {
            if (block.timestamp < HorseContract.checkStableExp(horseID)) {
                require(
                    val >= destablingFee,
                    "MUST SEND ETH >= DESTABLING FEE"
                );
                _addr = payable(FarmContract.ownerOf(farmID));
            } else {
                _addr = payable(address(0));
            }
        } else if (to == FarmContract.ownerOf(farmID)) {
            if (block.timestamp < HorseContract.checkStableExp(horseID)) {
                require(
                    val >= destablingFee,
                    "MUST SEND ETH >= DESTABLING FEE"
                );
                _addr = payable(HorseTestContract.ownerOf(horseID));
            } else {
                _addr = payable(address(0));
            }
        } else {
            revert("MUST BE HORSE/HORSEGOV OR FARM OWNER TO DESTABLE");
        }
        return _addr;
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return string(abi.encodePacked(_baseTokenURI));
    }

    function ensureMintConditions(uint256 count) internal view {
        require(totalSupply() + count <= _maxSupply, "EXCEEDS_MAX_SUPPLY");
    }

    function MAX_TOTAL_MINT() public view returns (uint256) {
        return _maxSupply;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
