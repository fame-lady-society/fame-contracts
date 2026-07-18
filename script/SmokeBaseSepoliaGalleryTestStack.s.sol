// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {BaseSepoliaTestRenderer} from "../src/BaseSepoliaTestRenderer.sol";
import {ClosedLoopGallerySwap} from "../src/ClosedLoopGallerySwap.sol";
import {CreatorArtistMagic} from "../src/CreatorArtistMagic.sol";
import {Fame} from "../src/Fame.sol";
import {FameMirror} from "../src/FameMirror.sol";
import {ValidateBaseSepoliaGalleryTestStack} from "./ValidateBaseSepoliaGalleryTestStack.s.sol";

contract SmokeBaseSepoliaGalleryTestStack is Script {
    uint256 internal constant BASE_SEPOLIA_CHAIN_ID = 84532;
    address internal constant BASE_SEPOLIA_FAME = 0x2cF0408Ee86b337216dD0073ab257F84497067cA;
    address internal constant BASE_SEPOLIA_MIRROR = 0x2907936013BDF568F98A98893AC1C746256A9cC5;
    address internal constant BASE_SEPOLIA_ADMIN = 0xD52E2A6bBcEba9673440e4D7843Db6713E9B6FD9;

    struct Configuration {
        Fame fame;
        CreatorArtistMagic creatorMagic;
        ClosedLoopGallerySwap gallery;
    }

    error ChainIdMismatch(uint256 expected, uint256 actual);
    error CanonicalAddressMismatch(string field, address expected, address actual);
    error SmokeNotConfirmed();
    error UnexpectedSigner(address expected, address actual);
    error SignerNotOperator(address signer);
    error SignerOwnsSocietyNfts(address signer, uint256 balance);
    error InsufficientFameBalance(uint256 required, uint256 available);
    error ZeroPremium();
    error PremiumTooLarge(uint256 premium);
    error InvalidRecipient(address recipient);
    error GalleryTokenNotFound();
    error MintPoolTokenNotFound();
    error SoldTokenOwnerMismatch(uint256 tokenId, address expected, address actual);
    error ReplacementTokenOwnerMismatch(uint256 tokenId, address expected, address actual);

    event GallerySmokeCompleted(
        uint256 indexed tokenId,
        uint256 indexed poolTokenId,
        address indexed recipient,
        uint256 premium,
        uint256 inventoryBefore,
        uint256 inventoryAfter
    );

    function run() external returns (uint256 tokenId, uint256 poolTokenId) {
        if (block.chainid != BASE_SEPOLIA_CHAIN_ID) revert ChainIdMismatch(BASE_SEPOLIA_CHAIN_ID, block.chainid);
        if (!vm.envOr("BASE_SEPOLIA_SMOKE_CONFIRMED", false)) revert SmokeNotConfirmed();

        uint256 privateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address signer = vm.addr(privateKey);
        if (signer != BASE_SEPOLIA_ADMIN) revert UnexpectedSigner(BASE_SEPOLIA_ADMIN, signer);
        Configuration memory configuration = _loadAndValidate();
        address recipient = vm.envAddress("BASE_SEPOLIA_SMOKE_RECIPIENT");
        uint256 premium = vm.envOr("BASE_SEPOLIA_SMOKE_PREMIUM", configuration.fame.unit() / 1000);
        (tokenId, poolTokenId) = preflight(
            configuration.fame, configuration.creatorMagic, configuration.gallery, signer, recipient, premium
        );

        vm.startBroadcast(privateKey);
        _executePrepared(configuration.fame, configuration.gallery, recipient, premium, tokenId, poolTokenId);
        vm.stopBroadcast();
    }

    function execute(
        Fame fame,
        CreatorArtistMagic creatorMagic,
        ClosedLoopGallerySwap gallery,
        address signer,
        address recipient,
        uint256 premium
    ) public returns (uint256 tokenId, uint256 poolTokenId) {
        (tokenId, poolTokenId) = preflight(fame, creatorMagic, gallery, signer, recipient, premium);
        _executePrepared(fame, gallery, recipient, premium, tokenId, poolTokenId);
    }

    function preflight(
        Fame fame,
        CreatorArtistMagic creatorMagic,
        ClosedLoopGallerySwap gallery,
        address signer,
        address recipient,
        uint256 premium
    ) public view returns (uint256 tokenId, uint256 poolTokenId) {
        _validatePreflightInputs(gallery, signer, recipient, premium);
        FameMirror mirror = fame.fameMirror();
        _validatePayerAndInventory(fame, mirror, gallery, signer, premium);
        uint256 mintPoolStart = creatorMagic.getMintPoolStart();
        tokenId = _findFreshGalleryToken(mirror, gallery, creatorMagic);
        poolTokenId = _requireFreshMintPoolToken(creatorMagic, mintPoolStart);
    }

    function _validatePreflightInputs(ClosedLoopGallerySwap gallery, address signer, address recipient, uint256 premium)
        internal
        view
    {
        if (!gallery.hasAnyRole(signer, gallery.roleOperator())) revert SignerNotOperator(signer);
        if (premium == 0) revert ZeroPremium();
        if (premium > type(uint96).max) revert PremiumTooLarge(premium);
        if (recipient == address(0) || recipient == signer || recipient.code.length != 0) {
            revert InvalidRecipient(recipient);
        }
    }

    function _validatePayerAndInventory(
        Fame fame,
        FameMirror mirror,
        ClosedLoopGallerySwap gallery,
        address signer,
        uint256 premium
    ) internal view {
        uint256 signerNftBalance = mirror.balanceOf(signer);
        if (signerNftBalance != 0) revert SignerOwnsSocietyNfts(signer, signerNftBalance);
        if (mirror.balanceOf(address(gallery)) == 0) revert GalleryTokenNotFound();
        uint256 requiredBalance = fame.unit() + premium;
        uint256 availableBalance = fame.balanceOf(signer);
        if (availableBalance < requiredBalance) revert InsufficientFameBalance(requiredBalance, availableBalance);
    }

    function _executePrepared(
        Fame fame,
        ClosedLoopGallerySwap gallery,
        address recipient,
        uint256 premium,
        uint256 tokenId,
        uint256 poolTokenId
    ) internal {
        uint256 unitAmount = fame.unit();

        gallery.rotateToMintPool(tokenId, poolTokenId);
        gallery.list(tokenId, premium);
        fame.approve(address(gallery), unitAmount + premium);
        (uint256 inventoryBefore, uint256 inventoryAfter) = gallery.fill(tokenId, recipient);

        FameMirror mirror = fame.fameMirror();
        address soldTokenOwner = mirror.ownerAt(tokenId);
        if (soldTokenOwner != recipient) {
            revert SoldTokenOwnerMismatch(tokenId, recipient, soldTokenOwner);
        }
        address replacementTokenOwner = mirror.ownerAt(poolTokenId);
        if (replacementTokenOwner != address(gallery)) {
            revert ReplacementTokenOwnerMismatch(poolTokenId, address(gallery), replacementTokenOwner);
        }

        emit GallerySmokeCompleted(tokenId, poolTokenId, recipient, premium, inventoryBefore, inventoryAfter);
    }

    function _loadAndValidate() internal returns (Configuration memory configuration) {
        configuration.fame = Fame(payable(vm.envAddress("BASE_SEPOLIA_FAME_ADDRESS")));
        address mirrorAddress = vm.envAddress("BASE_SEPOLIA_FAME_NFT_ADDRESS");
        if (address(configuration.fame) != BASE_SEPOLIA_FAME) {
            revert CanonicalAddressMismatch("fame", BASE_SEPOLIA_FAME, address(configuration.fame));
        }
        if (mirrorAddress != BASE_SEPOLIA_MIRROR) {
            revert CanonicalAddressMismatch("mirror", BASE_SEPOLIA_MIRROR, mirrorAddress);
        }
        BaseSepoliaTestRenderer renderer = BaseSepoliaTestRenderer(vm.envAddress("BASE_SEPOLIA_TEST_RENDERER_ADDRESS"));
        configuration.creatorMagic = CreatorArtistMagic(vm.envAddress("BASE_SEPOLIA_CREATOR_ARTIST_MAGIC_ADDRESS"));
        configuration.gallery = ClosedLoopGallerySwap(vm.envAddress("BASE_SEPOLIA_CLOSED_LOOP_GALLERY_ADDRESS"));

        new ValidateBaseSepoliaGalleryTestStack()
            .validateStack(
                configuration.fame,
                mirrorAddress,
                renderer,
                configuration.creatorMagic,
                configuration.gallery,
                vm.envAddress("BASE_SEPOLIA_GALLERY_OWNER"),
                vm.envAddress("BASE_SEPOLIA_GALLERY_OPERATOR"),
                vm.envAddress("BASE_SEPOLIA_GALLERY_FEE_RECIPIENT")
            );
    }

    function _findFreshGalleryToken(FameMirror mirror, ClosedLoopGallerySwap gallery, CreatorArtistMagic creatorMagic)
        internal
        view
        returns (uint256)
    {
        for (uint256 tokenId = 1; tokenId <= 888; ++tokenId) {
            (, bool active) = gallery.listings(tokenId);
            if (mirror.ownerAt(tokenId) == address(gallery) && !active && _metadataIsFresh(creatorMagic, tokenId)) {
                return tokenId;
            }
        }
        revert GalleryTokenNotFound();
    }

    function _requireFreshMintPoolToken(CreatorArtistMagic creatorMagic, uint256 tokenId)
        internal
        view
        returns (uint256)
    {
        if (!creatorMagic.isTokenInMintPool(tokenId) || !_metadataIsFresh(creatorMagic, tokenId)) {
            revert MintPoolTokenNotFound();
        }
        return tokenId;
    }

    function _metadataIsFresh(CreatorArtistMagic creatorMagic, uint256 tokenId) internal view returns (bool) {
        return keccak256(bytes(creatorMagic.tokenURI(tokenId)))
            == keccak256(bytes(creatorMagic.childRenderer().tokenURI(tokenId)));
    }
}
