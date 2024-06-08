// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {Fame} from "../src/Fame.sol";
import {FameLaunch} from "../src/FameLaunch.sol";
import {INonfungiblePositionManager} from "../src/v3-periphery/INonfungiblePositionManager.sol";
import {TickMath} from "../src/v3-core/TickMath.sol";
import "forge-std/console.sol";

interface IWETH {
    function deposit() external payable;
    function transfer(address to, uint value) external returns (bool);
    function withdraw(uint) external;
}

contract FameLaunchTest is Test {
    IWETH weth = IWETH(0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9);
    FameLaunch fameLaunch;
    Fame fame;

    function setUp() public {
        uint256 salt = 0x1;
        fame = new Fame{salt: bytes32(abi.encodePacked(salt))}(
            "Society",
            "FAME",
            address(this)
        );
        fameLaunch = new FameLaunch();
    }

    function test_Launch() public {
        fameLaunch.launch{value: 6 ether}(
            payable(address(fame)),
            address(weth),
            0xB7f907f7A9eBC822a80BD25E224be42Ce0A698A0,
            0x0227628f3F023bb0B980b67D528571c95c6DaC1c,
            0x1238536071E1c677A632429e3655c799b22cDA52
        );

        INonfungiblePositionManager v3nft = INonfungiblePositionManager(
            0x1238536071E1c677A632429e3655c799b22cDA52
        );
        assertEq(v3nft.balanceOf(address(this)), 2);
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
