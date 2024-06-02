// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {FameMirror} from "../src/FameMirror.sol";
import {DN404} from "../src/DN404.sol";
import {DN404Mirror} from "../src/DN404Mirror.sol";
import {Fame} from "../src/Fame.sol";

contract FameTest is Test {
    Fame public fame;
    FameMirror public dn404;

    function setUp() public {
        fame = new Fame("Fame", "FAME", address(this));
        dn404 = FameMirror(payable(fame.mirrorERC721()));
    }

    function test_NftSupply() public view {
        assertEq(fame.totalSupply(), 888000000000000000000000000);
    }

    function test_TransferTokenSupply() public {
        // assertEq(fame.balanceOf(address(this)), 999999999999999999999888);
        // new account
        address account = address(111);
        assertEq(fame.balanceOf(account), 0);

        assertEq(dn404.balanceOf(account), 0);

        fame.transfer(account, 888 * 10 ** 24);
        assertEq(fame.balanceOf(account), 888 * 10 ** 24);
        assertEq(dn404.balanceOf(account), 888);
        assertEq(fame.balanceOf(address(this)), 0);
        assertEq(dn404.balanceOf(address(this)), 0);
    }

    function test_MintBurnMint() public {
        address account1 = address(111);
        fame.transfer(account1, 8e24);
        assertEq(dn404.balanceOf(account1), 8);

        address account2 = address(112);
        vm.prank(account1);
        vm.expectEmit(address(dn404));
        emit DN404Mirror.Transfer(account1, address(0), 8);
        vm.expectEmit(address(fame));
        emit DN404.Transfer(account1, account2, 9e23);
        fame.transfer(account2, 9e23);
        assertEq(dn404.balanceOf(account1), 7);
        assertEq(dn404.balanceOf(account2), 0);

        vm.expectEmit(address(dn404));
        emit DN404Mirror.Transfer(address(0), account2, 8);
        fame.transfer(account2, 1e23);
    }

    function test_MintBurnBurnMint() public {
        address account1 = address(111);
        fame.transfer(account1, 8e24);
        assertEq(dn404.balanceOf(account1), 8);

        address account2 = address(112);
        address account3 = address(113);
        vm.prank(account1);
        vm.expectEmit(address(dn404));
        emit DN404Mirror.Transfer(account1, address(0), 8);
        vm.expectEmit(address(fame));
        emit DN404.Transfer(account1, account2, 9e23);
        fame.transfer(account2, 9e23);

        vm.prank(account1);
        vm.expectEmit(address(dn404));
        emit DN404Mirror.Transfer(account1, address(0), 7);
        vm.expectEmit(address(fame));
        emit DN404.Transfer(account1, account3, 9e23);
        fame.transfer(account3, 9e23);

        assertEq(dn404.balanceOf(account1), 6);
        assertEq(dn404.balanceOf(account2), 0);
        assertEq(dn404.balanceOf(account3), 0);

        vm.expectEmit(address(dn404));
        emit DN404Mirror.Transfer(address(0), account2, 8);
        fame.transfer(account2, 1e23);

        vm.expectEmit(address(dn404));
        emit DN404Mirror.Transfer(address(0), account3, 7);
        fame.transfer(account3, 1e23);
    }
}
