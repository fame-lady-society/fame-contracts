// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {UniversalPoolArtMarketplace} from "../src/UniversalPoolArtMarketplace.sol";
import {UniversalPoolArtMarketplaceTestBase} from "./helpers/UniversalPoolArtMarketplaceTestBase.sol";

contract UniversalPoolArtMarketplaceFuzzTest is UniversalPoolArtMarketplaceTestBase {
    struct HeldPurchaseCase {
        address payer;
        address destination;
        uint256 shellId;
        uint256 premium;
        uint256 maximumPremium;
        uint256 minimumBuyerMirrorBalance;
        bytes32 artwork;
        bool payerIsFeeRecipient;
    }

    struct StateSnapshot {
        uint256 payerFame;
        uint256 feeFame;
        uint256 marketFame;
        uint256 payerMirrorBalance;
        uint256 recipientMirrorBalance;
        uint256 marketMirrorBalance;
        uint256 premium;
        address feeRecipient;
        address owner;
        address shellOwner;
        address sourceOwner;
        bytes32 shellArtwork;
        bytes32 sourceArtwork;
        bool paused;
    }

    function testFuzzBatchDepositCreditsExactLength(uint8 rawCount, bool alreadyActive) public {
        uint256 count = bound(uint256(rawCount), 1, market.MAX_INVENTORY_BATCH_SIZE());
        address provider = address(0xD008);
        uint256 startingUnits;
        if (alreadyActive) {
            _depositUnits(market, provider, 1);
            startingUnits = 1;
        }

        uint256[] memory tokenIds = _prepareBatch(provider, count, market);
        vm.prank(provider);
        market.depositInventoryBatch(tokenIds);

        (uint256 unitCount, uint256 indexPlusOne) = market.providerPosition(provider);
        assertEq(unitCount, startingUnits + count);
        assertEq(indexPlusOne, 1);
        assertEq(market.activeProviderCount(), 1);
        assertEq(market.totalProviderUnits(), startingUnits + count);
        assertEq(market.inventory(), startingUnits + count);
        for (uint256 i; i < count; ++i) {
            assertEq(mirror.ownerAt(tokenIds[i]), address(market));
        }
    }

    function testFeeAcceptsTenPercentMaximumAndRejectsNextValue() public {
        uint256 maximum = fame.unit() / 10;
        market.setCommunityFee(maximum);
        assertEq(market.premium(), maximum);

        uint256 oversized = maximum + 1;
        vm.expectRevert(abi.encodeWithSelector(UniversalPoolArtMarketplace.FeeTooLarge.selector, oversized, maximum));
        market.setCommunityFee(oversized);
    }

    function testFuzzFeeConfiguration(uint256 candidate) public {
        uint256 maximum = fame.unit() / 10;
        if (candidate > maximum) {
            vm.expectRevert(
                abi.encodeWithSelector(UniversalPoolArtMarketplace.FeeTooLarge.selector, candidate, maximum)
            );
            market.setCommunityFee(candidate);
        } else {
            market.setCommunityFee(candidate);
            assertEq(market.premium(), candidate);
        }
    }

    function testFuzzPurchaseHeldSettlesExactTerms(
        uint96 rawPremium,
        uint96 rawHeadroom,
        bool buyerIsFeeRecipient,
        bool recipientIsBuyer,
        bool buyerSkipsNFT
    ) public {
        uint256 unit = fame.unit();
        uint256 currentPremium = bound(uint256(rawPremium), 1, unit / 10);
        market.setCommunityFee(currentPremium);

        address payer = buyerIsFeeRecipient ? feeRecipient : buyer;
        if (!buyerIsFeeRecipient) {
            vm.prank(payer);
            fame.setSkipNFT(buyerSkipsNFT);
        }
        HeldPurchaseCase memory purchase;
        purchase.payer = payer;
        purchase.destination = recipientIsBuyer ? payer : recipient;
        purchase.shellId = _seedShells(market, 2);
        purchase.artwork = market.artworkHash(purchase.shellId);
        purchase.premium = currentPremium;
        purchase.maximumPremium = currentPremium + bound(uint256(rawHeadroom), 0, unit * 4);
        purchase.minimumBuyerMirrorBalance = recipientIsBuyer ? 1 : 0;
        purchase.payerIsFeeRecipient = buyerIsFeeRecipient;
        _fundAndApprove(payer, market, unit + currentPremium);
        market.unpause();

        _assertHeldSettlement(purchase);
    }

    function _assertHeldSettlement(HeldPurchaseCase memory purchase) internal {
        uint256 payerFameBefore = fame.balanceOf(purchase.payer);
        uint256 feeFameBefore = fame.balanceOf(feeRecipient);
        uint256 marketFameBefore = fame.balanceOf(address(market));
        uint256 inventoryBefore = market.inventory();

        vm.prank(purchase.payer);
        (uint256 returnedBefore, uint256 returnedAfter) = market.purchaseHeld(
            purchase.shellId,
            purchase.artwork,
            purchase.maximumPremium,
            purchase.minimumBuyerMirrorBalance,
            purchase.destination
        );

        uint256 expectedPayerSpend = purchase.destination == purchase.payer ? 0 : fame.unit();
        if (!purchase.payerIsFeeRecipient) expectedPayerSpend += purchase.premium;
        assertEq(fame.balanceOf(purchase.payer), payerFameBefore - expectedPayerSpend);
        if (!purchase.payerIsFeeRecipient) {
            assertEq(fame.balanceOf(feeRecipient), feeFameBefore + purchase.premium);
        }
        assertEq(fame.balanceOf(address(market)), marketFameBefore);
        assertEq(returnedBefore, inventoryBefore);
        assertEq(returnedAfter, market.inventory());
        assertGe(returnedAfter, returnedBefore);
        assertEq(mirror.ownerOf(purchase.shellId), purchase.destination);
        assertEq(market.artworkHash(purchase.shellId), purchase.artwork);
        assertGe(mirror.balanceOf(purchase.payer), purchase.minimumBuyerMirrorBalance);
    }

    function testFuzzPurchaseHeldRejectsPremiumAboveMaximumAndRollsBack(
        uint96 rawPremium,
        uint96 rawMaximum,
        bool buyerSkipsNFT
    ) public {
        uint256 unit = fame.unit();
        uint256 currentPremium = bound(uint256(rawPremium), 1, unit / 10);
        uint256 maximumPremium = bound(uint256(rawMaximum), 0, currentPremium - 1);
        market.setCommunityFee(currentPremium);
        vm.prank(buyer);
        fame.setSkipNFT(buyerSkipsNFT);

        uint256 shellId = _seedShells(market, 2);
        bytes32 expectedArtwork = market.artworkHash(shellId);
        _fundAndApprove(buyer, market, unit + currentPremium);
        market.unpause();
        StateSnapshot memory beforeState = _snapshot(buyer, recipient, shellId, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                UniversalPoolArtMarketplace.PremiumExceedsMaximum.selector, currentPremium, maximumPremium
            )
        );
        vm.prank(buyer);
        market.purchaseHeld(shellId, expectedArtwork, maximumPremium, 0, recipient);

        _assertSnapshot(beforeState, buyer, recipient, shellId, 0);
    }

    function testFuzzPurchaseHeldBuyerMinimumRollsBack(uint96 rawPremium, uint16 rawMinimum) public {
        uint256 unit = fame.unit();
        uint256 currentPremium = bound(uint256(rawPremium), 1, unit / 10);
        uint256 minimum = bound(uint256(rawMinimum), 1, 888);
        market.setCommunityFee(currentPremium);
        vm.prank(buyer);
        fame.setSkipNFT(true);

        uint256 shellId = _seedShells(market, 2);
        bytes32 expectedArtwork = market.artworkHash(shellId);
        _fundAndApprove(buyer, market, unit + currentPremium);
        market.unpause();
        StateSnapshot memory beforeState = _snapshot(buyer, recipient, shellId, 0);

        vm.expectRevert(
            abi.encodeWithSelector(UniversalPoolArtMarketplace.BuyerMirrorBalanceTooLow.selector, minimum, 0)
        );
        vm.prank(buyer);
        market.purchaseHeld(shellId, expectedArtwork, currentPremium, minimum, recipient);

        _assertSnapshot(beforeState, buyer, recipient, shellId, 0);
    }

    function testFuzzPurchasePoolMaterializesMintArtwork(uint96 rawPremium, uint16 rawSourceId) public {
        uint256 unit = fame.unit();
        uint256 currentPremium = bound(uint256(rawPremium), 1, unit / 10);
        market.setCommunityFee(currentPremium);
        uint256 shellId = _seedShells(market, 2);
        uint256 sourceId =
            bound(uint256(rawSourceId), creatorMagic.getMintPoolStart(), creatorMagic.getMintPoolEnd() - 1);
        vm.assume(creatorMagic.isTokenInMintPool(sourceId));

        bytes32 selectedArtwork = market.artworkHash(sourceId);
        bytes32 displacedArtwork = market.artworkHash(shellId);
        vm.prank(buyer);
        fame.setSkipNFT(true);
        _fundAndApprove(buyer, market, unit + currentPremium);
        _enablePoolPurchases(market);

        uint256 feeBefore = fame.balanceOf(feeRecipient);
        uint256 inventoryBefore = market.inventory();
        vm.prank(buyer);
        (, uint256 inventoryAfter) =
            market.purchasePool(shellId, sourceId, selectedArtwork, currentPremium, 0, recipient);

        assertEq(fame.balanceOf(feeRecipient), feeBefore + currentPremium);
        assertEq(mirror.ownerOf(shellId), recipient);
        assertEq(market.artworkHash(shellId), selectedArtwork);
        assertEq(market.artworkHash(sourceId), displacedArtwork);
        assertGe(inventoryAfter, inventoryBefore);
    }

    function testFuzzPurchasePoolRejectsArtPoolAndRollsBack(uint96 rawPremium, uint16 rawSourceId) public {
        uint256 unit = fame.unit();
        uint256 currentPremium = bound(uint256(rawPremium), 1, unit / 10);
        market.setCommunityFee(currentPremium);
        uint256 shellId = _seedShells(market, 2);
        uint256 sourceId = bound(uint256(rawSourceId), creatorMagic.artPoolStartIndex(), creatorMagic.artPoolEndIndex());
        bytes32 selectedArtwork = market.artworkHash(sourceId);
        vm.prank(buyer);
        fame.setSkipNFT(true);
        _fundAndApprove(buyer, market, unit + currentPremium);
        _enablePoolPurchases(market);
        StateSnapshot memory beforeState = _snapshot(buyer, recipient, shellId, sourceId);

        vm.expectRevert(abi.encodeWithSelector(UniversalPoolArtMarketplace.ArtPoolSourceExcluded.selector, sourceId));
        vm.prank(buyer);
        market.purchasePool(shellId, sourceId, selectedArtwork, currentPremium, 0, recipient);

        _assertSnapshot(beforeState, buyer, recipient, shellId, sourceId);
    }

    function testFuzzStaleArtworkCommitmentsRollBack(uint96 rawPremium, bytes32 corruption, bool usePoolPath) public {
        vm.assume(corruption != bytes32(0));
        uint256 unit = fame.unit();
        uint256 currentPremium = bound(uint256(rawPremium), 1, unit / 10);
        market.setCommunityFee(currentPremium);
        uint256 shellId = _seedShells(market, 2);
        vm.prank(buyer);
        fame.setSkipNFT(true);
        _fundAndApprove(buyer, market, unit + currentPremium);

        uint256 sourceId;
        bytes32 actualArtwork;
        if (usePoolPath) {
            sourceId = _findMintPoolToken();
            actualArtwork = market.artworkHash(sourceId);
            _enablePoolPurchases(market);
        } else {
            actualArtwork = market.artworkHash(shellId);
            market.unpause();
        }
        bytes32 staleArtwork = actualArtwork ^ corruption;
        StateSnapshot memory beforeState = _snapshot(buyer, recipient, shellId, sourceId);

        vm.expectRevert(
            abi.encodeWithSelector(
                UniversalPoolArtMarketplace.ArtworkMismatch.selector,
                usePoolPath ? sourceId : shellId,
                staleArtwork,
                actualArtwork
            )
        );
        vm.prank(buyer);
        if (usePoolPath) {
            market.purchasePool(shellId, sourceId, staleArtwork, currentPremium, 0, recipient);
        } else {
            market.purchaseHeld(shellId, staleArtwork, currentPremium, 0, recipient);
        }

        _assertSnapshot(beforeState, buyer, recipient, shellId, sourceId);
    }

    function _snapshot(address payer, address destination, uint256 shellId, uint256 sourceId)
        internal
        view
        returns (StateSnapshot memory state)
    {
        state.payerFame = fame.balanceOf(payer);
        state.feeFame = fame.balanceOf(feeRecipient);
        state.marketFame = fame.balanceOf(address(market));
        state.payerMirrorBalance = mirror.balanceOf(payer);
        state.recipientMirrorBalance = mirror.balanceOf(destination);
        state.marketMirrorBalance = market.inventory();
        state.premium = market.premium();
        state.feeRecipient = market.feeRecipient();
        state.owner = market.owner();
        state.shellOwner = mirror.ownerAt(shellId);
        state.shellArtwork = market.artworkHash(shellId);
        state.paused = market.paused();
        if (sourceId != 0) {
            state.sourceOwner = mirror.ownerAt(sourceId);
            state.sourceArtwork = market.artworkHash(sourceId);
        }
    }

    function _assertSnapshot(
        StateSnapshot memory expected,
        address payer,
        address destination,
        uint256 shellId,
        uint256 sourceId
    ) internal view {
        StateSnapshot memory actual = _snapshot(payer, destination, shellId, sourceId);
        assertEq(actual.payerFame, expected.payerFame);
        assertEq(actual.feeFame, expected.feeFame);
        assertEq(actual.marketFame, expected.marketFame);
        assertEq(actual.payerMirrorBalance, expected.payerMirrorBalance);
        assertEq(actual.recipientMirrorBalance, expected.recipientMirrorBalance);
        assertEq(actual.marketMirrorBalance, expected.marketMirrorBalance);
        assertEq(actual.premium, expected.premium);
        assertEq(actual.feeRecipient, expected.feeRecipient);
        assertEq(actual.owner, expected.owner);
        assertEq(actual.shellOwner, expected.shellOwner);
        assertEq(actual.sourceOwner, expected.sourceOwner);
        assertEq(actual.shellArtwork, expected.shellArtwork);
        assertEq(actual.sourceArtwork, expected.sourceArtwork);
        assertEq(actual.paused, expected.paused);
    }
}
