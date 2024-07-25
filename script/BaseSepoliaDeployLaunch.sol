// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";
import "forge-std/console.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IERC20} from "@openzeppelin5/contracts/token/ERC20/IERC20.sol";
import {ISwapRouter02} from "../src/swap-router-contracts/ISwapRouter02.sol";
import {TickMath} from "../src/v3-core/TickMath.sol";
import {Fame, IBalanceOf} from "../src/Fame.sol";
import {FameLaunch} from "../src/FameLaunch.sol";
import {ClaimToFame} from "../src/ClaimToFame.sol";
import {AirdropHelper, IAirdropSource} from "./utils/AirdropHelper.sol";

interface IWETH {
    function deposit() external payable;
    function transfer(address to, uint value) external returns (bool);
    function withdraw(uint) external;
}

contract DeployLaunch is Script {
    address private weth = 0x4200000000000000000000000000000000000006;

    function run() external {
        // Setup the deployer wallet
        uint256 deployerPrivateKey = vm.envUint(
            "BASE_SEPOLIA_DEPLOYER_PRIVATE_KEY"
        );
        VmSafe.Wallet memory wallet = vm.createWallet(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // :tada: FAME :tada:
        Fame fame = new Fame(
            "Example",
            "TEST",
            address(0x2d78B13a2E735Bc96ec797A37AaF4e17C4431C83)
        );
        // FameLaunch fl = new FameLaunch();
        fame.grantRoles(
            wallet.addr,
            (1 << 0) | (1 << 2) | (1 << 3) | (1 << 4) | (1 << 255)
        );
        // fame.transfer(address(fl), 444_000_000 ether);
        // fl.launch{value: 1 ether}(
        //     payable(address(fame)),
        //     weth, // WETH on sepolia
        //     address(0), // v2 factory on sepolia
        //     0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24, // v3 factory on base sepolia
        //     0xd7c6e867591608D32Fe476d0DbDc95d0cf584c8F //  v3 nonfungiblePositionManager on base sepolia
        // );
        fame.launchPublic();
        vm.stopBroadcast();
    }
}
