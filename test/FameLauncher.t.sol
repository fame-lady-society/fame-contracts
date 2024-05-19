// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {FameMirror} from "../src/FameMirror.sol";
import {Fame} from "../src/Fame.sol";
import {FameLauncher} from "../src/FameLauncher.sol";
import {TickMath} from "../src/TickMath.sol";

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
            0xB7f907f7A9eBC822a80BD25E224be42Ce0A698A0, // v2 factory on sepolia
            0x0227628f3F023bb0B980b67D528571c95c6DaC1c, // v3 factory on sepolia
            0x1238536071E1c677A632429e3655c799b22cDA52 //  v3 nonfungiblePositionManager on sepolia
        );
    }

    function sqrtPriceX96(
        uint256 amountToken0,
        uint256 amountToken1
    ) internal pure returns (uint160) {
        // Calculate ratio
        uint256 ratio = (amountToken1 * 1e18) / amountToken0; // Multiplied by 1e18 to maintain precision

        // Calculate square root of the ratio
        uint256 sqrtRatio = sqrt(ratio);

        // Scale by 2^96
        uint256 s = (sqrtRatio * 2 ** 96) / 1e9; // Divided by 1e9 to adjust for the precision multiplier

        return uint160(s);
    }

    // Babylonian Method for square root
    function sqrt(uint y) internal pure returns (uint z) {
        if (y > 3) {
            z = y;
            uint x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    function test_LaunchV2Liquidity() public {
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

    function test_InitializeV3Liquidity() public {
        fame.transfer(address(fameLauncher), 100_000_000 ether);
        uint160 price = sqrtPriceX96(888_000_000 ether, 8 ether);
        fameLauncher.createV3Liquidity(price, 100_000_000 ether);
    }
}
