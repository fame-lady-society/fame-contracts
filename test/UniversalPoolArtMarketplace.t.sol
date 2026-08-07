// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin5/contracts/token/ERC721/ERC721.sol";
import {Vm} from "forge-std/Vm.sol";
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
    uint256 internal constant FAME_SKIP_MANAGER_ROLE = 1 << 3;

    event AuthorizedCheckoutChanged(address indexed previousCheckout, address indexed newCheckout);
    event ArtworkPurchased(
        address indexed buyer,
        address indexed recipient,
        uint256 indexed shellId,
        UniversalPoolArtMarketplace.FulfillmentPath path,
        uint256 sourceId,
        bytes32 artwork,
        uint256 unitAmount,
        uint256 grossPremiumAmount,
        uint256 inventoryBefore,
        uint256 inventoryAfter
    );

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

    function testConstructorRejectsInvalidFeeOwnerAndFeeRecipient() public {
        uint256 oversized = fame.unit() / 10 + 1;
        vm.expectRevert(
            abi.encodeWithSelector(UniversalPoolArtMarketplace.FeeTooLarge.selector, oversized, fame.unit() / 10)
        );
        _deployMarket(oversized, feeRecipient, owner);

        vm.expectRevert(UniversalPoolArtMarketplace.ZeroAddress.selector);
        _deployMarket(1, feeRecipient, address(0));

        // Non-skip fee recipients are allowed (fee recipient may mint NFTs).
        UniversalPoolArtMarketplace nonSkipMarket = _deployMarket(1, address(0xBEEF), owner);
        assertEq(nonSkipMarket.feeRecipient(), address(0xBEEF));
    }

    function testConstructorRejectsInvalidDependenciesAndStack() public {
        vm.expectRevert(abi.encodeWithSelector(UniversalPoolArtMarketplace.InvalidDependency.selector, address(0)));
        new UniversalPoolArtMarketplace(
            payable(address(0)), address(creatorMagic), 1, 0, feeRecipient, owner, TEST_ACTIVE_PROVIDER_CAP
        );

        vm.expectRevert(abi.encodeWithSelector(UniversalPoolArtMarketplace.InvalidDependency.selector, buyer));
        new UniversalPoolArtMarketplace(
            payable(buyer), address(creatorMagic), 1, 0, feeRecipient, owner, TEST_ACTIVE_PROVIDER_CAP
        );

        Fame otherFame = new Fame("Other", "OTHER", address(0));
        vm.expectRevert(UniversalPoolArtMarketplace.StackMismatch.selector);
        new UniversalPoolArtMarketplace(
            payable(address(otherFame)), address(creatorMagic), 1, 0, feeRecipient, owner, TEST_ACTIVE_PROVIDER_CAP
        );
    }

    function testOwnerUpdatesGlobalConfigurationAndPause() public {
        uint256 updatedPremium = fame.unit() / 10;
        market.setCommunityFee(updatedPremium);
        assertEq(market.premium(), updatedPremium);

        address updatedRecipient = address(0x2001);
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
        market.setCommunityFee(1);
        vm.expectRevert();
        market.setFeeRecipient(feeRecipient);
        vm.expectRevert();
        market.unpause();
        vm.stopPrank();

        market.setCommunityFee(0);
        assertEq(market.communityFee(), 0);

        uint256 oversized = fame.unit() / 10 + 1;
        vm.expectRevert(
            abi.encodeWithSelector(UniversalPoolArtMarketplace.FeeTooLarge.selector, oversized, fame.unit() / 10)
        );
        market.setCommunityFee(oversized);

        market.setFeeRecipient(buyer);
        assertEq(market.feeRecipient(), buyer);

        vm.expectRevert(
            abi.encodeWithSelector(UniversalPoolArtMarketplace.InvalidFeeRecipient.selector, address(market))
        );
        market.setFeeRecipient(address(market));
    }

    function testOwnerConfiguresAuthorizedCheckoutOnlyWhilePaused() public {
        vm.expectEmit(true, true, false, true, address(market));
        emit AuthorizedCheckoutChanged(address(0), address(this));
        market.setAuthorizedCheckout(address(this));
        assertEq(market.authorizedCheckout(), address(this));

        vm.expectEmit(true, true, false, true, address(market));
        emit AuthorizedCheckoutChanged(address(this), address(creatorMagic));
        market.setAuthorizedCheckout(address(creatorMagic));
        assertEq(market.authorizedCheckout(), address(creatorMagic));

        market.setAuthorizedCheckout(address(0));
        assertEq(market.authorizedCheckout(), address(0));

        vm.prank(buyer);
        vm.expectRevert();
        market.setAuthorizedCheckout(address(this));

        vm.expectRevert(abi.encodeWithSelector(UniversalPoolArtMarketplace.InvalidDependency.selector, buyer));
        market.setAuthorizedCheckout(buyer);

        market.unpause();
        vm.expectRevert(UniversalPoolArtMarketplace.MarketNotPaused.selector);
        market.setAuthorizedCheckout(address(this));
    }

    function testSetFeeRecipientRejectsCurrentAuthorizedCheckout() public {
        market.setAuthorizedCheckout(address(this));

        vm.expectRevert(
            abi.encodeWithSelector(UniversalPoolArtMarketplace.CheckoutIsFeeRecipient.selector, address(this))
        );
        market.setFeeRecipient(address(this));

        assertEq(market.authorizedCheckout(), address(this));
        assertEq(market.feeRecipient(), feeRecipient);
    }

    function testSetAuthorizedCheckoutRejectsCurrentFeeRecipientBeforeContractValidation() public {
        vm.expectRevert(
            abi.encodeWithSelector(UniversalPoolArtMarketplace.CheckoutIsFeeRecipient.selector, feeRecipient)
        );
        market.setAuthorizedCheckout(feeRecipient);

        assertEq(market.authorizedCheckout(), address(0));
        assertEq(market.feeRecipient(), feeRecipient);
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

    function testAuthorizedCheckoutPurchaseHeldPullsFromCheckoutAndAttributesBuyer() public {
        uint256 shellId = _seedShells(market, 2);
        bytes32 expectedArtwork = market.artworkHash(shellId);
        uint256 currentPremium = market.premium();
        uint256 checkoutBefore = fame.balanceOf(address(this));
        uint256 buyerBefore = fame.balanceOf(buyer);
        uint256 feeBefore = fame.balanceOf(feeRecipient);

        market.setAuthorizedCheckout(address(this));
        fame.approve(address(market), fame.unit() + currentPremium);
        market.unpause();

        vm.expectEmit(true, true, true, true, address(market));
        emit ArtworkPurchased(
            buyer,
            buyer,
            shellId,
            UniversalPoolArtMarketplace.FulfillmentPath.Held,
            0,
            expectedArtwork,
            fame.unit(),
            currentPremium,
            2,
            2
        );
        market.purchaseHeldFor(buyer, shellId, expectedArtwork, currentPremium, 1);

        assertEq(mirror.ownerOf(shellId), buyer);
        assertEq(fame.balanceOf(address(this)), checkoutBefore - fame.unit() - currentPremium);
        assertEq(fame.balanceOf(buyer), buyerBefore + fame.unit());
        assertEq(fame.balanceOf(feeRecipient), feeBefore + currentPremium);
        assertEq(fame.allowance(address(this), address(market)), 0);
    }

    function testAuthorizedCheckoutPurchaseHeldChargesFeeRecipientBuyerFullPremium() public {
        uint256 shellId = _seedShells(market, 2);
        bytes32 expectedArtwork = market.artworkHash(shellId);
        uint256 currentPremium = market.premium();

        market.setFeeRecipient(buyer);
        market.setAuthorizedCheckout(address(this));
        // Checkout (this) is the FAME payer; buyer is only the attributed purchaser.
        fame.approve(address(market), fame.unit() + currentPremium);
        market.unpause();

        uint256 checkoutBefore = fame.balanceOf(address(this));
        uint256 buyerBefore = fame.balanceOf(buyer);
        market.purchaseHeldFor(buyer, shellId, expectedArtwork, currentPremium, 1);

        assertEq(mirror.ownerOf(shellId), buyer);
        assertEq(fame.balanceOf(address(this)), checkoutBefore - (fame.unit() + currentPremium));
        // Buyer receives the shell (unit-backed); community fee self-pays into buyer as fee recipient.
        assertEq(fame.balanceOf(buyer), buyerBefore + fame.unit() + currentPremium);
        assertEq(fame.allowance(address(this), address(market)), 0);
    }

    function testAuthorizedCheckoutRejectsUnauthorizedCallerBeforePayment() public {
        uint256 shellId = _seedShells(market, 2);
        bytes32 expectedArtwork = market.artworkHash(shellId);
        uint256 currentPremium = market.premium();
        market.setAuthorizedCheckout(address(this));
        market.unpause();

        vm.expectRevert(abi.encodeWithSelector(UniversalPoolArtMarketplace.UnauthorizedCheckout.selector, buyer));
        vm.prank(buyer);
        market.purchaseHeldFor(buyer, shellId, expectedArtwork, currentPremium, 1);

        assertEq(mirror.ownerOf(shellId), address(market));
        assertEq(fame.balanceOf(feeRecipient), 0);
    }

    function testAuthorizedCheckoutRejectsZeroBuyerBeforePayment() public {
        uint256 shellId = _seedShells(market, 2);
        bytes32 expectedArtwork = market.artworkHash(shellId);
        market.setAuthorizedCheckout(address(this));
        market.unpause();
        uint256 currentPremium = market.premium();

        vm.expectRevert(UniversalPoolArtMarketplace.InvalidRecipient.selector);
        market.purchaseHeldFor(address(0), shellId, expectedArtwork, currentPremium, 0);

        assertEq(mirror.ownerOf(shellId), address(market));
        assertEq(fame.balanceOf(feeRecipient), 0);
    }

    function testPurchaseHeldAcceptsLargerAllowanceAndLowerCurrentPremium() public {
        uint256 shellId = _seedShells(market, 2);
        bytes32 expectedArtwork = market.artworkHash(shellId);
        uint256 originalPremium = market.premium();
        uint256 lowerPremium = originalPremium / 2;
        market.setCommunityFee(lowerPremium);
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

    function testPurchaseHeldAllowsFeeRecipientWithoutSkipNFT() public {
        uint256 shellId = _seedShells(market, 2);
        bytes32 expectedArtwork = market.artworkHash(shellId);
        _fundAndApprove(buyer, market, fame.unit() + market.premium());
        market.unpause();

        vm.prank(feeRecipient);
        fame.setSkipNFT(false);
        assertFalse(fame.getSkipNFT(feeRecipient));

        uint256 maxPremium = market.premium();
        uint256 feeBefore = fame.balanceOf(feeRecipient);
        vm.prank(buyer);
        market.purchaseHeld(shellId, expectedArtwork, maxPremium, 0, recipient);

        assertEq(mirror.ownerOf(shellId), recipient);
        assertEq(fame.balanceOf(feeRecipient), feeBefore + maxPremium);
    }

    function testPurchaseHeldChargesFullPremiumWhenBuyerIsFeeRecipient() public {
        uint256 shellId = _seedShells(market, 2);
        bytes32 expectedArtwork = market.artworkHash(shellId);
        market.setFeeRecipient(buyer);
        uint256 maxPremium = market.premium();
        _fundAndApprove(buyer, market, fame.unit() + maxPremium);
        market.unpause();

        uint256 buyerBefore = fame.balanceOf(buyer);
        vm.prank(buyer);
        market.purchaseHeld(shellId, expectedArtwork, maxPremium, 0, recipient);

        assertEq(mirror.ownerOf(shellId), recipient);
        // Unit leaves to market inventory; community fee self-transfers (net zero on that leg).
        // Net: buyer loses unit only when premium is pure community (providerFee == 0).
        assertEq(fame.balanceOf(buyer), buyerBefore - fame.unit());
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

    function testPurchaseHeldInventoryBreakRollsBackEverything() public {
        uint256 shellId = _seedShells(market, 2);
        bytes32 expectedArtwork = market.artworkHash(shellId);
        _fundAndApprove(buyer, market, fame.unit() + market.premium());
        market.unpause();
        fame.grantRoles(address(this), FAME_SKIP_MANAGER_ROLE);
        fame.setSkipNftForAccount(address(market), true);

        uint256 buyerBefore = fame.balanceOf(buyer);
        uint256 feeBefore = fame.balanceOf(feeRecipient);
        uint256 marketFameBefore = fame.balanceOf(address(market));
        uint256 allowanceBefore = fame.allowance(buyer, address(market));
        uint256 maxPremium = market.premium();
        vm.expectRevert(
            abi.encodeWithSelector(
                UniversalPoolArtMarketplace.InventoryInvariantBroken.selector, uint256(2), uint256(1)
            )
        );
        vm.prank(buyer);
        market.purchaseHeld(shellId, expectedArtwork, maxPremium, 0, recipient);

        assertEq(fame.balanceOf(buyer), buyerBefore);
        assertEq(fame.balanceOf(feeRecipient), feeBefore);
        assertEq(fame.balanceOf(address(market)), marketFameBefore);
        assertEq(fame.allowance(buyer, address(market)), allowanceBefore);
        assertEq(market.inventory(), 2);
        assertEq(mirror.ownerOf(shellId), address(market));
        assertEq(market.artworkHash(shellId), expectedArtwork);
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
        assertEq(
            bytes4(ownerRecipient.attemptedActionRevertData()),
            UniversalPoolArtMarketplace.SettlementInProgress.selector
        );
        assertEq(ownedMarket.premium(), market.premium());
    }

    function testPurchaseHeldBlocksAuthorizedCheckoutMutationDuringCallback() public {
        ReentrantUniversalPoolMarketplaceRecipient ownerRecipient = new ReentrantUniversalPoolMarketplaceRecipient();
        UniversalPoolArtMarketplace ownedMarket = _deployMarket(market.premium(), feeRecipient, address(ownerRecipient));
        uint256 shellId = _seedShells(ownedMarket, 2);
        bytes32 expectedArtwork = ownedMarket.artworkHash(shellId);
        ownerRecipient.configure(
            ownedMarket,
            ReentrantUniversalPoolMarketplaceRecipient.Action.SetAuthorizedCheckout,
            address(creatorMagic),
            expectedArtwork
        );
        vm.prank(address(ownerRecipient));
        ownedMarket.setAuthorizedCheckout(address(this));
        vm.prank(address(ownerRecipient));
        ownedMarket.unpause();
        _fundAndApprove(buyer, ownedMarket, fame.unit() + ownedMarket.premium());
        uint256 currentPremium = ownedMarket.premium();

        vm.prank(buyer);
        ownedMarket.purchaseHeld(shellId, expectedArtwork, currentPremium, 0, address(ownerRecipient));

        assertFalse(ownerRecipient.attemptedActionSucceeded());
        assertEq(
            bytes4(ownerRecipient.attemptedActionRevertData()),
            UniversalPoolArtMarketplace.SettlementInProgress.selector
        );
        assertEq(ownedMarket.authorizedCheckout(), address(this));
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
        assertEq(
            bytes4(ownerRecipient.attemptedActionRevertData()),
            UniversalPoolArtMarketplace.SettlementInProgress.selector
        );
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
        // Solady ReentrancyGuard custom error selector
        assertEq(bytes4(reentrantRecipient.attemptedActionRevertData()), bytes4(0xab143c06));
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

    function testAuthorizedCheckoutPurchasePoolUsesTypedPoolPath() public {
        uint256 shellId = _seedShells(market, 2);
        uint256 sourceId = _findMintPoolToken();
        bytes32 selectedArtwork = market.artworkHash(sourceId);
        bytes32 displacedArtwork = market.artworkHash(shellId);
        uint256 currentPremium = market.premium();

        market.setAuthorizedCheckout(address(this));
        fame.approve(address(market), fame.unit() + currentPremium);
        _enablePoolPurchases(market);

        market.purchasePoolFor(buyer, shellId, sourceId, selectedArtwork, currentPremium, 1);

        assertEq(mirror.ownerOf(shellId), buyer);
        assertEq(market.artworkHash(shellId), selectedArtwork);
        assertEq(market.artworkHash(sourceId), displacedArtwork);
        assertEq(fame.allowance(address(this), address(market)), 0);
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

    function testPurchasePoolInventoryBreakRollsBackPaymentMetadataAndCustody() public {
        uint256 shellId = _seedShells(market, 2);
        uint256 sourceId = _findMintPoolToken();
        bytes32 selectedArtwork = market.artworkHash(sourceId);
        bytes32 displacedArtwork = market.artworkHash(shellId);
        vm.prank(buyer);
        fame.setSkipNFT(true);
        _fundAndApprove(buyer, market, fame.unit() + market.premium());
        _enablePoolPurchases(market);
        fame.grantRoles(address(this), FAME_SKIP_MANAGER_ROLE);
        fame.setSkipNftForAccount(address(market), true);

        uint256 buyerBefore = fame.balanceOf(buyer);
        uint256 feeBefore = fame.balanceOf(feeRecipient);
        uint256 marketFameBefore = fame.balanceOf(address(market));
        uint256 allowanceBefore = fame.allowance(buyer, address(market));
        uint256 maxPremium = market.premium();
        vm.expectRevert(
            abi.encodeWithSelector(
                UniversalPoolArtMarketplace.InventoryInvariantBroken.selector, uint256(2), uint256(1)
            )
        );
        vm.prank(buyer);
        market.purchasePool(shellId, sourceId, selectedArtwork, maxPremium, 0, recipient);

        assertEq(fame.balanceOf(buyer), buyerBefore);
        assertEq(fame.balanceOf(feeRecipient), feeBefore);
        assertEq(fame.balanceOf(address(market)), marketFameBefore);
        assertEq(fame.allowance(buyer, address(market)), allowanceBefore);
        assertEq(market.inventory(), 2);
        assertEq(mirror.ownerOf(shellId), address(market));
        assertEq(market.artworkHash(shellId), displacedArtwork);
        assertEq(market.artworkHash(sourceId), selectedArtwork);
        assertTrue(creatorMagic.isTokenInMintPool(sourceId));
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
