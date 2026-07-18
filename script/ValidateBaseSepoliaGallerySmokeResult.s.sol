// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {BaseSepoliaTestRenderer} from "../src/BaseSepoliaTestRenderer.sol";
import {ClosedLoopGallerySwap} from "../src/ClosedLoopGallerySwap.sol";
import {CreatorArtistMagic} from "../src/CreatorArtistMagic.sol";
import {Fame} from "../src/Fame.sol";
import {FameMirror} from "../src/FameMirror.sol";

contract ValidateBaseSepoliaGallerySmokeResult is Script {
    uint256 internal constant BASE_SEPOLIA_CHAIN_ID = 84532;
    address internal constant BASE_SEPOLIA_FAME = 0x2cF0408Ee86b337216dD0073ab257F84497067cA;
    address internal constant BASE_SEPOLIA_MIRROR = 0x2907936013BDF568F98A98893AC1C746256A9cC5;
    uint256 internal constant EXPECTED_UNIT = 1_000_000 ether;
    uint256 internal constant MINIMUM_GALLERY_INVENTORY = 2;

    error ChainIdMismatch(uint256 expected, uint256 actual);
    error CanonicalAddressMismatch(string field, address expected, address actual);
    error StackAddressMismatch(string field, address expected, address actual);
    error FameIdentityMismatch();
    error InvalidRecipient(address recipient);
    error InvalidTokenIds(uint256 tokenId, uint256 poolTokenId);
    error SoldTokenOwnerMismatch(uint256 tokenId, address expected, address actual);
    error ReplacementTokenOwnerMismatch(uint256 tokenId, address expected, address actual);
    error ActiveRendererMismatch(address expected, address actual);
    error MetadataSwapMismatch(uint256 tokenId, uint256 poolTokenId);
    error ListingStillActive(uint256 tokenId);
    error GalleryInventoryTooLow(uint256 minimum, uint256 actual);

    function run() external view {
        if (block.chainid != BASE_SEPOLIA_CHAIN_ID) revert ChainIdMismatch(BASE_SEPOLIA_CHAIN_ID, block.chainid);

        Fame fame = Fame(payable(vm.envAddress("BASE_SEPOLIA_FAME_ADDRESS")));
        FameMirror mirror = FameMirror(payable(vm.envAddress("BASE_SEPOLIA_FAME_NFT_ADDRESS")));
        BaseSepoliaTestRenderer renderer = BaseSepoliaTestRenderer(vm.envAddress("BASE_SEPOLIA_TEST_RENDERER_ADDRESS"));
        ClosedLoopGallerySwap gallery = ClosedLoopGallerySwap(vm.envAddress("BASE_SEPOLIA_CLOSED_LOOP_GALLERY_ADDRESS"));
        address recipient = vm.envAddress("BASE_SEPOLIA_SMOKE_RECIPIENT");
        uint256 tokenId = vm.envUint("BASE_SEPOLIA_SMOKE_TOKEN_ID");
        uint256 poolTokenId = vm.envUint("BASE_SEPOLIA_SMOKE_POOL_TOKEN_ID");

        _validateCanonicalFame(fame, mirror);
        validateResult(fame, mirror, renderer, gallery, recipient, tokenId, poolTokenId);
    }

    function validateResult(
        Fame fame,
        FameMirror mirror,
        BaseSepoliaTestRenderer renderer,
        ClosedLoopGallerySwap gallery,
        address recipient,
        uint256 tokenId,
        uint256 poolTokenId
    ) public view {
        _checkAddress("gallery.fame", address(fame), address(gallery.fame()));
        _checkAddress("gallery.mirror", address(mirror), address(gallery.mirror()));
        CreatorArtistMagic creatorMagic = gallery.creatorMagic();
        _checkAddress("creatorMagic.childRenderer", address(renderer), address(creatorMagic.childRenderer()));
        if (recipient == address(0) || recipient == address(gallery) || recipient.code.length != 0) {
            revert InvalidRecipient(recipient);
        }
        if (tokenId == 0 || poolTokenId == 0 || tokenId == poolTokenId) {
            revert InvalidTokenIds(tokenId, poolTokenId);
        }

        address soldTokenOwner = mirror.ownerAt(tokenId);
        if (soldTokenOwner != recipient) {
            revert SoldTokenOwnerMismatch(tokenId, recipient, soldTokenOwner);
        }

        address replacementTokenOwner = mirror.ownerAt(poolTokenId);
        if (replacementTokenOwner != address(gallery)) {
            revert ReplacementTokenOwnerMismatch(poolTokenId, address(gallery), replacementTokenOwner);
        }

        address activeRenderer = address(fame.renderer());
        if (activeRenderer != address(creatorMagic)) {
            revert ActiveRendererMismatch(address(creatorMagic), activeRenderer);
        }

        bytes32 expectedSoldMetadata = keccak256(bytes(creatorMagic.childRenderer().tokenURI(poolTokenId)));
        bytes32 expectedReplacementMetadata = keccak256(bytes(creatorMagic.childRenderer().tokenURI(tokenId)));
        if (
            keccak256(bytes(creatorMagic.tokenURI(tokenId))) != expectedSoldMetadata
                || keccak256(bytes(creatorMagic.tokenURI(poolTokenId))) != expectedReplacementMetadata
                || keccak256(bytes(mirror.tokenURI(tokenId))) != expectedSoldMetadata
                || keccak256(bytes(mirror.tokenURI(poolTokenId))) != expectedReplacementMetadata
        ) {
            revert MetadataSwapMismatch(tokenId, poolTokenId);
        }

        (, bool active) = gallery.listings(tokenId);
        if (active) revert ListingStillActive(tokenId);

        uint256 inventory = mirror.balanceOf(address(gallery));
        if (inventory < MINIMUM_GALLERY_INVENTORY) {
            revert GalleryInventoryTooLow(MINIMUM_GALLERY_INVENTORY, inventory);
        }
    }

    function _validateCanonicalFame(Fame fame, FameMirror mirror) internal view {
        if (address(fame) != BASE_SEPOLIA_FAME) {
            revert CanonicalAddressMismatch("fame", BASE_SEPOLIA_FAME, address(fame));
        }
        if (address(mirror) != BASE_SEPOLIA_MIRROR) {
            revert CanonicalAddressMismatch("mirror", BASE_SEPOLIA_MIRROR, address(mirror));
        }
        if (
            address(fame).code.length == 0 || address(mirror).code.length == 0
                || keccak256(bytes(fame.name())) != keccak256("Example")
                || keccak256(bytes(fame.symbol())) != keccak256("TEST") || fame.unit() != EXPECTED_UNIT
                || address(fame.fameMirror()) != address(mirror)
        ) {
            revert FameIdentityMismatch();
        }
    }

    function _checkAddress(string memory field, address expected, address actual) internal pure {
        if (actual != expected) revert StackAddressMismatch(field, expected, actual);
    }
}
