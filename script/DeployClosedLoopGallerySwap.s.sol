// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {ClosedLoopGallerySwap} from "../src/ClosedLoopGallerySwap.sol";
import {CreatorArtistMagic} from "../src/CreatorArtistMagic.sol";

contract DeployClosedLoopGallerySwap is Script {
    error GalleryChainIdMismatch(uint256 expected, uint256 actual);
    error ZeroGalleryOwner();
    error ZeroGalleryOperator();

    function run() external returns (ClosedLoopGallerySwap gallery) {
        uint256 expectedChainId = vm.envUint("BASE_CHAIN_ID");
        if (block.chainid != expectedChainId) {
            revert GalleryChainIdMismatch(expectedChainId, block.chainid);
        }

        uint256 deployerPrivateKey = vm.envUint("BASE_DEPLOYER_PRIVATE_KEY");
        address fame = vm.envAddress("BASE_FAME_ADDRESS");
        address creatorMagic = vm.envAddress("BASE_CREATOR_ARTIST_MAGIC_ADDRESS");
        address feeRecipient =
            vm.envOr("BASE_CLOSED_LOOP_GALLERY_FEE_RECIPIENT", vm.envAddress("BASE_FAME_ROUTER_FEE_RECIPIENT"));
        address owner = vm.envOr("BASE_CLOSED_LOOP_GALLERY_OWNER", vm.addr(deployerPrivateKey));
        address operator = vm.envOr("BASE_CLOSED_LOOP_GALLERY_OPERATOR", owner);

        vm.startBroadcast(deployerPrivateKey);
        gallery = deployConfiguredGallery(fame, creatorMagic, feeRecipient, owner, operator);
        vm.stopBroadcast();
    }

    function deployConfiguredGallery(
        address fame,
        address creatorMagic,
        address feeRecipient,
        address owner,
        address operator
    ) public returns (ClosedLoopGallerySwap gallery) {
        if (owner == address(0)) revert ZeroGalleryOwner();
        if (operator == address(0)) revert ZeroGalleryOperator();

        gallery = new ClosedLoopGallerySwap(payable(fame), creatorMagic, feeRecipient, owner, operator);
        CreatorArtistMagic(creatorMagic).grantRoles(address(gallery), gallery.requiredCreatorMagicRoles());
    }
}
