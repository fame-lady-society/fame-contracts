// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {FameMirror} from "../src/FameMirror.sol";
import {Fame} from "../src/Fame.sol";

contract FameTest is Test {
    Fame public fame;

    function setUp() public {
        fame = new Fame("Fame", "FAME", address(this));
    }

    function test_NftSupply() public view {
        assertEq(fame.totalSupply(), 888000000000000000000000000);
    }

    function test_TransferTokenSupply() public {
        // assertEq(fame.balanceOf(address(this)), 999999999999999999999888);
        // new account
        address account = address(111);
        assertEq(fame.balanceOf(account), 0);

        FameMirror dn404 = FameMirror(payable(fame.mirrorERC721()));
        assertEq(dn404.balanceOf(account), 0);

        fame.transfer(account, 888000000000000000000000000);
        assertEq(fame.balanceOf(account), 888000000000000000000000000);
        assertEq(dn404.balanceOf(account), 888);
        assertEq(fame.balanceOf(address(this)), 0);
        assertEq(dn404.balanceOf(address(this)), 0);
    }

    // function testFuzz_SetNumber(uint256 x) public {
    //     counter.setNumber(x);
    //     assertEq(counter.number(), x);
    // }
}
