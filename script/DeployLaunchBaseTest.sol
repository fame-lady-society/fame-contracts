// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {Fame, IBalanceOf} from "../src/Fame.sol";
import {FameLaunch} from "../src/FameLaunch.sol";
import {FameLadySocietyOwners} from "./holders/FameLadySocietyOwners.sol";

contract DeployLaunch is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        VmSafe.Wallet memory wallet = vm.createWallet(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        FameLadySocietyOwners societyOwners = new FameLadySocietyOwners();
        Fame fame = new Fame("Example", "TEST", address(societyOwners));
        FameLaunch fl = new FameLaunch();
        fame.transfer(address(fl), 444_000_000 ether);
        fl.launch{value: 0.001 ether}(
            payable(address(fame)),
            0x4200000000000000000000000000000000000006, // WETH on base
            0x8909Dc15e40173Ff4699343b6eB8132c65e18eC6, // v2 factory on base
            0x33128a8fC17869897dcE68Ed026d694621f6FDfD, // v3 factory on base
            0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1 //  v3 nonfungiblePositionManager on base
        );

        fame.grantRoles(
            wallet.addr,
            (1 << 0) | (1 << 2) | (1 << 3) | (1 << 4) | (1 << 255)
        );

        // Don't renounce ownership riught away, need to setup opensea
        // fame.renounceOwnership();

        vm.stopBroadcast();
    }
}
