// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {BaseSepoliaTestRenderer} from "../src/BaseSepoliaTestRenderer.sol";
import {ClosedLoopGallerySwap} from "../src/ClosedLoopGallerySwap.sol";
import {CreatorArtistMagic} from "../src/CreatorArtistMagic.sol";
import {Fame} from "../src/Fame.sol";
import {FameMirror} from "../src/FameMirror.sol";

contract ValidateBaseSepoliaGalleryTestStack is Script {
    uint256 internal constant BASE_SEPOLIA_CHAIN_ID = 84532;
    address internal constant BASE_SEPOLIA_FAME = 0x2cF0408Ee86b337216dD0073ab257F84497067cA;
    address internal constant BASE_SEPOLIA_MIRROR = 0x2907936013BDF568F98A98893AC1C746256A9cC5;
    uint256 internal constant FAME_ADMIN_ROLE = 1 << 255;
    uint256 internal constant FAME_RENDERER_ROLE = 1 << 0;
    uint256 internal constant EXPECTED_UNIT = 1_000_000 ether;
    uint16 internal constant EXPECTED_NEXT_TOKEN_ID = 500;
    uint256 internal constant MINIMUM_GALLERY_INVENTORY = 2;

    error ChainIdMismatch(uint256 expected, uint256 actual);
    error FameIdentityMismatch();
    error CanonicalAddressMismatch(string field, address expected, address actual);
    error StackCodeMissing(string field, address target);
    error StackAddressMismatch(string field, address expected, address actual);
    error StackValueMismatch(string field, uint256 expected, uint256 actual);
    error FameAdminMissing(address expectedAdmin);
    error FameRendererRoleMissing(address creatorMagic);
    error RendererNotUnique();
    error GallerySkipNftEnabled();
    error GalleryInventoryTooLow(uint256 minimum, uint256 actual);
    error CreatorMagicRoleMissing(uint256 role);
    error CreatorMagicCreatorRoleTooBroad();
    error GalleryOperatorMissing(address operator);

    function run() external view {
        if (block.chainid != BASE_SEPOLIA_CHAIN_ID) revert ChainIdMismatch(BASE_SEPOLIA_CHAIN_ID, block.chainid);

        Fame fame = Fame(payable(vm.envAddress("BASE_SEPOLIA_FAME_ADDRESS")));
        address mirror = vm.envAddress("BASE_SEPOLIA_FAME_NFT_ADDRESS");
        validateCanonicalFame(fame, mirror);
        BaseSepoliaTestRenderer renderer = BaseSepoliaTestRenderer(vm.envAddress("BASE_SEPOLIA_TEST_RENDERER_ADDRESS"));
        CreatorArtistMagic creatorMagic = CreatorArtistMagic(vm.envAddress("BASE_SEPOLIA_CREATOR_ARTIST_MAGIC_ADDRESS"));
        ClosedLoopGallerySwap gallery = ClosedLoopGallerySwap(vm.envAddress("BASE_SEPOLIA_CLOSED_LOOP_GALLERY_ADDRESS"));
        address owner = vm.envAddress("BASE_SEPOLIA_GALLERY_OWNER");
        address operator = vm.envAddress("BASE_SEPOLIA_GALLERY_OPERATOR");
        address feeRecipient = vm.envAddress("BASE_SEPOLIA_GALLERY_FEE_RECIPIENT");

        validateFameIdentity(fame, mirror);
        validateStack(fame, mirror, renderer, creatorMagic, gallery, owner, operator, feeRecipient);
    }

    function validateCanonicalFame(Fame fame, address mirror) public pure {
        if (address(fame) != BASE_SEPOLIA_FAME) {
            revert CanonicalAddressMismatch("fame", BASE_SEPOLIA_FAME, address(fame));
        }
        if (mirror != BASE_SEPOLIA_MIRROR) {
            revert CanonicalAddressMismatch("mirror", BASE_SEPOLIA_MIRROR, mirror);
        }
    }

    function validateFameIdentity(Fame fame, address expectedMirror) public view {
        if (
            address(fame).code.length == 0 || keccak256(bytes(fame.name())) != keccak256("Example")
                || keccak256(bytes(fame.symbol())) != keccak256("TEST") || fame.unit() != EXPECTED_UNIT
        ) revert FameIdentityMismatch();
        if (expectedMirror.code.length == 0) revert StackCodeMissing("mirror", expectedMirror);
        _checkAddress("fameMirror", expectedMirror, address(fame.fameMirror()));
    }

    function validateStack(
        Fame fame,
        address expectedMirror,
        BaseSepoliaTestRenderer renderer,
        CreatorArtistMagic creatorMagic,
        ClosedLoopGallerySwap gallery,
        address expectedOwner,
        address expectedOperator,
        address expectedFeeRecipient
    ) public view {
        validateFameIdentity(fame, expectedMirror);

        if (address(renderer).code.length == 0) revert StackCodeMissing("renderer", address(renderer));
        if (address(creatorMagic).code.length == 0) revert StackCodeMissing("creatorMagic", address(creatorMagic));
        if (address(gallery).code.length == 0) revert StackCodeMissing("gallery", address(gallery));
        _checkAddress("childRenderer", address(renderer), address(creatorMagic.childRenderer()));
        _checkAddress("creatorMagic.fame", address(fame), address(creatorMagic.fame()));
        if (creatorMagic.nextTokenId() != EXPECTED_NEXT_TOKEN_ID) {
            revert StackValueMismatch("nextTokenId", EXPECTED_NEXT_TOKEN_ID, creatorMagic.nextTokenId());
        }
        _checkAddress("fame.renderer", address(creatorMagic), address(fame.renderer()));
        if (!fame.hasAnyRole(address(creatorMagic), FAME_RENDERER_ROLE)) {
            revert FameRendererRoleMissing(address(creatorMagic));
        }
        _checkAddress("gallery.fame", address(fame), address(gallery.fame()));
        _checkAddress("gallery.mirror", expectedMirror, address(gallery.mirror()));
        _checkAddress("gallery.creatorMagic", address(creatorMagic), address(gallery.creatorMagic()));
        _checkAddress("gallery.owner", expectedOwner, gallery.owner());
        _checkAddress("creatorMagic.owner", expectedOwner, creatorMagic.owner());
        _checkAddress("gallery.feeRecipient", expectedFeeRecipient, gallery.feeRecipient());
        if (!fame.hasAnyRole(expectedOwner, FAME_ADMIN_ROLE)) revert FameAdminMissing(expectedOwner);

        bytes32 first = keccak256(bytes(renderer.tokenURI(12)));
        bytes32 second = keccak256(bytes(renderer.tokenURI(420)));
        if (first == keccak256("") || second == keccak256("") || first == second) revert RendererNotUnique();

        if (fame.getSkipNFT(address(gallery))) revert GallerySkipNftEnabled();
        uint256 galleryInventory = FameMirror(payable(expectedMirror)).balanceOf(address(gallery));
        if (galleryInventory < MINIMUM_GALLERY_INVENTORY) {
            revert GalleryInventoryTooLow(MINIMUM_GALLERY_INVENTORY, galleryInventory);
        }
        if (!gallery.hasAnyRole(expectedOperator, gallery.roleOperator())) {
            revert GalleryOperatorMissing(expectedOperator);
        }
        if (!creatorMagic.hasAnyRole(address(gallery), gallery.creatorMagicBanisherRole())) {
            revert CreatorMagicRoleMissing(gallery.creatorMagicBanisherRole());
        }
        if (!creatorMagic.hasAnyRole(address(gallery), gallery.creatorMagicArtPoolManagerRole())) {
            revert CreatorMagicRoleMissing(gallery.creatorMagicArtPoolManagerRole());
        }
        if (creatorMagic.hasAnyRole(address(gallery), gallery.creatorMagicCreatorRole())) {
            revert CreatorMagicCreatorRoleTooBroad();
        }
    }

    function _checkAddress(string memory field, address expected, address actual) internal pure {
        if (actual != expected) revert StackAddressMismatch(field, expected, actual);
    }
}
