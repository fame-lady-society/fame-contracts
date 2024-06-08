// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {Fame} from "../src/Fame.sol";
import {FameLaunch} from "../src/FameLaunch.sol";

interface IWETH {
    function deposit() external payable;
    function transfer(address to, uint value) external returns (bool);
    function withdraw(uint) external;
}

contract DeployLaunch is Script {
    address private weth = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("SEPOLIA_DEPLOYER_PRIVATE_KEY");
        VmSafe.Wallet memory wallet = vm.createWallet(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        Fame fame = new Fame("Example", "TEST", wallet.addr);
        FameLaunch fl = new FameLaunch();
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

        vm.stopBroadcast();
    }

    function swapFor(
        uint256 privateKey,
        address recipient,
        bool zeroForOne,
        int256 amount
    ) public returns (int256 amount0, int256 amount1, uint160 afterPrice) {
        IUniswapV3Pool pool = fameLauncher.v3Pool();
        bytes memory emptyBytes;

        if (!zeroForOne) {
            weth.deposit{value: uint256(amount)}();
            IERC20(address(weth)).transfer(recipient, uint256(amount));
            // approve as recipient
            vm.startBroadcast(deployerPrivateKey);
            IERC20(address(weth)).approve(address(this), uint256(amount));
        }

        (amount0, amount1) = pool.swap(
            recipient,
            zeroForOne,
            amount,
            zeroForOne
                ? TickMath.MIN_SQRT_RATIO + 1
                : TickMath.MAX_SQRT_RATIO - 1,
            emptyBytes
        );

        (afterPrice, , , , , , ) = pool.slot0();
    }
}
