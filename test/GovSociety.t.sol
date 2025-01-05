// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {GovSociety} from "../src/GovSociety.sol";
import {Fame} from "../src/Fame.sol";
import {FameMirror} from "../src/FameMirror.sol";
import {StubBalanceOf} from "./mocks/StubBalanceOf.sol";
import {ITokenURIGenerator} from "../src/ITokenURIGenerator.sol";
import {EchoMetadata} from "./mocks/EchoMetadata.sol";

contract GovSocietyTest is Test {
    GovSociety public govSociety;
    FameMirror public fameMirror;
    Fame public fame;
    StubBalanceOf public stubBalanceOf;
    address public admin = makeAddr("admin");

    function setUp() public {
        stubBalanceOf = new StubBalanceOf();
        fame = new Fame("Fame", "FAME", address(stubBalanceOf));
        fameMirror = FameMirror(payable(fame.mirrorERC721()));
        govSociety = new GovSociety(
            address(fameMirror),
            admin,
            address(new EchoMetadata())
        );
    }

    function test_Wrap() public {
        address account = address(111);
        fame.transfer(account, 1 * 10 ** 24);
        vm.startPrank(account);
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;
        fameMirror.approve(address(govSociety), 1);
        govSociety.depositFor(address(account), tokenIds);
        assertEq(govSociety.balanceOf(address(account)), 1);
    }

    function test_LockToken() public {
        // Setup token ownership
        address owner = address(111);
        fame.transfer(owner, 1 * 10 ** 24);
        vm.startPrank(owner);
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;
        fameMirror.approve(address(govSociety), 1);
        govSociety.depositFor(owner, tokenIds);

        // Lock the token
        govSociety.lock(1);
        assertTrue(govSociety.isLocked(1));

        // Attempt to transfer should fail
        vm.expectRevert(
            abi.encodeWithSelector(GovSociety.TokenIsLocked.selector, 1)
        );
        govSociety.transferFrom(owner, address(222), 1);

        // Unlock the token
        govSociety.unlock(1);
        assertFalse(govSociety.isLocked(1));

        // Transfer should work
        govSociety.transferFrom(owner, address(222), 1);
        assertEq(govSociety.guardianForTokenId(1), address(0));
        assertEq(govSociety.ownerOf(1), address(222));
    }

    function test_LockMany() public {
        address owner = address(111);
        fame.transfer(owner, 2 * 10 ** 24);
        vm.startPrank(owner);
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 1;
        tokenIds[1] = 2;
        fameMirror.setApprovalForAll(address(govSociety), true);
        govSociety.depositFor(owner, tokenIds);
        govSociety.lockMany(tokenIds);
        assertTrue(govSociety.isLocked(1));
        assertTrue(govSociety.isLocked(2));
    }

    function test_LockWithGuardian() public {
        // Setup token ownership
        address owner = address(111);
        address guardian = address(222);
        fame.transfer(owner, 1 * 10 ** 24);
        vm.startPrank(owner);
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;
        fameMirror.approve(address(govSociety), 1);
        govSociety.depositFor(owner, tokenIds);

        // Lock with guardian
        govSociety.lockWithGuardian(1, guardian);
        assertTrue(govSociety.isLocked(1));
        assertEq(govSociety.guardianForTokenId(1), guardian);
        vm.stopPrank();

        // Owner cannot unlock
        vm.startPrank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(GovSociety.OnlyGuardianOrOwner.selector, 1)
        );
        govSociety.unlock(1);
        vm.stopPrank();

        // Transfer should fail
        vm.expectRevert(
            abi.encodeWithSelector(GovSociety.TokenIsLocked.selector, 1)
        );
        govSociety.transferFrom(owner, address(222), 1);

        // Guardian can unlock
        vm.startPrank(guardian);
        govSociety.unlock(1);
        assertFalse(govSociety.isLocked(1));
        vm.stopPrank();

        // Transfer should work
        vm.startPrank(owner);
        govSociety.transferFrom(owner, address(333), 1);
        assertEq(govSociety.guardianForTokenId(1), address(0));
        assertEq(govSociety.ownerOf(1), address(333));
        vm.stopPrank();
    }

    function test_GuardianResetOnTransfer() public {
        // Setup token ownership
        address owner = address(111);
        address guardian = address(222);
        address newOwner = address(333);
        fame.transfer(owner, 1 * 10 ** 24);
        vm.startPrank(owner);
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;
        fameMirror.approve(address(govSociety), 1);
        govSociety.depositFor(owner, tokenIds);

        // Lock with guardian and then unlock
        govSociety.lockWithGuardian(1, guardian);
        vm.stopPrank();

        vm.prank(guardian);
        govSociety.unlock(1);

        // Transfer should reset guardian
        vm.prank(owner);
        govSociety.transferFrom(owner, newOwner, 1);
        assertEq(govSociety.guardianForTokenId(1), address(0));
    }
}
