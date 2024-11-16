// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/StdCheats.sol";
import {ClaimToFame} from "../src/ClaimToFame.sol";
import {Fame} from "../src/Fame.sol";
import {MockBalanceOf} from "./mocks/MockBalanceOf.sol";
import {TokenVesting} from "@AbdelStark/token-vesting-contracts/TokenVesting.sol";
import {FameVesting} from "../src/FameVesting.sol";

contract FameVestingTest is Test {
    Fame public fame;
    FameVesting public fameVesting;
    MockBalanceOf public mockBalanceOf;

    function setUp() public {
        mockBalanceOf = new MockBalanceOf();
        fame = new Fame("Fame", "FAME", address(mockBalanceOf));
        fameVesting = new FameVesting(address(fame));
        fame.launchPublic();
        fame.transfer(address(fameVesting), 888_000_000 ether);
    }

    function test_EmptyOutVesting() public {
        address account1 = address(111);
        // July 26, 2024 0 utc
        uint256 start = vm.getBlockTimestamp();

        fameVesting.createVestingSchedule(
            account1,
            start,
            0,
            7776000,
            1,
            false,
            1 ether
        );
        bytes32 id = fameVesting.computeVestingScheduleIdForAddressAndIndex(
            account1,
            0
        );
        assertEq(fameVesting.computeReleasableAmount(id), 0);

        skip(7776000);

        assertEq(fameVesting.computeReleasableAmount(id), 1 ether);

        skip(7776000);

        assertEq(fameVesting.computeReleasableAmount(id), 1 ether);

        vm.prank(account1);
        fameVesting.release(id, 0.5 ether);
        assertEq(fame.balanceOf(account1), 0.5 ether);
        assertEq(fameVesting.computeReleasableAmount(id), 0.5 ether);

        skip(7776000);

        fameVesting.release(id, 0.5 ether);
        assertEq(fame.balanceOf(account1), 1 ether);
        assertEq(fameVesting.computeReleasableAmount(id), 0);
    }
}
