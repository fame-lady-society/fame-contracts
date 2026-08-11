// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {FameRouterTypes} from "../src/router/FameRouterTypes.sol";
import {UniversalPoolArtMarketplace} from "../src/UniversalPoolArtMarketplace.sol";
import {FameMarketplaceCheckoutTestBase} from "./helpers/FameMarketplaceCheckoutTestBase.sol";

contract FameMarketplaceCheckoutFuzzTest is FameMarketplaceCheckoutTestBase {
    struct LateFailureSnapshot {
        uint256 buyerInput;
        uint256 buyerFame;
        uint256 buyerMirror;
        uint256 venueInput;
        uint256 venueFame;
        uint256 routerInput;
        uint256 routerFame;
        uint256 checkoutInput;
        uint256 checkoutFame;
        uint256 checkoutMirror;
        uint256 checkoutNative;
        uint256 feeFame;
        uint256 inventory;
        bytes32 shellArtwork;
    }

    function testFuzzRedemptionBatchConsumesMeasuredFameAndClearsInventory(uint8 rawCount, uint96 rawAmbientFame)
        public
    {
        uint256 tokenCount = bound(uint256(rawCount), 1, 32);
        uint256 ambientFame = bound(uint256(rawAmbientFame), 0, fame.unit() - 1);
        uint256[] memory tokenIds = _mintSocietyTokens(buyer, tokenCount);
        _approveSocietyTokens(buyer);
        if (ambientFame != 0) fame.transfer(address(checkout), ambientFame);
        FameRouterTypes.Route memory route = _redemptionRoute(address(weth), tokenCount * fame.unit(), 1 ether);

        vm.prank(buyer);
        (uint256 actualFameInput, uint256 netAmountOut) = checkout.redeemSociety(route, tokenIds);

        assertEq(actualFameInput, tokenCount * fame.unit() + ambientFame);
        assertEq(netAmountOut, 1 ether);
        assertEq(fame.balanceOf(address(checkout)), 0);
        assertEq(mirror.balanceOf(address(checkout)), 0);
        assertEq(fame.allowance(address(checkout), address(router)), 0);
    }

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

        // Boon: buyer recovers input residue + ambient USDC; ambient FAME with surplus.
        assertEq(usdc.balanceOf(buyer), buyerInputBefore - spend + ambientUsdc);
        assertEq(fame.balanceOf(buyer), buyerFameBefore + fame.unit() + surplus + ambientFame);
        assertEq(usdc.balanceOf(address(checkout)), 0);
        assertEq(fame.balanceOf(address(checkout)), 0);
        assertEq(usdc.allowance(address(checkout), address(router)), 0);
        assertEq(fame.allowance(address(checkout), address(market)), 0);
        assertEq(mirror.balanceOf(address(checkout)), 0);
    }

    function testFuzzPremiumDecreaseRefundsTheDifference(uint96 rawQuotedPremium, uint96 rawCurrentPremium) public {
        uint256 quotedPremium = bound(uint256(rawQuotedPremium), 1, fame.unit() / 10);
        uint256 currentPremium = bound(uint256(rawCurrentPremium), 1, quotedPremium);
        market.setCommunityFee(quotedPremium);

        uint256 shellId = _seedShells(market, 2);
        bytes32 artwork = market.artworkHash(shellId);
        FameRouterTypes.Route memory route =
            _singleLegRoute(address(weth), 1 ether, 1 ether, fame.unit() + quotedPremium);
        market.setCommunityFee(currentPremium);
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

        LateFailureSnapshot memory beforeState = _snapshotLateFailure(shellId);

        vm.expectRevert(abi.encodeWithSelector(UniversalPoolArtMarketplace.BuyerMirrorBalanceTooLow.selector, 2, 1));
        vm.prank(buyer);
        checkout.checkoutHeld(route, shellId, artwork, maxPremium, 2);

        _assertLateFailureRollback(shellId, beforeState);
        assertEq(venue.nextOutputIndex(), 0);
        assertEq(mirror.ownerOf(shellId), address(market));
        assertEq(usdc.allowance(address(checkout), address(router)), 0);
        assertEq(fame.allowance(address(checkout), address(market)), 0);
    }

    function _snapshotLateFailure(uint256 shellId) private view returns (LateFailureSnapshot memory state) {
        state = LateFailureSnapshot({
            buyerInput: usdc.balanceOf(buyer),
            buyerFame: fame.balanceOf(buyer),
            buyerMirror: mirror.balanceOf(buyer),
            venueInput: usdc.balanceOf(address(venue)),
            venueFame: fame.balanceOf(address(venue)),
            routerInput: usdc.balanceOf(address(router)),
            routerFame: fame.balanceOf(address(router)),
            checkoutInput: usdc.balanceOf(address(checkout)),
            checkoutFame: fame.balanceOf(address(checkout)),
            checkoutMirror: mirror.balanceOf(address(checkout)),
            checkoutNative: address(checkout).balance,
            feeFame: fame.balanceOf(feeRecipient),
            inventory: market.inventory(),
            shellArtwork: market.artworkHash(shellId)
        });
    }

    function _assertLateFailureRollback(uint256 shellId, LateFailureSnapshot memory beforeState) private view {
        assertEq(usdc.balanceOf(buyer), beforeState.buyerInput);
        assertEq(fame.balanceOf(buyer), beforeState.buyerFame);
        assertEq(mirror.balanceOf(buyer), beforeState.buyerMirror);
        assertEq(usdc.balanceOf(address(venue)), beforeState.venueInput);
        assertEq(fame.balanceOf(address(venue)), beforeState.venueFame);
        assertEq(usdc.balanceOf(address(router)), beforeState.routerInput);
        assertEq(fame.balanceOf(address(router)), beforeState.routerFame);
        assertEq(usdc.balanceOf(address(checkout)), beforeState.checkoutInput);
        assertEq(fame.balanceOf(address(checkout)), beforeState.checkoutFame);
        assertEq(mirror.balanceOf(address(checkout)), beforeState.checkoutMirror);
        assertEq(address(checkout).balance, beforeState.checkoutNative);
        assertEq(fame.balanceOf(feeRecipient), beforeState.feeFame);
        assertEq(market.inventory(), beforeState.inventory);
        assertEq(market.artworkHash(shellId), beforeState.shellArtwork);
    }
}
