// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {BaseSepoliaTestRenderer} from "../src/BaseSepoliaTestRenderer.sol";
import {ClosedLoopGallerySwap} from "../src/ClosedLoopGallerySwap.sol";
import {CreatorArtistMagic} from "../src/CreatorArtistMagic.sol";
import {Fame} from "../src/Fame.sol";
import {FameMirror} from "../src/FameMirror.sol";
import {SmokeBaseSepoliaGalleryTestStack} from "../script/SmokeBaseSepoliaGalleryTestStack.s.sol";
import {ValidateBaseSepoliaGalleryTestStack} from "../script/ValidateBaseSepoliaGalleryTestStack.s.sol";

abstract contract BaseSepoliaGalleryForkTestBase is Test {
    uint256 internal constant BASE_SEPOLIA_CHAIN_ID = 84532;
    uint256 internal constant FAME_METADATA_ROLE = 1 << 1;

    address internal recipient = address(0xCAFE);

    Fame internal fame;
    FameMirror internal mirror;
    BaseSepoliaTestRenderer internal renderer;
    CreatorArtistMagic internal creatorMagic;
    ClosedLoopGallerySwap internal gallery;
    address internal admin;

    error MissingReleaseGateInput(string name);

    function _selectForkOrSkip() internal {
        string memory rpc = vm.envOr("BASE_SEPOLIA_RPC", string(""));
        if (bytes(rpc).length == 0) {
            if (vm.envOr("BASE_SEPOLIA_REQUIRE_DEPLOYED_STACK", false)) {
                revert MissingReleaseGateInput("BASE_SEPOLIA_RPC");
            }
            vm.skip(true);
            return;
        }
        vm.createSelectFork(rpc);
        assertEq(block.chainid, BASE_SEPOLIA_CHAIN_ID);
    }

    function _exerciseRotationAndFill() internal {
        uint256 premium = fame.unit() / 100;
        (uint256 tokenId, uint256 poolTokenId) =
            new SmokeBaseSepoliaGalleryTestStack().preflight(fame, creatorMagic, gallery, admin, recipient, premium);
        string memory displacedUri = creatorMagic.tokenURI(tokenId);
        string memory selectedUri = creatorMagic.tokenURI(poolTokenId);
        assertNotEq(keccak256(bytes(displacedUri)), keccak256(bytes(selectedUri)));

        vm.prank(admin);
        gallery.rotateToMintPool(tokenId, poolTokenId);
        assertEq(creatorMagic.tokenURI(tokenId), selectedUri);
        assertEq(creatorMagic.tokenURI(poolTokenId), displacedUri);

        uint256 totalPrice = fame.unit() + premium;
        vm.prank(admin);
        gallery.list(tokenId, premium);

        vm.prank(admin);
        fame.approve(address(gallery), totalPrice);

        uint256 inventoryBefore = mirror.balanceOf(address(gallery));
        uint256 feesBefore = gallery.accruedProtocolFees();
        uint256 fameBalanceBefore = fame.balanceOf(address(gallery));
        vm.prank(admin, admin);
        (uint256 reportedBefore, uint256 reportedAfter) = gallery.fill(tokenId, recipient);

        assertEq(reportedBefore, inventoryBefore);
        assertGe(reportedAfter, inventoryBefore);
        assertEq(mirror.balanceOf(address(gallery)), reportedAfter);
        assertEq(mirror.ownerOf(tokenId), recipient);
        assertEq(mirror.ownerOf(poolTokenId), address(gallery));
        assertEq(mirror.tokenURI(tokenId), selectedUri);
        assertEq(mirror.tokenURI(poolTokenId), displacedUri);
        assertEq(gallery.accruedProtocolFees(), feesBefore + premium);
        assertEq(fame.balanceOf(address(gallery)), fameBalanceBefore + premium);
    }
}

contract ClosedLoopGallerySwapPredeployForkBaseSepoliaTest is BaseSepoliaGalleryForkTestBase {
    function setUp() public {
        _selectForkOrSkip();

        fame = Fame(payable(vm.envAddress("BASE_SEPOLIA_FAME_ADDRESS")));
        mirror = FameMirror(payable(vm.envAddress("BASE_SEPOLIA_FAME_NFT_ADDRESS")));
        admin = vm.envAddress("BASE_SEPOLIA_FAME_EXPECTED_ADMIN");

        vm.startPrank(admin, admin);
        renderer = new BaseSepoliaTestRenderer();
        creatorMagic = new CreatorArtistMagic(address(renderer), payable(address(fame)), 500);
        if (!fame.hasAnyRole(admin, FAME_METADATA_ROLE)) fame.grantRoles(admin, FAME_METADATA_ROLE);
        fame.setRenderer(address(creatorMagic));
        gallery = new ClosedLoopGallerySwap(payable(address(fame)), address(creatorMagic), admin, admin, admin);
        creatorMagic.grantRoles(address(gallery), gallery.requiredCreatorMagicRoles());
        fame.transfer(address(gallery), 2 * fame.unit());
        vm.stopPrank();
    }

    function testPredeploymentForkRehearsal() public {
        new ValidateBaseSepoliaGalleryTestStack()
            .validateStack(fame, address(mirror), renderer, creatorMagic, gallery, admin, admin, admin);
        _exerciseRotationAndFill();
    }
}

contract ClosedLoopGallerySwapDeployedForkBaseSepoliaTest is BaseSepoliaGalleryForkTestBase {
    function setUp() public {
        _selectForkOrSkip();

        address rendererAddress = vm.envOr("BASE_SEPOLIA_TEST_RENDERER_ADDRESS", address(0));
        address creatorMagicAddress = vm.envOr("BASE_SEPOLIA_CREATOR_ARTIST_MAGIC_ADDRESS", address(0));
        address galleryAddress = vm.envOr("BASE_SEPOLIA_CLOSED_LOOP_GALLERY_ADDRESS", address(0));
        if (rendererAddress == address(0) || creatorMagicAddress == address(0) || galleryAddress == address(0)) {
            if (vm.envOr("BASE_SEPOLIA_REQUIRE_DEPLOYED_STACK", false)) {
                revert MissingReleaseGateInput("deployed stack addresses");
            }
            vm.skip(true);
            return;
        }

        fame = Fame(payable(vm.envAddress("BASE_SEPOLIA_FAME_ADDRESS")));
        mirror = FameMirror(payable(vm.envAddress("BASE_SEPOLIA_FAME_NFT_ADDRESS")));
        admin = vm.envAddress("BASE_SEPOLIA_FAME_EXPECTED_ADMIN");
        renderer = BaseSepoliaTestRenderer(rendererAddress);
        creatorMagic = CreatorArtistMagic(creatorMagicAddress);
        gallery = ClosedLoopGallerySwap(galleryAddress);

        ValidateBaseSepoliaGalleryTestStack validator = new ValidateBaseSepoliaGalleryTestStack();
        validator.validateCanonicalFame(fame, address(mirror));
        validator.validateStack(fame, address(mirror), renderer, creatorMagic, gallery, admin, admin, admin);
        assertGt(mirror.balanceOf(address(gallery)), 0);
    }

    function testDeployedStackForkGate() public {
        _exerciseRotationAndFill();
    }
}
