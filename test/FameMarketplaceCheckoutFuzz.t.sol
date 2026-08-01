// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {FameRouterTypes} from "../src/router/FameRouterTypes.sol";
import {FameMarketplaceCheckoutTestBase} from "./helpers/FameMarketplaceCheckoutTestBase.sol";

contract FameMarketplaceCheckoutFuzzTest is FameMarketplaceCheckoutTestBase {
    function testFuzzUsdcFundingOutputAndAmbientBalancesReconcile(
        uint64 rawAmountIn,
        uint64 rawSpend,
        uint96 rawSurplus,
        uint64 rawAmbientUsdc,
        uint96 rawAmbientFame
    ) public {
        uint256 amountIn = bound(uint256(rawAmountIn), 1, 1_000_000e6);
        uint256 spend = bound(uint256(rawSpend), 1, amountIn);
        uint256 surplus = bound(uint256(rawSurplus), 0, fame.unit() / 2);
        uint256 ambientUsdc = bound(uint256(rawAmbientUsdc), 0, 1_000_000e6);
        uint256 ambientFame = bound(uint256(rawAmbientFame), 0, fame.unit() / 2);
        usdc.mint(address(checkout), ambientUsdc);
        if (ambientFame != 0) fame.transfer(address(checkout), ambientFame);

        uint256 shellId = _seedShells(market, 2);
        bytes32 artwork = market.artworkHash(shellId);
        uint256 maxPremium = market.premium();
        FameRouterTypes.Route memory route = _singleLegRoute(address(usdc), amountIn, spend, _marketCharge() + surplus);
        market.unpause();

        uint256 buyerInputBefore = usdc.balanceOf(buyer);
        uint256 buyerFameBefore = fame.balanceOf(buyer);
        vm.prank(buyer);
        checkout.checkoutHeld(route, shellId, artwork, maxPremium, 1);

        assertEq(usdc.balanceOf(buyer), buyerInputBefore - spend);
        assertEq(fame.balanceOf(buyer), buyerFameBefore + fame.unit() + surplus);
        assertEq(usdc.balanceOf(address(checkout)), ambientUsdc);
        assertEq(fame.balanceOf(address(checkout)), ambientFame);
        assertEq(usdc.allowance(address(checkout), address(router)), 0);
        assertEq(fame.allowance(address(checkout), address(market)), 0);
        assertEq(mirror.balanceOf(address(checkout)), 0);
    }

    function testFuzzPremiumDecreaseRefundsTheDifference(uint96 rawQuotedPremium, uint96 rawCurrentPremium) public {
        uint256 quotedPremium = bound(uint256(rawQuotedPremium), 1, fame.unit() / 2);
        uint256 currentPremium = bound(uint256(rawCurrentPremium), 1, quotedPremium);
        market.setPremium(quotedPremium);

        uint256 shellId = _seedShells(market, 2);
        bytes32 artwork = market.artworkHash(shellId);
        FameRouterTypes.Route memory route =
            _singleLegRoute(address(weth), 1 ether, 1 ether, fame.unit() + quotedPremium);
        market.setPremium(currentPremium);
        market.unpause();

        uint256 buyerFameBefore = fame.balanceOf(buyer);
        vm.prank(buyer);
        checkout.checkoutHeld(route, shellId, artwork, quotedPremium, 1);

        assertEq(fame.balanceOf(buyer), buyerFameBefore + fame.unit() + quotedPremium - currentPremium);
        assertEq(fame.balanceOf(address(checkout)), 0);
    }

    function testFuzzLateFailureRollsBackEverySwapDelta(uint64 rawAmountIn, uint64 rawSpend, uint96 rawSurplus) public {
        uint256 amountIn = bound(uint256(rawAmountIn), 1, 1_000_000e6);
        uint256 spend = bound(uint256(rawSpend), 1, amountIn);
        uint256 surplus = bound(uint256(rawSurplus), 0, fame.unit() / 2);
        uint256 shellId = _seedShells(market, 2);
        bytes32 artwork = market.artworkHash(shellId);
        uint256 maxPremium = market.premium();
        FameRouterTypes.Route memory route = _singleLegRoute(address(usdc), amountIn, spend, _marketCharge() + surplus);
        market.unpause();

        uint256 buyerInputBefore = usdc.balanceOf(buyer);
        uint256 venueInputBefore = usdc.balanceOf(address(venue));
        uint256 venueFameBefore = fame.balanceOf(address(venue));
        uint256 feeFameBefore = fame.balanceOf(feeRecipient);

        vm.expectRevert();
        vm.prank(buyer);
        checkout.checkoutHeld(route, shellId, artwork, maxPremium, 2);

        assertEq(usdc.balanceOf(buyer), buyerInputBefore);
        assertEq(usdc.balanceOf(address(venue)), venueInputBefore);
        assertEq(fame.balanceOf(address(venue)), venueFameBefore);
        assertEq(fame.balanceOf(feeRecipient), feeFameBefore);
        assertEq(venue.nextOutputIndex(), 0);
        assertEq(mirror.ownerOf(shellId), address(market));
        assertEq(usdc.allowance(address(checkout), address(router)), 0);
        assertEq(fame.allowance(address(checkout), address(market)), 0);
    }
}
