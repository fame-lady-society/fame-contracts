// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import "forge-std/console.sol";
import {ClaimToFame} from "../src/ClaimToFame.sol";
import {Fame} from "../src/Fame.sol";
import {MockBalanceOf} from "./mocks/MockBalanceOf.sol";

contract ClaimToFameTest is Test {
    Fame public fame;
    ClaimToFame public claimToFame;
    MockBalanceOf public mockBalanceOf;

    function setUp() public {
        mockBalanceOf = new MockBalanceOf();
        fame = new Fame("Fame", "FAME", address(mockBalanceOf));
        claimToFame = new ClaimToFame(address(fame), address(this));
    }

    function test_Bitmap1() public view {
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 1;
        assertEq(
            claimToFame.generateTokenIds(
                claimToFame.generatePackedData(tokenIds)
            ),
            tokenIds
        );
    }

    function test_Bitmap101() public view {
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 0;
        tokenIds[1] = 2;
        assertEq(
            claimToFame.generateTokenIds(
                claimToFame.generatePackedData(tokenIds)
            ),
            tokenIds
        );
    }

    function test_BitmapWide() public view {
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 0;
        tokenIds[1] = 8887;

        // Create a new bitmap with the maximum token id.
        bytes memory packedData = claimToFame.generatePackedData(tokenIds);

        assertEq(claimToFame.generateTokenIds(packedData), tokenIds);
    }
}
