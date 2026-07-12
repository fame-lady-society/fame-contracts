// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DeployClosedLoopGallerySwap} from "../script/DeployClosedLoopGallerySwap.s.sol";
import {ValidateClosedLoopGallerySwapBase} from "../script/ValidateClosedLoopGallerySwapBase.s.sol";
import {ClosedLoopGallerySwap} from "../src/ClosedLoopGallerySwap.sol";
import {CreatorArtistMagic} from "../src/CreatorArtistMagic.sol";
import {Fame} from "../src/Fame.sol";
import {FameMirror} from "../src/FameMirror.sol";
import {EchoMetadata} from "./mocks/EchoMetadata.sol";

contract ClosedLoopGallerySwapDeploymentValidationTest is Test {
    uint256 internal constant FAME_RENDERER_ROLE = 1;
    uint256 internal constant FAME_SKIP_MANAGER_ROLE = 8;
    uint256 internal constant CREATOR_MAGIC_CREATOR_ROLE = 2;
    uint256 internal constant CREATOR_MAGIC_SWAP_ROLES = 12;

    address internal owner = address(0x1001);
    address internal operator = address(0x1002);
    address internal feeRecipient = address(0x1003);

    EchoMetadata internal childRenderer;
    Fame internal fame;
    FameMirror internal fameMirror;
    CreatorArtistMagic internal creatorMagic;
    ValidateClosedLoopGallerySwapBase internal validator;

    function setUp() public {
        childRenderer = new EchoMetadata();
        fame = new Fame("Fame Lady Society", "FAME", address(0));
        fameMirror = fame.fameMirror();
        creatorMagic = new CreatorArtistMagic(address(childRenderer), payable(address(fame)), 500);
        fame.grantRoles(address(creatorMagic), FAME_RENDERER_ROLE);
        validator = new ValidateClosedLoopGallerySwapBase();
    }

    function testDeployConfiguredGalleryInitializesSkipAndCreatorMagicRoles() public {
        DeployClosedLoopGallerySwap deployer = new DeployClosedLoopGallerySwap();
        creatorMagic.transferOwnership(address(deployer));

        ClosedLoopGallerySwap gallery =
            deployer.deployConfiguredGallery(address(fame), address(creatorMagic), feeRecipient, owner, operator);

        assertEq(gallery.owner(), owner);
        assertTrue(gallery.hasAnyRole(operator, gallery.roleOperator()));
        assertEq(gallery.feeRecipient(), feeRecipient);
        assertFalse(fame.getSkipNFT(address(gallery)));
        assertTrue(creatorMagic.hasAnyRole(address(gallery), gallery.creatorMagicBanisherRole()));
        assertTrue(creatorMagic.hasAnyRole(address(gallery), gallery.creatorMagicArtPoolManagerRole()));
        assertFalse(creatorMagic.hasAnyRole(address(gallery), gallery.creatorMagicCreatorRole()));
    }

    function testDeployRunFailsOnWrongChainBeforeBroadcast() public {
        vm.setEnv("BASE_CHAIN_ID", vm.toString(block.chainid + 1));
        DeployClosedLoopGallerySwap deployer = new DeployClosedLoopGallerySwap();

        vm.expectRevert(
            abi.encodeWithSelector(
                DeployClosedLoopGallerySwap.GalleryChainIdMismatch.selector, block.chainid + 1, block.chainid
            )
        );
        deployer.run();
    }

    function testValidationPassesConfiguredGalleryChecks() public {
        ClosedLoopGallerySwap gallery = _deployGallery();

        validator.validateGalleryConfiguration(
            gallery, address(fame), address(fameMirror), address(creatorMagic), feeRecipient, owner, operator
        );
        validator.validateVaultSkipNft(address(fame), address(gallery));
        validator.validateCreatorMagicRoles(gallery, creatorMagic, address(this));
    }

    function testValidationFailsWhenVaultSkipNftEnabled() public {
        ClosedLoopGallerySwap gallery = _deployGallery();
        fame.grantRoles(address(this), FAME_SKIP_MANAGER_ROLE);
        fame.setSkipNftForAccount(address(gallery), true);

        vm.expectRevert(
            abi.encodeWithSelector(ValidateClosedLoopGallerySwapBase.GallerySkipNftEnabled.selector, address(gallery))
        );
        validator.validateVaultSkipNft(address(fame), address(gallery));
    }

    function testValidationFailsWhenCreatorMagicRoleMissing() public {
        ClosedLoopGallerySwap gallery =
            new ClosedLoopGallerySwap(payable(address(fame)), address(creatorMagic), feeRecipient, owner, operator);

        vm.expectRevert(
            abi.encodeWithSelector(
                ValidateClosedLoopGallerySwapBase.GalleryCreatorMagicRoleMissing.selector,
                gallery.creatorMagicBanisherRole()
            )
        );
        validator.validateCreatorMagicRoles(gallery, creatorMagic, address(this));
    }

    function testValidationFailsWhenCreatorMagicRoleTooBroad() public {
        ClosedLoopGallerySwap gallery = _deployGallery();
        creatorMagic.grantRoles(address(gallery), CREATOR_MAGIC_CREATOR_ROLE);

        vm.expectRevert(ValidateClosedLoopGallerySwapBase.GalleryCreatorRoleTooBroad.selector);
        validator.validateCreatorMagicRoles(gallery, creatorMagic, address(this));
    }

    function testValidationFailsWhenOperatorMismatches() public {
        ClosedLoopGallerySwap gallery = _deployGallery();
        address wrongOperator = address(0xBEEF);

        vm.expectRevert(
            abi.encodeWithSelector(ValidateClosedLoopGallerySwapBase.GalleryOperatorMissing.selector, wrongOperator)
        );
        validator.validateGalleryConfiguration(
            gallery, address(fame), address(fameMirror), address(creatorMagic), feeRecipient, owner, wrongOperator
        );
    }

    function _deployGallery() internal returns (ClosedLoopGallerySwap gallery) {
        gallery =
            new ClosedLoopGallerySwap(payable(address(fame)), address(creatorMagic), feeRecipient, owner, operator);
        creatorMagic.grantRoles(address(gallery), gallery.requiredCreatorMagicRoles());
    }
}
