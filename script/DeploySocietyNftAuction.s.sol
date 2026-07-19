// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {SocietyNftAuction} from "../src/SocietyNftAuction.sol";

contract DeploySocietyNftAuction is Script {
    uint256 public constant BASE_CHAIN_ID = 8453;

    error ChainIdMismatch(uint256 expected, uint256 actual);
    error ZeroOwner();
    error DeployerMustBeOwner(address deployer, address owner);

    function run() external returns (SocietyNftAuction auction) {
        if (block.chainid != BASE_CHAIN_ID) revert ChainIdMismatch(BASE_CHAIN_ID, block.chainid);

        address initialOwner = vm.envAddress("BASE_SOCIETY_NFT_AUCTION_OWNER");
        if (initialOwner == address(0)) revert ZeroOwner();

        uint256 deployerPrivateKey = vm.envUint("BASE_DEPLOYER_PRIVATE_KEY");
        requireDeployerOwner(vm.addr(deployerPrivateKey), initialOwner);

        vm.startBroadcast(deployerPrivateKey);
        auction = deployConfigured(initialOwner);
        vm.stopBroadcast();
    }

    function deployConfigured(address initialOwner) public returns (SocietyNftAuction auction) {
        if (block.chainid != BASE_CHAIN_ID) revert ChainIdMismatch(BASE_CHAIN_ID, block.chainid);
        if (initialOwner == address(0)) revert ZeroOwner();
        auction = new SocietyNftAuction(initialOwner);
    }

    function requireDeployerOwner(address deployer, address initialOwner) internal pure {
        if (deployer != initialOwner) revert DeployerMustBeOwner(deployer, initialOwner);
    }
}
