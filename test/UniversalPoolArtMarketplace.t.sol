// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin5/contracts/token/ERC721/ERC721.sol";
import {UniversalPoolArtMarketplace} from "../src/UniversalPoolArtMarketplace.sol";
import {Fame} from "../src/Fame.sol";
import {UniversalPoolArtMarketplaceTestBase} from "./helpers/UniversalPoolArtMarketplaceTestBase.sol";
import {ReentrantUniversalPoolMarketplaceRecipient} from "./mocks/ReentrantUniversalPoolMarketplaceRecipient.sol";
import {MockERC20} from "./router/mocks/MockERC20.sol";

contract MarketplaceMockERC721 is ERC721 {
    constructor() ERC721("Unrelated", "OTHER") {}

    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }
}

contract UniversalPoolArtMarketplaceTest is UniversalPoolArtMarketplaceTestBase {
    function testConstructorInitializesPausedCanonicalMarket() public view {
        assertEq(address(market.fame()), address(fame));
        assertEq(address(market.mirror()), address(mirror));
        assertEq(address(market.creatorMagic()), address(creatorMagic));
        assertEq(market.owner(), owner);
        assertEq(market.premium(), fame.unit() / 10);
        assertEq(market.feeRecipient(), feeRecipient);
        assertTrue(market.paused());
        assertFalse(fame.getSkipNFT(address(market)));
        assertEq(market.inventory(), 0);
        assertEq(market.artworkHash(7), keccak256(bytes(creatorMagic.tokenURI(7))));
    }

    function testConstructorRejectsInvalidPremiumOwnerAndFeeRecipient() public {
        vm.expectRevert(UniversalPoolArtMarketplace.ZeroPremium.selector);
        _deployMarket(0, feeRecipient, owner);

        uint256 oversized = uint256(type(uint96).max) + 1;
        vm.expectRevert(abi.encodeWithSelector(UniversalPoolArtMarketplace.PremiumTooLarge.selector, oversized));
        _deployMarket(oversized, feeRecipient, owner);

        vm.expectRevert(UniversalPoolArtMarketplace.ZeroAddress.selector);
        _deployMarket(1, feeRecipient, address(0));

        address nonSkip = address(0xBEEF);
        vm.expectRevert(
            abi.encodeWithSelector(UniversalPoolArtMarketplace.FeeRecipientNotSkippingNFT.selector, nonSkip)
        );
        _deployMarket(1, nonSkip, owner);
    }

    function testConstructorRejectsInvalidDependenciesAndStack() public {
        vm.expectRevert(abi.encodeWithSelector(UniversalPoolArtMarketplace.InvalidDependency.selector, address(0)));
        new UniversalPoolArtMarketplace(payable(address(0)), address(creatorMagic), 1, feeRecipient, owner);

        vm.expectRevert(abi.encodeWithSelector(UniversalPoolArtMarketplace.InvalidDependency.selector, buyer));
        new UniversalPoolArtMarketplace(payable(buyer), address(creatorMagic), 1, feeRecipient, owner);

        Fame otherFame = new Fame("Other", "OTHER", address(0));
        vm.expectRevert(UniversalPoolArtMarketplace.StackMismatch.selector);
        new UniversalPoolArtMarketplace(payable(address(otherFame)), address(creatorMagic), 1, feeRecipient, owner);
    }

    function testOwnerUpdatesGlobalConfigurationAndPause() public {
        uint256 updatedPremium = fame.unit() / 5;
        market.setPremium(updatedPremium);
        assertEq(market.premium(), updatedPremium);

        address updatedRecipient = address(0x2001);
        vm.prank(updatedRecipient);
        fame.setSkipNFT(true);
        market.setFeeRecipient(updatedRecipient);
        assertEq(market.feeRecipient(), updatedRecipient);

        market.unpause();
        assertFalse(market.paused());
        market.pause();
        assertTrue(market.paused());
    }

    function testOwnerUpdatesRejectInvalidValuesAndUnauthorizedCaller() public {
        vm.startPrank(buyer);
        vm.expectRevert();
        market.setPremium(1);
        vm.expectRevert();
        market.setFeeRecipient(feeRecipient);
        vm.expectRevert();
        market.unpause();
        vm.stopPrank();

        vm.expectRevert(UniversalPoolArtMarketplace.ZeroPremium.selector);
        market.setPremium(0);

        uint256 oversized = uint256(type(uint96).max) + 1;
        vm.expectRevert(abi.encodeWithSelector(UniversalPoolArtMarketplace.PremiumTooLarge.selector, oversized));
        market.setPremium(oversized);

        vm.expectRevert(abi.encodeWithSelector(UniversalPoolArtMarketplace.FeeRecipientNotSkippingNFT.selector, buyer));
        market.setFeeRecipient(buyer);

        vm.expectRevert(
            abi.encodeWithSelector(UniversalPoolArtMarketplace.InvalidFeeRecipient.selector, address(market))
        );
        market.setFeeRecipient(address(market));
    }

    function testOwnershipTransferAndHandoverWorkButRenunciationIsDisabled() public {
        address nextOwner = address(0x3001);
        market.transferOwnership(nextOwner);
        assertEq(market.owner(), nextOwner);

        vm.prank(nextOwner);
        vm.expectRevert(UniversalPoolArtMarketplace.OwnershipRenunciationDisabled.selector);
        market.renounceOwnership();

        address pendingOwner = address(0x3002);
        vm.prank(pendingOwner);
        market.requestOwnershipHandover();
        vm.prank(nextOwner);
        market.completeOwnershipHandover(pendingOwner);
        assertEq(market.owner(), pendingOwner);
    }

    function testCanonicalSocietyShellReceiptAndUnrelatedReceiverRejection() public {
        fame.transfer(buyer, fame.unit());
        uint256 shellId = _ownedTokenAt(buyer, 0);

        vm.prank(buyer);
        mirror.safeTransferFrom(buyer, address(market), shellId);
        assertEq(mirror.ownerOf(shellId), address(market));
        assertEq(market.inventory(), 1);

        vm.expectRevert(abi.encodeWithSelector(UniversalPoolArtMarketplace.UnsupportedNFT.selector, address(this)));
        market.onERC721Received(address(this), buyer, shellId, "");
    }

    function testPausedRecoveryOnlyAllowsUnrelatedAssets() public {
        MockERC20 token = new MockERC20("Other", "OTHER", 18);
        token.mint(address(market), 10 ether);
        market.rescueERC20(address(token), recipient, 10 ether);
        assertEq(token.balanceOf(recipient), 10 ether);

        MarketplaceMockERC721 nft = new MarketplaceMockERC721();
        nft.mint(address(market), 7);
        market.rescueERC721(address(nft), recipient, 7);
        assertEq(nft.ownerOf(7), recipient);

        vm.expectRevert(UniversalPoolArtMarketplace.CoreAssetRescueBlocked.selector);
        market.rescueERC20(address(fame), recipient, 1);
        vm.expectRevert(UniversalPoolArtMarketplace.CoreAssetRescueBlocked.selector);
        market.rescueERC721(address(mirror), recipient, 1);

        market.unpause();
        vm.expectRevert(UniversalPoolArtMarketplace.MarketNotPaused.selector);
        market.rescueERC20(address(token), recipient, 0);
    }

    function testPurchaseHeldSplitsPaymentHandsOffExactArtAndPreservesInventory() public {
        uint256 shellId = _seedShells(market, 2);
        bytes32 expectedArtwork = market.artworkHash(shellId);
        uint256 unit = fame.unit();
        uint256 currentPremium = market.premium();
        _fundAndApprove(buyer, market, unit + currentPremium);
        market.unpause();

        uint256 feeBefore = fame.balanceOf(feeRecipient);
        uint256 marketFameBefore = fame.balanceOf(address(market));
        uint256 inventoryBefore = market.inventory();

        vm.prank(buyer);
        (uint256 reportedBefore, uint256 reportedAfter) =
            market.purchaseHeld(shellId, expectedArtwork, currentPremium, 0, recipient);

        assertEq(reportedBefore, inventoryBefore);
        assertEq(reportedAfter, market.inventory());
        assertGe(reportedAfter, inventoryBefore);
        assertEq(fame.balanceOf(feeRecipient) - feeBefore, currentPremium);
        assertEq(fame.balanceOf(address(market)), marketFameBefore);
        assertEq(mirror.ownerOf(shellId), recipient);
        assertEq(market.artworkHash(shellId), expectedArtwork);
    }

    function testPurchaseHeldAcceptsLargerAllowanceAndLowerCurrentPremium() public {
        uint256 shellId = _seedShells(market, 2);
        bytes32 expectedArtwork = market.artworkHash(shellId);
        uint256 originalPremium = market.premium();
        uint256 lowerPremium = originalPremium / 2;
        market.setPremium(lowerPremium);
        _fundAndApprove(buyer, market, 3 * fame.unit());
        market.unpause();

        vm.prank(buyer);
        market.purchaseHeld(shellId, expectedArtwork, originalPremium, 0, recipient);

        assertEq(fame.balanceOf(feeRecipient), lowerPremium);
        assertEq(mirror.ownerOf(shellId), recipient);
    }

    function testPurchaseHeldRejectsHigherPremiumBeforePayment() public {
        uint256 shellId = _seedShells(market, 2);
        bytes32 expectedArtwork = market.artworkHash(shellId);
        uint256 currentPremium = market.premium();
        _fundAndApprove(buyer, market, fame.unit() + currentPremium);
        market.unpause();

        uint256 buyerBefore = fame.balanceOf(buyer);
        uint256 feeBefore = fame.balanceOf(feeRecipient);
        vm.expectRevert(
            abi.encodeWithSelector(
                UniversalPoolArtMarketplace.PremiumExceedsMaximum.selector, currentPremium, currentPremium - 1
            )
        );
        vm.prank(buyer);
        market.purchaseHeld(shellId, expectedArtwork, currentPremium - 1, 0, recipient);

        assertEq(fame.balanceOf(buyer), buyerBefore);
        assertEq(fame.balanceOf(feeRecipient), feeBefore);
        assertEq(mirror.ownerOf(shellId), address(market));
    }

    function testPurchaseHeldRejectsFeeRecipientPostureDriftBeforePayment() public {
        uint256 shellId = _seedShells(market, 2);
        bytes32 expectedArtwork = market.artworkHash(shellId);
        _fundAndApprove(buyer, market, fame.unit() + market.premium());
        market.unpause();

        vm.prank(feeRecipient);
        fame.setSkipNFT(false);

        uint256 maxPremium = market.premium();
        vm.expectRevert(
            abi.encodeWithSelector(UniversalPoolArtMarketplace.FeeRecipientNotSkippingNFT.selector, feeRecipient)
        );
        vm.prank(buyer);
        market.purchaseHeld(shellId, expectedArtwork, maxPremium, 0, recipient);
    }

    function testPurchaseHeldSkipsPremiumSelfTransferWhenBuyerIsFeeRecipient() public {
        uint256 shellId = _seedShells(market, 2);
        bytes32 expectedArtwork = market.artworkHash(shellId);
        vm.prank(buyer);
        fame.setSkipNFT(true);
        market.setFeeRecipient(buyer);
        _fundAndApprove(buyer, market, fame.unit());
        market.unpause();

        uint256 maxPremium = market.premium();
        vm.prank(buyer);
        market.purchaseHeld(shellId, expectedArtwork, maxPremium, 0, recipient);

        assertEq(mirror.ownerOf(shellId), recipient);
        assertEq(fame.allowance(buyer, address(market)), 0);
    }

    function testPurchaseHeldBuyerMirrorMinimumRollsBackEverything() public {
        uint256 shellId = _seedShells(market, 2);
        bytes32 expectedArtwork = market.artworkHash(shellId);
        _fundAndApprove(buyer, market, fame.unit() + market.premium());
        market.unpause();

        uint256 inventoryBefore = market.inventory();
        uint256 feeBefore = fame.balanceOf(feeRecipient);
        uint256 buyerBefore = fame.balanceOf(buyer);
        uint256 maxPremium = market.premium();
        vm.expectRevert(abi.encodeWithSelector(UniversalPoolArtMarketplace.BuyerMirrorBalanceTooLow.selector, 1, 0));
        vm.prank(buyer);
        market.purchaseHeld(shellId, expectedArtwork, maxPremium, 1, recipient);

        assertEq(market.inventory(), inventoryBefore);
        assertEq(fame.balanceOf(feeRecipient), feeBefore);
        assertEq(fame.balanceOf(buyer), buyerBefore);
        assertEq(mirror.ownerOf(shellId), address(market));
    }

    function testPurchaseHeldRejectsPausedUnavailableAndStaleArtwork() public {
        uint256 shellId = _seedShells(market, 2);
        bytes32 expectedArtwork = market.artworkHash(shellId);
        _fundAndApprove(buyer, market, fame.unit() + market.premium());
        uint256 maxPremium = market.premium();

        vm.expectRevert(UniversalPoolArtMarketplace.PurchasesPaused.selector);
        vm.prank(buyer);
        market.purchaseHeld(shellId, expectedArtwork, maxPremium, 0, recipient);

        market.unpause();
        vm.expectRevert(
            abi.encodeWithSelector(
                UniversalPoolArtMarketplace.ArtworkMismatch.selector, shellId, bytes32(uint256(1)), expectedArtwork
            )
        );
        vm.prank(buyer);
        market.purchaseHeld(shellId, bytes32(uint256(1)), maxPremium, 0, recipient);

        vm.expectRevert(abi.encodeWithSelector(UniversalPoolArtMarketplace.UnavailableShell.selector, 888));
        vm.prank(buyer);
        market.purchaseHeld(888, expectedArtwork, maxPremium, 0, recipient);
    }

    function testPurchaseHeldAllowsRecipientForwardingAtHandoff() public {
        ReentrantUniversalPoolMarketplaceRecipient forwardingRecipient =
            new ReentrantUniversalPoolMarketplaceRecipient();
        uint256 shellId = _seedShells(market, 2);
        bytes32 expectedArtwork = market.artworkHash(shellId);
        forwardingRecipient.configure(
            market, ReentrantUniversalPoolMarketplaceRecipient.Action.Forward, recipient, expectedArtwork
        );
        _fundAndApprove(buyer, market, fame.unit() + market.premium());
        market.unpause();

        uint256 maxPremium = market.premium();
        vm.prank(buyer);
        market.purchaseHeld(shellId, expectedArtwork, maxPremium, 0, address(forwardingRecipient));

        assertEq(forwardingRecipient.observedTokenId(), shellId);
        assertEq(forwardingRecipient.observedArtworkHash(), expectedArtwork);
        assertEq(mirror.ownerOf(shellId), recipient);
    }

    function testPurchaseHeldBlocksPremiumMutationDuringCallback() public {
        ReentrantUniversalPoolMarketplaceRecipient ownerRecipient = new ReentrantUniversalPoolMarketplaceRecipient();
        UniversalPoolArtMarketplace ownedMarket = _deployMarket(market.premium(), feeRecipient, address(ownerRecipient));
        uint256 shellId = _seedShells(ownedMarket, 2);
        bytes32 expectedArtwork = ownedMarket.artworkHash(shellId);
        ownerRecipient.configure(
            ownedMarket, ReentrantUniversalPoolMarketplaceRecipient.Action.SetPremium, recipient, expectedArtwork
        );
        vm.prank(address(ownerRecipient));
        ownedMarket.unpause();
        _fundAndApprove(buyer, ownedMarket, fame.unit() + ownedMarket.premium());

        uint256 maxPremium = ownedMarket.premium();
        vm.prank(buyer);
        ownedMarket.purchaseHeld(shellId, expectedArtwork, maxPremium, 0, address(ownerRecipient));

        assertFalse(ownerRecipient.attemptedActionSucceeded());
        assertGt(ownerRecipient.attemptedActionRevertData().length, 0);
        assertEq(ownedMarket.premium(), market.premium());
    }

    function testPurchaseHeldBlocksOwnershipTransferDuringCallback() public {
        ReentrantUniversalPoolMarketplaceRecipient ownerRecipient = new ReentrantUniversalPoolMarketplaceRecipient();
        UniversalPoolArtMarketplace ownedMarket = _deployMarket(market.premium(), feeRecipient, address(ownerRecipient));
        uint256 shellId = _seedShells(ownedMarket, 2);
        bytes32 expectedArtwork = ownedMarket.artworkHash(shellId);
        ownerRecipient.configure(
            ownedMarket, ReentrantUniversalPoolMarketplaceRecipient.Action.TransferOwnership, recipient, expectedArtwork
        );
        vm.prank(address(ownerRecipient));
        ownedMarket.unpause();
        _fundAndApprove(buyer, ownedMarket, fame.unit() + ownedMarket.premium());

        uint256 maxPremium = ownedMarket.premium();
        vm.prank(buyer);
        ownedMarket.purchaseHeld(shellId, expectedArtwork, maxPremium, 0, address(ownerRecipient));

        assertFalse(ownerRecipient.attemptedActionSucceeded());
        assertGt(ownerRecipient.attemptedActionRevertData().length, 0);
        assertEq(ownedMarket.owner(), address(ownerRecipient));
    }

    function testPurchaseHeldBlocksPurchaseReentryDuringCallback() public {
        ReentrantUniversalPoolMarketplaceRecipient reentrantRecipient = new ReentrantUniversalPoolMarketplaceRecipient();
        uint256 shellId = _seedShells(market, 2);
        bytes32 expectedArtwork = market.artworkHash(shellId);
        reentrantRecipient.configure(
            market, ReentrantUniversalPoolMarketplaceRecipient.Action.ReenterPurchase, address(0), expectedArtwork
        );
        _fundAndApprove(buyer, market, fame.unit() + market.premium());
        market.unpause();

        uint256 maxPremium = market.premium();
        vm.prank(buyer);
        market.purchaseHeld(shellId, expectedArtwork, maxPremium, 0, address(reentrantRecipient));

        assertFalse(reentrantRecipient.attemptedActionSucceeded());
        assertGt(reentrantRecipient.attemptedActionRevertData().length, 0);
        assertEq(mirror.ownerOf(shellId), address(reentrantRecipient));
    }

    function testPurchaseHeldRejectingReceiverRollsBack() public {
        ReentrantUniversalPoolMarketplaceRecipient rejectingRecipient = new ReentrantUniversalPoolMarketplaceRecipient();
        uint256 shellId = _seedShells(market, 2);
        bytes32 expectedArtwork = market.artworkHash(shellId);
        rejectingRecipient.configure(
            market, ReentrantUniversalPoolMarketplaceRecipient.Action.Reject, address(0), expectedArtwork
        );
        _fundAndApprove(buyer, market, fame.unit() + market.premium());
        market.unpause();

        uint256 feeBefore = fame.balanceOf(feeRecipient);
        uint256 maxPremium = market.premium();
        vm.expectRevert();
        vm.prank(buyer);
        market.purchaseHeld(shellId, expectedArtwork, maxPremium, 0, address(rejectingRecipient));

        assertEq(fame.balanceOf(feeRecipient), feeBefore);
        assertEq(mirror.ownerOf(shellId), address(market));
    }

    function testPurchaseHeldFailsClosedOnRendererDriftBeforePayment() public {
        uint256 shellId = _seedShells(market, 2);
        bytes32 expectedArtwork = market.artworkHash(shellId);
        _fundAndApprove(buyer, market, fame.unit() + market.premium());
        market.unpause();
        fame.setRenderer(address(childRenderer));

        uint256 maxPremium = market.premium();
        vm.expectRevert(UniversalPoolArtMarketplace.StackMismatch.selector);
        vm.prank(buyer);
        market.purchaseHeld(shellId, expectedArtwork, maxPremium, 0, recipient);
    }

    function testPurchasePoolMaterializesMintArtworkAndPreservesDisplacedArt() public {
        uint256 shellId = _seedShells(market, 2);
        _fundAndApprove(buyer, market, fame.unit() + market.premium());
        uint256 sourceId = _findMintPoolToken();
        bytes32 selectedArtwork = market.artworkHash(sourceId);
        bytes32 displacedArtwork = market.artworkHash(shellId);
        _enablePoolPurchases(market);

        uint256 inventoryBefore = market.inventory();
        uint256 maxPremium = market.premium();
        vm.prank(buyer);
        market.purchasePool(shellId, sourceId, selectedArtwork, maxPremium, 0, recipient);

        assertEq(mirror.ownerOf(shellId), recipient);
        assertEq(market.artworkHash(shellId), selectedArtwork);
        assertEq(market.artworkHash(sourceId), displacedArtwork);
        assertGe(market.inventory(), inventoryBefore);
    }

    function testPurchasePoolMaterializesBurnArtwork() public {
        (uint256 shellId, uint256 sourceId) = _prepareBurnPoolPurchase();
        bytes32 selectedArtwork = market.artworkHash(sourceId);
        bytes32 displacedArtwork = market.artworkHash(shellId);
        _enablePoolPurchases(market);

        uint256 maxPremium = market.premium();
        vm.prank(buyer);
        market.purchasePool(shellId, sourceId, selectedArtwork, maxPremium, 0, recipient);

        assertEq(mirror.ownerOf(shellId), recipient);
        assertEq(market.artworkHash(shellId), selectedArtwork);
        assertEq(market.artworkHash(sourceId), displacedArtwork);
    }

    function testPurchasePoolRejectsArtPoolAndEndOfMintBeforePayment() public {
        uint256 shellId = _seedShells(market, 2);
        _fundAndApprove(buyer, market, fame.unit() + market.premium());
        _enablePoolPurchases(market);
        uint256 feeBefore = fame.balanceOf(feeRecipient);
        uint256 maxPremium = market.premium();

        uint256 artPoolSource = creatorMagic.artPoolStartIndex();
        bytes32 artPoolArtwork = market.artworkHash(artPoolSource);
        vm.expectRevert(
            abi.encodeWithSelector(UniversalPoolArtMarketplace.ArtPoolSourceExcluded.selector, artPoolSource)
        );
        vm.prank(buyer);
        market.purchasePool(shellId, artPoolSource, artPoolArtwork, maxPremium, 0, recipient);

        uint256 endOfMintSource = creatorMagic.getMintPoolEnd();
        bytes32 endOfMintArtwork = market.artworkHash(endOfMintSource);
        vm.expectRevert(
            abi.encodeWithSelector(UniversalPoolArtMarketplace.IneligiblePoolSource.selector, endOfMintSource)
        );
        vm.prank(buyer);
        market.purchasePool(shellId, endOfMintSource, endOfMintArtwork, maxPremium, 0, recipient);

        assertEq(fame.balanceOf(feeRecipient), feeBefore);
    }

    function testPurchasePoolRejectsShellAsSourceAndCollectorOwnedSource() public {
        uint256 shellId = _seedShells(market, 2);
        _fundAndApprove(buyer, market, fame.unit() + market.premium());
        _enablePoolPurchases(market);
        uint256 maxPremium = market.premium();

        bytes32 shellArtwork = market.artworkHash(shellId);
        vm.expectRevert(abi.encodeWithSelector(UniversalPoolArtMarketplace.SourceEqualsShell.selector, shellId));
        vm.prank(buyer);
        market.purchasePool(shellId, shellId, shellArtwork, maxPremium, 0, recipient);

        uint256 collectorToken = _ownedTokenAt(buyer, 0);
        bytes32 collectorArtwork = market.artworkHash(collectorToken);
        vm.expectRevert(
            abi.encodeWithSelector(UniversalPoolArtMarketplace.IneligiblePoolSource.selector, collectorToken)
        );
        vm.prank(buyer);
        market.purchasePool(shellId, collectorToken, collectorArtwork, maxPremium, 0, recipient);
    }

    function testPurchasePoolStaleArtworkRollsBackWithoutPayment() public {
        uint256 shellId = _seedShells(market, 2);
        _fundAndApprove(buyer, market, fame.unit() + market.premium());
        uint256 sourceId = _findMintPoolToken();
        bytes32 actualArtwork = market.artworkHash(sourceId);
        bytes32 staleArtwork = bytes32(uint256(actualArtwork) ^ 1);
        _enablePoolPurchases(market);

        uint256 feeBefore = fame.balanceOf(feeRecipient);
        uint256 maxPremium = market.premium();
        vm.expectRevert(
            abi.encodeWithSelector(
                UniversalPoolArtMarketplace.ArtworkMismatch.selector, sourceId, staleArtwork, actualArtwork
            )
        );
        vm.prank(buyer);
        market.purchasePool(shellId, sourceId, staleArtwork, maxPremium, 0, recipient);

        assertEq(fame.balanceOf(feeRecipient), feeBefore);
        assertEq(mirror.ownerOf(shellId), address(market));
    }

    function testPurchasePoolSourceAcquiredBeforeCallMovesNoPayment() public {
        uint256 shellId = _seedShells(market, 2);
        _fundAndApprove(buyer, market, fame.unit() + market.premium());
        uint256 sourceId = _findMintPoolToken();
        bytes32 selectedArtwork = market.artworkHash(sourceId);
        _enablePoolPurchases(market);

        fame.transfer(recipient, fame.unit());
        assertEq(mirror.ownerAt(sourceId), recipient);

        uint256 feeBefore = fame.balanceOf(feeRecipient);
        uint256 maxPremium = market.premium();
        vm.expectRevert(abi.encodeWithSelector(UniversalPoolArtMarketplace.IneligiblePoolSource.selector, sourceId));
        vm.prank(buyer);
        market.purchasePool(shellId, sourceId, selectedArtwork, maxPremium, 0, recipient);

        assertEq(fame.balanceOf(feeRecipient), feeBefore);
        assertEq(mirror.ownerOf(shellId), address(market));
    }
}
