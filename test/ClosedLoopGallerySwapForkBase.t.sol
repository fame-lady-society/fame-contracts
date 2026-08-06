// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Fame} from "../src/Fame.sol";

contract ClosedLoopGallerySwapForkBaseTest is Test {
    error MissingBaseRpc();

    function test_BaseForkFameMirrorMatchesPublicConfig() public {
        string memory rpc = vm.envOr("BASE_RPC", string(""));
        if (bytes(rpc).length == 0) {
            revert MissingBaseRpc();
        }

        uint256 forkId = vm.createSelectFork(rpc);
        assertEq(vm.activeFork(), forkId);
        assertEq(block.chainid, 8453);

        address fameAddress = vm.envAddress("BASE_FAME_ADDRESS");
        address mirrorAddress = vm.envAddress("BASE_FAME_NFT_ADDRESS");

        assertGt(fameAddress.code.length, 0);
        assertGt(mirrorAddress.code.length, 0);
        assertEq(address(Fame(payable(fameAddress)).fameMirror()), mirrorAddress);
    }
}
