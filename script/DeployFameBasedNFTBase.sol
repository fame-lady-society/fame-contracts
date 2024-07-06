// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {FameLadySocietyOwners} from "./holders/FameLadySocietyOwners.sol";
import {IGasliteDrop} from "../src/IGasliteDrop.sol";
import {FameBasedNFT} from "../src/PresaleNFT.sol";
import {PresaleNFTRendererMetadataQuick} from "../src/PresaleNFTRenderer_quick.sol";

contract DeployLaunch is Script {
    FameLadySocietyOwners flsocOwners = new FameLadySocietyOwners();

    function run() external {
        uint256 deployerPrivateKey = vm.envUint(
            "FAMELADY_DEPLOYER_PRIVATE_KEY"
        );
        VmSafe.Wallet memory wallet = vm.createWallet(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);
        PresaleNFTRendererMetadataQuick r = new PresaleNFTRendererMetadataQuick();
        FameBasedNFT nft = new FameBasedNFT(address(r));

        nft.grantRoles(wallet.addr, (1 << 0) | (1 << 1) | (1 << 2));

        IGasliteDrop drop = IGasliteDrop(
            0x09350F89e2D7B6e96bA730783c2d76137B045FEF
        );

        address[] memory owners = flsocOwners.allOwners();
        uint256[] memory tokenIds = new uint256[](owners.length);
        for (uint256 i = 1; i <= owners.length; i++) {
            tokenIds[i - 1] = i;
        }
        nft.mint(wallet.addr, owners.length);
        nft.setApprovalForAll(address(drop), true);
        drop.airdropERC721(address(nft), owners, tokenIds);
        nft.lock();
        vm.stopBroadcast();
    }
}
