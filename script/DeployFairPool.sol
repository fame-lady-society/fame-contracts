// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {FairReveal} from "../src/FairReveal.sol";
import {FairPoolReveal} from "../src/FairPoolReveal.sol";
import {Fame} from "../src/Fame.sol";

contract DeployFairPool is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address fameAddress = vm.envAddress("FAME_ADDRESS");
        vm.startBroadcast(deployerPrivateKey);

        FairPoolReveal fairPoolReveal = new FairPoolReveal(
            address(fameAddress),
            address(fameAddress),
            1,
            888
        );

        Fame fame = Fame(payable(fameAddress));
        fame.setRenderer(address(fairPoolReveal));

        vm.stopBroadcast();
    }
}
