// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import "forge-std/console.sol";
import {Bitmap} from "./utils/Bitmap.sol";
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

    struct RevealData {
        uint256 size;
        uint256 totalSize;
        uint16[] reveals;
        uint16[] availables;
        uint16 minTotalAvailableSize;
        uint16 maxTotalAvailableSize;
        uint16 revealEventCount;
        uint16 revealCount;
    }

    // function fixturePrevrandao()
    //     public
    //     pure
    //     returns (uint256[][] memory prevrandao)
    // {
    //     prevrandao = new uint256[][](8);
    //     for (uint256 i = 0; i < 8; i++) {
    //         prevrandao[i] = new uint256[](8);
    //         for (uint256 j = 0; j < 8; j++) {
    //             prevrandao[i][j] = uint256(keccak256(abi.encodePacked(i, j)));
    //         }
    //     }
    // }

    // function fixtureReveals() public pure returns (uint16[][] memory reveals) {
    //     reveals = new uint16[][](8);
    //     for (uint16 i = 0; i < 8; i++) {
    //         reveals[i] = new uint16[](8);
    //         for (uint16 j = 0; j < 8; j++) {
    //             reveals[i][j] = uint16(8) * (i + 1);
    //         }
    //     }
    // }

    // function fixtureAvailables()
    //     public
    //     pure
    //     returns (uint16[][] memory availables)
    // {
    //     availables = new uint16[][](8);
    //     for (uint16 i = 0; i < 8; i++) {
    //         availables[i] = new uint16[](8);
    //         for (uint16 j = 0; j < 8; j++) {
    //             availables[i][j] = uint16(64) * (j + 1);
    //         }
    //     }
    // }

    function test_Fuzz(bytes32 prevrandao, uint16 seed) public {
        uint16 available = (seed % 1024) + 128;
        uint16 iterations = (seed % 16) + 4;
        uint16 targetIterationSize = available / iterations;

        fairReveal = new FairReveal(
            address(0),
            "revealed://",
            "unrevealed://",
            available
        );

        Bitmap revealed = new Bitmap();
        for (uint256 i = 0; i < iterations; i++) {
            vm.prevrandao(
                bytes32(uint256(keccak256(abi.encodePacked(prevrandao, i))))
            );
            fairReveal.reveal(i, targetIterationSize, available);

            // Now walk through each newly revealed token and verify that we
            // have not revealed any token more than once.
            uint256 startIndex = i * targetIterationSize;
            for (
                uint256 j = startIndex;
                j < startIndex + targetIterationSize - 1;
                j++
            ) {
                (uint256 tokenId, uint256 salt) = fairReveal.resolveTokenId(j);
                bool wasRevealed = revealed.get(tokenId);
                if (!wasRevealed) {
                    revealed.set(tokenId);
                } else {
                    console.log("Iteration: ", i);
                    console.log("Index: ", j);
                    console.log("Seed: ", seed);
                    console.log("Available: ", available);
                    console.log("Iterations: ", iterations);
                    console.log("startIndex: ", startIndex);
                    console.log("TargetIterationSize: ", targetIterationSize);
                    console.log("Salt: ", salt);
                    console.log("TokenId: ", tokenId);
                    console.log("Revealed: ", revealed.get(tokenId));
                    assert(false);
                }
            }
        }
    }

    function test_Reveal1() public {
        fairReveal.reveal(0, 4, 8);
        vm.prevrandao(bytes32(uint256(0)));
        (uint256 tokenId, uint256 salt) = fairReveal.resolveTokenId(0);
        assertEq(tokenId, 4);
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
        assertEq(tokenId, 7);

        assertEq(fairReveal.tokenURI(5), "unrevealed://5");
    }

    function test_RevealCannotRemoveSize() public {
        fairReveal.reveal(0, 2, 8);
        vm.prevrandao(bytes32(uint256(0)));
        vm.expectRevert(FairReveal.SizeCannotDecrease.selector);
        fairReveal.reveal(0, 2, 6);
    }

    function test_RevealFull() public {
        vm.prevrandao(bytes32(uint256(0)));
        fairReveal.reveal(0, 8, 8);
        (uint256 tokenId, uint256 salt) = fairReveal.resolveTokenId(0);
        assertEq(tokenId, 4);
        uint256 saltedTokenId = uint256(
            keccak256(abi.encodePacked(tokenId, salt))
        );
        assertEq(
            fairReveal.tokenURI(1),
            LibString.concat("revealed://", saltedTokenId.toString())
        );
        (tokenId, salt) = fairReveal.resolveTokenId(7);
        assertEq(tokenId, 3);
        saltedTokenId = uint256(keccak256(abi.encodePacked(tokenId, salt)));
        assertEq(
            fairReveal.tokenURI(8),
            LibString.concat("revealed://", saltedTokenId.toString())
        );
    }

    function test_RevealLayers() public {
        vm.prevrandao(bytes32(uint256(0)));
        fairReveal.reveal(1, 2, 8);
        vm.prevrandao(bytes32(uint256(0)));
        fairReveal.reveal(2, 2, 8);
        vm.prevrandao(bytes32(uint256(5)));
        fairReveal.reveal(3, 2, 8);
        vm.prevrandao(bytes32(uint256(0)));
        fairReveal.reveal(4, 2, 8);

        uint256 saltedTokenId;
        uint256 tokenId;
        uint256 salt;
        (tokenId, salt) = fairReveal.resolveTokenId(0);
        assertEq(tokenId, 0);
        saltedTokenId = uint256(keccak256(abi.encodePacked(tokenId, salt)));
        assertEq(
            fairReveal.tokenURI(1),
            LibString.concat("revealed://", saltedTokenId.toString())
        );

        (tokenId, salt) = fairReveal.resolveTokenId(1);
        assertEq(tokenId, 1);
        saltedTokenId = uint256(keccak256(abi.encodePacked(tokenId, salt)));
        assertEq(
            fairReveal.tokenURI(2),
            LibString.concat("revealed://", saltedTokenId.toString())
        );

        (tokenId, salt) = fairReveal.resolveTokenId(2);
        assertEq(tokenId, 6);
        saltedTokenId = uint256(keccak256(abi.encodePacked(tokenId, salt)));
        assertEq(
            fairReveal.tokenURI(3),
            LibString.concat("revealed://", saltedTokenId.toString())
        );

        (tokenId, salt) = fairReveal.resolveTokenId(3);
        assertEq(tokenId, 7);
        saltedTokenId = uint256(keccak256(abi.encodePacked(tokenId, salt)));
        assertEq(
            fairReveal.tokenURI(4),
            LibString.concat("revealed://", saltedTokenId.toString())
        );

        (tokenId, salt) = fairReveal.resolveTokenId(4);
        assertEq(tokenId, 3);
        saltedTokenId = uint256(keccak256(abi.encodePacked(tokenId, salt)));
        assertEq(
            fairReveal.tokenURI(5),
            LibString.concat("revealed://", saltedTokenId.toString())
        );

        (tokenId, salt) = fairReveal.resolveTokenId(5);
        assertEq(tokenId, 4);
        saltedTokenId = uint256(keccak256(abi.encodePacked(tokenId, salt)));
        assertEq(
            fairReveal.tokenURI(6),
            LibString.concat("revealed://", saltedTokenId.toString())
        );

        (tokenId, salt) = fairReveal.resolveTokenId(6);
        assertEq(tokenId, 5);
        saltedTokenId = uint256(keccak256(abi.encodePacked(tokenId, salt)));
        assertEq(
            fairReveal.tokenURI(7),
            LibString.concat("revealed://", saltedTokenId.toString())
        );

        (tokenId, salt) = fairReveal.resolveTokenId(7);
        assertEq(tokenId, 2);
        saltedTokenId = uint256(keccak256(abi.encodePacked(tokenId, salt)));
        assertEq(
            fairReveal.tokenURI(8),
            LibString.concat("revealed://", saltedTokenId.toString())
        );
    }

    function test_RollingReveal() public {
        vm.prevrandao(bytes32(uint256(5)));
        fairReveal.reveal(0, 2, 4);
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

        assertEq(fairReveal.tokenURI(3), "unrevealed://3");

        fairReveal.reveal(0, 2, 4);
        (tokenId, salt) = fairReveal.resolveTokenId(2);
        assertEq(tokenId, 0);
        saltedTokenId = uint256(keccak256(abi.encodePacked(tokenId, salt)));
        assertEq(
            fairReveal.tokenURI(3),
            LibString.concat("revealed://", saltedTokenId.toString())
        );

        (tokenId, salt) = fairReveal.resolveTokenId(3);
        assertEq(tokenId, 3);
        saltedTokenId = uint256(keccak256(abi.encodePacked(tokenId, salt)));
        assertEq(
            fairReveal.tokenURI(4),
            LibString.concat("revealed://", saltedTokenId.toString())
        );

        vm.prevrandao(bytes32(uint256(3)));
        fairReveal.reveal(0, 1, 8);

        (tokenId, salt) = fairReveal.resolveTokenId(4);
        assertEq(tokenId, 6);
        saltedTokenId = uint256(keccak256(abi.encodePacked(tokenId, salt)));
        assertEq(
            fairReveal.tokenURI(5),
            LibString.concat("revealed://", saltedTokenId.toString())
        );

        vm.prevrandao(bytes32(uint256(4)));
        fairReveal.reveal(0, 3, 8);

        (tokenId, salt) = fairReveal.resolveTokenId(5);
        assertEq(tokenId, 4);
        saltedTokenId = uint256(keccak256(abi.encodePacked(tokenId, salt)));
        assertEq(
            fairReveal.tokenURI(6),
            LibString.concat("revealed://", saltedTokenId.toString())
        );
        (tokenId, salt) = fairReveal.resolveTokenId(6);
        assertEq(tokenId, 5);
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
