// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/SimpleOffchainReveal.sol";
import "../src/ITokenURIGenerator.sol";

contract MockChildRenderer is ITokenURIGenerator {
    function tokenURI(
        uint256 tokenId
    ) external pure override returns (string memory) {
        return string(abi.encodePacked("child_", LibString.toString(tokenId)));
    }
}

contract MockTokenEmitable is ITokenEmitable {
    bool public shouldRevert;
    event MetadataUpdate(uint256 tokenId);
    event BatchMetadataUpdate(uint256 start, uint256 end);

    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    function emitMetadataUpdate(uint256 tokenId) external {
        if (shouldRevert) revert("Forced revert");
        emit MetadataUpdate(tokenId);
    }

    function emitBatchMetadataUpdate(uint256 start, uint256 end) external {
        if (shouldRevert) revert("Forced revert");
        emit BatchMetadataUpdate(start, end);
    }
}

contract SimpleOffchainRevealTest is Test {
    using LibString for uint256;
    using LibString for string;
    SimpleOffchainReveal public offchainReveal;
    MockChildRenderer public mockChildRenderer;
    MockTokenEmitable public mockTokenEmitable;

    function setUp() public {
        mockChildRenderer = new MockChildRenderer();
        mockTokenEmitable = new MockTokenEmitable();
        offchainReveal = new SimpleOffchainReveal(
            address(mockChildRenderer),
            address(mockTokenEmitable),
            498
        );
    }

    function testTokenURIBeforeStartAtToken() public {
        assertEq(offchainReveal.tokenURI(497), "child_497");
    }

    function testTokenURIAfterStartAtTokenWithoutBatch() public {
        assertEq(offchainReveal.tokenURI(498), "child_498");
    }

    function testPushBatch() public {
        offchainReveal.pushBatch(0, 100, "https://example.com/");
        (
            ,
            uint256 startAtToken,
            uint256 length,
            string memory baseUri
        ) = offchainReveal.batches(0);
        assertEq(startAtToken, 498);
        assertEq(length, 100);
        assertEq(baseUri, "https://example.com/");
    }

    function testTokenURIWithBatch() public {
        offchainReveal.pushBatch(0, 100, "https://example.com/");
        assertEq(
            offchainReveal.tokenURI(550),
            LibString.concat(
                "https://example.com/",
                saltedTokenId(0, 550).toString().concat(".json")
            )
        );
    }

    function testTokenURIOutsideBatch() public {
        offchainReveal.pushBatch(0, 100, "https://example.com/");
        assertEq(offchainReveal.tokenURI(600), "child_600");
    }

    function testMaxTokenIdWithoutBatches() public {
        assertEq(offchainReveal.maxTokenId(), 497);
    }

    function testMaxTokenIdWithBatches() public {
        offchainReveal.pushBatch(0, 100, "https://example.com/");
        offchainReveal.pushBatch(0, 50, "https://another.com/");
        assertEq(offchainReveal.maxTokenId(), 647);
    }

    function testPushBatchOnlyOwner() public {
        vm.prank(address(1));
        vm.expectRevert();
        offchainReveal.pushBatch(0, 100, "https://example.com/");
    }

    function saltedTokenId(
        uint256 salt,
        uint256 tokenId
    ) internal returns (uint256 _saltedTokenId) {
        uint256 offset = offchainReveal.offsetForTokenId(tokenId);
        _saltedTokenId = uint256(
            keccak256(abi.encodePacked(uint256(tokenId - offset), salt))
        );
    }

    function testMultipleBatches() public {
        uint256 salt = 0;
        offchainReveal.pushBatch(salt, 100, "https://example1.com/");
        offchainReveal.pushBatch(salt, 50, "https://example2.com/");

        assertEq(
            offchainReveal.tokenURI(550),
            LibString
                .concat(
                    "https://example1.com/",
                    saltedTokenId(salt, 550).toString()
                )
                .concat(".json")
        );
        assertEq(
            offchainReveal.tokenURI(625),
            LibString
                .concat(
                    "https://example2.com/",
                    saltedTokenId(salt, 625).toString()
                )
                .concat(".json")
        );
        assertEq(
            offchainReveal.tokenURI(600),
            LibString
                .concat(
                    "https://example2.com/",
                    saltedTokenId(salt, 600).toString()
                )
                .concat(".json")
        );
        assertEq(offchainReveal.tokenURI(650), "child_650");
    }

    function testConsecutiveBatchPushing() public {
        offchainReveal.pushBatch(0, 100, "https://example1.com/");
        (, uint256 startAtToken1, , ) = offchainReveal.batches(0);
        assertEq(startAtToken1, 498);

        offchainReveal.pushBatch(0, 50, "https://example2.com/");
        (, uint256 startAtToken2, , ) = offchainReveal.batches(1);
        assertEq(startAtToken2, 598);

        offchainReveal.pushBatch(0, 75, "https://example3.com/");
        (, uint256 startAtToken3, , ) = offchainReveal.batches(2);
        assertEq(startAtToken3, 648);
    }
}
