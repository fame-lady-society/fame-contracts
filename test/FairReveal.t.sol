// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {LibString} from "solady/utils/LibString.sol";
import {FairReveal} from "../src/FairReveal.sol";

contract FairRevealTest is Test {
    using LibString for uint256;
    FairReveal public fairReveal;

    function setUp() public {
        fairReveal = new FairReveal(
            address(0),
            "revealed://",
            "unrevealed://",
            8
        );
    }

    function test_Reveal1() public {
        fairReveal.reveal(0, 4);
        vm.prevrandao(bytes32(uint256(0)));
        (uint256 tokenId, uint256 salt) = fairReveal.resolveTokenId(0);
        assertEq(tokenId, 5);
        uint256 saltedTokenId = uint256(
            keccak256(abi.encodePacked(tokenId, salt))
        );
        assertEq(
            fairReveal.tokenURI(1),
            LibString.concat("revealed://", saltedTokenId.toString())
        );
        (tokenId, salt) = fairReveal.resolveTokenId(3);
        saltedTokenId = uint256(keccak256(abi.encodePacked(tokenId, salt)));
        assertEq(
            fairReveal.tokenURI(4),
            LibString.concat("revealed://", saltedTokenId.toString())
        );
        assertEq(tokenId, 0);

        assertEq(fairReveal.tokenURI(5), "unrevealed://5");
    }

    function test_RevealFull() public {
        vm.prevrandao(bytes32(uint256(0)));
        fairReveal.reveal(0, 8);
        (uint256 tokenId, uint256 salt) = fairReveal.resolveTokenId(0);
        assertEq(tokenId, 5);
        uint256 saltedTokenId = uint256(
            keccak256(abi.encodePacked(tokenId, salt))
        );
        assertEq(
            fairReveal.tokenURI(1),
            LibString.concat("revealed://", saltedTokenId.toString())
        );
        (tokenId, salt) = fairReveal.resolveTokenId(7);
        assertEq(tokenId, 4);
        saltedTokenId = uint256(keccak256(abi.encodePacked(tokenId, salt)));
        assertEq(
            fairReveal.tokenURI(8),
            LibString.concat("revealed://", saltedTokenId.toString())
        );
    }

    function test_RevealLayers() public {
        vm.prevrandao(bytes32(uint256(0)));
        fairReveal.reveal(1, 2);
        vm.prevrandao(bytes32(uint256(0)));
        fairReveal.reveal(2, 2);
        vm.prevrandao(bytes32(uint256(5)));
        fairReveal.reveal(3, 2);
        vm.prevrandao(bytes32(uint256(0)));
        fairReveal.reveal(4, 2);
        // [startAtIndex: 1, length: 2]
        // [startAtIndex: 3, length: 2]
        // [startAtIndex: 0, length: 1]
        // [startAtIndex: 5, length: 1]
        // [startAtIndex: 6, length: 2]
        uint256 saltedTokenId;
        uint256 tokenId;
        uint256 salt;
        (tokenId, salt) = fairReveal.resolveTokenId(0);
        assertEq(tokenId, 1);
        saltedTokenId = uint256(keccak256(abi.encodePacked(tokenId, salt)));
        assertEq(
            fairReveal.tokenURI(1),
            LibString.concat("revealed://", saltedTokenId.toString())
        );

        (tokenId, salt) = fairReveal.resolveTokenId(1);
        assertEq(tokenId, 2);
        saltedTokenId = uint256(keccak256(abi.encodePacked(tokenId, salt)));
        assertEq(
            fairReveal.tokenURI(2),
            LibString.concat("revealed://", saltedTokenId.toString())
        );

        (tokenId, salt) = fairReveal.resolveTokenId(2);
        assertEq(tokenId, 3);
        saltedTokenId = uint256(keccak256(abi.encodePacked(tokenId, salt)));
        assertEq(
            fairReveal.tokenURI(3),
            LibString.concat("revealed://", saltedTokenId.toString())
        );

        (tokenId, salt) = fairReveal.resolveTokenId(3);
        assertEq(tokenId, 4);
        saltedTokenId = uint256(keccak256(abi.encodePacked(tokenId, salt)));
        assertEq(
            fairReveal.tokenURI(4),
            LibString.concat("revealed://", saltedTokenId.toString())
        );

        (tokenId, salt) = fairReveal.resolveTokenId(4);
        assertEq(tokenId, 0);
        saltedTokenId = uint256(keccak256(abi.encodePacked(tokenId, salt)));
        assertEq(
            fairReveal.tokenURI(5),
            LibString.concat("revealed://", saltedTokenId.toString())
        );

        (tokenId, salt) = fairReveal.resolveTokenId(5);
        assertEq(tokenId, 5);
        saltedTokenId = uint256(keccak256(abi.encodePacked(tokenId, salt)));
        assertEq(
            fairReveal.tokenURI(6),
            LibString.concat("revealed://", saltedTokenId.toString())
        );

        (tokenId, salt) = fairReveal.resolveTokenId(6);
        assertEq(tokenId, 6);
        saltedTokenId = uint256(keccak256(abi.encodePacked(tokenId, salt)));
        assertEq(
            fairReveal.tokenURI(7),
            LibString.concat("revealed://", saltedTokenId.toString())
        );

        (tokenId, salt) = fairReveal.resolveTokenId(7);
        assertEq(tokenId, 7);
        saltedTokenId = uint256(keccak256(abi.encodePacked(tokenId, salt)));
        assertEq(
            fairReveal.tokenURI(8),
            LibString.concat("revealed://", saltedTokenId.toString())
        );
    }
}
