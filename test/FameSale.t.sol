// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {FameSale} from "../src/FameSale.sol";
import {FameSaleToken} from "../src/FameSaleToken.sol";

/*
Proofs:
address(0x111)
[
  '0x9a55cc1ef3b65ea09d157343f357fea90e17def41707c2e055093172b9606974',
  '0xe7bff8cb316c97d44c067b104df8126513d3f51e003f26dd55f5bc6344c88195'
]
address(0x112)
[
  '0x6f89f15140d06c971ed5d798e73433d7bd63e582512b54604de4f680653f69a7'
]
address(0x113)
[
  '0xd40372c37de6c8255526c4418472bfafcf95a26fdba5a8e2a61097f286756715',
  '0xe7bff8cb316c97d44c067b104df8126513d3f51e003f26dd55f5bc6344c88195'
]
*/

contract FameSaleTest is Test {
    FameSale public fameSale;
    FameSaleToken public fameSaleToken;

    function setUp() public {
        fameSale = new FameSale();
        fameSaleToken = FameSaleToken(fameSale.fameSaleToken());

        fameSale.grantRoles(
            address(this),
            fameSale.roleTreasurer() |
                fameSale.roleExecutive() |
                fameSale.roleAllowlist()
        );
        fameSaleToken.grantRoles(
            address(fameSale),
            fameSaleToken.roleBurner() |
                fameSaleToken.roleController() |
                fameSaleToken.roleMinter()
        );

        fameSale.setMerkleRoot(
            0x3d6eaf3883135010a604694ace4ab85209a2cbbcde968a128c91e2650ec89568
        );
        fameSale.unpause();
        fameSale.setMaxRaise(10 ether);
        fameSale.setMaxBuy(1 ether);
    }

    function test_SameOwner() public view {
        assertEq(fameSale.owner(), address(this));
        assertEq(fameSaleToken.owner(), address(this));
    }

    function test_Buy() public {
        address buyer = address(0x111);
        // transfer 1 ether to buyer
        payable(buyer).transfer(1 ether);

        vm.prank(buyer);
        bytes32[] memory proof = new bytes32[](2);
        proof[
            0
        ] = 0x9a55cc1ef3b65ea09d157343f357fea90e17def41707c2e055093172b9606974;
        proof[
            1
        ] = 0xe7bff8cb316c97d44c067b104df8126513d3f51e003f26dd55f5bc6344c88195;
        fameSale.buy{value: 1 ether}(proof);

        assertEq(fameSale.fameTotalSupply(), 1 ether);
        assertEq(fameSaleToken.balanceOf(buyer), 1 ether);
        assertEq(fameSale.raiseRemaining(), 9 ether);
    }

    function test_MaxBuyRespect() public {
        address buyer = address(0x112);
        // transfer 1 ether to buyer
        payable(buyer).transfer(10 ether);

        vm.prank(buyer);
        vm.expectRevert(FameSale.MaxBuyExceeded.selector);
        bytes32[] memory proof = new bytes32[](1);
        proof[
            0
        ] = 0x6f89f15140d06c971ed5d798e73433d7bd63e582512b54604de4f680653f69a7;
        fameSale.buy{value: 10 ether}(proof);

        assertEq(fameSale.fameTotalSupply(), 0 ether);
        assertEq(fameSaleToken.balanceOf(buyer), 0 ether);
        assertEq(fameSale.raiseRemaining(), 10 ether);
    }

    function test_MaxRaiseRespect() public {
        fameSale.setMaxRaise(1 ether);
        address buyer = address(0x112);
        // transfer 1 ether to buyer
        payable(buyer).transfer(1 ether);

        vm.prank(buyer);
        bytes32[] memory proof = new bytes32[](1);
        proof[
            0
        ] = 0x6f89f15140d06c971ed5d798e73433d7bd63e582512b54604de4f680653f69a7;
        fameSale.buy{value: 1 ether}(proof);

        address buyer2 = address(0x113);
        // transfer 1 ether to buyer
        payable(buyer2).transfer(1 ether);

        vm.prank(buyer2);
        vm.expectRevert(FameSale.MaxRaisedExceeded.selector);
        bytes32[] memory proof2 = new bytes32[](2);
        proof2[
            0
        ] = 0xd40372c37de6c8255526c4418472bfafcf95a26fdba5a8e2a61097f286756715;
        proof2[
            1
        ] = 0xe7bff8cb316c97d44c067b104df8126513d3f51e003f26dd55f5bc6344c88195;

        fameSale.buy{value: 1 ether}(proof2);

        assertEq(fameSale.fameTotalSupply(), 1 ether);
        assertEq(fameSaleToken.balanceOf(buyer), 1 ether);
        assertEq(fameSale.raiseRemaining(), 0 ether);
    }

    function test_RefundSingle() public {
        address buyer = address(0x111);
        // transfer 1 ether to buyer
        payable(buyer).transfer(1 ether);

        vm.prank(buyer);
        bytes32[] memory proof = new bytes32[](2);
        proof[
            0
        ] = 0x9a55cc1ef3b65ea09d157343f357fea90e17def41707c2e055093172b9606974;
        proof[
            1
        ] = 0xe7bff8cb316c97d44c067b104df8126513d3f51e003f26dd55f5bc6344c88195;
        fameSale.buy{value: 1 ether}(proof);

        fameSale.refund(buyer, 1 ether);

        assertEq(fameSale.fameTotalSupply(), 0 ether);
        assertEq(fameSaleToken.balanceOf(buyer), 0 ether);
        assertEq(fameSale.raiseRemaining(), 10 ether);
    }

    function testRefundPartial() public {
        address buyer = address(0x111);
        // transfer 1 ether to buyer
        payable(buyer).transfer(1 ether);

        vm.prank(buyer);
        bytes32[] memory proof = new bytes32[](2);
        proof[
            0
        ] = 0x9a55cc1ef3b65ea09d157343f357fea90e17def41707c2e055093172b9606974;
        proof[
            1
        ] = 0xe7bff8cb316c97d44c067b104df8126513d3f51e003f26dd55f5bc6344c88195;
        fameSale.buy{value: 1 ether}(proof);

        fameSale.refund(buyer, 0.5 ether);

        assertEq(fameSale.fameTotalSupply(), 0.5 ether);
        assertEq(fameSaleToken.balanceOf(buyer), 0.5 ether);
        assertEq(fameSale.raiseRemaining(), 9.5 ether);
    }

    function test_RefundMultiple() public {
        address buyer = address(0x112);
        // transfer 1 ether to buyer
        payable(buyer).transfer(1 ether);

        vm.prank(buyer);
        bytes32[] memory proof = new bytes32[](1);
        proof[
            0
        ] = 0x6f89f15140d06c971ed5d798e73433d7bd63e582512b54604de4f680653f69a7;
        fameSale.buy{value: 1 ether}(proof);

        address buyer2 = address(0x113);
        // transfer 1 ether to buyer
        payable(buyer2).transfer(1 ether);

        vm.prank(buyer2);
        bytes32[] memory proof2 = new bytes32[](2);
        proof2[
            0
        ] = 0xd40372c37de6c8255526c4418472bfafcf95a26fdba5a8e2a61097f286756715;
        proof2[
            1
        ] = 0xe7bff8cb316c97d44c067b104df8126513d3f51e003f26dd55f5bc6344c88195;

        fameSale.buy{value: 1 ether}(proof2);

        assertEq(fameSale.fameTotalSupply(), 2 ether);
        assertEq(fameSaleToken.balanceOf(buyer2), 1 ether);
        assertEq(fameSale.raiseRemaining(), 8 ether);

        fameSale.refund(buyer, 1 ether);
        assertEq(fameSale.fameTotalSupply(), 1 ether);
        assertEq(fameSaleToken.balanceOf(buyer), 0 ether);
        assertEq(fameSaleToken.balanceOf(buyer2), 1 ether);
        assertEq(fameSale.raiseRemaining(), 9 ether);

        fameSale.refund(buyer2, 1 ether);
        assertEq(fameSale.fameTotalSupply(), 0 ether);
        assertEq(fameSaleToken.balanceOf(buyer), 0 ether);
        assertEq(fameSaleToken.balanceOf(buyer2), 0 ether);
        assertEq(fameSale.raiseRemaining(), 10 ether);
    }

    function test_Execute() public {
        address buyer = address(0x112);
        // transfer 1 ether to buyer
        payable(buyer).transfer(1 ether);

        // assertEq(buyer.balance, 1 ether);

        vm.prank(buyer);
        bytes32[] memory proof = new bytes32[](1);
        proof[
            0
        ] = 0x6f89f15140d06c971ed5d798e73433d7bd63e582512b54604de4f680653f69a7;
        fameSale.buy{value: 1 ether}(proof);
        uint256 currentBalance = address(this).balance;

        fameSale.withdraw();

        assertEq(address(this).balance, currentBalance + 1 ether);
    }

    function test_ExecuteRestricted() public {
        address buyer = address(0x112);
        // transfer 1 ether to buyer
        payable(buyer).transfer(1 ether);

        vm.prank(buyer);
        bytes32[] memory proof = new bytes32[](1);
        proof[
            0
        ] = 0x6f89f15140d06c971ed5d798e73433d7bd63e582512b54604de4f680653f69a7;
        fameSale.buy{value: 1 ether}(proof);

        fameSale.revokeRoles(
            address(this),
            fameSale.roleTreasurer() |
                fameSale.roleExecutive() |
                fameSale.roleAllowlist()
        );

        vm.expectRevert(0x82b42900);
        fameSale.withdraw();
    }

    function test_AllowListRestricted() public {
        fameSale.revokeRoles(
            address(this),
            fameSale.roleTreasurer() |
                fameSale.roleExecutive() |
                fameSale.roleAllowlist()
        );
        vm.expectRevert(0x82b42900);
        fameSale.setMerkleRoot(
            0x3d6eaf3883135010a604694ace4ab85209a2cbbcde968a128c91e2650ec89568
        );
    }

    function test_RefundRestricted() public {
        fameSale.revokeRoles(
            address(this),
            fameSale.roleTreasurer() |
                fameSale.roleExecutive() |
                fameSale.roleAllowlist()
        );
        vm.expectRevert(0x82b42900);
        fameSale.refund(address(0x111), 1 ether);
    }

    function test_Pause() public {
        fameSale.pause();
        assert(fameSale.isPaused());
    }

    receive() external payable {}
}
