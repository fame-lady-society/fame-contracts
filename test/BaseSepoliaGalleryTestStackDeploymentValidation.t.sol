// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DeployBaseSepoliaGalleryTestStack} from "../script/DeployBaseSepoliaGalleryTestStack.s.sol";
import {ValidateBaseSepoliaGalleryTestStack} from "../script/ValidateBaseSepoliaGalleryTestStack.s.sol";
import {BaseSepoliaTestRenderer} from "../src/BaseSepoliaTestRenderer.sol";
import {ClosedLoopGallerySwap} from "../src/ClosedLoopGallerySwap.sol";
import {CreatorArtistMagic} from "../src/CreatorArtistMagic.sol";
import {Fame} from "../src/Fame.sol";
import {FameMirror} from "../src/FameMirror.sol";
import {PresaleNFTRendererMetadataQuick} from "../src/PresaleNFTRenderer_quick.sol";

contract BaseSepoliaGalleryTestStackDeploymentValidationTest is Test {
    uint256 internal constant FAME_METADATA_ROLE = 2;
    uint256 internal constant FAME_RENDERER_ROLE = 1;
    uint256 internal constant FAME_SKIP_MANAGER_ROLE = 8;
    uint256 internal constant CREATOR_MAGIC_CREATOR_ROLE = 2;

    address internal operator = address(0x1002);
    address internal feeRecipient = address(0x1003);

    Fame internal fame;
    FameMirror internal mirror;
    BaseSepoliaTestRenderer internal renderer;
    CreatorArtistMagic internal creatorMagic;
    ClosedLoopGallerySwap internal gallery;
    DeployBaseSepoliaGalleryTestStack internal deployer;
    ValidateBaseSepoliaGalleryTestStack internal validator;

    function setUp() public {
        fame = new Fame("Example", "TEST", address(0));
        mirror = fame.fameMirror();
        fame.grantRoles(address(this), FAME_METADATA_ROLE);
        fame.launchPublic();
        deployer = new DeployBaseSepoliaGalleryTestStack();
        fame.grantRoles(address(deployer), FAME_METADATA_ROLE);
        fame.transfer(address(deployer), 2 * fame.unit());
        (renderer, creatorMagic, gallery) = deployer.deployConfiguredStack(fame, feeRecipient, address(this), operator);
        validator = new ValidateBaseSepoliaGalleryTestStack();
    }

    function testDeployRunFailsOnWrongChainBeforeReadingSecrets() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                DeployBaseSepoliaGalleryTestStack.ChainIdMismatch.selector, uint256(84532), block.chainid
            )
        );
        deployer.run();
    }

    function testDeploymentReadinessRejectsNonceDrift() public {
        address account = address(0xBEEF);
        uint256 actualNonce = vm.getNonce(account);

        vm.expectRevert(
            abi.encodeWithSelector(
                DeployBaseSepoliaGalleryTestStack.DeployerNonceMismatch.selector, actualNonce + 1, actualNonce
            )
        );
        deployer.validateDeployerReadiness(fame, account, actualNonce + 1);
    }

    function testDeploymentReadinessRejectsInsufficientFame() public {
        address account = address(0xBEEF);
        uint256 requiredBalance = 2 * fame.unit();

        vm.expectRevert(
            abi.encodeWithSelector(
                DeployBaseSepoliaGalleryTestStack.InsufficientDeploymentFameBalance.selector,
                requiredBalance,
                uint256(0)
            )
        );
        deployer.validateDeployerReadiness(fame, account, vm.getNonce(account));
    }

    function testValidationPassesForConfiguredStack() public view {
        validator.validateFameIdentity(fame, address(mirror));
        validator.validateStack(
            fame, address(mirror), renderer, creatorMagic, gallery, address(this), operator, feeRecipient
        );
        assertEq(mirror.balanceOf(address(gallery)), 2);
    }

    function testValidationRejectsWrongFameIdentity() public {
        Fame wrongFame = new Fame("Example", "NOPE", address(0));
        address wrongMirror = address(wrongFame.fameMirror());

        vm.expectRevert(ValidateBaseSepoliaGalleryTestStack.FameIdentityMismatch.selector);
        validator.validateFameIdentity(wrongFame, wrongMirror);
    }

    function testValidationRejectsWrongMirror() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ValidateBaseSepoliaGalleryTestStack.StackCodeMissing.selector, "mirror", address(0xBEEF)
            )
        );
        validator.validateFameIdentity(fame, address(0xBEEF));
    }

    function testValidationRejectsConstantRenderer() public {
        PresaleNFTRendererMetadataQuick constantRenderer = new PresaleNFTRendererMetadataQuick();
        CreatorArtistMagic constantMagic =
            new CreatorArtistMagic(address(constantRenderer), payable(address(fame)), 500);
        fame.setRenderer(address(constantMagic));
        ClosedLoopGallerySwap constantGallery = new ClosedLoopGallerySwap(
            payable(address(fame)), address(constantMagic), feeRecipient, address(this), operator
        );
        constantMagic.grantRoles(address(constantGallery), constantGallery.requiredCreatorMagicRoles());

        vm.expectRevert(ValidateBaseSepoliaGalleryTestStack.RendererNotUnique.selector);
        validator.validateStack(
            fame,
            address(mirror),
            BaseSepoliaTestRenderer(address(constantRenderer)),
            constantMagic,
            constantGallery,
            address(this),
            operator,
            feeRecipient
        );
    }

    function testValidationRejectsMismatchedChildRenderer() public {
        BaseSepoliaTestRenderer otherRenderer = new BaseSepoliaTestRenderer();

        vm.expectRevert(
            abi.encodeWithSelector(
                ValidateBaseSepoliaGalleryTestStack.StackAddressMismatch.selector,
                "childRenderer",
                address(otherRenderer),
                address(renderer)
            )
        );
        validator.validateStack(
            fame, address(mirror), otherRenderer, creatorMagic, gallery, address(this), operator, feeRecipient
        );
    }

    function testValidationRejectsGallerySkipNft() public {
        fame.grantRoles(address(this), FAME_SKIP_MANAGER_ROLE);
        fame.setSkipNftForAccount(address(gallery), true);

        vm.expectRevert(ValidateBaseSepoliaGalleryTestStack.GallerySkipNftEnabled.selector);
        _validateStack();
    }

    function testValidationRejectsInsufficientGalleryInventory() public {
        uint256 tokenId = _firstGalleryToken();
        vm.prank(address(gallery));
        mirror.transferFrom(address(gallery), address(0xBEEF), tokenId);

        vm.expectRevert(
            abi.encodeWithSelector(
                ValidateBaseSepoliaGalleryTestStack.GalleryInventoryTooLow.selector, uint256(2), uint256(1)
            )
        );
        _validateStack();
    }

    function testValidationRejectsMissingCreatorMagicRole() public {
        creatorMagic.revokeRoles(address(gallery), gallery.creatorMagicBanisherRole());

        vm.expectRevert(
            abi.encodeWithSelector(
                ValidateBaseSepoliaGalleryTestStack.CreatorMagicRoleMissing.selector, gallery.creatorMagicBanisherRole()
            )
        );
        _validateStack();
    }

    function testValidationRejectsBroadCreatorMagicRole() public {
        creatorMagic.grantRoles(address(gallery), CREATOR_MAGIC_CREATOR_ROLE);

        vm.expectRevert(ValidateBaseSepoliaGalleryTestStack.CreatorMagicCreatorRoleTooBroad.selector);
        _validateStack();
    }

    function testValidationRejectsWrongOperator() public {
        vm.expectRevert(
            abi.encodeWithSelector(ValidateBaseSepoliaGalleryTestStack.GalleryOperatorMissing.selector, address(0xBEEF))
        );
        validator.validateStack(
            fame, address(mirror), renderer, creatorMagic, gallery, address(this), address(0xBEEF), feeRecipient
        );
    }

    function testValidationRejectsWrongActiveFameRenderer() public {
        fame.setRenderer(address(renderer));

        vm.expectRevert(
            abi.encodeWithSelector(
                ValidateBaseSepoliaGalleryTestStack.StackAddressMismatch.selector,
                "fame.renderer",
                address(creatorMagic),
                address(renderer)
            )
        );
        _validateStack();
    }

    function testValidationRejectsMissingFameRendererRole() public {
        fame.revokeRoles(address(creatorMagic), FAME_RENDERER_ROLE);

        vm.expectRevert(
            abi.encodeWithSelector(
                ValidateBaseSepoliaGalleryTestStack.FameRendererRoleMissing.selector, address(creatorMagic)
            )
        );
        _validateStack();
    }

    function testValidationRejectsWrongFeeRecipient() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ValidateBaseSepoliaGalleryTestStack.StackAddressMismatch.selector,
                "gallery.feeRecipient",
                address(0xBEEF),
                feeRecipient
            )
        );
        validator.validateStack(
            fame, address(mirror), renderer, creatorMagic, gallery, address(this), operator, address(0xBEEF)
        );
    }

    function testValidationRejectsWrongCreatorMagicOwner() public {
        creatorMagic.transferOwnership(address(0xBEEF));

        vm.expectRevert(
            abi.encodeWithSelector(
                ValidateBaseSepoliaGalleryTestStack.StackAddressMismatch.selector,
                "creatorMagic.owner",
                address(this),
                address(0xBEEF)
            )
        );
        _validateStack();
    }

    function _validateStack() internal view {
        validator.validateStack(
            fame, address(mirror), renderer, creatorMagic, gallery, address(this), operator, feeRecipient
        );
    }

    function _firstGalleryToken() internal view returns (uint256) {
        for (uint256 tokenId = 1; tokenId <= 888; ++tokenId) {
            if (mirror.ownerAt(tokenId) == address(gallery)) return tokenId;
        }
        revert("GALLERY_TOKEN_NOT_FOUND");
    }
}
