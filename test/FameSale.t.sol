// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {FameSale} from "../src/FameSale.sol";
import {FameSaleToken} from "../src/FameSaleToken.sol";

contract FameSaleTest is Test {
    FameSale public fameSale;
    FameSaleToken public fameSaleToken;

    function setUp() public {
        fameSale = new FameSale();
        fameSaleToken = FameSaleToken(fameSale.fameSaleToken());
    }

    function test_SameOwner() public {
        assertEq(fameSale.owner(), address(this));
        assertEq(fameSaleToken.owner(), address(this));
    }

    // function test_NftSupply() public view {
    //     assertEq(fame.totalSupply(), 888000000000000000000000000);
    // }

    // function test_TransferTokenSupply() public {
    //     // assertEq(fame.balanceOf(address(this)), 999999999999999999999888);
    //     // new account
    //     address account = address(111);
    //     assertEq(fame.balanceOf(account), 0);

    //     DN404Mirror dn404 = DN404Mirror(payable(fame.mirrorERC721()));
    //     assertEq(dn404.balanceOf(account), 0);

    //     fame.transfer(account, 888000000000000000000000000);
    //     assertEq(fame.balanceOf(account), 888000000000000000000000000);
    //     assertEq(dn404.balanceOf(account), 888);
    //     assertEq(fame.balanceOf(address(this)), 0);
    //     assertEq(dn404.balanceOf(address(this)), 0);
    // }

    // // function testFuzz_SetNumber(uint256 x) public {
    // //     counter.setNumber(x);
    // //     assertEq(counter.number(), x);
    // // }
}
