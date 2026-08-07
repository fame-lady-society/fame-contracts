// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {FameMarketplaceCheckout} from "../src/FameMarketplaceCheckout.sol";
import {FameRouterTypes} from "../src/router/FameRouterTypes.sol";
import {FameMarketplaceCheckoutTestBase} from "./helpers/FameMarketplaceCheckoutTestBase.sol";
import {IERC721Receiver} from "@openzeppelin5/contracts/token/ERC721/IERC721Receiver.sol";
import {MockERC20, TransferTaxERC20} from "./router/mocks/MockERC20.sol";
import {ForceNativeDonation} from "./mocks/PrefundedFameRouterVenue.sol";
import {ReentrantFameMarketplaceCheckoutToken} from "./mocks/ReentrantFameMarketplaceCheckoutToken.sol";

contract RejectingNativeCheckoutBuyer is IERC721Receiver {
    receive() external payable {
        revert("NO_NATIVE_REFUND");
    }

    function buyHeld(
        FameMarketplaceCheckout checkout,
        FameRouterTypes.Route calldata route,
        uint256 shellId,
        bytes32 artwork,
        uint256 maxPremium
    ) external payable {
        checkout.checkoutHeld{value: msg.value}(route, shellId, artwork, maxPremium, 1);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}

contract FameMarketplaceCheckoutTest is FameMarketplaceCheckoutTestBase {
    function testRoutedCheckoutPaysProvidersAndLeavesNoPayoutResidue() public {
        address provider = address(0xA001);
        fame.transfer(provider, fame.unit());
        uint256 depositedId = _ownedTokenAt(provider, 0);
        vm.startPrank(provider);
        mirror.approve(address(market), depositedId);
        market.depositInventory(depositedId);
        vm.stopPrank();
        market.setCommunityFee(11);
        market.setProviderFee(13);

        uint256 shellId = _ownedTokenAt(address(market), 0);
        bytes32 artwork = market.artworkHash(shellId);
        FameRouterTypes.Route memory route = _singleLegRoute(address(usdc), 100e6, 100e6, _marketCharge());
        uint256 communityBefore = fame.balanceOf(feeRecipient);
        uint256 maxPremium = market.premium();
        market.unpause();

        vm.prank(buyer);
        (uint256 routerOutput, uint256 marketCharge,,) = checkout.checkoutHeld(route, shellId, artwork, maxPremium, 1);

        assertEq(routerOutput, fame.unit() + 24);
        assertEq(marketCharge, fame.unit() + 24);
        assertEq(fame.balanceOf(provider), 13);
        assertEq(fame.balanceOf(feeRecipient) - communityBefore, 11);
        assertEq(fame.balanceOf(address(checkout)), 0);
        assertEq(fame.allowance(address(checkout), address(market)), 0);
    }

    function testCommunityRecipientCheckoutPaysFullPremiumIncludingCommunityFee() public {
        address firstProvider = address(0xA002);
        address secondProvider = address(0xA003);
        _depositUnits(market, firstProvider, 1);
        _depositUnits(market, secondProvider, 1);
        market.setCommunityFee(11);
        market.setProviderFee(13);

        uint256 shellId = _ownedTokenAt(address(market), 0);
        bytes32 artwork = market.artworkHash(shellId);
        FameRouterTypes.Route memory route = _singleLegRoute(address(usdc), 100e6, 100e6, _marketCharge());
        usdc.mint(feeRecipient, 100e6);
        vm.prank(feeRecipient);
        usdc.approve(address(checkout), 100e6);
        uint256 communityBefore = fame.balanceOf(feeRecipient);
        uint256 maxPremium = market.premium();
        market.unpause();

        vm.prank(feeRecipient);
        (, uint256 marketCharge, uint256 fameRefund,) = checkout.checkoutHeld(route, shellId, artwork, maxPremium, 0);

        // Full charge: unit + communityFee + providerFee (no buyer waiver).
        assertEq(marketCharge, fame.unit() + 24);
        assertEq(fame.balanceOf(firstProvider), 6);
        assertEq(fame.balanceOf(secondProvider), 6);
        // Buyer receives shell unit + fame refund + community (11) + provider dust (1).
        assertEq(fame.balanceOf(feeRecipient) - communityBefore, fame.unit() + fameRefund + 12);
        assertEq(fame.balanceOf(address(checkout)), 0);
        assertEq(fame.allowance(address(checkout), address(market)), 0);
    }

    function testConstructorBindsStackAndEnablesSkipNFT() public view {
        assertEq(address(checkout.router()), address(router));
        assertEq(address(checkout.market()), address(market));
        assertEq(address(checkout.fame()), address(fame));
        assertEq(checkout.usdc(), address(usdc));
        assertEq(checkout.weth(), address(weth));
        assertTrue(fame.getSkipNFT(address(checkout)));
    }

    function testCheckoutHeldWithUsdcSettlesAndRefundsSurplusFame() public {
        uint256 shellId = _seedShells(market, 2);
        bytes32 artwork = market.artworkHash(shellId);
        uint256 surplus = fame.unit() / 20;
        FameRouterTypes.Route memory route = _singleLegRoute(address(usdc), 100e6, 100e6, _marketCharge() + surplus);
        market.unpause();
        uint256 maxPremium = market.premium();

        uint256 buyerUsdcBefore = usdc.balanceOf(buyer);
        uint256 buyerFameBefore = fame.balanceOf(buyer);
        vm.prank(buyer);
        checkout.checkoutHeld(route, shellId, artwork, maxPremium, 1);

        assertEq(mirror.ownerOf(shellId), buyer);
        assertEq(usdc.balanceOf(buyer), buyerUsdcBefore - 100e6);
        assertEq(fame.balanceOf(buyer), buyerFameBefore + fame.unit() + surplus);
        assertEq(fame.balanceOf(address(checkout)), 0);
        assertEq(usdc.balanceOf(address(checkout)), 0);
        assertEq(usdc.allowance(address(checkout), address(router)), 0);
        assertEq(fame.allowance(address(checkout), address(market)), 0);
        assertTrue(fame.getSkipNFT(address(checkout)));
        assertEq(mirror.balanceOf(address(checkout)), 0);
    }

    function testCheckoutHeldWithWethExactOutputHasNoSurplusFameRefund() public {
        uint256 shellId = _seedShells(market, 2);
        bytes32 artwork = market.artworkHash(shellId);
        FameRouterTypes.Route memory route = _singleLegRoute(address(weth), 1 ether, 1 ether, _marketCharge());
        market.unpause();
        uint256 maxPremium = market.premium();

        uint256 buyerFameBefore = fame.balanceOf(buyer);
        vm.prank(buyer);
        checkout.checkoutHeld(route, shellId, artwork, maxPremium, 1);

        assertEq(mirror.ownerOf(shellId), buyer);
        assertEq(fame.balanceOf(buyer), buyerFameBefore + fame.unit());
        assertEq(fame.balanceOf(address(checkout)), 0);
    }

    function testCheckoutHeldWithNativeRefundsUnspentInput() public {
        uint256 shellId = _seedShells(market, 2);
        bytes32 artwork = market.artworkHash(shellId);
        FameRouterTypes.Route memory route = _nativeRoute(2 ether, 1 ether, _marketCharge());
        market.unpause();
        uint256 maxPremium = market.premium();

        uint256 buyerEthBefore = buyer.balance;
        vm.prank(buyer);
        checkout.checkoutHeld{value: 2 ether}(route, shellId, artwork, maxPremium, 1);

        assertEq(buyer.balance, buyerEthBefore - 1 ether);
        assertEq(address(checkout).balance, 0);
        assertEq(mirror.ownerOf(shellId), buyer);
    }

    function testCheckoutRefundsRouterInputResidue() public {
        uint256 shellId = _seedShells(market, 2);
        bytes32 artwork = market.artworkHash(shellId);
        FameRouterTypes.Route memory route = _singleLegRoute(address(usdc), 100e6, 40e6, _marketCharge());
        market.unpause();
        uint256 maxPremium = market.premium();

        uint256 buyerBefore = usdc.balanceOf(buyer);
        vm.prank(buyer);
        checkout.checkoutHeld(route, shellId, artwork, maxPremium, 1);

        assertEq(usdc.balanceOf(buyer), buyerBefore - 40e6);
        assertEq(usdc.balanceOf(address(checkout)), 0);
    }

    function testCheckoutRefundsIntermediateResidue() public {
        uint256 shellId = _seedShells(market, 2);
        bytes32 artwork = market.artworkHash(shellId);
        FameRouterTypes.Route memory route = _intermediateResidueRoute(100e6, 10 ether, 6 ether, _marketCharge());
        market.unpause();
        uint256 maxPremium = market.premium();

        uint256 buyerWethBefore = weth.balanceOf(buyer);
        vm.prank(buyer);
        checkout.checkoutHeld(route, shellId, artwork, maxPremium, 1);

        assertEq(weth.balanceOf(buyer), buyerWethBefore + 4 ether);
        assertEq(weth.balanceOf(address(checkout)), 0);
    }

    function testErc20RouteRefundsNativeIntermediateResidue() public {
        uint256 shellId = _seedShells(market, 2);
        bytes32 artwork = market.artworkHash(shellId);
        FameRouterTypes.Route memory route = _wethWithNativeResidueRoute(1 ether, 0.4 ether, 0.6 ether, _marketCharge());
        market.unpause();
        uint256 maxPremium = market.premium();

        uint256 buyerEthBefore = buyer.balance;
        uint256 buyerWethBefore = weth.balanceOf(buyer);
        vm.prank(buyer);
        checkout.checkoutHeld(route, shellId, artwork, maxPremium, 1);

        assertEq(buyer.balance, buyerEthBefore + 0.4 ether);
        assertEq(weth.balanceOf(buyer), buyerWethBefore - 1 ether);
        assertEq(address(checkout).balance, 0);
        assertEq(weth.balanceOf(address(checkout)), 0);
    }

    function testCheckoutPoolUsesTypedMintPoolPath() public {
        uint256 shellId = _seedShells(market, 2);
        uint256 sourceId = _findMintPoolToken();
        bytes32 artwork = market.artworkHash(sourceId);
        FameRouterTypes.Route memory route = _singleLegRoute(address(weth), 1 ether, 1 ether, _marketCharge());
        _enablePoolPurchases(market);
        uint256 maxPremium = market.premium();

        vm.prank(buyer);
        checkout.checkoutPool(route, shellId, sourceId, artwork, maxPremium, 1);

        assertEq(mirror.ownerOf(shellId), buyer);
        assertEq(market.artworkHash(shellId), artwork);
    }

    function testCheckoutPoolUsesTypedBurnPoolPath() public {
        (uint256 shellId, uint256 sourceId) = _prepareBurnPoolPurchase();
        bytes32 artwork = market.artworkHash(sourceId);
        FameRouterTypes.Route memory route = _singleLegRoute(address(usdc), 100e6, 100e6, _marketCharge());
        _enablePoolPurchases(market);
        uint256 maxPremium = market.premium();

        vm.prank(buyer);
        checkout.checkoutPool(route, shellId, sourceId, artwork, maxPremium, 1);

        assertEq(mirror.ownerOf(shellId), buyer);
        assertEq(market.artworkHash(shellId), artwork);
    }

    function testPremiumDecreaseBecomesFameRefund() public {
        uint256 shellId = _seedShells(market, 2);
        bytes32 artwork = market.artworkHash(shellId);
        uint256 quotedPremium = market.premium();
        FameRouterTypes.Route memory route = _singleLegRoute(address(usdc), 100e6, 100e6, fame.unit() + quotedPremium);
        market.setCommunityFee(quotedPremium / 2);
        market.unpause();

        uint256 buyerFameBefore = fame.balanceOf(buyer);
        vm.prank(buyer);
        checkout.checkoutHeld(route, shellId, artwork, quotedPremium, 1);

        assertEq(fame.balanceOf(buyer), buyerFameBefore + fame.unit() + quotedPremium / 2);
    }

    function testBuyerFeeRecipientPaysFullPremiumCharge() public {
        market.setFeeRecipient(buyer);
        uint256 shellId = _seedShells(market, 2);
        bytes32 artwork = market.artworkHash(shellId);
        uint256 maxPremium = market.premium();
        FameRouterTypes.Route memory route = _singleLegRoute(address(usdc), 100e6, 100e6, fame.unit() + maxPremium);
        market.unpause();

        vm.prank(buyer);
        (uint256 output, uint256 charge, uint256 refund,) =
            checkout.checkoutHeld(route, shellId, artwork, maxPremium, 1);

        // No waiver: charge is unit + full premium; exact route leaves no FAME refund.
        assertEq(output, fame.unit() + maxPremium);
        assertEq(charge, fame.unit() + maxPremium);
        assertEq(refund, 0);
        assertEq(fame.balanceOf(address(checkout)), 0);
        assertEq(mirror.ownerOf(shellId), buyer);
    }

    function testSuccessfulCheckoutBoonsSnapshottedAmbientBalances() public {
        uint256 shellId = _seedShells(market, 2);
        bytes32 artwork = market.artworkHash(shellId);
        uint256 ambientFame = fame.unit() / 5;
        uint256 ambientUsdc = 17e6;
        uint256 ambientWeth = 3 ether;
        uint256 ambientEth = 2 ether;
        fame.transfer(address(checkout), ambientFame);
        usdc.mint(address(checkout), ambientUsdc);
        weth.mint(address(checkout), ambientWeth);
        ForceNativeDonation donation = new ForceNativeDonation{value: ambientEth}();
        donation.donate(payable(address(checkout)));
        // Route assets: USDC + FAME. WETH/ETH ambient is not on this route and stays.
        FameRouterTypes.Route memory route = _singleLegRoute(address(usdc), 100e6, 40e6, _marketCharge());
        market.unpause();
        uint256 maxPremium = market.premium();

        uint256 buyerUsdcBefore = usdc.balanceOf(buyer);
        uint256 buyerFameBefore = fame.balanceOf(buyer);
        vm.prank(buyer);
        checkout.checkoutHeld(route, shellId, artwork, maxPremium, 1);

        // Spend 40e6; residue 60e6 + ambient USDC booned; ambient FAME booned with surplus.
        assertEq(usdc.balanceOf(buyer), buyerUsdcBefore - 40e6 + ambientUsdc);
        assertEq(fame.balanceOf(buyer), buyerFameBefore + fame.unit() + ambientFame);
        assertEq(usdc.balanceOf(address(checkout)), 0);
        assertEq(fame.balanceOf(address(checkout)), 0);
        assertEq(weth.balanceOf(address(checkout)), ambientWeth);
        assertEq(address(checkout).balance, ambientEth);
    }

    function testLateMarketplaceRevertRollsBackSwapAndFunding() public {
        uint256 shellId = _seedShells(market, 2);
        bytes32 artwork = market.artworkHash(shellId);
        FameRouterTypes.Route memory route = _singleLegRoute(address(usdc), 100e6, 100e6, _marketCharge());
        market.unpause();
        uint256 maxPremium = market.premium();
        uint256 buyerUsdcBefore = usdc.balanceOf(buyer);
        uint256 venueFameBefore = fame.balanceOf(address(venue));

        vm.expectRevert();
        vm.prank(buyer);
        checkout.checkoutHeld(route, shellId, artwork, maxPremium, 2);

        assertEq(usdc.balanceOf(buyer), buyerUsdcBefore);
        assertEq(fame.balanceOf(address(venue)), venueFameBefore);
        assertEq(venue.nextOutputIndex(), 0);
        assertEq(mirror.ownerOf(shellId), address(market));
        assertEq(usdc.allowance(address(checkout), address(router)), 0);
        assertEq(fame.allowance(address(checkout), address(market)), 0);
    }

    function testTaxedInputIsRejectedBeforeRouterApproval() public {
        TransferTaxERC20 taxed = new TransferTaxERC20("Taxed", "TAX", 18, 1_000);
        FameMarketplaceCheckout taxedCheckout = new FameMarketplaceCheckout(
            address(router), address(market), payable(address(fame)), address(taxed), address(weth)
        );
        market.setAuthorizedCheckout(address(taxedCheckout));
        taxed.mint(buyer, 100 ether);
        vm.prank(buyer);
        taxed.approve(address(taxedCheckout), type(uint256).max);
        uint256 shellId = _seedShells(market, 2);
        bytes32 artwork = market.artworkHash(shellId);
        uint256 maxPremium = market.premium();
        FameRouterTypes.Route memory route = _singleLegRoute(address(taxed), 100 ether, 100 ether, _marketCharge());
        route.recipient = address(taxedCheckout);
        market.unpause();

        vm.expectRevert(
            abi.encodeWithSelector(FameMarketplaceCheckout.InputTransferMismatch.selector, 100 ether, 90 ether)
        );
        vm.prank(buyer);
        taxedCheckout.checkoutHeld(route, shellId, artwork, maxPremium, 1);

        assertEq(taxed.balanceOf(buyer), 100 ether);
        assertEq(taxed.allowance(address(taxedCheckout), address(router)), 0);
        assertEq(venue.nextOutputIndex(), 0);
    }

    function testRejectingNativeRefundRecipientRevertsAtomically() public {
        RejectingNativeCheckoutBuyer rejectingBuyer = new RejectingNativeCheckoutBuyer();
        uint256 shellId = _seedShells(market, 2);
        bytes32 artwork = market.artworkHash(shellId);
        uint256 maxPremium = market.premium();
        FameRouterTypes.Route memory route = _nativeRoute(2 ether, 1 ether, _marketCharge());
        market.unpause();

        vm.expectRevert();
        rejectingBuyer.buyHeld{value: 2 ether}(checkout, route, shellId, artwork, maxPremium);

        assertEq(venue.nextOutputIndex(), 0);
        assertEq(mirror.ownerOf(shellId), address(market));
        assertEq(address(checkout).balance, 0);
        assertEq(fame.allowance(address(checkout), address(market)), 0);
    }

    function testInputTokenCallbackCannotReenterCheckout() public {
        ReentrantFameMarketplaceCheckoutToken reentrant = new ReentrantFameMarketplaceCheckoutToken();
        FameMarketplaceCheckout reentrantCheckout = new FameMarketplaceCheckout(
            address(router), address(market), payable(address(fame)), address(reentrant), address(weth)
        );
        market.setAuthorizedCheckout(address(reentrantCheckout));
        reentrant.mint(buyer, 100 ether);
        vm.prank(buyer);
        reentrant.approve(address(reentrantCheckout), type(uint256).max);
        uint256 shellId = _seedShells(market, 2);
        bytes32 artwork = market.artworkHash(shellId);
        uint256 maxPremium = market.premium();
        FameRouterTypes.Route memory route = _singleLegRoute(address(reentrant), 100 ether, 100 ether, _marketCharge());
        route.recipient = address(reentrantCheckout);
        reentrant.arm(reentrantCheckout, route, shellId, artwork, maxPremium);
        market.unpause();

        vm.prank(buyer);
        reentrantCheckout.checkoutHeld(route, shellId, artwork, maxPremium, 1);

        assertTrue(reentrant.attemptedReentry());
        assertTrue(reentrant.blockedByGuard());
        assertEq(mirror.ownerOf(shellId), buyer);
        assertEq(reentrant.allowance(address(reentrantCheckout), address(router)), 0);
        assertEq(fame.allowance(address(reentrantCheckout), address(market)), 0);
    }

    function testInvalidRouteFieldsRevertBeforeFunding() public {
        uint256 shellId = _seedShells(market, 2);
        bytes32 artwork = market.artworkHash(shellId);
        FameRouterTypes.Route memory route = _singleLegRoute(address(usdc), 100e6, 100e6, _marketCharge());
        market.unpause();
        uint256 maxPremium = market.premium();
        uint256 buyerUsdcBefore = usdc.balanceOf(buyer);

        route.recipient = buyer;
        vm.expectRevert();
        vm.prank(buyer);
        checkout.checkoutHeld(route, shellId, artwork, maxPremium, 1);
        assertEq(usdc.balanceOf(buyer), buyerUsdcBefore);
        assertEq(venue.nextOutputIndex(), 0);

        route.recipient = address(checkout);
        route.tokenOut = address(weth);
        vm.expectRevert();
        vm.prank(buyer);
        checkout.checkoutHeld(route, shellId, artwork, maxPremium, 1);
        assertEq(usdc.balanceOf(buyer), buyerUsdcBefore);

        route.tokenOut = address(fame);
        route.minAmountOutAfterFee = _marketCharge() - 1;
        vm.expectRevert();
        vm.prank(buyer);
        checkout.checkoutHeld(route, shellId, artwork, maxPremium, 1);
        assertEq(usdc.balanceOf(buyer), buyerUsdcBefore);
    }

    function testMalformedRoutesRevertBeforeFunding() public {
        uint256 shellId = _seedShells(market, 2);
        bytes32 artwork = market.artworkHash(shellId);
        uint256 maxPremium = market.premium();
        FameRouterTypes.Route memory route = _singleLegRoute(address(usdc), 100e6, 100e6, _marketCharge());
        FameRouterTypes.Leg memory validLeg = route.legs[0];
        market.unpause();

        route.version = FameRouterTypes.SCHEMA_VERSION + 1;
        _assertRouteRejectedBeforeFunding(
            route,
            shellId,
            artwork,
            maxPremium,
            abi.encodeWithSelector(FameMarketplaceCheckout.BadRouteVersion.selector, route.version),
            0
        );

        route.version = FameRouterTypes.SCHEMA_VERSION;
        route.amountIn = 0;
        _assertRouteRejectedBeforeFunding(
            route,
            shellId,
            artwork,
            maxPremium,
            abi.encodeWithSelector(FameMarketplaceCheckout.ZeroInputAmount.selector),
            0
        );

        route.amountIn = 100e6;
        route.legs = new FameRouterTypes.Leg[](0);
        _assertRouteRejectedBeforeFunding(
            route, shellId, artwork, maxPremium, abi.encodeWithSelector(FameMarketplaceCheckout.EmptyRoute.selector), 0
        );

        route.legs = new FameRouterTypes.Leg[](FameRouterTypes.MAX_ROUTE_LEGS + 1);
        route.legs[0] = validLeg;
        _assertRouteRejectedBeforeFunding(
            route,
            shellId,
            artwork,
            maxPremium,
            abi.encodeWithSelector(FameMarketplaceCheckout.TooManyRouteLegs.selector, route.legs.length),
            0
        );

        route.legs = new FameRouterTypes.Leg[](1);
        route.legs[0] = validLeg;
        route.tokenIn = FameRouterTypes.NATIVE_ETH;
        route.amountIn = 1 ether;
        _assertRouteRejectedBeforeFunding(
            route,
            shellId,
            artwork,
            maxPremium,
            abi.encodeWithSelector(FameMarketplaceCheckout.NativeValueMismatch.selector, route.amountIn, 0),
            0
        );
    }

    function testRouterFeeRecipientConfigurationRevertsBeforeFunding() public {
        uint256 shellId = _seedShells(market, 2);
        bytes32 artwork = market.artworkHash(shellId);
        uint256 maxPremium = market.premium();
        FameRouterTypes.Route memory route = _singleLegRoute(address(usdc), 100e6, 100e6, _marketCharge());
        router.setFeeRecipient(address(checkout));
        market.unpause();

        _assertRouteRejectedBeforeFunding(
            route,
            shellId,
            artwork,
            maxPremium,
            abi.encodeWithSelector(FameMarketplaceCheckout.RouterFeeRecipientIsCheckout.selector),
            0
        );
    }

    function testUnsupportedInputAndWrongNativeValueRevertBeforeFunding() public {
        MockERC20 other = new MockERC20("Other", "OTHER", 18);
        uint256 shellId = _seedShells(market, 2);
        bytes32 artwork = market.artworkHash(shellId);
        FameRouterTypes.Route memory route = _singleLegRoute(address(usdc), 100e6, 100e6, _marketCharge());
        market.unpause();
        uint256 maxPremium = market.premium();

        route.tokenIn = address(other);
        vm.expectRevert();
        vm.prank(buyer);
        checkout.checkoutHeld(route, shellId, artwork, maxPremium, 1);

        route.tokenIn = address(usdc);
        vm.expectRevert();
        vm.prank(buyer);
        checkout.checkoutHeld{value: 1}(route, shellId, artwork, maxPremium, 1);
    }

    function testPurchaseTermsAndMarketConfigurationRevertBeforeFunding() public {
        uint256 shellId = _seedShells(market, 2);
        bytes32 artwork = market.artworkHash(shellId);
        FameRouterTypes.Route memory route = _singleLegRoute(address(usdc), 100e6, 100e6, _marketCharge());
        uint256 buyerUsdcBefore = usdc.balanceOf(buyer);
        uint256 maxPremium = market.premium();

        market.setAuthorizedCheckout(address(0));
        market.unpause();
        vm.expectRevert();
        vm.prank(buyer);
        checkout.checkoutHeld(route, shellId, artwork, maxPremium, 1);
        assertEq(usdc.balanceOf(buyer), buyerUsdcBefore);

        market.pause();
        market.setAuthorizedCheckout(address(checkout));
        market.unpause();
        vm.expectRevert();
        vm.prank(buyer);
        checkout.checkoutHeld(route, shellId, bytes32(uint256(1)), maxPremium, 1);
        assertEq(usdc.balanceOf(buyer), buyerUsdcBefore);

        vm.expectRevert();
        vm.prank(buyer);
        checkout.checkoutHeld(route, shellId, artwork, maxPremium - 1, 1);
        assertEq(usdc.balanceOf(buyer), buyerUsdcBefore);
    }

    function testCheckoutFeeRecipientConfigurationRevertsBeforeFunding() public {
        uint256 shellId = _seedShells(market, 2);
        bytes32 artwork = market.artworkHash(shellId);
        uint256 maxPremium = market.premium();
        FameRouterTypes.Route memory route = _singleLegRoute(address(usdc), 100e6, 100e6, _marketCharge());
        market.setFeeRecipient(address(checkout));
        market.unpause();
        uint256 buyerUsdcBefore = usdc.balanceOf(buyer);

        vm.expectRevert(FameMarketplaceCheckout.CheckoutIsFeeRecipient.selector);
        vm.prank(buyer);
        checkout.checkoutHeld(route, shellId, artwork, maxPremium, 1);

        assertEq(usdc.balanceOf(buyer), buyerUsdcBefore);
        assertEq(venue.nextOutputIndex(), 0);
    }

    function testPoolRejectsSameShellAndSourceBeforeFunding() public {
        uint256 shellId = _seedShells(market, 2);
        bytes32 artwork = market.artworkHash(shellId);
        FameRouterTypes.Route memory route = _singleLegRoute(address(usdc), 100e6, 100e6, _marketCharge());
        _enablePoolPurchases(market);
        uint256 maxPremium = market.premium();
        uint256 buyerUsdcBefore = usdc.balanceOf(buyer);

        vm.expectRevert();
        vm.prank(buyer);
        checkout.checkoutPool(route, shellId, shellId, artwork, maxPremium, 1);

        assertEq(usdc.balanceOf(buyer), buyerUsdcBefore);
        assertEq(venue.nextOutputIndex(), 0);
    }

    function testContractHasNoOwnerOrRescueSurface() public {
        (bool ownerSuccess,) = address(checkout).call(abi.encodeWithSignature("owner()"));
        (bool rescueSuccess,) =
            address(checkout).call(abi.encodeWithSignature("rescue(address,address,uint256)", address(usdc), buyer, 1));

        assertFalse(ownerSuccess);
        assertFalse(rescueSuccess);
    }

    function _assertRouteRejectedBeforeFunding(
        FameRouterTypes.Route memory route,
        uint256 shellId,
        bytes32 artwork,
        uint256 maxPremium,
        bytes memory expectedError,
        uint256 value
    ) private {
        uint256 buyerUsdcBefore = usdc.balanceOf(buyer);
        uint256 buyerEthBefore = buyer.balance;

        vm.expectRevert(expectedError);
        vm.prank(buyer);
        checkout.checkoutHeld{value: value}(route, shellId, artwork, maxPremium, 1);

        assertEq(usdc.balanceOf(buyer), buyerUsdcBefore);
        assertEq(buyer.balance, buyerEthBefore);
        assertEq(address(checkout).balance, 0);
        assertEq(usdc.balanceOf(address(checkout)), 0);
        assertEq(fame.balanceOf(address(checkout)), 0);
        assertEq(venue.nextOutputIndex(), 0);
    }
}
