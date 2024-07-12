// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";
import "forge-std/console.sol";
import {Fame} from "../src/Fame.sol";
import {ClaimToFame} from "../src/ClaimToFame.sol";

contract DeployLaunch is Script {
    address private gasliteAddress = 0x09350F89e2D7B6e96bA730783c2d76137B045FEF;

    Fame private fame;

    function run() external {
        // Setup the deployer wallet
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        VmSafe.Wallet memory wallet = vm.createWallet(deployerPrivateKey);
        address fameAddress = vm.envAddress("FAME_ADDRESS");
        fame = Fame(payable(fameAddress));

        vm.startBroadcast(deployerPrivateKey);

        fame.launchPublic();

        vm.stopBroadcast();
    }
}
