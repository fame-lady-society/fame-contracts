// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC721} from "@openzeppelin5/contracts/token/ERC721/IERC721.sol";
import {SocietyNftAuction} from "../src/SocietyNftAuction.sol";

contract SocietyNftAuctionBaseForkTest is Test {
    address internal constant MIRROR = 0xBB5ED04dD7B207592429eb8d599d103CCad646c4;
    IERC721 internal constant SOCIETY = IERC721(MIRROR);

    function setUp() public {
        string memory rpc = vm.envOr("BASE_RPC", string(""));
        if (bytes(rpc).length == 0) vm.skip(true);
        vm.createSelectFork(rpc);
    }

    function testFixedMirrorExposesRequiredNftSurface() public view {
        assertGt(MIRROR.code.length, 0);
        assertTrue(SOCIETY.supportsInterface(0x80ac58cd));

        (uint256 tokenId, address tokenOwner) = _findExistingToken();
        assertEq(SOCIETY.ownerOf(tokenId), tokenOwner);
        SOCIETY.getApproved(tokenId);
        SOCIETY.isApprovedForAll(tokenOwner, address(this));
    }

    function testAuctionEmbedsFixedMirror() public {
        SocietyNftAuction auction = new SocietyNftAuction(address(this));
        assertEq(auction.SOCIETY_NFT(), MIRROR);
    }

    function testLiveMirrorSupportsProductionAuctionLifecycle() public {
        (uint256 tokenId, address tokenOwner) = _findExistingToken();
        SocietyNftAuction auction = new SocietyNftAuction(tokenOwner);

        vm.prank(tokenOwner);
        SOCIETY.approve(address(auction), tokenId);

        uint256 expectedStart = block.timestamp;
        vm.prank(tokenOwner);
        auction.start(tokenId);

        assertEq(uint8(auction.lifecycle()), uint8(SocietyNftAuction.Lifecycle.Active));
        assertEq(auction.startTime(), expectedStart);
        assertEq(auction.endTime(), expectedStart + 3 days);
        assertEq(SOCIETY.ownerOf(tokenId), address(auction));

        vm.warp(auction.endTime());
        auction.settle();

        assertEq(uint8(auction.lifecycle()), uint8(SocietyNftAuction.Lifecycle.Settled));
        assertEq(SOCIETY.ownerOf(tokenId), tokenOwner);
    }

    function _findExistingToken() internal view returns (uint256 tokenId, address tokenOwner) {
        uint256 configuredTokenId = vm.envOr("BASE_SOCIETY_NFT_AUCTION_TOKEN_ID", uint256(0));
        if (configuredTokenId != 0) return (configuredTokenId, SOCIETY.ownerOf(configuredTokenId));

        for (uint256 candidate = 1; candidate <= 100; ++candidate) {
            try SOCIETY.ownerOf(candidate) returns (address foundOwner) {
                if (foundOwner != address(0)) return (candidate, foundOwner);
            } catch {}
        }
        revert("no Society NFT found in token range 1-100");
    }
}
