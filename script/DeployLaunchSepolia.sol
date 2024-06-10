// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IERC20} from "@openzeppelin5/contracts/token/ERC20/IERC20.sol";
import {ISwapRouter02} from "../src/swap-router-contracts/ISwapRouter02.sol";
import {TickMath} from "../src/v3-core/TickMath.sol";
import {Fame} from "../src/Fame.sol";
import {FameLaunch} from "../src/FameLaunch.sol";
import {ClaimToFame} from "../src/ClaimToFame.sol";

interface IWETH {
    function deposit() external payable;
    function transfer(address to, uint value) external returns (bool);
    function withdraw(uint) external;
}

contract DeployLaunch is Script {
    address private weth = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;
    ISwapRouter02 private swapRouter =
        ISwapRouter02(0x3bFA4769FB09eefC5a80d6E87c3B9C650f7Ae48E);

    Fame private fame;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("SEPOLIA_DEPLOYER_PRIVATE_KEY");
        VmSafe.Wallet memory wallet = vm.createWallet(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        fame = new Fame("Example", "TEST", wallet.addr);
        FameLaunch fl = new FameLaunch();
        fame.transfer(address(fl), 444_000_000 ether);
        fl.launch{value: 0.06 ether}(
            payable(address(fame)),
            weth, // WETH on sepolia
            0xB7f907f7A9eBC822a80BD25E224be42Ce0A698A0, // v2 factory on sepolia
            0x0227628f3F023bb0B980b67D528571c95c6DaC1c, // v3 factory on sepolia
            0x1238536071E1c677A632429e3655c799b22cDA52 //  v3 nonfungiblePositionManager on sepolia
        );

        fame.grantRoles(
            wallet.addr,
            fame.roleMetadata() |
                fame.roleBurnPoolManager() |
                fame.roleRenderer() |
                (1 << 255)
        );

        uint256 signerPrivateKey = vm.envUint("SEPOLIA_SIGNER_PRIVATE_KEY");
        VmSafe.Wallet memory signerWallet = vm.createWallet(signerPrivateKey);
        ClaimToFame ctf = new ClaimToFame(address(fame), signerWallet.addr);
        ctf.grantRoles(wallet.addr, ctf.roleSigner() | ctf.roleClaimPrimer());
        fame.transfer(address(ctf), 222_000_000 ether);

        vm.stopBroadcast();
        // swapFor(vm.envUint("SEPOLIA_SNIPE1_PRIVATE_KEY"), 0.001 ether);
        // swapFor(vm.envUint("SEPOLIA_SNIPE2_PRIVATE_KEY"), 0.001 ether);
        // swapFor(vm.envUint("SEPOLIA_SNIPE3_PRIVATE_KEY"), 0.001 ether);
    }

    function swapFor(uint256 privateKey, uint256 amount) public {
        VmSafe.Wallet memory wallet = vm.createWallet(privateKey);
        vm.startBroadcast(wallet.privateKey);
        IWETH(weth).deposit{value: amount}();
        IERC20(weth).approve(address(swapRouter), amount);
        ISwapRouter02.ExactInputSingleParams memory params = ISwapRouter02
            .ExactInputSingleParams({
                tokenIn: weth,
                tokenOut: address(fame),
                fee: 3000,
                recipient: wallet.addr,
                amountIn: amount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });
        swapRouter.exactInputSingle(params);
        vm.stopBroadcast();
    }
}
