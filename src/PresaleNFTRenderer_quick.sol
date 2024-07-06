// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "./ITokenURIGenerator.sol";

contract PresaleNFTRendererMetadataQuick is ITokenURIGenerator {
    function tokenURI(uint256) public pure returns (string memory) {
        return "https://www.fameladysociety.com/fountain/metadata.json";
    }
}
