// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Base64} from "solady/utils/Base64.sol";
import {LibString} from "solady/utils/LibString.sol";
import {BaseSepoliaTestRenderer} from "../src/BaseSepoliaTestRenderer.sol";

contract BaseSepoliaTestRendererTest is Test {
    using LibString for string;
    using LibString for uint256;

    string internal constant JSON_PREFIX = "data:application/json;base64,";
    string internal constant SVG_PREFIX = "data:image/svg+xml;base64,";

    BaseSepoliaTestRenderer internal renderer;

    function setUp() public {
        renderer = new BaseSepoliaTestRenderer();
    }

    function testTokenUriDecodesToTokenSpecificMetadataAndSvg() public view {
        uint256 tokenId = 12;
        string memory json = _decodeDataUri(renderer.tokenURI(tokenId), JSON_PREFIX);

        assertEq(vm.parseJsonString(json, ".name"), "Example Society #12");
        assertTrue(vm.parseJsonString(json, ".description").contains("Base Sepolia marketplace"));
        assertTrue(json.contains('"trait_type":"Token ID","value":"12"'));
        assertTrue(json.contains('"trait_type":"Network","value":"Base Sepolia"'));

        string memory svg = _decodeDataUri(vm.parseJsonString(json, ".image"), SVG_PREFIX);
        assertTrue(svg.contains('<svg xmlns="http://www.w3.org/2000/svg"'));
        assertTrue(svg.contains('fill="#'));
        assertFalse(svg.contains('fill="0x'));
        assertTrue(svg.contains(">#12<"));
    }

    function testDifferentTokenIdsProduceDifferentMetadataAndSvg() public view {
        string memory uri12 = renderer.tokenURI(12);
        string memory uri420 = renderer.tokenURI(420);
        assertNotEq(uri12, uri420);

        string memory json12 = _decodeDataUri(uri12, JSON_PREFIX);
        string memory json420 = _decodeDataUri(uri420, JSON_PREFIX);
        assertNotEq(vm.parseJsonString(json12, ".image"), vm.parseJsonString(json420, ".image"));
    }

    function testTokenUriIsDeterministic() public view {
        assertEq(renderer.tokenURI(420), renderer.tokenURI(420));
    }

    function testBoundaryTokenIdsRenderWithoutTruncation() public view {
        _assertTokenIdRendered(0);
        _assertTokenIdRendered(500);
        _assertTokenIdRendered(888);
        _assertTokenIdRendered(type(uint256).max);
    }

    function _assertTokenIdRendered(uint256 tokenId) internal view {
        string memory tokenIdString = tokenId.toString();
        string memory json = _decodeDataUri(renderer.tokenURI(tokenId), JSON_PREFIX);
        assertEq(vm.parseJsonString(json, ".name"), string.concat("Example Society #", tokenIdString));

        string memory svg = _decodeDataUri(vm.parseJsonString(json, ".image"), SVG_PREFIX);
        assertTrue(svg.contains(string.concat(">#", tokenIdString, "<")));
    }

    function _decodeDataUri(string memory uri, string memory prefix) internal pure returns (string memory) {
        assertTrue(uri.startsWith(prefix));
        return string(Base64.decode(uri.slice(bytes(prefix).length)));
    }
}
