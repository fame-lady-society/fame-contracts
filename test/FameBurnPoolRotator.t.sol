// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {FameBurnPoolRotator} from "../src/FameBurnPoolRotator.sol";
import {Fame} from "../src/Fame.sol";
import {FameMirror} from "../src/FameMirror.sol";
import {StubBalanceOf} from "./mocks/StubBalanceOf.sol";

contract FameBurnPoolRotatorTest is Test {
    Fame internal fame;
    FameMirror internal mirror;
    FameBurnPoolRotator internal rotator;

    address internal user = makeAddr("user");
    address internal recipient = makeAddr("recipient");
    address internal sink = makeAddr("skip-sink");
    uint256 internal unit;

    function setUp() public {
        fame = new Fame("Fame", "FAME", address(new StubBalanceOf()));
        mirror = fame.fameMirror();
        rotator = new FameBurnPoolRotator(fame);
        unit = fame.unit();

        vm.prank(sink);
        fame.setSkipNFT(true);
    }

    function test_RotatesToRequestedTokenAndRecipient() public {
        _giveUserNFTs(3);
        _burnFromUser(3);
        _approve(2);

        uint256 combinedBalanceBefore = fame.balanceOf(user) + fame.balanceOf(recipient);

        vm.prank(user);
        rotator.rotateTo(2, 3, 1, recipient);

        assertEq(mirror.ownerOf(3), recipient);
        assertEq(mirror.ownerAt(2), address(0));
        assertEq(fame.balanceOf(user) + fame.balanceOf(recipient), combinedBalanceBefore);
        assertEq(fame.balanceOf(address(rotator)), 0);
        assertEq(mirror.balanceOf(address(rotator)), 0);
    }

    function test_RotatesThroughMultiplePoolEntries() public {
        _giveUserNFTs(5);
        _burnFromUser(5);
        _burnFromUser(4);
        _burnFromUser(3);
        _approve(2);

        uint256 userBalanceBefore = fame.balanceOf(user);

        vm.prank(user);
        rotator.rotateTo(2, 3, 3, user);

        assertEq(mirror.ownerOf(3), user);
        assertEq(mirror.ownerAt(5), address(0));
        assertEq(mirror.ownerAt(4), address(0));
        assertEq(mirror.ownerAt(2), address(0));
        assertEq(fame.balanceOf(user), userBalanceBefore);
        assertEq(fame.balanceOf(address(rotator)), 0);
    }

    function test_RevertsAtomicallyWhenRotationLimitIsTooLow() public {
        _giveUserNFTs(5);
        _burnFromUser(5);
        _burnFromUser(4);
        _burnFromUser(3);
        _approve(2);

        uint256 userBalanceBefore = fame.balanceOf(user);
        uint256 userNftsBefore = mirror.balanceOf(user);

        vm.expectRevert(FameBurnPoolRotator.TargetNotReached.selector);
        vm.prank(user);
        rotator.rotateTo(2, 3, 2, user);

        assertEq(mirror.ownerOf(2), user);
        assertEq(mirror.ownerAt(3), address(0));
        assertEq(mirror.ownerAt(4), address(0));
        assertEq(mirror.ownerAt(5), address(0));
        assertEq(fame.balanceOf(user), userBalanceBefore);
        assertEq(mirror.balanceOf(user), userNftsBefore);
        assertEq(fame.balanceOf(address(rotator)), 0);
    }

    function test_RevertsWithoutOfferedTokenApproval() public {
        _giveUserNFTs(3);
        _burnFromUser(3);

        vm.expectRevert();
        vm.prank(user);
        rotator.rotateTo(2, 3, 1, user);

        assertEq(mirror.ownerOf(2), user);
        assertEq(mirror.ownerAt(3), address(0));
    }

    function _giveUserNFTs(uint256 count) internal {
        fame.transfer(user, count * unit);
    }

    function _burnFromUser(uint256 expectedTokenId) internal {
        vm.prank(user);
        fame.transfer(sink, unit);
        assertEq(mirror.ownerAt(expectedTokenId), address(0));
    }

    function _approve(uint256 tokenId) internal {
        vm.prank(user);
        mirror.approve(address(rotator), tokenId);
    }
}
