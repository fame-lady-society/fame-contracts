// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {FameSale} from "../src/FameSale.sol";
import {FameSaleToken} from "../src/FameSaleToken.sol";

contract DeployPresale is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address multiSig = vm.envAddress("BASE_MULTISIG_ADDRESS");
        vm.startBroadcast(deployerPrivateKey);

        FameSale fs = new FameSale();
        fs.grantRoles(
            multiSig,
            fs.roleTreasurer() | fs.roleExecutive() | fs.roleAllowlist()
        );
        fs.transferOwnership(multiSig);
        FameSaleToken fst = FameSaleToken(fs.fameSaleToken());
        fst.grantRoles(
            address(fs),
            fst.roleBurner() | fst.roleController() | fst.roleMinter()
        );
        fst.transferOwnership(multiSig);

        vm.stopBroadcast();
    }
}
