// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {FameSale} from "../src/FameSale.sol";
import {FameSaleToken} from "../src/FameSaleToken.sol";

contract FameSaleTokenTest is Test {
    FameSaleToken public fameSaleToken;

    function setUp() public {
        fameSaleToken = new FameSaleToken(address(this));
        fameSaleToken.grantRoles(
            address(this),
            fameSaleToken.roleMinter() |
                fameSaleToken.roleController() |
                fameSaleToken.roleBurner()
        );
        fameSaleToken.mint(address(this), 888 ether);
    }

    function test_OnlyTransferableByController() public {
        uint256 totalSupply = fameSaleToken.totalSupply();
        uint256 balance = fameSaleToken.balanceOf(address(this));
        address alice = makeAddr("alice");
        fameSaleToken.transfer(alice, 888);
        assertEq(fameSaleToken.balanceOf(alice), 888);
        assertEq(fameSaleToken.totalSupply(), totalSupply);
        assertEq(fameSaleToken.balanceOf(address(this)), balance - 888);
        vm.expectRevert(0x82b42900);
        vm.prank(alice);
        fameSaleToken.transfer(msg.sender, 888);
        assertEq(fameSaleToken.balanceOf(alice), 888);
        assertEq(fameSaleToken.totalSupply(), totalSupply);
        assertEq(fameSaleToken.balanceOf(address(this)), balance - 888);
    }

    function test_TransferrableByController() public {
        uint256 totalSupply = fameSaleToken.totalSupply();
        uint256 balance = fameSaleToken.balanceOf(address(this));
        address alice = makeAddr("alice");
        fameSaleToken.transfer(alice, 888);
        assertEq(fameSaleToken.balanceOf(alice), 888);
        assertEq(fameSaleToken.totalSupply(), totalSupply);
        assertEq(fameSaleToken.balanceOf(address(this)), balance - 888);
    }

    function test_BurnOnlyByBurner() public {
        uint256 totalSupply = fameSaleToken.totalSupply();
        uint256 balance = fameSaleToken.balanceOf(address(this));
        fameSaleToken.burn(address(this), 888);
        assertEq(fameSaleToken.totalSupply(), totalSupply - 888);
        assertEq(fameSaleToken.balanceOf(address(this)), balance - 888);

        address alice = makeAddr("alice");
        fameSaleToken.transfer(alice, 888);
        vm.expectRevert(0x82b42900);
        vm.prank(alice);
        fameSaleToken.burn(alice, 888);
        assertEq(fameSaleToken.totalSupply(), totalSupply - 888);
        assertEq(fameSaleToken.balanceOf(address(this)), balance - 888 * 2);
    }
}
