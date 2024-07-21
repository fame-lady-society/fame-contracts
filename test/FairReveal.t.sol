// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import "forge-std/console.sol";
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
    function generateRevealCheckpoint()
        internal
        returns (uint16[] memory reveals, uint16[] memory availables)
    {
        RevealData memory data = RevealData({
            size: 8 +
                (uint256(keccak256(abi.encodePacked(block.timestamp))) % 24),
            totalSize: 0, // Initialize to 0, will be set properly below
            reveals: new uint16[](0), // Temporary initialization
            availables: new uint16[](0), // Temporary initialization
            minTotalAvailableSize: 1,
            maxTotalAvailableSize: 0, // Will be set properly below
            revealEventCount: 0,
            revealCount: 0
        });

        // Create a random integer i between 8 and 32.
        data.totalSize =
            data.size *
            (8 + (uint256(keccak256(abi.encodePacked(block.timestamp))) % 24));
        data.reveals = new uint16[](data.size);
        data.availables = new uint16[](data.size);
        data.maxTotalAvailableSize = uint16(data.totalSize);

        while (data.revealCount < data.size) {
            uint16 revealSize = 1 +
                (uint16(
                    keccak256(
                        abi.encodePacked(
                            block.timestamp,
                            data.revealCount,
                            data.totalSize
                        )
                    )
                ) % (data.maxTotalAvailableSize - data.availables));
            uint16 availableSize = 1 +
                (uint16(
                    keccak256(
                        abi.encodePacked(
                            block.timestamp,
                            data.revealCount,
                            data.totalSize
                        )
                    )
                ) % (data.maxTotalAvailableSize - data.minTotalAvailableSize));
            data.reveals[data.revealCount] = revealSize;
            data.availables[data.revealCount] = availableSize;
            data.revealCount++;
            data.minTotalAvailableSize += revealSize;
        }
    }

    function fixtureRevealCheckpoints()
        public
        returns (uint16[] memory reveals, uint16[] memory availables)
    {
        // Create a random integer i between 8 and 32. Multiple that integer by a random integer between 8 and 32.
        // This will give us a random integer between 64 and 1024 and is the size of the collection to reveal.
        // For the size of the collection take a random chunk between 1 and the size of the collection and save
        // as revealCount and then take a second randomn chunk between 1 and the size of the collection to use as
        // totalAvailableAmount. Continue generating reveal chunks until total
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
