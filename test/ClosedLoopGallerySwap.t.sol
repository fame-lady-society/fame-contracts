// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test} from "forge-std/Test.sol";
import {ClosedLoopGallerySwap} from "../src/ClosedLoopGallerySwap.sol";
import {CreatorArtistMagic} from "../src/CreatorArtistMagic.sol";
import {Fame} from "../src/Fame.sol";
import {FameMirror} from "../src/FameMirror.sol";
import {EchoMetadata} from "./mocks/EchoMetadata.sol";
import {ReentrantGalleryRecipient} from "./mocks/ReentrantGalleryRecipient.sol";

contract ClosedLoopGallerySwapTest is Test {
    uint256 internal constant FAME_RENDERER_ROLE = 1;
    uint256 internal constant FAME_SKIP_MANAGER_ROLE = 8;
    uint256 internal constant CREATOR_MAGIC_SWAP_ROLES = 12;

    address internal owner = address(this);
    address internal operator = address(0x1001);
    address internal buyer = address(0x1002);
    address internal recipient = address(0x1003);
    address internal feeRecipient = address(0x1004);

    EchoMetadata internal childRenderer;
    Fame internal fame;
    FameMirror internal fameMirror;
    CreatorArtistMagic internal creatorMagic;
    ClosedLoopGallerySwap internal gallery;

    function setUp() public {
        _deployCore();
        _deployGallery(owner, operator);
    }

    function testConstructorInitializesVaultAsNonSkipNFT() public view {
        assertFalse(fame.getSkipNFT(address(gallery)));
        assertEq(gallery.owner(), owner);
        assertTrue(gallery.hasAnyRole(operator, gallery.roleOperator()));
        assertEq(gallery.feeRecipient(), feeRecipient);
    }

    function testListRequiresVaultOwnedTokenAndPositivePremium() public {
        uint256 tokenId = _galleryTokenAt(0);
        uint256 premium = fame.unit() / 10;

        vm.prank(operator);
        gallery.list(tokenId, premium);

        (uint96 storedPremium, bool active) = gallery.listings(tokenId);
        assertTrue(active);
        assertEq(storedPremium, premium);

        uint256 zeroPremiumToken = _galleryTokenAt(1);
        vm.expectRevert(ClosedLoopGallerySwap.ZeroPremium.selector);
        vm.prank(operator);
        gallery.list(zeroPremiumToken, 0);

        uint256 notVaultToken = _mintSocietyNFTTo(buyer, fame.unit());
        vm.expectRevert(abi.encodeWithSelector(ClosedLoopGallerySwap.NotVaultOwner.selector, notVaultToken));
        vm.prank(operator);
        gallery.list(notVaultToken, premium);
    }

    function testOperatorCannotUseOwnerOnlyControls() public {
        vm.startPrank(operator);
        vm.expectRevert();
        gallery.setFeeRecipient(address(0xBEEF));
        vm.expectRevert();
        gallery.rescueERC20(address(0xCAFE), recipient, 1);
        vm.stopPrank();
    }

    function testFillPreservesInventoryRecordsPremiumAndClearsListing() public {
        uint256 tokenId = _galleryTokenAt(0);
        uint256 premium = fame.unit() / 10;
        uint256 totalPrice = fame.unit() + premium;
        _list(tokenId, premium);
        _fundAndApprove(buyer, totalPrice);

        uint256 beforeInventory = fameMirror.balanceOf(address(gallery));

        vm.prank(buyer);
        (uint256 reportedBefore, uint256 reportedAfter) = gallery.fill(tokenId, recipient);

        assertEq(reportedBefore, beforeInventory);
        assertGe(reportedAfter, beforeInventory);
        assertEq(fameMirror.ownerOf(tokenId), recipient);
        assertEq(gallery.accruedProtocolFees(), premium);
        (, bool active) = gallery.listings(tokenId);
        assertFalse(active);
    }

    function testFillRevertsWhenVaultSkipNFTWouldDrainInventory() public {
        uint256 tokenId = _galleryTokenAt(0);
        uint256 premium = fame.unit() / 10;
        _list(tokenId, premium);
        _fundAndApprove(buyer, fame.unit() + premium);

        fame.grantRoles(address(this), FAME_SKIP_MANAGER_ROLE);
        fame.setSkipNftForAccount(address(gallery), true);
        assertTrue(fame.getSkipNFT(address(gallery)));

        uint256 beforeInventory = fameMirror.balanceOf(address(gallery));

        vm.expectRevert(
            abi.encodeWithSelector(
                ClosedLoopGallerySwap.InventoryInvariantBroken.selector, beforeInventory, beforeInventory - 1
            )
        );
        vm.prank(buyer);
        gallery.fill(tokenId, recipient);

        assertEq(fameMirror.balanceOf(address(gallery)), beforeInventory);
        assertEq(fameMirror.ownerOf(tokenId), address(gallery));
        (, bool active) = gallery.listings(tokenId);
        assertTrue(active);
    }

    function testFillRejectsUnavailableListedToken() public {
        uint256 tokenId = _galleryTokenAt(0);
        _list(tokenId, fame.unit() / 10);
        vm.prank(address(gallery));
        fameMirror.transferFrom(address(gallery), owner, tokenId);
        _fundAndApprove(buyer, fame.unit() + fame.unit() / 10);

        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(ClosedLoopGallerySwap.NotVaultOwner.selector, tokenId));
        gallery.fill(tokenId, recipient);
    }

    function testRotateToArtPoolUsesCreatorMagicWithoutCreatorRole() public {
        uint256 tokenId = _galleryTokenAt(0);

        vm.prank(operator);
        gallery.rotateToArtPool(tokenId, "gallery-art");

        assertEq(creatorMagic.tokenURI(tokenId), "gallery-art");
    }

    function testRotateToMintPoolUsesUnownedPoolLeg() public {
        uint256 tokenId = _galleryTokenAt(0);
        uint256 mintPoolToken = _findMintPoolToken();
        string memory expectedUri = childRenderer.tokenURI(mintPoolToken);

        vm.prank(operator);
        gallery.rotateToMintPool(tokenId, mintPoolToken);

        assertEq(creatorMagic.tokenURI(tokenId), expectedUri);
    }

    function testRotateToBurnPoolRejectsOwnedPoolLeg() public {
        uint256 tokenId = _galleryTokenAt(0);
        uint256 ownedToken = _galleryTokenAt(1);

        vm.prank(operator);
        vm.expectRevert(CreatorArtistMagic.TokenNotInBurnPool.selector);
        gallery.rotateToBurnPool(tokenId, ownedToken);
    }

    function testBuyerCannotRotateOrReachDirectMetadataUpdate() public {
        uint256 tokenId = _galleryTokenAt(0);

        vm.prank(buyer);
        vm.expectRevert();
        gallery.rotateToArtPool(tokenId, "buyer-art");

        (bool ok,) = address(gallery).call(abi.encodeWithSignature("updateMetadata(uint256,string)", tokenId, "bad"));
        assertFalse(ok);
    }

    function testWithdrawAccruedFeesPreservesInventoryWhenNoMirrorBurnOccurs() public {
        uint256 tokenId = _galleryTokenAt(0);
        uint256 premium = fame.unit() / 10;
        _list(tokenId, premium);
        _fundAndApprove(buyer, fame.unit() + premium);

        vm.prank(buyer);
        gallery.fill(tokenId, recipient);

        uint256 beforeInventory = fameMirror.balanceOf(address(gallery));
        gallery.withdrawAccruedFees(feeRecipient, premium);

        assertEq(gallery.accruedProtocolFees(), 0);
        assertEq(fameMirror.balanceOf(address(gallery)), beforeInventory);
        assertEq(fame.balanceOf(feeRecipient), premium);
    }

    function testWithdrawAccruedFeesRevertsWhenItWouldDrainInventory() public {
        uint256 tokenId = _galleryTokenAt(0);
        uint256 premium = fame.unit();
        _list(tokenId, premium);
        _fundAndApprove(buyer, fame.unit() + premium);

        vm.prank(buyer);
        gallery.fill(tokenId, recipient);

        uint256 beforeInventory = fameMirror.balanceOf(address(gallery));
        vm.expectRevert(
            abi.encodeWithSelector(
                ClosedLoopGallerySwap.InventoryInvariantBroken.selector, beforeInventory, beforeInventory - 1
            )
        );
        gallery.withdrawAccruedFees(feeRecipient, premium);

        assertEq(gallery.accruedProtocolFees(), premium);
        assertEq(fameMirror.balanceOf(address(gallery)), beforeInventory);
    }

    function testSafeSocietyNFTDepositAcceptedAndUnsupportedNFTRejected() public {
        uint256 tokenId = _mintSocietyNFTTo(buyer, fame.unit());

        vm.prank(buyer);
        fameMirror.safeTransferFrom(buyer, address(gallery), tokenId);

        assertEq(fameMirror.ownerOf(tokenId), address(gallery));

        vm.expectRevert(abi.encodeWithSelector(ClosedLoopGallerySwap.UnsupportedNFT.selector, address(this)));
        gallery.onERC721Received(address(this), buyer, tokenId, new bytes(0));
    }

    function testRescueBlocksListedSocietyNFTAndFame() public {
        uint256 tokenId = _galleryTokenAt(0);
        _list(tokenId, fame.unit() / 10);

        vm.expectRevert(abi.encodeWithSelector(ClosedLoopGallerySwap.ListedTokenRescueBlocked.selector, tokenId));
        gallery.rescueERC721(address(fameMirror), owner, tokenId);

        vm.expectRevert(ClosedLoopGallerySwap.FameRescueBlocked.selector);
        gallery.rescueERC20(address(fame), owner, 1);
    }

    function testReentrantOperatorRecipientCannotMutateDuringFill() public {
        ReentrantGalleryRecipient attackingRecipient = new ReentrantGalleryRecipient();
        gallery.grantRoles(address(attackingRecipient), gallery.roleOperator());

        uint256 tokenId = _galleryTokenAt(0);
        _list(tokenId, fame.unit() / 10);
        _fundAndApprove(buyer, fame.unit() + fame.unit() / 10);
        attackingRecipient.configure(
            gallery, ReentrantGalleryRecipient.Attack.List, tokenId, fame.unit() / 5, feeRecipient
        );

        vm.prank(buyer);
        gallery.fill(tokenId, address(attackingRecipient));

        assertFalse(attackingRecipient.attackSucceeded());
        assertGt(attackingRecipient.attackRevertData().length, 0);
    }

    function testReentrantOwnerRecipientCannotChangeFeeRecipientDuringFill() public {
        ReentrantGalleryRecipient ownerRecipient = new ReentrantGalleryRecipient();
        (ClosedLoopGallerySwap ownerGallery, uint256 tokenId, uint256 premium) =
            _prepareOwnerRecipientFill(ownerRecipient);
        ownerRecipient.configure(
            ownerGallery, ReentrantGalleryRecipient.Attack.SetFeeRecipient, tokenId, premium, address(0xBEEF)
        );

        vm.prank(buyer);
        ownerGallery.fill(tokenId, address(ownerRecipient));

        assertFalse(ownerRecipient.attackSucceeded());
        assertEq(ownerGallery.feeRecipient(), feeRecipient);
    }

    function testReentrantOwnerRecipientCannotGrantRolesDuringFill() public {
        ReentrantGalleryRecipient ownerRecipient = new ReentrantGalleryRecipient();
        (ClosedLoopGallerySwap ownerGallery, uint256 tokenId, uint256 premium) =
            _prepareOwnerRecipientFill(ownerRecipient);
        address attemptedOperator = address(0xBEEF);
        ownerRecipient.configure(
            ownerGallery, ReentrantGalleryRecipient.Attack.GrantOperatorRole, tokenId, premium, attemptedOperator
        );

        vm.prank(buyer);
        ownerGallery.fill(tokenId, address(ownerRecipient));

        assertFalse(ownerRecipient.attackSucceeded());
        assertGt(ownerRecipient.attackRevertData().length, 0);
        assertFalse(ownerGallery.hasAnyRole(attemptedOperator, ownerGallery.roleOperator()));
    }

    function testReentrantOwnerRecipientCannotTransferOwnershipDuringFill() public {
        ReentrantGalleryRecipient ownerRecipient = new ReentrantGalleryRecipient();
        (ClosedLoopGallerySwap ownerGallery, uint256 tokenId, uint256 premium) =
            _prepareOwnerRecipientFill(ownerRecipient);
        address attemptedOwner = address(0xBEEF);
        ownerRecipient.configure(
            ownerGallery, ReentrantGalleryRecipient.Attack.TransferOwnership, tokenId, premium, attemptedOwner
        );

        vm.prank(buyer);
        ownerGallery.fill(tokenId, address(ownerRecipient));

        assertFalse(ownerRecipient.attackSucceeded());
        assertGt(ownerRecipient.attackRevertData().length, 0);
        assertEq(ownerGallery.owner(), address(ownerRecipient));
    }

    function testFuzzFillPreservesInventoryForPositivePremium(uint96 premiumSeed) public {
        uint256 premium = 1 + (uint256(premiumSeed) % (fame.unit() - 1));
        uint256 tokenId = _galleryTokenAt(0);
        _list(tokenId, premium);
        _fundAndApprove(buyer, fame.unit() + premium);

        uint256 beforeInventory = fameMirror.balanceOf(address(gallery));

        vm.prank(buyer);
        (, uint256 afterInventory) = gallery.fill(tokenId, recipient);

        assertGe(afterInventory, beforeInventory);
        assertEq(gallery.accruedProtocolFees(), premium);
    }

    function testFuzzListRejectsNonVaultTokens(uint256 tokenSeed, uint96 premiumSeed) public {
        uint256 premium = 1 + (uint256(premiumSeed) % fame.unit());
        uint256 buyerToken = _mintSocietyNFTTo(buyer, fame.unit());
        uint256 tokenId = tokenSeed % 2 == 0 ? buyerToken : _ownedTokenAt(buyer, 0);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(ClosedLoopGallerySwap.NotVaultOwner.selector, tokenId));
        gallery.list(tokenId, premium);
    }

    function _deployCore() internal {
        childRenderer = new EchoMetadata();
        fame = new Fame("Fame Lady Society", "FAME", address(0));
        fameMirror = fame.fameMirror();
        creatorMagic = new CreatorArtistMagic(address(childRenderer), payable(address(fame)), 500);
        fame.grantRoles(address(creatorMagic), FAME_RENDERER_ROLE);
        fame.launchPublic();
    }

    function _deployGallery(address initialOwner, address initialOperator)
        internal
        returns (ClosedLoopGallerySwap deployed)
    {
        deployed = new ClosedLoopGallerySwap(
            payable(address(fame)), address(creatorMagic), feeRecipient, initialOwner, initialOperator
        );
        if (address(gallery) == address(0)) {
            gallery = deployed;
            creatorMagic.grantRoles(address(gallery), CREATOR_MAGIC_SWAP_ROLES);
            fame.transfer(address(gallery), 4 * fame.unit());
        }
    }

    function _list(uint256 tokenId, uint256 premium) internal {
        vm.prank(operator);
        gallery.list(tokenId, premium);
    }

    function _fundAndApprove(address account, uint256 amount) internal {
        _fundAndApproveFor(account, address(gallery), amount);
    }

    function _fundAndApproveFor(address account, address spender, uint256 amount) internal {
        fame.transfer(account, amount);
        vm.prank(account);
        fame.approve(spender, amount);
    }

    function _prepareOwnerRecipientFill(ReentrantGalleryRecipient ownerRecipient)
        internal
        returns (ClosedLoopGallerySwap ownerGallery, uint256 tokenId, uint256 premium)
    {
        ownerGallery = _deployGallery(address(ownerRecipient), operator);
        creatorMagic.grantRoles(address(ownerGallery), CREATOR_MAGIC_SWAP_ROLES);
        fame.transfer(address(ownerGallery), 2 * fame.unit());

        tokenId = _ownedTokenAt(address(ownerGallery), 0);
        premium = fame.unit() / 10;
        vm.prank(operator);
        ownerGallery.list(tokenId, premium);
        _fundAndApproveFor(buyer, address(ownerGallery), fame.unit() + premium);
    }

    function _mintSocietyNFTTo(address account, uint256 amount) internal returns (uint256 tokenId) {
        fame.transfer(account, amount);
        tokenId = _ownedTokenAt(account, fameMirror.balanceOf(account) - 1);
    }

    function _galleryTokenAt(uint256 index) internal view returns (uint256) {
        return _ownedTokenAt(address(gallery), index);
    }

    function _ownedTokenAt(address account, uint256 index) internal view returns (uint256) {
        uint256 seen;
        for (uint256 tokenId = 1; tokenId <= 888; ++tokenId) {
            if (fameMirror.ownerAt(tokenId) == account) {
                if (seen == index) return tokenId;
                ++seen;
            }
        }
        revert("OWNED_TOKEN_NOT_FOUND");
    }

    function _findMintPoolToken() internal view returns (uint256) {
        uint256 start = creatorMagic.getMintPoolStart();
        uint256 end = creatorMagic.getMintPoolEnd();
        for (uint256 tokenId = start; tokenId < end; ++tokenId) {
            if (creatorMagic.isTokenInMintPool(tokenId)) return tokenId;
        }
        revert("MINT_POOL_TOKEN_NOT_FOUND");
    }
}

contract ClosedLoopGallerySwapHandler is Test {
    Fame internal fame;
    FameMirror internal mirror;
    ClosedLoopGallerySwap internal gallery;
    uint256 public immutable initialInventory;

    constructor(Fame fame_, FameMirror mirror_, ClosedLoopGallerySwap gallery_) {
        fame = fame_;
        mirror = mirror_;
        gallery = gallery_;
        initialInventory = mirror.balanceOf(address(gallery));
        fame.approve(address(gallery), type(uint256).max);
    }

    function listVaultToken(uint256 tokenSeed, uint96 premiumSeed) external {
        uint256 tokenId = _vaultToken(tokenSeed);
        (, bool active) = gallery.listings(tokenId);
        if (active) return;

        uint256 premium = 1 + (uint256(premiumSeed) % (fame.unit() - 1));
        try gallery.list(tokenId, premium) {} catch {}
    }

    function fillListedToken(uint256 tokenSeed) external {
        uint256 tokenId = _vaultToken(tokenSeed);
        (uint96 premium, bool active) = gallery.listings(tokenId);
        if (!active) return;

        uint256 total = fame.unit() + uint256(premium);
        if (fame.balanceOf(address(this)) < total) return;

        try gallery.fill(tokenId, address(this)) {} catch {}
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return 0x150b7a02;
    }

    function _vaultToken(uint256 seed) private view returns (uint256) {
        uint256 count = mirror.balanceOf(address(gallery));
        if (count == 0) return 1;
        uint256 index = seed % count;
        uint256 seen;
        for (uint256 tokenId = 1; tokenId <= 888; ++tokenId) {
            if (mirror.ownerAt(tokenId) == address(gallery)) {
                if (seen == index) return tokenId;
                ++seen;
            }
        }
        return 1;
    }
}

contract ClosedLoopGallerySwapInvariantTest is StdInvariant, Test {
    uint256 internal constant FAME_RENDERER_ROLE = 1;
    uint256 internal constant CREATOR_MAGIC_SWAP_ROLES = 12;

    Fame internal fame;
    FameMirror internal fameMirror;
    CreatorArtistMagic internal creatorMagic;
    ClosedLoopGallerySwap internal gallery;
    ClosedLoopGallerySwapHandler internal handler;

    function setUp() public {
        EchoMetadata childRenderer = new EchoMetadata();
        fame = new Fame("Fame Lady Society", "FAME", address(0));
        fameMirror = fame.fameMirror();
        creatorMagic = new CreatorArtistMagic(address(childRenderer), payable(address(fame)), 500);
        fame.grantRoles(address(creatorMagic), FAME_RENDERER_ROLE);
        fame.launchPublic();

        gallery = new ClosedLoopGallerySwap(
            payable(address(fame)), address(creatorMagic), address(0x1004), address(this), address(this)
        );
        creatorMagic.grantRoles(address(gallery), CREATOR_MAGIC_SWAP_ROLES);
        fame.transfer(address(gallery), 6 * fame.unit());

        handler = new ClosedLoopGallerySwapHandler(fame, fameMirror, gallery);
        gallery.grantRoles(address(handler), gallery.roleOperator());
        fame.transfer(address(handler), 100 * fame.unit());

        targetContract(address(handler));
    }

    function invariant_GalleryInventoryNeverDropsBelowInitial() public view {
        assertGe(fameMirror.balanceOf(address(gallery)), handler.initialInventory());
    }
}
