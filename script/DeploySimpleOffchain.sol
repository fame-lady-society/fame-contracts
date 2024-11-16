// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {FairReveal} from "../src/FairReveal.sol";
import {FairPoolReveal} from "../src/FairPoolReveal.sol";
import {ArtPatcher} from "../src/ArtPatcher.sol";
import {FameSquadRemapper} from "../src/FameSquadRemapper.sol";
import {SimpleOffchainReveal} from "../src/SimpleOffchainReveal.sol";
import {Fame} from "../src/Fame.sol";

contract DeploySimpleOffchain is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address fameAddress = vm.envAddress("FAME_ADDRESS");
        vm.startBroadcast(deployerPrivateKey);

        Fame fame = Fame(payable(fameAddress));
        SimpleOffchainReveal renderer = new SimpleOffchainReveal(
            address(fame.renderer()),
            fameAddress
        );
        renderer.pushBatch(
            0,
            10,
            "https://gateway.irys.xyz/y9tZi-bOlxkhe0pMYyHblPACeL8c_uo-ZtUz05UxPzM/"
        );
        fame.setRenderer(address(renderer));

        vm.stopBroadcast();
    }
}
