// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";

contract FundFork is Script {
    function run() external {
        uint256 forkPrivateKey = vm.envUint("FORK_PRIVATE_KEY");
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        VmSafe.Wallet memory wallet = vm.createWallet(deployerPrivateKey);
        vm.startBroadcast(forkPrivateKey);
        // send 10E to wallet.addr using a boradcastable transaction
        (bool success, ) = payable(wallet.addr).call{value: 10 ether}("");
        require(success, "Transfer failed.");
        vm.stopBroadcast();
    }
}
