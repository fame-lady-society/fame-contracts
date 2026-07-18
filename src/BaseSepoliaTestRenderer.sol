// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Base64} from "solady/utils/Base64.sol";
import {LibString} from "solady/utils/LibString.sol";
import {ITokenURIGenerator} from "./ITokenURIGenerator.sol";

/// @notice Stateless on-chain metadata used to validate the Base Sepolia marketplace stack.
contract BaseSepoliaTestRenderer is ITokenURIGenerator {
    using LibString for uint256;

    function tokenURI(uint256 tokenId) public pure override returns (string memory) {
        string memory id = tokenId.toString();
        string memory image = string.concat("data:image/svg+xml;base64,", Base64.encode(bytes(_svg(tokenId, id))));
        string memory json = string.concat(
            '{"name":"Example Society #',
            id,
            '","description":"On-chain art for validating the Base Sepolia marketplace.","image":"',
            image,
            '","attributes":[{"trait_type":"Token ID","value":"',
            id,
            '"},{"trait_type":"Network","value":"Base Sepolia"},{"trait_type":"Purpose","value":"Marketplace Test"}]}'
        );

        return string.concat("data:application/json;base64,", Base64.encode(bytes(json)));
    }

    function _svg(uint256 tokenId, string memory id) private pure returns (string memory) {
        uint256 seed = uint256(keccak256(abi.encodePacked(tokenId)));
        string memory background = string.concat("#", (seed & 0xffffff).toHexStringNoPrefix(3));
        string memory accent = string.concat("#", ((seed >> 24) & 0xffffff).toHexStringNoPrefix(3));

        return string.concat(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">',
            '<rect width="512" height="512" fill="',
            background,
            '"/><circle cx="256" cy="210" r="142" fill="',
            accent,
            '"/><text x="256" y="226" text-anchor="middle" fill="white" font-family="monospace" font-size="54">#',
            id,
            '</text><text x="256" y="408" text-anchor="middle" fill="white" font-family="monospace" font-size="22">BASE SEPOLIA TEST</text></svg>'
        );
    }
}
