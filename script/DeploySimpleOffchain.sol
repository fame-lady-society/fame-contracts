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
            0xE5B20c26716bA7c42b398423c2F95e5F9D9aC093,
            0xf307e242BfE1EC1fF01a4Cef2fdaa81b10A52418,
            498
        );

        renderer.pushBatch(
            0,
            10,
            "https://gateway.irys.xyz/y9tZi-bOlxkhe0pMYyHblPACeL8c_uo-ZtUz05UxPzM/"
        );
        renderer.pushBatch(
            0,
            10,
            "https://gateway.irys.xyz/wIvHv-ihupt-HaMIUNYzIOcXLcEEsnxu3kcpyYmqQyo/"
        );
        renderer.pushBatch(
            0,
            10,
            "https://gateway.irys.xyz/HKUDEYYwt_73k8bb_UWDpxCe9uV3CGaICu8nor07430/"
        );
        renderer.pushBatch(
            1337000,
            12,
            "https://gateway.irys.xyz/FD1-OUXP9tuePs8mlTYk25hA8TgnuaZ67RfL3P7Qi08/"
        );
        renderer.pushBatch(
            33,
            24,
            "https://gateway.irys.xyz/0Qane4Rfo_gdoZmhfb0oU_NocOi2EG5P649OV0Sc0tc/"
        );
        renderer.pushBatch(
            24,
            16,
            "https://gateway.irys.xyz/nm6F0WrjGr4oKMwD4D8KnGx4pgdj3atvjbim3PbFMFM/"
        );
        renderer.pushBatch(
            888,
            13,
            "https://gateway.irys.xyz/AtQw-VDi13oYZd-fmOiDOp9y6ScNsAsT0HJsqWPuwpU/"
        );
        renderer.pushBatch(
            666,
            12,
            "https://gateway.irys.xyz/wZYsA8BZ7l0v0BgKaBwByhQA-C4P92Vxd9XTGf46KQ0/"
        );
        renderer.pushBatch(
            6969,
            10,
            "https://gateway.irys.xyz/w-9ZRQkSJeGc6uDcOtdQne6AkFxQn2eLjKRj-MHzYOg/"
        );
        renderer.pushBatch(
            187,
            10,
            "https://gateway.irys.xyz/-Z063Rq79ys-T2lWbArVMF4N1CRRsLZPC7VMj_2pydQ/"
        );

        fame.setRenderer(address(renderer));

        vm.stopBroadcast();
    }
}
