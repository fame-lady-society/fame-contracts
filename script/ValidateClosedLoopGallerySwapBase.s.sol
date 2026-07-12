// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {ClosedLoopGallerySwap} from "../src/ClosedLoopGallerySwap.sol";
import {CreatorArtistMagic} from "../src/CreatorArtistMagic.sol";
import {Fame} from "../src/Fame.sol";

contract ValidateClosedLoopGallerySwapBase is Script {
    error GalleryChainIdMismatch(uint256 expected, uint256 actual);
    error GalleryAddressMismatch(string field, address expected, address actual);
    error GallerySkipNftEnabled(address gallery);
    error GalleryOperatorMissing(address operator);
    error GalleryCreatorMagicRoleMissing(uint256 role);
    error GalleryCreatorRoleTooBroad();
    error GalleryCreatorMagicAuthorityOwnerMismatch(address expected, address actual);

    function run() external view {
        uint256 expectedChainId = vm.envUint("BASE_CHAIN_ID");
        if (block.chainid != expectedChainId) {
            revert GalleryChainIdMismatch(expectedChainId, block.chainid);
        }

        ClosedLoopGallerySwap gallery = ClosedLoopGallerySwap(vm.envAddress("BASE_CLOSED_LOOP_GALLERY_ADDRESS"));
        address fame = vm.envAddress("BASE_FAME_ADDRESS");
        address mirror = vm.envAddress("BASE_FAME_NFT_ADDRESS");
        address creatorMagic = vm.envAddress("BASE_CREATOR_ARTIST_MAGIC_ADDRESS");
        address feeRecipient =
            vm.envOr("BASE_CLOSED_LOOP_GALLERY_FEE_RECIPIENT", vm.envAddress("BASE_FAME_ROUTER_FEE_RECIPIENT"));
        address expectedOwner = vm.envOr("BASE_CLOSED_LOOP_GALLERY_OWNER", address(0));
        address expectedOperator = vm.envOr("BASE_CLOSED_LOOP_GALLERY_OPERATOR", address(0));
        address expectedCreatorMagicOwner = vm.envOr("BASE_CREATOR_ARTIST_MAGIC_EXPECTED_OWNER", address(0));

        validateGalleryConfiguration(gallery, fame, mirror, creatorMagic, feeRecipient, expectedOwner, expectedOperator);
        validateVaultSkipNft(fame, address(gallery));
        validateCreatorMagicRoles(gallery, CreatorArtistMagic(creatorMagic), expectedCreatorMagicOwner);
    }

    function validateGalleryConfiguration(
        ClosedLoopGallerySwap gallery,
        address fame,
        address mirror,
        address creatorMagic,
        address feeRecipient,
        address expectedOwner,
        address expectedOperator
    ) public view {
        if (address(gallery.fame()) != fame) {
            revert GalleryAddressMismatch("fame", fame, address(gallery.fame()));
        }
        if (address(gallery.mirror()) != mirror) {
            revert GalleryAddressMismatch("mirror", mirror, address(gallery.mirror()));
        }
        if (address(gallery.creatorMagic()) != creatorMagic) {
            revert GalleryAddressMismatch("creatorMagic", creatorMagic, address(gallery.creatorMagic()));
        }
        if (gallery.feeRecipient() != feeRecipient) {
            revert GalleryAddressMismatch("feeRecipient", feeRecipient, gallery.feeRecipient());
        }
        if (expectedOwner != address(0) && gallery.owner() != expectedOwner) {
            revert GalleryAddressMismatch("owner", expectedOwner, gallery.owner());
        }
        if (expectedOperator != address(0) && !gallery.hasAnyRole(expectedOperator, gallery.roleOperator())) {
            revert GalleryOperatorMissing(expectedOperator);
        }
    }

    function validateVaultSkipNft(address fame, address gallery) public view {
        if (Fame(payable(fame)).getSkipNFT(gallery)) revert GallerySkipNftEnabled(gallery);
    }

    function validateCreatorMagicRoles(
        ClosedLoopGallerySwap gallery,
        CreatorArtistMagic creatorMagic,
        address expectedCreatorMagicOwner
    ) public view {
        if (!creatorMagic.hasAnyRole(address(gallery), gallery.creatorMagicBanisherRole())) {
            revert GalleryCreatorMagicRoleMissing(gallery.creatorMagicBanisherRole());
        }
        if (!creatorMagic.hasAnyRole(address(gallery), gallery.creatorMagicArtPoolManagerRole())) {
            revert GalleryCreatorMagicRoleMissing(gallery.creatorMagicArtPoolManagerRole());
        }
        if (creatorMagic.hasAnyRole(address(gallery), gallery.creatorMagicCreatorRole())) {
            revert GalleryCreatorRoleTooBroad();
        }
        if (expectedCreatorMagicOwner != address(0) && creatorMagic.owner() != expectedCreatorMagicOwner) {
            revert GalleryCreatorMagicAuthorityOwnerMismatch(expectedCreatorMagicOwner, creatorMagic.owner());
        }
    }
}
