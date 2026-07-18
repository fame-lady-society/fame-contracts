// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DeployBaseSepoliaGalleryTestStack} from "../script/DeployBaseSepoliaGalleryTestStack.s.sol";
import {ValidateBaseSepoliaGallerySmokeResult} from "../script/ValidateBaseSepoliaGallerySmokeResult.s.sol";
import {BaseSepoliaTestRenderer} from "../src/BaseSepoliaTestRenderer.sol";
import {ClosedLoopGallerySwap} from "../src/ClosedLoopGallerySwap.sol";
import {CreatorArtistMagic} from "../src/CreatorArtistMagic.sol";
import {Fame} from "../src/Fame.sol";
import {FameMirror} from "../src/FameMirror.sol";
import {SmokeBaseSepoliaGalleryTestStack} from "../script/SmokeBaseSepoliaGalleryTestStack.s.sol";

contract BaseSepoliaGalleryTestStackSmokeTest is Test {
    uint256 internal constant FAME_METADATA_ROLE = 1 << 1;

    SmokeBaseSepoliaGalleryTestStack internal smoke;
    ValidateBaseSepoliaGallerySmokeResult internal resultValidator;
    Fame internal fame;
    FameMirror internal mirror;
    BaseSepoliaTestRenderer internal renderer;
    CreatorArtistMagic internal creatorMagic;
    ClosedLoopGallerySwap internal gallery;
    address internal recipient = address(0xCAFE);

    function setUp() public {
        smoke = new SmokeBaseSepoliaGalleryTestStack();
        resultValidator = new ValidateBaseSepoliaGallerySmokeResult();
        fame = new Fame("Example", "TEST", address(0));
        mirror = fame.fameMirror();
        renderer = new BaseSepoliaTestRenderer();
        creatorMagic = new CreatorArtistMagic(address(renderer), payable(address(fame)), 500);
        fame.grantRoles(address(this), FAME_METADATA_ROLE);
        fame.setRenderer(address(creatorMagic));
        fame.launchPublic();

        gallery = new ClosedLoopGallerySwap(
            payable(address(fame)), address(creatorMagic), address(this), address(smoke), address(smoke)
        );
        creatorMagic.grantRoles(address(gallery), gallery.requiredCreatorMagicRoles());
        fame.transfer(address(gallery), 2 * fame.unit());
        fame.transfer(address(smoke), 5 * fame.unit());
    }

    function testRunRejectsWrongChainBeforeOptInOrSecrets() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                SmokeBaseSepoliaGalleryTestStack.ChainIdMismatch.selector, uint256(84532), block.chainid
            )
        );
        smoke.run();
    }

    function testExecuteRotatesAndFillsBoundedSmoke() public {
        uint256 premium = fame.unit() / 1000;
        uint256 initialSmokeBalance = fame.balanceOf(address(smoke));
        (uint256 expectedTokenId, uint256 expectedPoolTokenId) =
            smoke.preflight(fame, creatorMagic, gallery, address(smoke), recipient, premium);
        string memory displacedUri = creatorMagic.tokenURI(expectedTokenId);
        string memory selectedUri = creatorMagic.tokenURI(expectedPoolTokenId);

        vm.prank(address(smoke), address(smoke));
        (uint256 tokenId, uint256 poolTokenId) =
            smoke.execute(fame, creatorMagic, gallery, address(smoke), recipient, premium);

        assertEq(tokenId, expectedTokenId);
        assertEq(poolTokenId, expectedPoolTokenId);
        assertEq(mirror.ownerOf(tokenId), recipient);
        assertEq(mirror.tokenURI(tokenId), selectedUri);
        assertEq(mirror.tokenURI(poolTokenId), displacedUri);
        assertEq(gallery.accruedProtocolFees(), premium);
        assertEq(mirror.balanceOf(address(gallery)), 2);
        assertEq(fame.balanceOf(address(smoke)), initialSmokeBalance - fame.unit() - premium);
        assertEq(mirror.ownerOf(poolTokenId), address(gallery));
        resultValidator.validateResult(fame, mirror, renderer, gallery, recipient, tokenId, poolTokenId);
    }

    function testSecondExecutionUsesFreshPoolLegAndPreservesInventory() public {
        uint256 premium = fame.unit() / 1000;

        vm.startPrank(address(smoke), address(smoke));
        (uint256 firstTokenId, uint256 firstPoolTokenId) =
            smoke.execute(fame, creatorMagic, gallery, address(smoke), recipient, premium);
        (uint256 secondTokenId, uint256 secondPoolTokenId) =
            smoke.execute(fame, creatorMagic, gallery, address(smoke), recipient, premium);
        vm.stopPrank();

        assertNotEq(firstTokenId, secondTokenId);
        assertNotEq(firstPoolTokenId, secondPoolTokenId);
        assertEq(mirror.ownerOf(firstTokenId), recipient);
        assertEq(mirror.ownerOf(secondTokenId), recipient);
        assertEq(mirror.ownerOf(firstPoolTokenId), address(gallery));
        assertEq(mirror.ownerOf(secondPoolTokenId), address(gallery));
        assertEq(mirror.balanceOf(address(gallery)), 2);
        assertEq(gallery.accruedProtocolFees(), 2 * premium);
    }

    function testPreflightRejectsLateFailureInputsBeforeMutation() public {
        uint256 premium = fame.unit() / 1000;

        vm.expectRevert(abi.encodeWithSelector(SmokeBaseSepoliaGalleryTestStack.InvalidRecipient.selector, address(0)));
        smoke.preflight(fame, creatorMagic, gallery, address(smoke), address(0), premium);

        vm.expectRevert(
            abi.encodeWithSelector(SmokeBaseSepoliaGalleryTestStack.InvalidRecipient.selector, address(smoke))
        );
        smoke.preflight(fame, creatorMagic, gallery, address(smoke), address(smoke), premium);

        uint256 oversizedPremium = uint256(type(uint96).max) + 1;
        vm.expectRevert(
            abi.encodeWithSelector(SmokeBaseSepoliaGalleryTestStack.PremiumTooLarge.selector, oversizedPremium)
        );
        smoke.preflight(fame, creatorMagic, gallery, address(smoke), recipient, oversizedPremium);

        assertEq(fame.balanceOf(address(gallery)), 2 * fame.unit());
        assertEq(mirror.balanceOf(address(gallery)), 2);
        assertEq(gallery.accruedProtocolFees(), 0);
    }

    function testPreflightSkipsActiveVaultListing() public {
        uint256 premium = fame.unit() / 1000;
        (uint256 firstTokenId,) = smoke.preflight(fame, creatorMagic, gallery, address(smoke), recipient, premium);

        vm.prank(address(smoke));
        gallery.list(firstTokenId, premium);

        (uint256 selectedTokenId,) = smoke.preflight(fame, creatorMagic, gallery, address(smoke), recipient, premium);
        assertNotEq(selectedTokenId, firstTokenId);
    }

    function testPreflightRejectsPartiallyRotatedNextPoolLeg() public {
        uint256 premium = fame.unit() / 1000;
        (uint256 tokenId, uint256 poolTokenId) =
            smoke.preflight(fame, creatorMagic, gallery, address(smoke), recipient, premium);

        vm.prank(address(smoke));
        gallery.rotateToMintPool(tokenId, poolTokenId);

        vm.expectRevert(SmokeBaseSepoliaGalleryTestStack.MintPoolTokenNotFound.selector);
        smoke.preflight(fame, creatorMagic, gallery, address(smoke), recipient, premium);
    }

    function testPreflightRejectsSignerThatOwnsSocietyNft() public {
        uint256 premium = fame.unit() / 1000;
        (uint256 tokenId,) = smoke.preflight(fame, creatorMagic, gallery, address(smoke), recipient, premium);

        vm.prank(address(gallery));
        mirror.transferFrom(address(gallery), address(smoke), tokenId);

        vm.expectRevert(
            abi.encodeWithSelector(
                SmokeBaseSepoliaGalleryTestStack.SignerOwnsSocietyNfts.selector, address(smoke), uint256(1)
            )
        );
        smoke.preflight(fame, creatorMagic, gallery, address(smoke), recipient, premium);
    }

    function testExecuteRejectsOutOfOrderBurnedPoolReplacement() public {
        address firstHolder = address(0xA1);
        address secondHolder = address(0xA2);
        address skipRecipient = address(0xA3);
        uint256 unitAmount = fame.unit();

        fame.transfer(firstHolder, unitAmount);
        fame.transfer(secondHolder, unitAmount);
        vm.prank(skipRecipient);
        fame.setSkipNFT(true);
        vm.prank(secondHolder);
        fame.transfer(skipRecipient, unitAmount);
        vm.prank(firstHolder);
        fame.transfer(skipRecipient, unitAmount);

        uint256 premium = unitAmount / 1000;
        (uint256 tokenId, uint256 poolTokenId) =
            smoke.preflight(fame, creatorMagic, gallery, address(smoke), recipient, premium);
        uint256 inventoryBefore = mirror.balanceOf(address(gallery));

        vm.expectRevert(
            abi.encodeWithSelector(
                SmokeBaseSepoliaGalleryTestStack.ReplacementTokenOwnerMismatch.selector,
                poolTokenId,
                address(gallery),
                address(0)
            )
        );
        vm.prank(address(smoke), address(smoke));
        smoke.execute(fame, creatorMagic, gallery, address(smoke), recipient, premium);

        assertEq(mirror.ownerOf(tokenId), address(gallery));
        assertEq(mirror.balanceOf(address(gallery)), inventoryBefore);
        assertEq(gallery.accruedProtocolFees(), 0);
    }

    function testDeploymentSizedSeedDoesNotHideThreeEntryBurnedPool() public {
        Fame localFame = new Fame("Example", "TEST", address(0));
        localFame.launchPublic();
        uint256 unitAmount = localFame.unit();
        address firstHolder = address(0xB1);
        address secondHolder = address(0xB2);
        address thirdHolder = address(0xB3);
        address skipRecipient = address(0xB4);

        localFame.transfer(firstHolder, unitAmount);
        localFame.transfer(secondHolder, unitAmount);
        localFame.transfer(thirdHolder, unitAmount);
        vm.prank(skipRecipient);
        localFame.setSkipNFT(true);
        vm.prank(secondHolder);
        localFame.transfer(skipRecipient, unitAmount);
        vm.prank(thirdHolder);
        localFame.transfer(skipRecipient, unitAmount);
        vm.prank(firstHolder);
        localFame.transfer(skipRecipient, unitAmount);

        DeployBaseSepoliaGalleryTestStack stackDeployer = new DeployBaseSepoliaGalleryTestStack();
        localFame.grantRoles(address(stackDeployer), FAME_METADATA_ROLE);
        localFame.transfer(address(stackDeployer), 2 * unitAmount);
        (, CreatorArtistMagic localCreatorMagic, ClosedLoopGallerySwap localGallery) =
            stackDeployer.deployConfiguredStack(localFame, address(this), address(this), address(smoke));
        localFame.transfer(address(smoke), 5 * unitAmount);

        vm.expectRevert(SmokeBaseSepoliaGalleryTestStack.MintPoolTokenNotFound.selector);
        smoke.preflight(localFame, localCreatorMagic, localGallery, address(smoke), recipient, unitAmount / 1000);
    }

    function testResultValidationRejectsWrongReplacementToken() public {
        uint256 premium = fame.unit() / 1000;
        vm.prank(address(smoke), address(smoke));
        (uint256 tokenId, uint256 poolTokenId) =
            smoke.execute(fame, creatorMagic, gallery, address(smoke), recipient, premium);

        vm.expectRevert(
            abi.encodeWithSelector(
                ValidateBaseSepoliaGallerySmokeResult.ReplacementTokenOwnerMismatch.selector,
                poolTokenId + 1,
                address(gallery),
                address(0)
            )
        );
        resultValidator.validateResult(fame, mirror, renderer, gallery, recipient, tokenId, poolTokenId + 1);
    }

    function testResultValidationRejectsActiveRendererDrift() public {
        uint256 premium = fame.unit() / 1000;
        vm.prank(address(smoke), address(smoke));
        (uint256 tokenId, uint256 poolTokenId) =
            smoke.execute(fame, creatorMagic, gallery, address(smoke), recipient, premium);
        BaseSepoliaTestRenderer wrongRenderer = new BaseSepoliaTestRenderer();
        fame.setRenderer(address(wrongRenderer));

        vm.expectRevert(
            abi.encodeWithSelector(
                ValidateBaseSepoliaGallerySmokeResult.ActiveRendererMismatch.selector,
                address(creatorMagic),
                address(wrongRenderer)
            )
        );
        resultValidator.validateResult(fame, mirror, renderer, gallery, recipient, tokenId, poolTokenId);
    }

    function testResultValidationRejectsDegenerateIdsAndGalleryRecipient() public {
        uint256 galleryTokenId = _firstGalleryToken();

        vm.expectRevert(
            abi.encodeWithSelector(ValidateBaseSepoliaGallerySmokeResult.InvalidRecipient.selector, address(gallery))
        );
        resultValidator.validateResult(
            fame, mirror, renderer, gallery, address(gallery), galleryTokenId, galleryTokenId
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ValidateBaseSepoliaGallerySmokeResult.InvalidTokenIds.selector, galleryTokenId, galleryTokenId
            )
        );
        resultValidator.validateResult(fame, mirror, renderer, gallery, recipient, galleryTokenId, galleryTokenId);
    }

    function _firstGalleryToken() internal view returns (uint256) {
        for (uint256 tokenId = 1; tokenId <= 888; ++tokenId) {
            if (mirror.ownerAt(tokenId) == address(gallery)) return tokenId;
        }
        revert("GALLERY_TOKEN_NOT_FOUND");
    }
}
