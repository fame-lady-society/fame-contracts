// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {FameMirror} from "../src/FameMirror.sol";
import {Fame} from "../src/Fame.sol";
import {FameLauncher} from "../src/FameLauncher.sol";

interface IWETH {
    function deposit() external payable;
    function transfer(address to, uint value) external returns (bool);
    function withdraw(uint) external;
}

contract FameTest is Test {
    Fame public fame;
    FameLauncher public fameLauncher;

    function setUp() public {
        fame = new Fame("Fame", "FAME", address(this));
        fameLauncher = new FameLauncher(
            address(fame),
            0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9, // WETH on sepolia
            0xB7f907f7A9eBC822a80BD25E224be42Ce0A698A0 // v2 factory on sepolia
        );
    }

    function test_LaunchLiquidity() public {
        // transfer 177_600_000 ether of fame to the launcher
        fame.transfer(address(fameLauncher), 177_600_000 ether);

        // assert that the fame contract has 177_600_000 $FAME
        assertEq(fame.balanceOf(address(fameLauncher)), 177_600_000 ether);

        // Wrap 8 ETH to WETH
        IWETH weth = IWETH(0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9);
        weth.deposit{value: 8 ether}();
        weth.transfer(address(fameLauncher), 8 ether);

        // create liquidity
        uint liquidity = fameLauncher.createV2Liquidity();
        assertEq(liquidity, 37693500766047188681023);
    }
}
