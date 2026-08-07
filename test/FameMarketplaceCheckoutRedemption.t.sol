// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {FameMarketplaceCheckout} from "../src/FameMarketplaceCheckout.sol";
import {DN404} from "../src/DN404.sol";
import {FameRouter} from "../src/FameRouter.sol";
import {FameRouterTypes} from "../src/router/FameRouterTypes.sol";
import {FameMarketplaceCheckoutTestBase} from "./helpers/FameMarketplaceCheckoutTestBase.sol";
import {Vm} from "forge-std/Vm.sol";

contract FameMarketplaceCheckoutRedemptionTest is FameMarketplaceCheckoutTestBase {
    event SocietyRedeemed(
        address indexed caller,
        address indexed outputAsset,
        bytes32 indexed tokenIdsHash,
        uint256 tokenCount,
        uint256 quotedFameInput,
        uint256 actualFameInput,
        bytes32 executedRouteHash,
        uint256 netAmountOut
    );

    function testOwnedSocietyTokenIdsScansOnlyRequestedOwnerAndRange() public {
        uint256[] memory buyerIds = _mintSocietyTokens(buyer, 3);
        uint256[] memory recipientIds = _mintSocietyTokens(recipient, 2);

        uint256[] memory owned = checkout.ownedSocietyTokenIds(buyer, buyerIds[0], recipientIds[0]);

        assertEq(owned.length, 3);
        assertEq(owned[0], buyerIds[0]);
        assertEq(owned[1], buyerIds[1]);
        assertEq(owned[2], buyerIds[2]);

        uint256[] memory boundary = checkout.ownedSocietyTokenIds(buyer, 1, 889);
        assertEq(boundary, buyerIds);
        assertEq(checkout.ownedSocietyTokenIds(buyer, 888, 889).length, 0);
    }

    function testOwnedSocietyTokenIdsRejectsInvalidOwnerAndRanges() public {
        vm.expectRevert(FameMarketplaceCheckout.ZeroSocietyOwner.selector);
        checkout.ownedSocietyTokenIds(address(0), 1, 889);

        vm.expectRevert(abi.encodeWithSelector(FameMarketplaceCheckout.InvalidSocietyTokenRange.selector, 0, 1));
        checkout.ownedSocietyTokenIds(buyer, 0, 1);

        vm.expectRevert(abi.encodeWithSelector(FameMarketplaceCheckout.InvalidSocietyTokenRange.selector, 1, 1));
        checkout.ownedSocietyTokenIds(buyer, 1, 1);

        vm.expectRevert(abi.encodeWithSelector(FameMarketplaceCheckout.InvalidSocietyTokenRange.selector, 1, 890));
        checkout.ownedSocietyTokenIds(buyer, 1, 890);
    }

    function testRedeemOneSocietyTokenForWeth() public {
        uint256[] memory tokenIds = _mintSocietyTokens(buyer, 1);
        _approveSocietyTokens(buyer);
        uint256 output = 2 ether;
        FameRouterTypes.Route memory route = _redemptionRoute(address(weth), fame.unit(), output);
        uint256 buyerWethBefore = weth.balanceOf(buyer);

        vm.prank(buyer);
        (uint256 actualFameInput, uint256 netAmountOut) = checkout.redeemSociety(route, tokenIds);

        assertEq(actualFameInput, fame.unit());
        assertEq(netAmountOut, output);
        assertEq(weth.balanceOf(buyer), buyerWethBefore + output);
        _assertRedemptionInventoryCleared();
        assertEq(fame.allowance(address(router), address(venue)), 0);
    }

    function testRedeemOneSocietyTokenForEth() public {
        uint256[] memory tokenIds = _mintSocietyTokens(buyer, 1);
        _approveSocietyTokens(buyer);
        uint256 output = 2 ether;
        FameRouterTypes.Route memory route = _redemptionRoute(FameRouterTypes.NATIVE_ETH, fame.unit(), output);
        uint256 buyerEthBefore = buyer.balance;

        vm.prank(buyer);
        (uint256 actualFameInput, uint256 netAmountOut) = checkout.redeemSociety(route, tokenIds);

        assertEq(actualFameInput, fame.unit());
        assertEq(netAmountOut, output);
        assertEq(buyer.balance, buyerEthBefore + output);
        _assertRedemptionInventoryCleared();
    }

    function testRedeemOneSocietyTokenForUsdc() public {
        uint256[] memory tokenIds = _mintSocietyTokens(buyer, 1);
        _approveSocietyTokens(buyer);
        uint256 output = 2_000e6;
        FameRouterTypes.Route memory route = _redemptionRoute(address(usdc), fame.unit(), output);
        uint256 buyerUsdcBefore = usdc.balanceOf(buyer);

        vm.prank(buyer);
        (uint256 actualFameInput, uint256 netAmountOut) = checkout.redeemSociety(route, tokenIds);

        assertEq(actualFameInput, fame.unit());
        assertEq(netAmountOut, output);
        assertEq(usdc.balanceOf(buyer), buyerUsdcBefore + output);
        _assertRedemptionInventoryCleared();
    }

    function testRedeemBoundaryBatchOfThirtyTwoForUsdc() public {
        uint256[] memory tokenIds = _mintSocietyTokens(buyer, 32);
        _approveSocietyTokens(buyer);
        uint256 output = 64_000e6;
        FameRouterTypes.Route memory route = _redemptionRoute(address(usdc), 32 * fame.unit(), output);
        uint256 buyerUsdcBefore = usdc.balanceOf(buyer);

        vm.prank(buyer);
        checkout.redeemSociety(route, tokenIds);

        assertEq(usdc.balanceOf(buyer), buyerUsdcBefore + output);
        _assertRedemptionInventoryCleared();
    }

    function testRedeemBoundaryBatchOfThirtyTwoForWeth() public {
        uint256[] memory tokenIds = _mintSocietyTokens(buyer, 32);
        _approveSocietyTokens(buyer);
        uint256 output = 64 ether;
        FameRouterTypes.Route memory route = _redemptionRoute(address(weth), 32 * fame.unit(), output);
        uint256 buyerWethBefore = weth.balanceOf(buyer);

        vm.prank(buyer);
        checkout.redeemSociety(route, tokenIds);

        assertEq(weth.balanceOf(buyer), buyerWethBefore + output);
        _assertRedemptionInventoryCleared();
    }

    function testRedeemBoundaryBatchOfThirtyTwoForEth() public {
        uint256[] memory tokenIds = _mintSocietyTokens(buyer, 32);
        _approveSocietyTokens(buyer);
        uint256 output = 64 ether;
        FameRouterTypes.Route memory route = _redemptionRoute(FameRouterTypes.NATIVE_ETH, 32 * fame.unit(), output);
        uint256 buyerEthBefore = buyer.balance;

        vm.prank(buyer);
        checkout.redeemSociety(route, tokenIds);

        assertEq(buyer.balance, buyerEthBefore + output);
        _assertRedemptionInventoryCleared();
    }

    function testRedeemConsumesOnlySelectedCallerToken() public {
        uint256[] memory owned = _mintSocietyTokens(buyer, 2);
        _approveSocietyTokens(buyer);
        uint256[] memory selected = new uint256[](1);
        selected[0] = owned[0];
        FameRouterTypes.Route memory route = _redemptionRoute(address(weth), fame.unit(), 1 ether);

        vm.prank(buyer);
        checkout.redeemSociety(route, selected);

        assertEq(mirror.ownerAt(owned[0]), address(0));
        assertEq(mirror.ownerOf(owned[1]), buyer);
        assertEq(mirror.balanceOf(buyer), 1);
    }

    function testRedeemConsumesAmbientFameAndDirectNftDonationAsBonus() public {
        uint256[] memory tokenIds = _mintSocietyTokens(buyer, 1);
        uint256[] memory donatedIds = _mintSocietyTokens(recipient, 1);
        _approveSocietyTokens(buyer);

        uint256 ambientFame = fame.unit() / 4;
        fame.transfer(address(checkout), ambientFame);
        vm.prank(recipient);
        mirror.transferFrom(recipient, address(checkout), donatedIds[0]);

        uint256 actualInput = 2 * fame.unit() + ambientFame;
        uint256 output = 3 ether;
        FameRouterTypes.Route memory route = _redemptionRoute(FameRouterTypes.NATIVE_ETH, fame.unit(), output);
        uint256 venueFameBefore = fame.balanceOf(address(universalVenue));
        uint256 buyerEthBefore = buyer.balance;

        vm.recordLogs();
        vm.prank(buyer);
        (uint256 reportedActualInput, uint256 netAmountOut) = checkout.redeemSociety(route, tokenIds);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(reportedActualInput, actualInput);
        assertEq(netAmountOut, output);
        assertEq(buyer.balance, buyerEthBefore + output);
        assertEq(fame.balanceOf(address(universalVenue)), venueFameBefore + actualInput);
        assertEq(fame.balanceOf(address(checkout)), 0);
        assertEq(mirror.balanceOf(address(checkout)), 0);
        assertEq(mirror.ownerAt(donatedIds[0]), address(0));
        assertEq(fame.allowance(address(checkout), address(router)), 0);
        _assertSocietyRedeemedEvent(logs, route, tokenIds, actualInput, output);
    }

    function testRedeemAllowsFinalFameInputLegBeforeNativeUnwrap() public {
        uint256[] memory tokenIds = _mintSocietyTokens(buyer, 1);
        _approveSocietyTokens(buyer);
        uint256 output = 2 ether;
        FameRouterTypes.Route memory route = _redemptionViaWethToNativeRoute(fame.unit(), output);
        uint256 buyerEthBefore = buyer.balance;

        vm.prank(buyer);
        (uint256 actualFameInput, uint256 netAmountOut) = checkout.redeemSociety(route, tokenIds);

        assertEq(actualFameInput, fame.unit());
        assertEq(netAmountOut, output);
        assertEq(buyer.balance, buyerEthBefore + output);
        assertEq(fame.balanceOf(address(checkout)), 0);
        assertEq(mirror.balanceOf(address(checkout)), 0);
    }

    function testRedeemAllowsEarlierExactFameLegAndRefundsItsNonFameOutputDelta() public {
        uint256[] memory tokenIds = _mintSocietyTokens(buyer, 1);
        _approveSocietyTokens(buyer);
        uint256 ambientUsdc = 7e6;
        uint256 intermediateUsdc = 100e6;
        uint256 finalWeth = 2 ether;
        usdc.mint(address(checkout), ambientUsdc);
        FameRouterTypes.Route memory route =
            _splitRedemptionRoute(fame.unit(), fame.unit() / 4, intermediateUsdc, finalWeth);
        uint256 buyerUsdcBefore = usdc.balanceOf(buyer);
        uint256 buyerWethBefore = weth.balanceOf(buyer);

        vm.prank(buyer);
        (uint256 actualFameInput, uint256 netAmountOut) = checkout.redeemSociety(route, tokenIds);

        assertEq(actualFameInput, fame.unit());
        assertEq(netAmountOut, finalWeth);
        // Intermediate USDC residue + ambient USDC are booned (USDC is on the route snapshot).
        assertEq(usdc.balanceOf(buyer), buyerUsdcBefore + intermediateUsdc + ambientUsdc);
        assertEq(weth.balanceOf(buyer), buyerWethBefore + finalWeth);
        assertEq(usdc.balanceOf(address(checkout)), 0);
        assertEq(fame.balanceOf(address(checkout)), 0);
        assertEq(mirror.balanceOf(address(checkout)), 0);
        assertEq(fame.allowance(address(checkout), address(router)), 0);
    }

    function testRedeemRejectsInvalidTokenArrays() public {
        uint256[] memory empty = new uint256[](0);
        FameRouterTypes.Route memory route = _redemptionRoute(address(weth), fame.unit(), 1 ether);
        vm.expectRevert(abi.encodeWithSelector(FameMarketplaceCheckout.InvalidSocietyTokenCount.selector, 0));
        vm.prank(buyer);
        checkout.redeemSociety(route, empty);

        uint256[] memory tooMany = new uint256[](33);
        vm.expectRevert(abi.encodeWithSelector(FameMarketplaceCheckout.InvalidSocietyTokenCount.selector, 33));
        vm.prank(buyer);
        checkout.redeemSociety(route, tooMany);

        uint256[] memory owned = _mintSocietyTokens(buyer, 2);
        _approveSocietyTokens(buyer);
        uint256[] memory duplicate = new uint256[](2);
        duplicate[0] = owned[0];
        duplicate[1] = owned[0];
        vm.expectRevert(
            abi.encodeWithSelector(
                FameMarketplaceCheckout.SocietyTokenIdsNotStrictlyAscending.selector, owned[0], owned[0]
            )
        );
        vm.prank(buyer);
        checkout.redeemSociety(route, duplicate);

        uint256[] memory descending = new uint256[](2);
        descending[0] = owned[1];
        descending[1] = owned[0];
        vm.expectRevert(
            abi.encodeWithSelector(
                FameMarketplaceCheckout.SocietyTokenIdsNotStrictlyAscending.selector, owned[1], owned[0]
            )
        );
        vm.prank(buyer);
        checkout.redeemSociety(route, descending);

        uint256[] memory zeroId = new uint256[](1);
        vm.expectRevert(abi.encodeWithSelector(FameMarketplaceCheckout.InvalidSocietyTokenId.selector, 0));
        vm.prank(buyer);
        checkout.redeemSociety(route, zeroId);

        uint256[] memory aboveRange = new uint256[](1);
        aboveRange[0] = 889;
        vm.expectRevert(abi.encodeWithSelector(FameMarketplaceCheckout.InvalidSocietyTokenId.selector, 889));
        vm.prank(buyer);
        checkout.redeemSociety(route, aboveRange);
    }

    function testVictimApprovalCannotBeUsedByAnotherCaller() public {
        uint256[] memory victimIds = _mintSocietyTokens(recipient, 1);
        vm.prank(recipient);
        mirror.setApprovalForAll(address(checkout), true);
        FameRouterTypes.Route memory route = _redemptionRoute(address(weth), fame.unit(), 1 ether);

        vm.expectRevert(DN404.TransferFromIncorrectOwner.selector);
        vm.prank(buyer);
        checkout.redeemSociety(route, victimIds);

        assertEq(mirror.ownerOf(victimIds[0]), recipient);
        assertEq(fame.balanceOf(address(checkout)), 0);
        assertEq(mirror.balanceOf(address(checkout)), 0);
        assertEq(fame.allowance(address(checkout), address(router)), 0);
    }

    function testRedeemValidatesRouteAndFinalAllFameLeg() public {
        uint256[] memory tokenIds = _mintSocietyTokens(buyer, 1);
        _approveSocietyTokens(buyer);
        FameRouterTypes.Route memory route = _redemptionRoute(address(weth), fame.unit(), 1 ether);

        route.amountIn = 0;
        _assertRedemptionRejected(
            route, tokenIds, abi.encodeWithSelector(FameMarketplaceCheckout.ZeroInputAmount.selector)
        );
        route.amountIn = fame.unit();

        FameRouterTypes.Leg memory finalFameLeg = route.legs[0];
        route.legs = new FameRouterTypes.Leg[](0);
        _assertRedemptionRejected(route, tokenIds, abi.encodeWithSelector(FameMarketplaceCheckout.EmptyRoute.selector));

        route.legs = new FameRouterTypes.Leg[](FameRouterTypes.MAX_ROUTE_LEGS + 1);
        _assertRedemptionRejected(
            route,
            tokenIds,
            abi.encodeWithSelector(FameMarketplaceCheckout.TooManyRouteLegs.selector, route.legs.length)
        );

        route.legs = new FameRouterTypes.Leg[](1);
        route.legs[0] = finalFameLeg;
        router.setFeeRecipient(address(checkout));
        _assertRedemptionRejected(
            route, tokenIds, abi.encodeWithSelector(FameMarketplaceCheckout.RouterFeeRecipientIsCheckout.selector)
        );
        router.setFeeRecipient(feeRecipient);

        route.tokenIn = address(usdc);
        _assertRedemptionRejected(
            route,
            tokenIds,
            abi.encodeWithSelector(
                FameMarketplaceCheckout.WrongRedemptionInputAsset.selector, address(usdc), address(fame)
            )
        );
        route.tokenIn = address(fame);

        route.tokenOut = address(0xBEEF);
        _assertRedemptionRejected(
            route,
            tokenIds,
            abi.encodeWithSelector(FameMarketplaceCheckout.UnsupportedRedemptionOutputAsset.selector, address(0xBEEF))
        );
        route.tokenOut = address(weth);

        route.recipient = recipient;
        _assertRedemptionRejected(
            route,
            tokenIds,
            abi.encodeWithSelector(FameMarketplaceCheckout.WrongRouteRecipient.selector, recipient, buyer)
        );
        route.recipient = buyer;

        route.version = FameRouterTypes.SCHEMA_VERSION + 1;
        _assertRedemptionRejected(
            route, tokenIds, abi.encodeWithSelector(FameMarketplaceCheckout.BadRouteVersion.selector, route.version)
        );
        route.version = FameRouterTypes.SCHEMA_VERSION;

        route.deadline = block.timestamp - 1;
        _assertRedemptionRejected(
            route,
            tokenIds,
            abi.encodeWithSelector(FameMarketplaceCheckout.DeadlineExpired.selector, route.deadline, block.timestamp)
        );
        route.deadline = block.timestamp + 1 hours;

        route.legs[0].amountMode = FameRouterTypes.AmountMode.Exact;
        _assertRedemptionRejected(
            route,
            tokenIds,
            abi.encodeWithSelector(FameMarketplaceCheckout.InvalidRedemptionFameLeg.selector, 0, type(uint256).max)
        );
        route.legs[0].amountMode = FameRouterTypes.AmountMode.All;

        route.legs = new FameRouterTypes.Leg[](2);
        route.legs[0] = finalFameLeg;
        route.legs[1] = finalFameLeg;
        _assertRedemptionRejected(
            route, tokenIds, abi.encodeWithSelector(FameMarketplaceCheckout.InvalidRedemptionFameLeg.selector, 2, 1)
        );

        route.legs[1] = _v2Leg(address(fame), address(usdc), fame.unit() / 4, 1, FameRouterTypes.AmountMode.Exact);
        route.legs[0].amountMode = FameRouterTypes.AmountMode.All;
        _assertRedemptionRejected(
            route, tokenIds, abi.encodeWithSelector(FameMarketplaceCheckout.InvalidRedemptionFameLeg.selector, 1, 0)
        );

        assertEq(mirror.ownerOf(tokenIds[0]), buyer);
    }

    function testRedeemRejectsQuoteBelowBatchBasisOrAboveActualBalance() public {
        uint256[] memory tokenIds = _mintSocietyTokens(buyer, 1);
        _approveSocietyTokens(buyer);
        FameRouterTypes.Route memory route = _redemptionRoute(address(weth), fame.unit() - 1, 1 ether);

        vm.expectRevert(
            abi.encodeWithSelector(
                FameMarketplaceCheckout.RedemptionQuoteBelowTokenBasis.selector, fame.unit() - 1, fame.unit()
            )
        );
        vm.prank(buyer);
        checkout.redeemSociety(route, tokenIds);

        route.amountIn = 2 * fame.unit();
        vm.expectRevert(
            abi.encodeWithSelector(
                FameMarketplaceCheckout.RedemptionActualInputBelowQuote.selector, fame.unit(), 2 * fame.unit()
            )
        );
        vm.prank(buyer);
        checkout.redeemSociety(route, tokenIds);

        assertEq(mirror.ownerOf(tokenIds[0]), buyer);
        assertEq(fame.balanceOf(address(checkout)), 0);
        assertEq(mirror.balanceOf(address(checkout)), 0);
        assertEq(fame.allowance(address(checkout), address(router)), 0);
    }

    function testLateRouterFailureRollsBackNftPullAndApproval() public {
        uint256[] memory tokenIds = _mintSocietyTokens(buyer, 1);
        _approveSocietyTokens(buyer);
        FameRouterTypes.Route memory route = _redemptionRoute(address(weth), fame.unit(), 1 ether);
        route.minAmountOutAfterFee = 2 ether;

        vm.expectRevert(abi.encodeWithSelector(FameRouter.FinalOutputTooLow.selector, 1 ether, 2 ether));
        vm.prank(buyer);
        checkout.redeemSociety(route, tokenIds);

        assertEq(mirror.ownerOf(tokenIds[0]), buyer);
        assertEq(venue.nextOutputIndex(), 0);
        assertEq(fame.balanceOf(address(checkout)), 0);
        assertEq(mirror.balanceOf(address(checkout)), 0);
        assertEq(fame.allowance(address(checkout), address(router)), 0);
    }

    function testFirstNftPullFailureRollsBackEntireRedemption() public {
        _assertNftPullFailureRollsBackEntireRedemption(0);
    }

    function testMiddleNftPullFailureRollsBackEntireRedemption() public {
        _assertNftPullFailureRollsBackEntireRedemption(1);
    }

    function testFinalNftPullFailureRollsBackEntireRedemption() public {
        _assertNftPullFailureRollsBackEntireRedemption(2);
    }

    function testPurchaseBoonsAmbientFameOnSuccessfulCheckout() public {
        uint256 shellId = _seedShells(market, 2);
        bytes32 artwork = market.artworkHash(shellId);
        uint256 ambientFame = fame.unit() / 5;
        fame.transfer(address(checkout), ambientFame);
        FameRouterTypes.Route memory route = _singleLegRoute(address(usdc), 100e6, 100e6, _marketCharge());
        market.unpause();
        uint256 maxPremium = market.premium();

        uint256 buyerFameBefore = fame.balanceOf(buyer);
        vm.prank(buyer);
        checkout.checkoutHeld(route, shellId, artwork, maxPremium, 1);

        assertEq(fame.balanceOf(address(checkout)), 0);
        assertEq(fame.balanceOf(buyer), buyerFameBefore + fame.unit() + ambientFame);
        assertEq(mirror.balanceOf(address(checkout)), 0);
    }

    function _assertRedemptionRejected(
        FameRouterTypes.Route memory route,
        uint256[] memory tokenIds,
        bytes memory expectedError
    ) private {
        vm.expectRevert(expectedError);
        vm.prank(buyer);
        checkout.redeemSociety(route, tokenIds);
        assertEq(mirror.ownerOf(tokenIds[0]), buyer);
        assertEq(fame.balanceOf(address(checkout)), 0);
        assertEq(fame.allowance(address(checkout), address(router)), 0);
    }

    function _assertNftPullFailureRollsBackEntireRedemption(uint256 failureIndex) private {
        uint256[] memory tokenIds = _mintSocietyTokens(buyer, 3);
        vm.prank(buyer);
        mirror.transferFrom(buyer, recipient, tokenIds[failureIndex]);
        _approveSocietyTokens(buyer);
        FameRouterTypes.Route memory route = _redemptionRoute(address(weth), 3 * fame.unit(), 1 ether);

        vm.expectRevert(DN404.TransferFromIncorrectOwner.selector);
        vm.prank(buyer);
        checkout.redeemSociety(route, tokenIds);

        for (uint256 i; i < tokenIds.length; ++i) {
            assertEq(mirror.ownerOf(tokenIds[i]), i == failureIndex ? recipient : buyer);
        }
        assertEq(venue.nextOutputIndex(), 0);
        _assertRedemptionInventoryCleared();
    }

    function _assertRedemptionInventoryCleared() private view {
        assertEq(fame.balanceOf(address(checkout)), 0);
        assertEq(mirror.balanceOf(address(checkout)), 0);
        assertEq(fame.allowance(address(checkout), address(router)), 0);
    }

    function _assertSocietyRedeemedEvent(
        Vm.Log[] memory logs,
        FameRouterTypes.Route memory quotedRoute,
        uint256[] memory tokenIds,
        uint256 actualFameInput,
        uint256 netAmountOut
    ) private {
        bytes32 signature = keccak256(
            "SocietyRedeemed(address,address,bytes32,uint256,uint256,uint256,bytes32,uint256)"
        );
        uint256 quotedFameInput = quotedRoute.amountIn;
        FameRouterTypes.Route memory executedRoute = quotedRoute;
        executedRoute.amountIn = actualFameInput;

        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(checkout) || logs[i].topics[0] != signature) continue;
            assertEq(address(uint160(uint256(logs[i].topics[1]))), buyer);
            assertEq(address(uint160(uint256(logs[i].topics[2]))), quotedRoute.tokenOut);
            assertEq(logs[i].topics[3], keccak256(abi.encode(tokenIds)));
            (uint256 count, uint256 quoted, uint256 actual, bytes32 routeHash, uint256 net) =
                abi.decode(logs[i].data, (uint256, uint256, uint256, bytes32, uint256));
            assertEq(count, tokenIds.length);
            assertEq(quoted, quotedFameInput);
            assertEq(actual, actualFameInput);
            assertEq(routeHash, keccak256(abi.encode(executedRoute)));
            assertEq(net, netAmountOut);
            return;
        }
        fail();
    }
}
