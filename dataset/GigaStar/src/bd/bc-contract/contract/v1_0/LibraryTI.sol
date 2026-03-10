// SPDX-License-Identifier: UNLICENSED
// Copyright 2025, GigaStar Technologies LLC, All Rights Reserved, https://gigastar.io
pragma solidity ^0.8.29;

import './LibraryUtil.sol';

/// @dev Token Info Library
/// @custom:api public
// prettier-ignore
library TI { // Token Info

    enum TokenType  { None, NativeCoin, Erc20, Erc1155, Erc1155Crt,
                      Count // Metadata: Used for input validation; Must remain last item
                    }

    /// @dev Token information
    /// - Upgradability is not a concern for this fundamental type
    struct TokenInfo {
        string tokSym;          /// Token symbol (eg USDC)
        TokenType tokType;      /// Affects how token processing
        address tokAddr;        /// Token address
        uint tokenId;           /// For ERC-1155, else 0
    }
}
