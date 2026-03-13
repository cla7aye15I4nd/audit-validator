// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Chainlink, ChainlinkClient} from "@chainlink/contracts@1.1.1/src/v0.8/ChainlinkClient.sol";
import {ConfirmedOwner} from "@chainlink/contracts@1.1.1/src/v0.8/shared/access/ConfirmedOwner.sol";
import {LinkTokenInterface} from "@chainlink/contracts@1.1.1/src/v0.8/shared/interfaces/LinkTokenInterface.sol";

contract PriceConsumer is ChainlinkClient, ConfirmedOwner {
    
    using Chainlink for Chainlink.Request;
    uint256 private constant ORACLE_PAYMENT = (1 * LINK_DIVISIBILITY) / 10;  // 0.1 = 1 / 10, 0.01 = 1 / 10
    uint256 public currentPrice;

    /**
        chainlinkOracleAddress
        1. operator address (eth sepolia - eth ) : 0xE687a15c2e1D4fD076Eac96866225ED1b9D7B17D
        2. operator address (arb sepolia - eth ) : 0xB5ee550DeA943A02CcDe242680Cd92505b791Ea4
        3. operator address (bsc testnet )       : 0x1abee4dC41006c0736D10d58bd3CeEC6066F5Ca8
    **/

    address private constant chainlinkOracleAddress = 0x1abee4dC41006c0736D10d58bd3CeEC6066F5Ca8;
    
    event logRequest(string path, address _caller);
    event CallbackPriceFulfilled(bytes32 indexed requestId,uint256 indexed price);

    /**
     *  Sepolia
     *  @dev LINK address in Sepolia (eth) network: 0x779877A7B0D9E8603169DdbD7836e478b4624789
     *  @dev LINK address in Sepolia (arb) network: 0xb1D4538B4571d411F07960EF2838Ce337FE1E80E
     *  BSC testnet                               : 0x84b9B910527Ad5C03A9Ca831909E21e236EA7b06
     *  @dev Check https://docs.chain.link/docs/link-token-contracts/ for LINK address for the right network
     */
    constructor() ConfirmedOwner(msg.sender) {
        _setChainlinkToken(0x84b9B910527Ad5C03A9Ca831909E21e236EA7b06);
        emit logRequest("constructor",msg.sender);
    }

    function requestPrice(address _oracle, string memory _jobId) public onlyOwner {
        Chainlink.Request memory req = _buildChainlinkRequest(
            stringToBytes32(_jobId),
            address(this),
            this.callbackPrice.selector
        );
        req._add("get", "https://price.amorphoux.io:900/data/price");
        req._add("path", "price");
        req._addInt("times", 1000000000000000000);
        emit logRequest("requestPrice", msg.sender);
        _sendChainlinkRequestTo(_oracle, req, ORACLE_PAYMENT);
    }

    function callbackPrice(bytes32 _requestId, uint256 _price) public onlyChainlink recordChainlinkFulfillment(_requestId) {
        currentPrice = _price;
        emit logRequest("callbackPrice", msg.sender);
        emit CallbackPriceFulfilled(_requestId, _price);
    }

    modifier onlyChainlink() {
        require(msg.sender == chainlinkOracleAddress, "Only Chainlink oracle can call this");
        _;
    }

    function withdrawLink() public onlyOwner {
        LinkTokenInterface link = LinkTokenInterface(_chainlinkTokenAddress());
        require(
            link.transfer(msg.sender, link.balanceOf(address(this))),
            "Unable to transfer"
        );
    }

    function stringToBytes32(string memory source) private pure returns (bytes32 result) {
        bytes memory tempEmptyStringTest = bytes(source);
        if (tempEmptyStringTest.length == 0) {
            return 0x0;
        }

        assembly { // solhint-disable-line no-inline-assembly
            result := mload(add(source, 32))
        }
    }
}