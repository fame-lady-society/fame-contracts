// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {LibString} from "solady/utils/LibString.sol";
import "../../src/ITokenURIGenerator.sol";

contract EchoMetadata is ITokenURIGenerator {
    using LibString for string;
    using LibString for uint256;

    function tokenURI(uint256 tokenId) public pure returns (string memory) {
        return tokenId.toString();
    }
}
