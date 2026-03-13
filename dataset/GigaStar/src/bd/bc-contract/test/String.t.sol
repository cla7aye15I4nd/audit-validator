// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

// See LIB_PATHS
import '../lib/forge-std/src/console.sol';
import '../lib/forge-std/src/StdError.sol';
import '../lib/forge-std/src/Test.sol';

import '../contract/v1_0/LibraryString.sol';

// Helper to allow calldata to be received easily
contract StringSpy {
    function toBytes32(string calldata source) public pure returns (bytes32 result) {
        return String.toBytes32(source);
    }
}

contract StringTest is Test {

    string[10] samples = [ '', 'a', 'BC', 'DEF', 'GHIJ', 'ABC.1', 'ABCD.1', 'ABCDE.99', 'ABCDE.999',
        '12345678901234567890123456789012' // 32 chars
    ];

    string long =    '12345678901234567890123456789012';  // 32 chars
    string tooLong = '123456789012345678901234567890123'; // 33 chars

    function test_String_bytes32_string_roundtrip() public {
        StringSpy spy = new StringSpy();
        for (uint i = 0; i < samples.length; i++) {
            bytes32 b = spy.toBytes32(samples[i]);
            string memory roundTrip = String.toString(b);
            assertEq(roundTrip, samples[i]);
        }
        assertEq(String.toString(spy.toBytes32(tooLong)), long, 'truncated');
    }

    function test_String_toBytes32_roundtrip() public view {
        for (uint i = 0; i < samples.length; i++) {
            bytes32 b = String.toBytes32Mem(samples[i]);
            string memory back = String.toString(b);
            assertEq(back, samples[i]);
        }
        assertEq(String.toString(String.toBytes32Mem(tooLong)), long, 'truncated');
    }
}
