// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {UniversalPoolArtMarketplace} from "../src/UniversalPoolArtMarketplace.sol";
import {UniversalPoolArtMarketplaceTestBase} from "./helpers/UniversalPoolArtMarketplaceTestBase.sol";
import {ReentrantUniversalPoolMarketplaceRecipient} from "./mocks/ReentrantUniversalPoolMarketplaceRecipient.sol";

contract UniversalPoolArtMarketplaceProviderInventoryTest is UniversalPoolArtMarketplaceTestBase {
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
    event InventoryDeposited(address indexed provider, uint256 indexed tokenId, uint256 providerUnits);
    event InventoryBatchDeposited(address indexed provider, uint256[] tokenIds, uint256 providerUnits);
    event InventoryWithdrawn(
        address indexed provider, uint256 indexed tokenId, uint256 providerUnits, uint256 grossPremiumAmount
    );

    function testBatchDepositCreditsEightUnitsInOneProviderSlotWhilePaused() public {
        address provider = address(0x9008);
        uint256[] memory tokenIds = _prepareBatch(provider, 8, market);

        vm.expectEmit(true, false, false, true, address(market));
        emit InventoryBatchDeposited(provider, tokenIds, 8);
        vm.prank(provider);
        market.depositInventoryBatch(tokenIds);

        (uint256 unitCount, uint256 indexPlusOne) = market.providerPosition(provider);
        assertEq(unitCount, 8);
        assertEq(indexPlusOne, 1);
        assertEq(market.activeProviderCount(), 1);
        assertEq(market.totalProviderUnits(), 8);
        assertEq(market.inventory(), 8);
        assertTrue(market.paused());
        for (uint256 i; i < tokenIds.length; ++i) {
            assertEq(mirror.ownerAt(tokenIds[i]), address(market));
        }
    }

    function testBatchDepositRejectsEmptyAndMoreThanEightBeforeCustody() public {
        uint256[] memory empty = new uint256[](0);
        vm.expectRevert(
            abi.encodeWithSelector(
                UniversalPoolArtMarketplace.InvalidInventoryBatchSize.selector, uint256(0), uint256(8)
            )
        );
        market.depositInventoryBatch(empty);

        uint256[] memory oversized = new uint256[](9);
        vm.expectRevert(
            abi.encodeWithSelector(
                UniversalPoolArtMarketplace.InvalidInventoryBatchSize.selector, uint256(9), uint256(8)
            )
        );
        market.depositInventoryBatch(oversized);

        assertEq(market.activeProviderCount(), 0);
        assertEq(market.totalProviderUnits(), 0);
        assertEq(market.inventory(), 0);
    }

    function testBatchDepositRejectsInvalidAndDuplicateIdsBeforeCustody() public {
        address provider = address(0x9009);
        uint256[] memory owned = _prepareBatch(provider, 2, market);
        uint256[] memory duplicate = new uint256[](2);
        duplicate[0] = owned[0];
        duplicate[1] = owned[0];

        vm.expectRevert(abi.encodeWithSelector(UniversalPoolArtMarketplace.DuplicateInventoryToken.selector, owned[0]));
        vm.prank(provider);
        market.depositInventoryBatch(duplicate);

        uint256[] memory invalid = new uint256[](2);
        invalid[0] = owned[0];
        invalid[1] = 889;
        vm.expectRevert(abi.encodeWithSelector(UniversalPoolArtMarketplace.UnavailableShell.selector, uint256(889)));
        vm.prank(provider);
        market.depositInventoryBatch(invalid);

        assertEq(mirror.ownerAt(owned[0]), provider);
        assertEq(mirror.ownerAt(owned[1]), provider);
        assertEq(market.activeProviderCount(), 0);
        assertEq(market.totalProviderUnits(), 0);
    }

    function testBatchDepositRollsBackEarlierTransfersWhenLaterTransferFails() public {
        address provider = address(0x9012);
        address otherOwner = address(0x9013);
        uint256[] memory owned = _prepareBatch(provider, 1, market);
        fame.transfer(otherOwner, fame.unit());
        uint256 otherTokenId = _ownedTokenAt(otherOwner, 0);
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = owned[0];
        tokenIds[1] = otherTokenId;

        vm.expectRevert();
        vm.prank(provider);
        market.depositInventoryBatch(tokenIds);

        assertEq(mirror.ownerAt(owned[0]), provider);
        assertEq(mirror.ownerAt(otherTokenId), otherOwner);
        assertEq(market.activeProviderCount(), 0);
        assertEq(market.totalProviderUnits(), 0);
        assertEq(market.inventory(), 0);
    }

    function testBatchDepositUsesOneCapSlotAndLetsActiveProviderAddWhenFull() public {
        UniversalPoolArtMarketplace cappedMarket = _deployMarketWithFees(0, 0, feeRecipient, owner, 1);
        address activeProvider = address(0x9014);
        address blockedProvider = address(0x9015);
        uint256[] memory firstBatch = _prepareBatch(activeProvider, 2, cappedMarket);
        vm.prank(activeProvider);
        cappedMarket.depositInventoryBatch(firstBatch);

        uint256[] memory additionalBatch = _prepareBatch(activeProvider, 3, cappedMarket);
        vm.prank(activeProvider);
        cappedMarket.depositInventoryBatch(additionalBatch);

        uint256[] memory blockedBatch = _prepareBatch(blockedProvider, 2, cappedMarket);
        vm.expectRevert(
            abi.encodeWithSelector(UniversalPoolArtMarketplace.ActiveProviderCapReached.selector, uint256(1))
        );
        vm.prank(blockedProvider);
        cappedMarket.depositInventoryBatch(blockedBatch);

        (uint256 activeUnits, uint256 indexPlusOne) = cappedMarket.providerPosition(activeProvider);
        assertEq(activeUnits, 5);
        assertEq(indexPlusOne, 1);
        assertEq(cappedMarket.activeProviderCount(), 1);
        assertEq(cappedMarket.totalProviderUnits(), 5);
        assertEq(cappedMarket.inventory(), 5);
        for (uint256 i; i < blockedBatch.length; ++i) {
            assertEq(mirror.ownerAt(blockedBatch[i]), blockedProvider);
        }
    }

    function testBatchPositionsPreservePartialExitSwapPopAndFinalRemoval() public {
        address firstProvider = address(0x9016);
        address secondProvider = address(0x9017);
        uint256[] memory firstBatch = _prepareBatch(firstProvider, 3, market);
        uint256[] memory secondBatch = _prepareBatch(secondProvider, 2, market);
        vm.prank(firstProvider);
        market.depositInventoryBatch(firstBatch);
        vm.prank(secondProvider);
        market.depositInventoryBatch(secondBatch);

        vm.warp(block.timestamp + 24 hours);
        vm.startPrank(firstProvider);
        market.withdrawInventory(firstBatch[0], 0);
        market.withdrawInventory(firstBatch[1], 0);
        vm.stopPrank();
        (uint256 firstUnits, uint256 firstIndex) = market.providerPosition(firstProvider);
        assertEq(firstUnits, 1);
        assertEq(firstIndex, 1);

        vm.prank(firstProvider);
        market.withdrawInventory(firstBatch[2], 0);
        (firstUnits, firstIndex) = market.providerPosition(firstProvider);
        (uint256 secondUnits, uint256 secondIndex) = market.providerPosition(secondProvider);
        assertEq(firstUnits, 0);
        assertEq(firstIndex, 0);
        assertEq(secondUnits, 2);
        assertEq(secondIndex, 1);
        assertEq(market.activeProviderAt(0), secondProvider);

        vm.startPrank(secondProvider);
        market.withdrawInventory(secondBatch[0], 0);
        market.withdrawInventory(secondBatch[1], 0);
        vm.stopPrank();
        assertEq(market.activeProviderCount(), 0);
        assertEq(market.totalProviderUnits(), 0);
        assertEq(market.inventory(), 0);
    }

    function testProviderCapAllowsExistingProviderAddsAndReleasesSlotOnFinalExit() public {
        UniversalPoolArtMarketplace cappedMarket = _deployMarketWithFees(0, 0, feeRecipient, owner, 1);
        address firstProvider = address(0x9010);
        address nextProvider = address(0x9011);
        _depositUnits(cappedMarket, firstProvider, 2);

        fame.transfer(nextProvider, fame.unit());
        uint256 nextTokenId = _ownedTokenAt(nextProvider, 0);
        vm.startPrank(nextProvider);
        mirror.approve(address(cappedMarket), nextTokenId);
        vm.expectRevert(
            abi.encodeWithSelector(UniversalPoolArtMarketplace.ActiveProviderCapReached.selector, uint256(1))
        );
        cappedMarket.depositInventory(nextTokenId);
        vm.stopPrank();

        vm.warp(block.timestamp + 24 hours);
        vm.startPrank(firstProvider);
        cappedMarket.withdrawInventory(_ownedTokenAt(address(cappedMarket), 0), 0);
        cappedMarket.withdrawInventory(_ownedTokenAt(address(cappedMarket), 0), 0);
        vm.stopPrank();
        assertEq(cappedMarket.activeProviderCount(), 0);

        vm.startPrank(nextProvider);
        cappedMarket.depositInventory(nextTokenId);
        vm.stopPrank();
        assertEq(cappedMarket.activeProviderAt(0), nextProvider);
    }

    function testWeightedProviderPayoutSendsRoundingDustToCommunity() public {
        address firstProvider = address(0x9020);
        address secondProvider = address(0x9021);
        _depositUnits(market, firstProvider, 1);
        _depositUnits(market, secondProvider, 2);
        market.setCommunityFee(0);
        market.setProviderFee(10);

        uint256 shellId = _ownedTokenAt(address(market), 0);
        bytes32 artwork = market.artworkHash(shellId);
        _fundAndApprove(buyer, market, fame.unit() + 10);
        uint256 communityBefore = fame.balanceOf(feeRecipient);
        market.unpause();

        vm.prank(buyer);
        market.purchaseHeld(shellId, artwork, 10, 0, buyer);

        assertEq(fame.balanceOf(firstProvider), 3);
        assertEq(fame.balanceOf(secondProvider), 6);
        assertEq(fame.balanceOf(feeRecipient) - communityBefore, 1);
    }

    function testSelectedWithdrawalExcludesExitingUnitFromProviderPayout() public {
        address exitingProvider = address(0x9030);
        address remainingProvider = address(0x9031);
        _depositUnits(market, exitingProvider, 1);
        _depositUnits(market, remainingProvider, 1);
        market.setCommunityFee(0);
        market.setProviderFee(100);
        uint256 selectedId = _ownedTokenAt(address(market), 0);

        fame.transfer(exitingProvider, 100);
        vm.startPrank(exitingProvider);
        fame.approve(address(market), 100);
        market.withdrawInventory(selectedId, 100);
        vm.stopPrank();

        assertEq(fame.balanceOf(remainingProvider), 100);
        assertEq(fame.balanceOf(exitingProvider), fame.unit());
        (uint256 unitCount,) = market.providerPosition(exitingProvider);
        assertEq(unitCount, 0);
    }

    function testWithdrawalChargesFullGrossPremiumAtAgeZero() public {
        address exitingProvider = address(0x9034);
        address remainingProvider = address(0x9035);
        _depositUnits(market, exitingProvider, 1);
        _depositUnits(market, remainingProvider, 1);
        market.setCommunityFee(11);
        market.setProviderFee(13);
        uint256 selectedId = _ownedTokenAt(address(market), 0);
        uint256 communityBefore = fame.balanceOf(feeRecipient);

        fame.transfer(exitingProvider, 24);
        vm.startPrank(exitingProvider);
        fame.approve(address(market), 24);
        vm.expectEmit(true, true, false, true, address(market));
        emit InventoryWithdrawn(exitingProvider, selectedId, 0, 24);
        market.withdrawInventory(selectedId, 24);
        vm.stopPrank();

        assertEq(fame.balanceOf(remainingProvider), 13);
        assertEq(fame.balanceOf(feeRecipient) - communityBefore, 11);
        assertEq(fame.allowance(exitingProvider, address(market)), 0);
        assertEq(mirror.ownerAt(selectedId), exitingProvider);
    }

    function testWithdrawalPremiumDecaysLinearlyAndRoundsUpUntilMaturity() public {
        address provider = address(0x9036);
        _depositUnits(market, provider, 1);
        market.setCommunityFee(86_401);
        uint256 depositedAt = block.timestamp;

        assertEq(market.withdrawalPremium(provider), 86_401);
        vm.warp(depositedAt + 12 hours);
        assertEq(market.withdrawalPremium(provider), 43_201);
        vm.warp(depositedAt + 24 hours - 1);
        assertEq(market.withdrawalPremium(provider), 2);
        vm.warp(depositedAt + 24 hours);
        assertEq(market.withdrawalPremium(provider), 0);
        vm.warp(depositedAt + 48 hours);
        assertEq(market.withdrawalPremium(provider), 0);
    }

    function testProviderTimestampRingWrapsWithoutLosingFifoAge() public {
        address provider = address(0x903B);
        _depositUnits(market, provider, 2);

        vm.pauseGasMetering();
        vm.startPrank(provider);
        for (uint256 i; i < 889; ++i) {
            vm.warp(block.timestamp + 24 hours);
            uint256 selectedId = _ownedTokenAt(address(market), 0);
            market.withdrawInventory(selectedId, 0);
            mirror.approve(address(market), selectedId);
            market.depositInventory(selectedId);
        }
        vm.stopPrank();
        vm.resumeGasMetering();

        (uint256 unitCount,) = market.providerPosition(provider);
        assertEq(unitCount, 2);
        assertEq(market.totalProviderUnits(), 2);
        assertEq(market.inventory(), 2);
        assertEq(market.withdrawalPremium(provider), 0);
    }

    function testWithdrawalConsumesOldestUnitWithoutResettingOrBorrowingAge() public {
        address provider = address(0x9037);
        market.setCommunityFee(86_400);
        _depositUnits(market, provider, 1);
        uint256 firstTokenId = _ownedTokenAt(address(market), 0);
        uint256 firstDepositedAt = block.timestamp;

        vm.warp(firstDepositedAt + 12 hours);
        _depositUnits(market, provider, 1);
        uint256 secondTokenId = _ownedTokenAt(address(market), 1);
        fame.transfer(provider, 129_600);
        vm.startPrank(provider);
        fame.approve(address(market), 129_600);

        assertEq(market.withdrawalPremium(provider), 43_200);
        market.withdrawInventory(firstTokenId, 43_200);
        assertEq(market.withdrawalPremium(provider), 86_400);
        market.withdrawInventory(secondTokenId, 86_400);
        vm.stopPrank();

        assertEq(fame.allowance(provider, address(market)), 0);
        assertEq(market.totalProviderUnits(), 0);
    }

    function testBatchUnitsShareTimestampAndRemainAheadOfLaterDeposit() public {
        address provider = address(0x9038);
        market.setCommunityFee(86_400);
        uint256[] memory batch = _prepareBatch(provider, 2, market);
        vm.prank(provider);
        market.depositInventoryBatch(batch);
        uint256 batchDepositedAt = block.timestamp;

        vm.warp(batchDepositedAt + 12 hours);
        _depositUnits(market, provider, 1);
        uint256 laterTokenId = _ownedTokenAt(address(market), 2);
        fame.transfer(provider, 172_800);
        vm.startPrank(provider);
        fame.approve(address(market), 172_800);

        assertEq(market.withdrawalPremium(provider), 43_200);
        market.withdrawInventory(batch[0], 43_200);
        assertEq(market.withdrawalPremium(provider), 43_200);
        market.withdrawInventory(batch[1], 43_200);
        assertEq(market.withdrawalPremium(provider), 86_400);
        market.withdrawInventory(laterTokenId, 86_400);
        vm.stopPrank();

        assertEq(market.totalProviderUnits(), 0);
    }

    function testWithdrawalRejectsExceededPremiumAndUnavailableShellWithoutConsumingUnit() public {
        address provider = address(0x9039);
        address externalOwner = address(0x9041);
        _depositUnits(market, provider, 1);
        market.setCommunityFee(11);
        market.setProviderFee(13);
        uint256 marketTokenId = _ownedTokenAt(address(market), 0);
        fame.transfer(externalOwner, fame.unit());
        uint256 externalTokenId = _ownedTokenAt(externalOwner, 0);
        fame.transfer(provider, 24);
        vm.prank(provider);
        fame.approve(address(market), 24);

        vm.expectRevert(
            abi.encodeWithSelector(UniversalPoolArtMarketplace.PremiumExceedsMaximum.selector, uint256(24), uint256(23))
        );
        vm.prank(provider);
        market.withdrawInventory(marketTokenId, 23);

        vm.expectRevert(abi.encodeWithSelector(UniversalPoolArtMarketplace.UnavailableShell.selector, externalTokenId));
        vm.prank(provider);
        market.withdrawInventory(externalTokenId, 24);

        vm.expectRevert(abi.encodeWithSelector(UniversalPoolArtMarketplace.UnavailableShell.selector, uint256(889)));
        vm.prank(provider);
        market.withdrawInventory(889, 24);

        (uint256 units,) = market.providerPosition(provider);
        assertEq(units, 1);
        assertEq(market.withdrawalPremium(provider), 24);
        assertEq(fame.allowance(provider, address(market)), 24);
        assertEq(mirror.ownerAt(marketTokenId), address(market));
    }

    function testPurchaseAndWithdrawalContentionHasAtomicWinnerAndLoser() public {
        address provider = address(0x9042);
        _depositUnits(market, provider, 2);
        uint256 purchasedFirst = _ownedTokenAt(address(market), 0);
        uint256 withdrawnFirst = _ownedTokenAt(address(market), 1);
        bytes32 purchasedArtwork = market.artworkHash(purchasedFirst);
        bytes32 withdrawnArtwork = market.artworkHash(withdrawnFirst);
        uint256 charge = fame.unit() + market.premium();
        _fundAndApprove(buyer, market, charge);
        vm.warp(block.timestamp + 24 hours);
        market.unpause();
        uint256 currentPremium = market.premium();

        vm.prank(buyer);
        market.purchaseHeld(purchasedFirst, purchasedArtwork, currentPremium, 0, buyer);

        vm.expectRevert(abi.encodeWithSelector(UniversalPoolArtMarketplace.UnavailableShell.selector, purchasedFirst));
        vm.prank(provider);
        market.withdrawInventory(purchasedFirst, 0);
        (uint256 unitsAfterPurchaseWin,) = market.providerPosition(provider);
        assertEq(unitsAfterPurchaseWin, 2);

        vm.prank(provider);
        market.withdrawInventory(withdrawnFirst, 0);
        uint256 feeBefore = fame.balanceOf(feeRecipient);
        vm.expectRevert(abi.encodeWithSelector(UniversalPoolArtMarketplace.UnavailableShell.selector, withdrawnFirst));
        vm.prank(buyer);
        market.purchaseHeld(withdrawnFirst, withdrawnArtwork, currentPremium, 0, buyer);

        (uint256 unitsAfterWithdrawalWin,) = market.providerPosition(provider);
        assertEq(unitsAfterWithdrawalWin, 1);
        assertEq(fame.balanceOf(feeRecipient), feeBefore);
        assertEq(mirror.ownerAt(withdrawnFirst), provider);
    }

    function testWithdrawalDistributesToRemainingUnitIncludingPayerSelfTransfer() public {
        address exitingProvider = address(0x9032);
        address otherProvider = address(0x9033);
        _depositUnits(market, exitingProvider, 2);
        _depositUnits(market, otherProvider, 1);
        market.setCommunityFee(0);
        market.setProviderFee(300);
        uint256 selectedId = _ownedTokenAt(address(market), 0);
        uint256 communityBefore = fame.balanceOf(feeRecipient);

        fame.transfer(exitingProvider, 300);
        vm.startPrank(exitingProvider);
        fame.approve(address(market), 300);
        market.withdrawInventory(selectedId, 300);
        vm.stopPrank();

        assertEq(fame.balanceOf(otherProvider), 150);
        assertEq(fame.balanceOf(feeRecipient) - communityBefore, 0);
        assertEq(fame.balanceOf(exitingProvider), fame.unit() + 150);
        assertEq(fame.allowance(exitingProvider, address(market)), 0);
        (uint256 unitCount,) = market.providerPosition(exitingProvider);
        assertEq(unitCount, 1);
    }

    function testSelectedFinalWithdrawalRoutesEntirePremiumToCommunity() public {
        address provider = address(0x9040);
        _depositUnits(market, provider, 1);
        market.setCommunityFee(11);
        market.setProviderFee(13);
        uint256 selectedId = _ownedTokenAt(address(market), 0);
        uint256 communityBefore = fame.balanceOf(feeRecipient);

        fame.transfer(provider, 24);
        vm.startPrank(provider);
        fame.approve(address(market), 24);
        market.withdrawInventory(selectedId, 24);
        vm.stopPrank();

        assertEq(fame.balanceOf(feeRecipient) - communityBefore, 24);
        assertEq(market.activeProviderCount(), 0);
        assertEq(market.inventory(), 0);
    }

    function testCommunityBuyerPaysFullPremiumIncludingProviderShare() public {
        address provider = address(0x9050);
        _depositUnits(market, provider, 1);
        market.setCommunityFee(11);
        market.setProviderFee(13);
        uint256 shellId = _ownedTokenAt(address(market), 0);
        bytes32 artwork = market.artworkHash(shellId);
        // Full charge: unit + communityFee + providerFee
        _fundAndApprove(feeRecipient, market, fame.unit() + 24);
        uint256 communityBefore = fame.balanceOf(feeRecipient);
        market.unpause();

        vm.prank(feeRecipient);
        market.purchaseHeld(shellId, artwork, 24, 0, feeRecipient);

        assertEq(fame.balanceOf(provider), 13);
        // Keeps shell (unit nets); community self-pay nets zero; only provider share leaves.
        assertEq(fame.balanceOf(feeRecipient), communityBefore - 13);
    }

    function testCommunityBuyerPaysCommunityAndEmptyPoolProviderDustToSelf() public {
        uint256 shellId = _seedShells(market, 1);
        bytes32 artwork = market.artworkHash(shellId);
        market.setCommunityFee(11);
        market.setProviderFee(13);
        _fundAndApprove(feeRecipient, market, fame.unit() + 24);
        uint256 communityBefore = fame.balanceOf(feeRecipient);
        market.unpause();

        vm.prank(feeRecipient);
        market.purchaseHeld(shellId, artwork, 24, 0, feeRecipient);

        // No active providers: providerFee + communityFee self-pay (net 0); shell unit nets.
        assertEq(fame.balanceOf(feeRecipient), communityBefore);
        assertEq(mirror.ownerOf(shellId), feeRecipient);
    }

    function testProviderPayerExecutesAndCountsItsFullPremiumSelfTransfer() public {
        address provider = address(0x9051);
        _depositUnits(market, provider, 1);
        market.setCommunityFee(11);
        market.setProviderFee(13);
        uint256 shellId = _ownedTokenAt(address(market), 0);
        bytes32 artwork = market.artworkHash(shellId);
        uint256 unit = fame.unit();
        _fundAndApprove(provider, market, unit + 24);
        uint256 providerBefore = fame.balanceOf(provider);
        market.unpause();

        vm.expectEmit(true, true, true, true, address(market));
        emit ArtworkPurchased(
            provider, provider, shellId, UniversalPoolArtMarketplace.FulfillmentPath.Held, 0, artwork, unit, 24, 1, 1
        );
        vm.prank(provider);
        market.purchaseHeld(shellId, artwork, 24, 0, provider);

        assertEq(fame.balanceOf(provider), providerBefore - 11);
        assertEq(fame.allowance(provider, address(market)), 0);
    }

    function testDirectFameAndSocietyTransfersCreateNoProviderCredit() public {
        address donor = address(0x9060);
        fame.transfer(donor, fame.unit());
        uint256 tokenId = _ownedTokenAt(donor, 0);

        vm.prank(donor);
        mirror.transferFrom(donor, address(market), tokenId);

        (uint256 unitCount, uint256 indexPlusOne) = market.providerPosition(donor);
        assertEq(unitCount, 0);
        assertEq(indexPlusOne, 0);
        assertEq(market.totalProviderUnits(), 0);
        assertEq(market.inventory(), 1);

        vm.prank(donor);
        vm.expectRevert(abi.encodeWithSelector(UniversalPoolArtMarketplace.NoProviderPosition.selector, donor));
        market.withdrawInventory(tokenId, 0);
    }

    function testIndependentFeesAllowZeroAndTenPercentEach() public {
        uint256 maximum = fame.unit() / 10;
        market.setCommunityFee(0);
        market.setProviderFee(maximum);
        market.setCommunityFee(maximum);
        assertEq(market.communityFee(), maximum);
        assertEq(market.providerFee(), maximum);
        assertEq(market.premium(), maximum * 2);

        vm.expectRevert(abi.encodeWithSelector(UniversalPoolArtMarketplace.FeeTooLarge.selector, maximum + 1, maximum));
        market.setProviderFee(maximum + 1);
    }

    function testProviderDepositCreatesDirectPositionAndReceivesWeightedPremium() public {
        address provider = address(0x9001);
        uint256 unit = fame.unit();
        fame.transfer(provider, unit);
        uint256 tokenId = _ownedTokenAt(provider, 0);

        vm.startPrank(provider);
        mirror.approve(address(market), tokenId);
        vm.expectEmit(true, true, false, true, address(market));
        emit InventoryDeposited(provider, tokenId, 1);
        market.depositInventory(tokenId);
        vm.stopPrank();

        (uint256 unitCount, uint256 indexPlusOne) = market.providerPosition(provider);
        assertEq(unitCount, 1);
        assertEq(indexPlusOne, 1);
        assertEq(market.activeProviderCount(), 1);
        assertEq(market.totalProviderUnits(), 1);

        market.setCommunityFee(unit / 100);
        market.setProviderFee(unit / 100);
        uint256 shellId = _ownedTokenAt(address(market), 0);
        bytes32 artwork = market.artworkHash(shellId);
        _fundAndApprove(buyer, market, unit + market.premium());
        uint256 providerBefore = fame.balanceOf(provider);
        market.unpause();

        uint256 maxPremium = market.premium();
        vm.prank(buyer);
        market.purchaseHeld(shellId, artwork, maxPremium, 0, buyer);

        assertEq(fame.balanceOf(provider) - providerBefore, unit / 100);
        assertEq(market.totalProviderUnits(), 1);
    }

    function testPausedMarketAllowsMatureProviderWithdrawalAndReleasesSlot() public {
        address provider = address(0x9002);
        fame.transfer(provider, fame.unit());
        uint256 depositedId = _ownedTokenAt(provider, 0);

        vm.startPrank(provider);
        mirror.approve(address(market), depositedId);
        market.depositInventory(depositedId);
        vm.warp(block.timestamp + 24 hours);
        uint256 communityBefore = fame.balanceOf(feeRecipient);
        vm.expectEmit(true, true, false, true, address(market));
        emit InventoryWithdrawn(provider, depositedId, 0, 0);
        market.withdrawInventory(depositedId, 0);
        vm.stopPrank();

        assertEq(mirror.ownerAt(depositedId), provider);
        (uint256 unitCount, uint256 indexPlusOne) = market.providerPosition(provider);
        assertEq(unitCount, 0);
        assertEq(indexPlusOne, 0);
        assertEq(market.activeProviderCount(), 0);
        assertEq(market.totalProviderUnits(), 0);
        assertEq(fame.balanceOf(feeRecipient), communityBefore);
        assertTrue(market.paused());
    }

    function testRejectedWithdrawalRollsBackPayoutPositionTimestampAndCustody() public {
        ReentrantUniversalPoolMarketplaceRecipient provider = new ReentrantUniversalPoolMarketplaceRecipient();
        provider.setSkipNFT(fame, false);
        fame.transfer(address(provider), fame.unit());
        uint256 tokenId = _ownedTokenAt(address(provider), 0);
        provider.deposit(mirror, market, tokenId);
        market.setCommunityFee(11);
        market.setProviderFee(13);
        fame.transfer(address(provider), 24);
        provider.configure(market, ReentrantUniversalPoolMarketplaceRecipient.Action.Reject, address(0), bytes32(0));
        uint256 communityBefore = fame.balanceOf(feeRecipient);
        uint256 premiumBefore = market.withdrawalPremium(address(provider));

        vm.expectRevert();
        provider.withdraw(fame, tokenId, 24);

        (uint256 units, uint256 indexPlusOne) = market.providerPosition(address(provider));
        assertEq(units, 1);
        assertEq(indexPlusOne, 1);
        assertEq(market.totalProviderUnits(), 1);
        assertEq(market.activeProviderCount(), 1);
        assertEq(fame.balanceOf(feeRecipient), communityBefore);
        assertEq(mirror.ownerAt(tokenId), address(market));
        assertEq(market.withdrawalPremium(address(provider)), premiumBefore);
    }

    function testReentrantWithdrawalCannotConsumeAnotherProviderUnit() public {
        ReentrantUniversalPoolMarketplaceRecipient provider = new ReentrantUniversalPoolMarketplaceRecipient();
        provider.setSkipNFT(fame, false);
        fame.transfer(address(provider), 2 * fame.unit());
        uint256 firstTokenId = _ownedTokenAt(address(provider), 0);
        provider.deposit(mirror, market, firstTokenId);
        uint256 secondTokenId = _ownedTokenAt(address(provider), 0);
        provider.deposit(mirror, market, secondTokenId);
        provider.configure(
            market, ReentrantUniversalPoolMarketplaceRecipient.Action.ReenterWithdrawal, address(0), bytes32(0)
        );

        market.setCommunityFee(0);
        market.setProviderFee(0);
        provider.withdraw(fame, firstTokenId, 0);

        assertEq(mirror.ownerAt(firstTokenId), address(provider));
        assertFalse(provider.attemptedActionSucceeded());
        assertEq(bytes4(provider.attemptedActionRevertData()), bytes4(0xab143c06));
        (uint256 units,) = market.providerPosition(address(provider));
        assertEq(units, 1);
        assertEq(market.totalProviderUnits(), 1);
        assertEq(market.inventory(), 1);
    }
}
