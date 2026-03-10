// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import "@chainlink/contracts/src/v0.8/ConfirmedOwner.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

abstract contract ContractGlossaryAPI {
    function getAddress(string memory name)
        public
        view
        virtual
        returns (address);
}

abstract contract Farmer {
    function wrapLandtoFarmFul(address to) external virtual;
}

contract APIConsumer is ChainlinkClient, ConfirmedOwner {
    using Chainlink for Chainlink.Request;

    string public plots_gend;
    bytes32 private jobId;
    uint256 private fee;
    address public FarmAddress;
    string public testurl;
    bytes32 public reqid;
    mapping(bytes32 => address) private requests;
    mapping(bytes32 => string) private responses;
    mapping(address => bytes32) private _reqbyad;

    event FarmVerified(bytes32 indexed requestId, string plots_gend);

    ContractGlossaryAPI Index;

    /**
     * @notice Initialize the link token and target oracle
     *
     * Goerli Testnet details:
     * Link Token: 0x326C977E6efc84E512bB9C30f76E30c160eD06FB
     * Oracle: 0xCC79157eb46F5624204f47AB42b3906cAA40eaB7 (Chainlink DevRel)
     * jobId: 7d80a6386ef543a3abb52817f6707e3b
     *
     */
    constructor(address indexContract) ConfirmedOwner(msg.sender) {
        setChainlinkToken(0x326C977E6efc84E512bB9C30f76E30c160eD06FB);
        setChainlinkOracle(0xCC79157eb46F5624204f47AB42b3906cAA40eaB7);
        jobId = "7d80a6386ef543a3abb52817f6707e3b";
        fee = (1 * LINK_DIVISIBILITY) / 10; // 0,1 * 10**18 (Varies by network and job)
        Index = ContractGlossaryAPI(indexContract);
    }

    /**
     * Create a Chainlink request to retrieve API response, find the target
     */

    function checkcontiguity(
        address to,
        uint256[] memory ids,
        uint256 tokenCount,
        string memory farmName,
        bool upgrade
    ) public returns (bytes32 requestId) {
        FarmAddress = Index.getAddress("Farm");
        require(msg.sender == FarmAddress);
        Chainlink.Request memory req = buildChainlinkRequest(
            jobId,
            address(this),
            this.fulfill.selector
        );
        if (upgrade == true) {
            for (uint256 i = 0; i < ids.length; i++) {
                require(
                    IERC721(Index.getAddress("Land")).ownerOf(ids[i]) == to,
                    "MUST OWN NEW LAND TOKENS"
                );
            }
            string
                memory url = "https://land-mint.dev.silks.io/api/v1/checkcontiguity?upgrade=true&tokenCount=";
        }
        string
            memory url = "https://land-mint.dev.silks.io/api/v1/checkcontiguity?tokenCount=";
        string memory tokenCountst = Strings.toString(tokenCount);
        bytes memory base_url = abi.encodePacked(
            url,
            tokenCountst,
            "&name=",
            farmName
        );
        bytes memory args;
        for (uint256 i = 0; i < ids.length; i++) {
            args = abi.encodePacked(
                string(args),
                "&",
                "t",
                Strings.toString(i),
                "=",
                Strings.toString(ids[i])
            );
        }
        string memory full_url_st = string(abi.encodePacked(base_url, args));
        testurl = full_url_st;
        // Set the URL to perform the GET request on
        req.add("get", full_url_st);
        req.add("path", "Response"); // Chainlink nodes 1.0.0 and later support this format
        // int256 timesAmount = 1;
        // req.addInt("times", timesAmount);

        // Sends the request
        reqid = sendChainlinkRequest(req, fee);
        requests[reqid] = to;
        _reqbyad[to] = reqid;
        return reqid;
    }

    /**
     * Receive the response in the form of a string
     */
    function fulfill(bytes32 _requestId, string memory _plots)
        public
        recordChainlinkFulfillment(_requestId)
    {
        emit FarmVerified(_requestId, _plots);
        responses[_requestId] = _plots;
        // plots_gend = _plots;
        // address to = requests[_requestId];
        // Farmer FarmContract = Farmer(FarmAddress);
        // FarmContract.wrapLandtoFarmFul(to);
    }

    function manfulfill(address from) public {
        FarmAddress = Index.getAddress("Farm");
        require(msg.sender == FarmAddress, "MUST BE CALLED FROM FARM CONTRACT");
        reqid = _reqbyad[from];
        require(
            keccak256(abi.encodePacked(responses[reqid])) == keccak256("True"),
            "PIECES MUST BE CONTIGUOUS AND NO DUPLICATE IDS"
        );
        delete _reqbyad[from];
        Farmer FarmContract = Farmer(FarmAddress);
        FarmContract.wrapLandtoFarmFul(from);
    }

    /**
     * Allow withdraw of Link tokens from the contract
     */
    function withdrawLink() public onlyOwner {
        LinkTokenInterface link = LinkTokenInterface(chainlinkTokenAddress());
        require(
            link.transfer(msg.sender, link.balanceOf(address(this))),
            "Unable to transfer"
        );
    }
}
