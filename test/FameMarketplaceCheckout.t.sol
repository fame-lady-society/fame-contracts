// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {FameMarketplaceCheckout} from "../src/FameMarketplaceCheckout.sol";
import {UniversalPoolArtMarketplace} from "../src/UniversalPoolArtMarketplace.sol";
import {FameRouterTypes} from "../src/router/FameRouterTypes.sol";
import {FameMarketplaceCheckoutTestBase} from "./helpers/FameMarketplaceCheckoutTestBase.sol";
import {IERC721Receiver} from "@openzeppelin5/contracts/token/ERC721/IERC721Receiver.sol";
import {MockERC20, TransferTaxERC20} from "./router/mocks/MockERC20.sol";
import {ForceNativeDonation} from "./mocks/PrefundedFameRouterVenue.sol";
import {ReentrantFameMarketplaceCheckoutToken} from "./mocks/ReentrantFameMarketplaceCheckoutToken.sol";
import {CreatorArtistMagic} from "../src/CreatorArtistMagic.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {Vm} from "forge-std/Vm.sol";
import {
    FameDonatingCheckoutRefundToken,
    FameDonatingShellRecipient,
    MismatchedOutputCheckoutRouter,
    StickyCheckoutRefundToken
} from "./mocks/CheckoutAccountingMocks.sol";

contract RejectingNativeCheckoutBuyer is IERC721Receiver {
    receive() external payable {
        revert("NO_NATIVE_REFUND");
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}

contract FameMarketplaceCheckoutTest is FameMarketplaceCheckoutTestBase {
    bytes32 private constant CHECKOUT_SETTLED_TOPIC = keccak256(
        "CheckoutSettled(address,address,uint256,bytes32,uint8,uint256,bytes32,uint256,uint256,uint256,uint256,uint256)"
    );

    struct CheckoutSettlementExpectation {
        address buyer;
        address inputAsset;
        uint256 shellId;
        bytes32 routeHash;
        UniversalPoolArtMarketplace.FulfillmentPath fulfillmentPath;
        uint256 sourceId;
        bytes32 artwork;
        uint256 inputAmount;
        uint256 inputRefund;
        uint256 routerFameOutput;
        uint256 marketplaceFameCharge;
        uint256 fameRefund;
    }

    struct RollbackSnapshot {
        uint256 buyerInput;
        uint256 buyerFame;
        uint256 buyerMirror;
        uint256 buyerCheckoutAllowance;
        uint256 checkoutInput;
        uint256 checkoutFame;
        uint256 checkoutMirror;
        uint256 checkoutNative;
        uint256 checkoutRouterAllowance;
        uint256 checkoutMarketAllowance;
        uint256 routerInput;
        uint256 routerFame;
        uint256 venueInput;
        uint256 venueFame;
        uint256 venueOutputIndex;
        address shellOwner;
        bytes32 shellArtwork;
        uint256 marketInventory;
        uint256 marketProviderUnits;
        uint256 providerFame;
        uint256 communityFame;
    }

    struct RollbackContext {
        FameMarketplaceCheckout testedCheckout;
        MockERC20 inputToken;
        address selectedBuyer;
        address routeRouter;
        uint256 shellId;
        address provider;
    }

    struct NativeRollbackSnapshot {
        uint256 buyerNative;
        uint256 buyerFame;
        uint256 buyerMirror;
        uint256 venueWeth;
        uint256 venueFame;
        uint256 routerWeth;
        uint256 routerFame;
        uint256 communityFame;
        uint256 inventory;
        bytes32 shellArtwork;
    }

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

    function testCheckoutHeldBoonsUnsolicitedSocietyAndEmitsCompleteReceipt() public {
        uint256 shellId = _seedShells(market, 2);
        bytes32 artwork = market.artworkHash(shellId);
        _rawTransferSocietyToCheckout(1);
        uint256 charge = _marketCharge();
        uint256 maximumPremium = market.premium();
        FameRouterTypes.Route memory route = _singleLegRoute(address(usdc), 100e6, 100e6, charge);
        uint256 buyerFameBefore = fame.balanceOf(buyer);
        CheckoutSettlementExpectation memory expected;
        expected.buyer = buyer;
        expected.inputAsset = address(usdc);
        expected.shellId = shellId;
        expected.routeHash = keccak256(abi.encode(route));
        expected.fulfillmentPath = UniversalPoolArtMarketplace.FulfillmentPath.Held;
        expected.artwork = artwork;
        expected.inputAmount = 100e6;
        expected.routerFameOutput = charge;
        expected.marketplaceFameCharge = charge;
        expected.fameRefund = fame.unit();
        market.unpause();

        vm.recordLogs();
        vm.prank(buyer);
        (uint256 routerOutput, uint256 marketCharge, uint256 fameRefund, uint256 inputRefund) =
            checkout.checkoutHeld(route, shellId, artwork, maximumPremium, 1);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(routerOutput, charge);
        assertEq(marketCharge, charge);
        assertEq(fameRefund, fame.unit());
        assertEq(inputRefund, 0);
        assertEq(fame.balanceOf(buyer), buyerFameBefore + 2 * fame.unit());
        assertEq(mirror.ownerOf(shellId), buyer);
        _assertCleanCheckout(checkout, address(usdc), address(router));
        _assertCheckoutSettled(logs, checkout, expected);
    }

    function testCheckoutPoolBoonsUnsolicitedSocietyAndEmitsCompleteReceipt() public {
        uint256 shellId = _seedShells(market, 2);
        _rawTransferSocietyToCheckout(1);
        uint256 sourceId = _findMintPoolToken();
        bytes32 artwork = market.artworkHash(sourceId);
        uint256 charge = _marketCharge();
        uint256 maximumPremium = market.premium();
        FameRouterTypes.Route memory route = _singleLegRoute(address(weth), 1 ether, 1 ether, charge);
        uint256 buyerFameBefore = fame.balanceOf(buyer);
        CheckoutSettlementExpectation memory expected;
        expected.buyer = buyer;
        expected.inputAsset = address(weth);
        expected.shellId = shellId;
        expected.routeHash = keccak256(abi.encode(route));
        expected.fulfillmentPath = UniversalPoolArtMarketplace.FulfillmentPath.MintPool;
        expected.sourceId = sourceId;
        expected.artwork = artwork;
        expected.inputAmount = 1 ether;
        expected.routerFameOutput = charge;
        expected.marketplaceFameCharge = charge;
        expected.fameRefund = fame.unit();
        _enablePoolPurchases(market);

        vm.recordLogs();
        vm.prank(buyer);
        (uint256 routerOutput, uint256 marketCharge, uint256 fameRefund, uint256 inputRefund) =
            checkout.checkoutPool(route, shellId, sourceId, artwork, maximumPremium, 1);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(routerOutput, charge);
        assertEq(marketCharge, charge);
        assertEq(fameRefund, fame.unit());
        assertEq(inputRefund, 0);
        assertEq(fame.balanceOf(buyer), buyerFameBefore + 2 * fame.unit());
        assertEq(mirror.ownerOf(shellId), buyer);
        assertEq(market.artworkHash(shellId), artwork);
        _assertCleanCheckout(checkout, address(weth), address(router));
        _assertCheckoutSettled(logs, checkout, expected);
    }

    function testCheckoutCleansEightUnsolicitedSocietyWithinGasBudget() public {
        uint256 shellId = _seedShells(market, 2);
        bytes32 artwork = market.artworkHash(shellId);
        _rawTransferSocietyToCheckout(8);
        uint256 maximumPremium = market.premium();
        FameRouterTypes.Route memory route = _singleLegRoute(address(usdc), 100e6, 100e6, _marketCharge());
        uint256 buyerFameBefore = fame.balanceOf(buyer);
        market.unpause();

        vm.prank(buyer);
        uint256 gasBefore = gasleft();
        checkout.checkoutHeld(route, shellId, artwork, maximumPremium, 1);
        uint256 gasUsed = gasBefore - gasleft();

        assertLt(gasUsed, 15_000_000, "eight-Society cleanup exceeds checkout gas budget");
        assertEq(fame.balanceOf(buyer), buyerFameBefore + 9 * fame.unit());
        assertEq(mirror.ownerOf(shellId), buyer);
        _assertCleanCheckout(checkout, address(usdc), address(router));
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

        vm.expectRevert(abi.encodeWithSelector(UniversalPoolArtMarketplace.BuyerMirrorBalanceTooLow.selector, 2, 1));
        vm.prank(buyer);
        checkout.checkoutHeld(route, shellId, artwork, maxPremium, 2);

        assertEq(usdc.balanceOf(buyer), buyerUsdcBefore);
        assertEq(fame.balanceOf(address(venue)), venueFameBefore);
        assertEq(venue.nextOutputIndex(), 0);
        assertEq(mirror.ownerOf(shellId), address(market));
        assertEq(usdc.allowance(address(checkout), address(router)), 0);
        assertEq(fame.allowance(address(checkout), address(market)), 0);
    }

    function testRouterOutputMismatchRevertsCompleteCheckoutState() public {
        (address provider, uint256 shellId, bytes32 artwork) = _prepareAccountingRollbackMarket();
        uint256 charge = _marketCharge();
        uint256 maximumPremium = market.premium();
        MismatchedOutputCheckoutRouter faultRouter =
            new MismatchedOutputCheckoutRouter(fame, feeRecipient, charge, charge + 1);
        fame.transfer(address(faultRouter), 4 * fame.unit());
        FameMarketplaceCheckout faultCheckout = _replaceCheckout(address(faultRouter), usdc);
        vm.prank(buyer);
        usdc.approve(address(faultCheckout), type(uint256).max);
        FameRouterTypes.Route memory route = _singleLegRoute(address(usdc), 100e6, 100e6, charge);
        route.recipient = address(faultCheckout);
        market.unpause();
        RollbackContext memory context =
            RollbackContext(faultCheckout, usdc, buyer, address(faultRouter), shellId, provider);
        RollbackSnapshot memory beforeState = _snapshotRollback(context);

        vm.expectRevert(
            abi.encodeWithSelector(FameMarketplaceCheckout.RouterOutputMismatch.selector, charge + 1, charge)
        );
        vm.prank(buyer);
        faultCheckout.checkoutHeld(route, shellId, artwork, maximumPremium, 1);

        _assertRollback(context, beforeState);
        assertEq(faultRouter.executionCount(), 0);
    }

    function testMarketplaceChargeMismatchRevertsCompleteCheckoutState() public {
        (address provider, uint256 shellId, bytes32 artwork) = _prepareAccountingRollbackMarket();
        uint256 donation = 7;
        FameDonatingShellRecipient faultBuyer = new FameDonatingShellRecipient(fame);
        faultBuyer.arm(address(checkout), donation);
        fame.transfer(address(faultBuyer), donation);
        usdc.mint(address(faultBuyer), 100e6);
        vm.prank(address(faultBuyer));
        usdc.approve(address(checkout), type(uint256).max);
        uint256 charge = _marketCharge();
        uint256 maximumPremium = market.premium();
        FameRouterTypes.Route memory route = _singleLegRoute(address(usdc), 100e6, 100e6, charge);
        market.unpause();
        RollbackContext memory context =
            RollbackContext(checkout, usdc, address(faultBuyer), address(router), shellId, provider);
        RollbackSnapshot memory beforeState = _snapshotRollback(context);

        vm.expectRevert(
            abi.encodeWithSelector(
                FameMarketplaceCheckout.MarketplaceChargeMismatch.selector, charge, charge - donation
            )
        );
        vm.prank(address(faultBuyer));
        checkout.checkoutHeld(route, shellId, artwork, maximumPremium, 1);

        _assertRollback(context, beforeState);
    }

    function testRefundBalanceMismatchRevertsCompleteCheckoutState() public {
        (address provider, uint256 shellId, bytes32 artwork) = _prepareAccountingRollbackMarket();
        StickyCheckoutRefundToken sticky = new StickyCheckoutRefundToken();
        uint256 maximumPremium = market.premium();
        FameMarketplaceCheckout faultCheckout = _replaceCheckout(address(router), sticky);
        sticky.setCheckout(address(faultCheckout));
        sticky.mint(buyer, 100e6);
        vm.prank(buyer);
        sticky.approve(address(faultCheckout), type(uint256).max);
        FameRouterTypes.Route memory route = _singleLegRoute(address(sticky), 100e6, 40e6, _marketCharge());
        route.recipient = address(faultCheckout);
        market.unpause();
        RollbackContext memory context =
            RollbackContext(faultCheckout, sticky, buyer, address(router), shellId, provider);
        RollbackSnapshot memory beforeState = _snapshotRollback(context);

        vm.expectRevert(
            abi.encodeWithSelector(
                FameMarketplaceCheckout.RefundBalanceMismatch.selector, address(sticky), uint256(0), uint256(60e6)
            )
        );
        vm.prank(buyer);
        faultCheckout.checkoutHeld(route, shellId, artwork, maximumPremium, 1);

        _assertRollback(context, beforeState);
    }

    function testFameAccountingMismatchRevertsCompleteCheckoutState() public {
        (address provider, uint256 shellId, bytes32 artwork) = _prepareAccountingRollbackMarket();
        uint256 donation = 7;
        FameDonatingCheckoutRefundToken hooked = new FameDonatingCheckoutRefundToken(fame);
        FameMarketplaceCheckout faultCheckout = _replaceCheckout(address(router), hooked);
        hooked.arm(address(faultCheckout), donation);
        hooked.mint(buyer, 100e6);
        fame.transfer(address(hooked), donation);
        vm.prank(buyer);
        hooked.approve(address(faultCheckout), type(uint256).max);
        uint256 charge = _marketCharge();
        uint256 maximumPremium = market.premium();
        FameRouterTypes.Route memory route = _singleLegRoute(address(hooked), 100e6, 40e6, charge);
        route.recipient = address(faultCheckout);
        market.unpause();
        RollbackContext memory context =
            RollbackContext(faultCheckout, hooked, buyer, address(router), shellId, provider);
        RollbackSnapshot memory beforeState = _snapshotRollback(context);
        uint256 hookFameBefore = fame.balanceOf(address(hooked));

        vm.expectRevert(
            abi.encodeWithSelector(FameMarketplaceCheckout.FameAccountingMismatch.selector, charge, charge, donation)
        );
        vm.prank(buyer);
        faultCheckout.checkoutHeld(route, shellId, artwork, maximumPremium, 1);

        _assertRollback(context, beforeState);
        assertEq(fame.balanceOf(address(hooked)), hookFameBefore);
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
        vm.deal(address(rejectingBuyer), 2 ether);
        market.unpause();
        NativeRollbackSnapshot memory beforeState = _snapshotNativeRollback(address(rejectingBuyer), shellId);

        vm.expectRevert(SafeTransferLib.ETHTransferFailed.selector);
        vm.prank(address(rejectingBuyer));
        checkout.checkoutHeld{value: 2 ether}(route, shellId, artwork, maxPremium, 1);

        _assertNativeRollback(address(rejectingBuyer), shellId, beforeState);
        assertEq(venue.nextOutputIndex(), 0);
        assertEq(mirror.ownerOf(shellId), address(market));
        assertEq(address(checkout).balance, 0);
        assertEq(weth.balanceOf(address(checkout)), 0);
        assertEq(fame.balanceOf(address(checkout)), 0);
        assertEq(mirror.balanceOf(address(checkout)), 0);
        assertEq(weth.allowance(address(checkout), address(router)), 0);
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
        vm.expectRevert(
            abi.encodeWithSelector(FameMarketplaceCheckout.WrongRouteRecipient.selector, buyer, address(checkout))
        );
        vm.prank(buyer);
        checkout.checkoutHeld(route, shellId, artwork, maxPremium, 1);
        assertEq(usdc.balanceOf(buyer), buyerUsdcBefore);
        assertEq(venue.nextOutputIndex(), 0);

        route.recipient = address(checkout);
        route.tokenOut = address(weth);
        vm.expectRevert(
            abi.encodeWithSelector(FameMarketplaceCheckout.WrongOutputAsset.selector, address(weth), address(fame))
        );
        vm.prank(buyer);
        checkout.checkoutHeld(route, shellId, artwork, maxPremium, 1);
        assertEq(usdc.balanceOf(buyer), buyerUsdcBefore);

        route.tokenOut = address(fame);
        route.minAmountOutAfterFee = _marketCharge() - 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                FameMarketplaceCheckout.ProtectedOutputTooLow.selector, route.minAmountOutAfterFee, _marketCharge()
            )
        );
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
        vm.expectRevert(abi.encodeWithSelector(FameMarketplaceCheckout.UnsupportedInputAsset.selector, address(other)));
        vm.prank(buyer);
        checkout.checkoutHeld(route, shellId, artwork, maxPremium, 1);

        route.tokenIn = address(usdc);
        vm.expectRevert(abi.encodeWithSelector(FameMarketplaceCheckout.UnexpectedNativeValue.selector, uint256(1)));
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
        vm.expectRevert(abi.encodeWithSelector(FameMarketplaceCheckout.CheckoutNotAuthorized.selector, address(0)));
        vm.prank(buyer);
        checkout.checkoutHeld(route, shellId, artwork, maxPremium, 1);
        assertEq(usdc.balanceOf(buyer), buyerUsdcBefore);

        market.pause();
        market.setAuthorizedCheckout(address(checkout));
        market.unpause();
        bytes32 stale = bytes32(uint256(1));
        vm.expectRevert(
            abi.encodeWithSelector(FameMarketplaceCheckout.ArtworkMismatch.selector, shellId, stale, artwork)
        );
        vm.prank(buyer);
        checkout.checkoutHeld(route, shellId, stale, maxPremium, 1);
        assertEq(usdc.balanceOf(buyer), buyerUsdcBefore);

        vm.expectRevert(
            abi.encodeWithSelector(FameMarketplaceCheckout.PremiumExceedsMaximum.selector, maxPremium, maxPremium - 1)
        );
        vm.prank(buyer);
        checkout.checkoutHeld(route, shellId, artwork, maxPremium - 1, 1);
        assertEq(usdc.balanceOf(buyer), buyerUsdcBefore);
    }

    function testPoolRejectsSameShellAndSourceBeforeFunding() public {
        uint256 shellId = _seedShells(market, 2);
        bytes32 artwork = market.artworkHash(shellId);
        FameRouterTypes.Route memory route = _singleLegRoute(address(usdc), 100e6, 100e6, _marketCharge());
        _enablePoolPurchases(market);
        uint256 maxPremium = market.premium();
        uint256 buyerUsdcBefore = usdc.balanceOf(buyer);

        vm.expectRevert(abi.encodeWithSelector(FameMarketplaceCheckout.SourceEqualsShell.selector, shellId));
        vm.prank(buyer);
        checkout.checkoutPool(route, shellId, shellId, artwork, maxPremium, 1);

        assertEq(usdc.balanceOf(buyer), buyerUsdcBefore);
        assertEq(venue.nextOutputIndex(), 0);
    }

    function testAmbiguousPoolSourceRevertsBeforeFundingOnCheckoutAndMarket() public {
        uint256 shellId = _seedShells(market, 2);
        uint256 sourceId = _findMintPoolToken();
        bytes32 artwork = market.artworkHash(sourceId);
        _enablePoolPurchases(market);
        uint256 maxPremium = market.premium();
        FameRouterTypes.Route memory route = _singleLegRoute(address(usdc), 100e6, 100e6, _marketCharge());
        uint256 buyerUsdcBefore = usdc.balanceOf(buyer);

        vm.mockCall(
            address(creatorMagic),
            abi.encodeWithSelector(CreatorArtistMagic.isTokenInMintPool.selector, sourceId),
            abi.encode(true)
        );
        vm.mockCall(
            address(creatorMagic),
            abi.encodeWithSelector(CreatorArtistMagic.isTokenInBurnedPool.selector, sourceId),
            abi.encode(true)
        );

        vm.expectRevert(abi.encodeWithSelector(FameMarketplaceCheckout.AmbiguousPoolSource.selector, sourceId));
        vm.prank(buyer);
        checkout.checkoutPool(route, shellId, sourceId, artwork, maxPremium, 1);
        assertEq(usdc.balanceOf(buyer), buyerUsdcBefore);

        _fundAndApprove(buyer, market, fame.unit() + maxPremium);
        vm.expectRevert(abi.encodeWithSelector(UniversalPoolArtMarketplace.AmbiguousPoolSource.selector, sourceId));
        vm.prank(buyer);
        market.purchasePool(shellId, sourceId, artwork, maxPremium, 0, recipient);

        vm.clearMockedCalls();
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

    function _rawTransferSocietyToCheckout(uint256 count) private {
        address donor = address(0xD011);
        fame.transfer(donor, count * fame.unit());
        uint256[] memory tokenIds = _ownedTokenIds(donor, count);
        vm.startPrank(donor);
        for (uint256 i; i < count; ++i) {
            mirror.transferFrom(donor, address(checkout), tokenIds[i]);
        }
        vm.stopPrank();
        assertEq(mirror.balanceOf(address(checkout)), count);
        assertEq(fame.balanceOf(address(checkout)), count * fame.unit());
    }

    function _assertCleanCheckout(FameMarketplaceCheckout testedCheckout, address inputAsset, address routeRouter)
        private
        view
    {
        assertEq(mirror.balanceOf(address(testedCheckout)), 0);
        assertEq(fame.balanceOf(address(testedCheckout)), 0);
        assertEq(MockERC20(inputAsset).balanceOf(address(testedCheckout)), 0);
        assertEq(MockERC20(inputAsset).allowance(address(testedCheckout), routeRouter), 0);
        assertEq(fame.allowance(address(testedCheckout), address(market)), 0);
    }

    function _assertCheckoutSettled(
        Vm.Log[] memory logs,
        FameMarketplaceCheckout testedCheckout,
        CheckoutSettlementExpectation memory expected
    ) private pure {
        uint256 matches;
        for (uint256 i; i < logs.length; ++i) {
            Vm.Log memory entry = logs[i];
            if (
                entry.emitter != address(testedCheckout) || entry.topics.length != 4
                    || entry.topics[0] != CHECKOUT_SETTLED_TOPIC
            ) continue;
            ++matches;
            assertEq(address(uint160(uint256(entry.topics[1]))), expected.buyer);
            assertEq(address(uint160(uint256(entry.topics[2]))), expected.inputAsset);
            assertEq(uint256(entry.topics[3]), expected.shellId);
            (
                bytes32 routeHash,
                UniversalPoolArtMarketplace.FulfillmentPath fulfillmentPath,
                uint256 sourceId,
                bytes32 artwork,
                uint256 inputAmount,
                uint256 inputRefund,
                uint256 routerFameOutput,
                uint256 marketplaceFameCharge,
                uint256 fameRefund
            ) = abi.decode(
                entry.data,
                (
                    bytes32,
                    UniversalPoolArtMarketplace.FulfillmentPath,
                    uint256,
                    bytes32,
                    uint256,
                    uint256,
                    uint256,
                    uint256,
                    uint256
                )
            );
            assertEq(routeHash, expected.routeHash);
            assertEq(uint8(fulfillmentPath), uint8(expected.fulfillmentPath));
            assertEq(sourceId, expected.sourceId);
            assertEq(artwork, expected.artwork);
            assertEq(inputAmount, expected.inputAmount);
            assertEq(inputRefund, expected.inputRefund);
            assertEq(routerFameOutput, expected.routerFameOutput);
            assertEq(marketplaceFameCharge, expected.marketplaceFameCharge);
            assertEq(fameRefund, expected.fameRefund);
        }
        assertEq(matches, 1);
    }

    function _prepareAccountingRollbackMarket() private returns (address provider, uint256 shellId, bytes32 artwork) {
        provider = address(0xA004);
        _depositUnits(market, provider, 1);
        market.setCommunityFee(11);
        market.setProviderFee(13);
        shellId = _ownedTokenAt(address(market), 0);
        artwork = market.artworkHash(shellId);
    }

    function _snapshotNativeRollback(address selectedBuyer, uint256 shellId)
        private
        view
        returns (NativeRollbackSnapshot memory state)
    {
        state = NativeRollbackSnapshot({
            buyerNative: selectedBuyer.balance,
            buyerFame: fame.balanceOf(selectedBuyer),
            buyerMirror: mirror.balanceOf(selectedBuyer),
            venueWeth: weth.balanceOf(address(venue)),
            venueFame: fame.balanceOf(address(venue)),
            routerWeth: weth.balanceOf(address(router)),
            routerFame: fame.balanceOf(address(router)),
            communityFame: fame.balanceOf(feeRecipient),
            inventory: market.inventory(),
            shellArtwork: market.artworkHash(shellId)
        });
    }

    function _assertNativeRollback(address selectedBuyer, uint256 shellId, NativeRollbackSnapshot memory beforeState)
        private
        view
    {
        assertEq(selectedBuyer.balance, beforeState.buyerNative);
        assertEq(fame.balanceOf(selectedBuyer), beforeState.buyerFame);
        assertEq(mirror.balanceOf(selectedBuyer), beforeState.buyerMirror);
        assertEq(weth.balanceOf(address(venue)), beforeState.venueWeth);
        assertEq(fame.balanceOf(address(venue)), beforeState.venueFame);
        assertEq(weth.balanceOf(address(router)), beforeState.routerWeth);
        assertEq(fame.balanceOf(address(router)), beforeState.routerFame);
        assertEq(fame.balanceOf(feeRecipient), beforeState.communityFame);
        assertEq(market.inventory(), beforeState.inventory);
        assertEq(market.artworkHash(shellId), beforeState.shellArtwork);
    }

    function _replaceCheckout(address routeRouter, MockERC20 inputToken)
        private
        returns (FameMarketplaceCheckout replacement)
    {
        replacement = new FameMarketplaceCheckout(
            routeRouter, address(market), payable(address(fame)), address(inputToken), address(weth)
        );
        market.setAuthorizedCheckout(address(replacement));
    }

    function _snapshotRollback(RollbackContext memory context) private view returns (RollbackSnapshot memory state) {
        state = RollbackSnapshot({
            buyerInput: context.inputToken.balanceOf(context.selectedBuyer),
            buyerFame: fame.balanceOf(context.selectedBuyer),
            buyerMirror: mirror.balanceOf(context.selectedBuyer),
            buyerCheckoutAllowance: context.inputToken
                .allowance(context.selectedBuyer, address(context.testedCheckout)),
            checkoutInput: context.inputToken.balanceOf(address(context.testedCheckout)),
            checkoutFame: fame.balanceOf(address(context.testedCheckout)),
            checkoutMirror: mirror.balanceOf(address(context.testedCheckout)),
            checkoutNative: address(context.testedCheckout).balance,
            checkoutRouterAllowance: context.inputToken.allowance(address(context.testedCheckout), context.routeRouter),
            checkoutMarketAllowance: fame.allowance(address(context.testedCheckout), address(market)),
            routerInput: context.inputToken.balanceOf(context.routeRouter),
            routerFame: fame.balanceOf(context.routeRouter),
            venueInput: context.inputToken.balanceOf(address(venue)),
            venueFame: fame.balanceOf(address(venue)),
            venueOutputIndex: venue.nextOutputIndex(),
            shellOwner: mirror.ownerAt(context.shellId),
            shellArtwork: market.artworkHash(context.shellId),
            marketInventory: market.inventory(),
            marketProviderUnits: market.totalProviderUnits(),
            providerFame: fame.balanceOf(context.provider),
            communityFame: fame.balanceOf(feeRecipient)
        });
    }

    function _assertRollback(RollbackContext memory context, RollbackSnapshot memory beforeState) private view {
        assertEq(context.inputToken.balanceOf(context.selectedBuyer), beforeState.buyerInput);
        assertEq(fame.balanceOf(context.selectedBuyer), beforeState.buyerFame);
        assertEq(mirror.balanceOf(context.selectedBuyer), beforeState.buyerMirror);
        assertEq(
            context.inputToken.allowance(context.selectedBuyer, address(context.testedCheckout)),
            beforeState.buyerCheckoutAllowance
        );
        assertEq(context.inputToken.balanceOf(address(context.testedCheckout)), beforeState.checkoutInput);
        assertEq(fame.balanceOf(address(context.testedCheckout)), beforeState.checkoutFame);
        assertEq(mirror.balanceOf(address(context.testedCheckout)), beforeState.checkoutMirror);
        assertEq(address(context.testedCheckout).balance, beforeState.checkoutNative);
        assertEq(
            context.inputToken.allowance(address(context.testedCheckout), context.routeRouter),
            beforeState.checkoutRouterAllowance
        );
        assertEq(fame.allowance(address(context.testedCheckout), address(market)), beforeState.checkoutMarketAllowance);
        assertEq(context.inputToken.balanceOf(context.routeRouter), beforeState.routerInput);
        assertEq(fame.balanceOf(context.routeRouter), beforeState.routerFame);
        assertEq(context.inputToken.balanceOf(address(venue)), beforeState.venueInput);
        assertEq(fame.balanceOf(address(venue)), beforeState.venueFame);
        assertEq(venue.nextOutputIndex(), beforeState.venueOutputIndex);
        assertEq(mirror.ownerAt(context.shellId), beforeState.shellOwner);
        assertEq(market.artworkHash(context.shellId), beforeState.shellArtwork);
        assertEq(market.inventory(), beforeState.marketInventory);
        assertEq(market.totalProviderUnits(), beforeState.marketProviderUnits);
        assertEq(fame.balanceOf(context.provider), beforeState.providerFame);
        assertEq(fame.balanceOf(feeRecipient), beforeState.communityFame);
    }
}
