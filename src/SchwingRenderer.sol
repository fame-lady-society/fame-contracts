// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {LibString} from "solady/utils/LibString.sol";
import "./ITokenURIGenerator.sol";

contract SchwingRenderer is ITokenURIGenerator {
    using LibString for string;
    using LibString for uint256;

    string constant baseURI = "https://onchaingas.vercel.app/schwing/metadata/";
    function tokenURI(uint256 tokenId) public pure returns (string memory) {
        return baseURI.concat(tokenId.toString());
    }
}
