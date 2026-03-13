// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SolidStateDiamond} from "../../lib/solidstate/proxy/diamond/SolidStateDiamond.sol";
import {IERC721Receiver} from "../../lib/openzeppelin/token/ERC721/IERC721Receiver.sol";

contract Game is SolidStateDiamond, IERC721Receiver {
    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
