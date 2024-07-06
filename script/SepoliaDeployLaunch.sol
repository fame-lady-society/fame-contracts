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
import {FameLadySocietyBalanceOf} from "./holders/FameLadySocietyBalanceOf.sol";
import {FameLadySocietyOwners} from "./holders/FameLadySocietyOwners.sol";
import {HunnysOwners} from "./holders/HunnysOwners.sol";
import {MermaidPowerOwners} from "./holders/MermaidPowerOwners.sol";
import {MetavixenOwners} from "./holders/MetavixenOwners.sol";
import {OnChainCheckGasOwners} from "./holders/OnChainCheckGasOwners.sol";
import {OnChainGasOwners} from "./holders/OnChainGasOwners.sol";

interface IWETH {
    function deposit() external payable;
    function transfer(address to, uint value) external returns (bool);
    function withdraw(uint) external;
}

contract DeployLaunch is Script {
    address private weth = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;
    ISwapRouter02 private swapRouter =
        ISwapRouter02(0x3bFA4769FB09eefC5a80d6E87c3B9C650f7Ae48E);
    address private gasliteAddress = 0x09350F89e2D7B6e96bA730783c2d76137B045FEF;

    function run() external {
        // Setup the deployer wallet
        uint256 deployerPrivateKey = vm.envUint("SEPOLIA_DEPLOYER_PRIVATE_KEY");
        VmSafe.Wallet memory wallet = vm.createWallet(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // :tada: FAME :tada:
        Fame fame = new Fame(
            "Example",
            "TEST",
            address(0x4f42062bBf446D569d2A8088357187b4a9186ba6)
        );
        FameLaunch fl = new FameLaunch();
        fame.grantRoles(
            wallet.addr,
            (1 << 0) | (1 << 2) | (1 << 3) | (1 << 4) | (1 << 255)
        );
        fame.transfer(address(fl), 444_000_000 ether);
        fl.launch{value: 0.06 ether}(
            payable(address(fame)),
            weth, // WETH on sepolia
            0xB7f907f7A9eBC822a80BD25E224be42Ce0A698A0, // v2 factory on sepolia
            0x0227628f3F023bb0B980b67D528571c95c6DaC1c, // v3 factory on sepolia
            0x1238536071E1c677A632429e3655c799b22cDA52 //  v3 nonfungiblePositionManager on sepolia
        );

        uint256 signerPrivateKey = vm.envUint("SIGNER_PRIVATE_KEY");
        VmSafe.Wallet memory signerWallet = vm.createWallet(signerPrivateKey);
        ClaimToFame ctf = new ClaimToFame(address(fame), signerWallet.addr);
        ctf.grantRoles(wallet.addr, ctf.roleSigner() | ctf.roleClaimPrimer());

        vm.stopBroadcast();
    }
}
