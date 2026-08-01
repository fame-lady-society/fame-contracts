// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test} from "forge-std/Test.sol";
import {FameMarketplaceCheckout} from "../src/FameMarketplaceCheckout.sol";
import {FameRouter} from "../src/FameRouter.sol";
import {FameRouterTypes} from "../src/router/FameRouterTypes.sol";
import {UniswapV2Adapter} from "../src/router/adapters/UniswapV2Adapter.sol";
import {UniversalPoolArtMarketplace} from "../src/UniversalPoolArtMarketplace.sol";
import {Fame} from "../src/Fame.sol";
import {FameMirror} from "../src/FameMirror.sol";
import {FameMarketplaceCheckoutTestBase} from "./helpers/FameMarketplaceCheckoutTestBase.sol";
import {MockERC20, MockWETH} from "./router/mocks/MockERC20.sol";
import {PrefundedFameRouterVenue} from "./mocks/PrefundedFameRouterVenue.sol";

contract FameMarketplaceCheckoutHandler is Test {
    struct CheckoutCase {
        address buyer;
        address tokenIn;
        uint256 amountIn;
        uint256 spend;
        uint256 surplus;
        uint256 shellSeed;
        bool nativeInput;
    }

    struct BuyerSnapshot {
        uint256 inputBalance;
        uint256 fameBalance;
    }

    FameMarketplaceCheckout public immutable checkout;
    FameRouter public immutable router;
    UniversalPoolArtMarketplace public immutable market;
    Fame public immutable fame;
    FameMirror public immutable mirror;
    MockERC20 public immutable usdc;
    MockWETH public immutable weth;
    PrefundedFameRouterVenue public immutable venue;

    address[3] private _buyers;

    uint256 public expectedFame;
    uint256 public expectedUsdc;
    uint256 public expectedWeth;
    uint256 public expectedNative;
    uint256 public usdcSuccesses;
    uint256 public wethSuccesses;
    uint256 public nativeSuccesses;
    uint256 public donationActions;

    constructor(
        FameMarketplaceCheckout checkout_,
        FameRouter router_,
        UniversalPoolArtMarketplace market_,
        Fame fame_,
        FameMirror mirror_,
        MockERC20 usdc_,
        MockWETH weth_,
        PrefundedFameRouterVenue venue_,
        address[3] memory buyers_
    ) {
        checkout = checkout_;
        router = router_;
        market = market_;
        fame = fame_;
        mirror = mirror_;
        usdc = usdc_;
        weth = weth_;
        venue = venue_;
        _buyers = buyers_;

        for (uint256 i; i < buyers_.length; ++i) {
            usdc_.mint(buyers_[i], 1_000_000_000e6);
            weth_.mint(buyers_[i], 1_000_000 ether);
            vm.deal(buyers_[i], 1_000_000 ether);
            vm.prank(buyers_[i]);
            usdc_.approve(address(checkout_), type(uint256).max);
            vm.prank(buyers_[i]);
            weth_.approve(address(checkout_), type(uint256).max);
        }
        fame_.setSkipNFT(true);
        vm.deal(address(this), 1_000_000 ether);
    }

    function checkoutUsdc(uint256 buyerSeed, uint64 amountSeed, uint64 spendSeed, uint96 surplusSeed, uint16 shellSeed)
        external
    {
        address selectedBuyer = _buyers[buyerSeed % _buyers.length];
        uint256 amountIn = 1 + (uint256(amountSeed) % 1_000e6);
        uint256 spend = 1 + (uint256(spendSeed) % amountIn);
        uint256 surplus = uint256(surplusSeed) % (fame.unit() / 10);
        _checkoutHeld(CheckoutCase(selectedBuyer, address(usdc), amountIn, spend, surplus, shellSeed, false));
        ++usdcSuccesses;
    }

    function checkoutWeth(uint256 buyerSeed, uint96 amountSeed, uint96 spendSeed, uint96 surplusSeed, uint16 shellSeed)
        external
    {
        address selectedBuyer = _buyers[buyerSeed % _buyers.length];
        uint256 amountIn = 1 + (uint256(amountSeed) % 10 ether);
        uint256 spend = 1 + (uint256(spendSeed) % amountIn);
        uint256 surplus = uint256(surplusSeed) % (fame.unit() / 10);
        _checkoutHeld(CheckoutCase(selectedBuyer, address(weth), amountIn, spend, surplus, shellSeed, false));
        ++wethSuccesses;
    }

    function checkoutNative(
        uint256 buyerSeed,
        uint96 amountSeed,
        uint96 spendSeed,
        uint96 surplusSeed,
        uint16 shellSeed
    ) external {
        address selectedBuyer = _buyers[buyerSeed % _buyers.length];
        uint256 amountIn = 1 + (uint256(amountSeed) % 10 ether);
        uint256 spend = 1 + (uint256(spendSeed) % amountIn);
        uint256 surplus = uint256(surplusSeed) % (fame.unit() / 10);
        _checkoutHeld(
            CheckoutCase(selectedBuyer, FameRouterTypes.NATIVE_ETH, amountIn, spend, surplus, shellSeed, true)
        );
        ++nativeSuccesses;
    }

    function donateAmbient(uint64 usdcSeed, uint96 wethSeed, uint96 fameSeed, uint96 nativeSeed) external {
        uint256 usdcAmount = uint256(usdcSeed) % 10e6;
        uint256 wethAmount = uint256(wethSeed) % 0.1 ether;
        uint256 fameAmount = uint256(fameSeed) % (fame.unit() / 100);
        uint256 nativeAmount = uint256(nativeSeed) % 0.1 ether;

        if (usdcAmount != 0) usdc.mint(address(checkout), usdcAmount);
        if (wethAmount != 0) weth.mint(address(checkout), wethAmount);
        if (fameAmount != 0) fame.transfer(address(checkout), fameAmount);
        if (nativeAmount != 0) {
            (bool success,) = payable(address(checkout)).call{value: nativeAmount}("");
            assertTrue(success);
        }
        expectedUsdc += usdcAmount;
        expectedWeth += wethAmount;
        expectedFame += fameAmount;
        expectedNative += nativeAmount;
        ++donationActions;
    }

    function _checkoutHeld(CheckoutCase memory purchase) private {
        uint256 shellId = _marketShell(purchase.shellSeed);
        bytes32 artwork = market.artworkHash(shellId);
        uint256 premium = market.premium();
        uint256 fameOutput = fame.unit() + premium + purchase.surplus;
        venue.queueOutput(fameOutput);
        FameRouterTypes.Route memory route = purchase.nativeInput
            ? _nativeRoute(purchase.amountIn, purchase.spend, fameOutput)
            : _erc20Route(purchase.tokenIn, purchase.amountIn, purchase.spend, fameOutput);

        BuyerSnapshot memory beforeState = BuyerSnapshot({
            inputBalance: purchase.nativeInput ? purchase.buyer.balance : _balanceOf(purchase.tokenIn, purchase.buyer),
            fameBalance: fame.balanceOf(purchase.buyer)
        });
        vm.prank(purchase.buyer);
        checkout.checkoutHeld{value: purchase.nativeInput ? purchase.amountIn : 0}(route, shellId, artwork, premium, 1);
        _assertCheckout(purchase, shellId, beforeState);
    }

    function _assertCheckout(CheckoutCase memory purchase, uint256 shellId, BuyerSnapshot memory beforeState)
        private
        view
    {
        uint256 buyerInputAfter =
            purchase.nativeInput ? purchase.buyer.balance : _balanceOf(purchase.tokenIn, purchase.buyer);
        assertEq(buyerInputAfter, beforeState.inputBalance - purchase.spend);
        assertEq(fame.balanceOf(purchase.buyer), beforeState.fameBalance + fame.unit() + purchase.surplus);
        assertEq(mirror.ownerOf(shellId), purchase.buyer);
        assertEq(usdc.balanceOf(address(checkout)), expectedUsdc);
        assertEq(weth.balanceOf(address(checkout)), expectedWeth);
        assertEq(fame.balanceOf(address(checkout)), expectedFame);
        assertEq(address(checkout).balance, expectedNative);
        if (!purchase.nativeInput) {
            assertEq(_allowance(purchase.tokenIn, address(checkout), address(router)), 0);
        }
        assertEq(fame.allowance(address(checkout), address(market)), 0);
    }

    function _erc20Route(address tokenIn, uint256 amountIn, uint256 spend, uint256 fameOutput)
        private
        view
        returns (FameRouterTypes.Route memory route)
    {
        route.version = FameRouterTypes.SCHEMA_VERSION;
        route.tokenIn = tokenIn;
        route.tokenOut = address(fame);
        route.amountIn = amountIn;
        route.minAmountOutAfterFee = fame.unit() + market.premium();
        route.recipient = address(checkout);
        route.deadline = block.timestamp + 1 hours;
        route.legs = new FameRouterTypes.Leg[](1);
        route.legs[0] = _v2Leg(tokenIn, spend, fameOutput);
    }

    function _nativeRoute(uint256 amountIn, uint256 spend, uint256 fameOutput)
        private
        view
        returns (FameRouterTypes.Route memory route)
    {
        route.version = FameRouterTypes.SCHEMA_VERSION;
        route.tokenIn = FameRouterTypes.NATIVE_ETH;
        route.tokenOut = address(fame);
        route.amountIn = amountIn;
        route.minAmountOutAfterFee = fame.unit() + market.premium();
        route.recipient = address(checkout);
        route.deadline = block.timestamp + 1 hours;
        route.legs = new FameRouterTypes.Leg[](2);
        route.legs[0] = FameRouterTypes.Leg({
            tokenIn: FameRouterTypes.NATIVE_ETH,
            tokenOut: address(weth),
            venue: FameRouterTypes.VenueFamily.NativeWrap,
            amountMode: FameRouterTypes.AmountMode.Exact,
            amount: spend,
            minAmountOut: 0,
            target: address(weth),
            data: ""
        });
        route.legs[1] = _v2Leg(address(weth), spend, fameOutput);
    }

    function _v2Leg(address tokenIn, uint256 spend, uint256 fameOutput)
        private
        view
        returns (FameRouterTypes.Leg memory leg)
    {
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = address(fame);
        leg = FameRouterTypes.Leg({
            tokenIn: tokenIn,
            tokenOut: address(fame),
            venue: FameRouterTypes.VenueFamily.UniswapV2,
            amountMode: FameRouterTypes.AmountMode.Exact,
            amount: spend,
            minAmountOut: fameOutput,
            target: address(venue),
            data: abi.encode(UniswapV2Adapter.Payload({path: path, deadline: block.timestamp + 1 hours}))
        });
    }

    function _marketShell(uint256 seed) private view returns (uint256 shellId) {
        uint256 inventory = mirror.balanceOf(address(market));
        uint256 selected = seed % inventory;
        uint256 seen;
        for (uint256 tokenId = 1; tokenId <= 888; ++tokenId) {
            if (mirror.ownerAt(tokenId) == address(market)) {
                if (seen == selected) return tokenId;
                ++seen;
            }
        }
        revert("MARKET_SHELL_NOT_FOUND");
    }

    function _balanceOf(address token, address account) private view returns (uint256 balance) {
        (bool success, bytes memory data) = token.staticcall(abi.encodeWithSelector(0x70a08231, account));
        assertTrue(success && data.length == 32);
        balance = abi.decode(data, (uint256));
    }

    function _allowance(address token, address owner, address spender) private view returns (uint256 allowance_) {
        (bool success, bytes memory data) = token.staticcall(abi.encodeWithSelector(0xdd62ed3e, owner, spender));
        assertTrue(success && data.length == 32);
        allowance_ = abi.decode(data, (uint256));
    }
}

contract FameMarketplaceCheckoutInvariantTest is StdInvariant, FameMarketplaceCheckoutTestBase {
    FameMarketplaceCheckoutHandler internal handler;

    function setUp() public override {
        super.setUp();
        _seedShells(market, 8);
        fame.transfer(address(venue), 512 * fame.unit());
        market.unpause();

        address[3] memory buyers = [address(0x5101), address(0x5102), address(0x5103)];
        handler = new FameMarketplaceCheckoutHandler(checkout, router, market, fame, mirror, usdc, weth, venue, buyers);
        fame.transfer(address(handler), 16 * fame.unit());

        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = handler.checkoutUsdc.selector;
        selectors[1] = handler.checkoutWeth.selector;
        selectors[2] = handler.checkoutNative.selector;
        selectors[3] = handler.donateAmbient.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariantCheckoutRetainsOnlyAmbientBalances() public view {
        assertEq(usdc.balanceOf(address(checkout)), handler.expectedUsdc());
        assertEq(weth.balanceOf(address(checkout)), handler.expectedWeth());
        assertEq(fame.balanceOf(address(checkout)), handler.expectedFame());
        assertEq(address(checkout).balance, handler.expectedNative());
    }

    function invariantAllowancesAndMirrorInventoryRemainEmpty() public view {
        assertEq(usdc.allowance(address(checkout), address(router)), 0);
        assertEq(weth.allowance(address(checkout), address(router)), 0);
        assertEq(fame.allowance(address(checkout), address(market)), 0);
        assertEq(mirror.balanceOf(address(checkout)), 0);
        assertTrue(fame.getSkipNFT(address(checkout)));
    }

    function invariantMarketKeepsTheConfiguredCheckout() public view {
        assertEq(market.authorizedCheckout(), address(checkout));
        assertFalse(market.paused());
    }

    function testHandlerExercisesEveryLane() public {
        handler.checkoutUsdc(0, 100e6, 40e6, 1, 0);
        handler.checkoutWeth(1, 1 ether, 0.5 ether, 2, 1);
        handler.checkoutNative(2, 2 ether, 1 ether, 3, 2);
        handler.donateAmbient(1e6, 1e15, 1e18, 1e15);

        assertEq(handler.usdcSuccesses(), 1);
        assertEq(handler.wethSuccesses(), 1);
        assertEq(handler.nativeSuccesses(), 1);
        assertEq(handler.donationActions(), 1);
    }
}
