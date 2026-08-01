// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {FameMarketplaceCheckout} from "../../src/FameMarketplaceCheckout.sol";
import {FameRouter} from "../../src/FameRouter.sol";
import {FameRouterTypes} from "../../src/router/FameRouterTypes.sol";
import {UniswapV2Adapter} from "../../src/router/adapters/UniswapV2Adapter.sol";
import {UniversalPoolArtMarketplaceTestBase} from "./UniversalPoolArtMarketplaceTestBase.sol";
import {MockERC20, MockWETH} from "../router/mocks/MockERC20.sol";
import {PrefundedFameRouterVenue} from "../mocks/PrefundedFameRouterVenue.sol";

abstract contract FameMarketplaceCheckoutTestBase is UniversalPoolArtMarketplaceTestBase {
    FameRouter internal router;
    FameMarketplaceCheckout internal checkout;
    MockERC20 internal usdc;
    MockWETH internal weth;
    PrefundedFameRouterVenue internal venue;

    function setUp() public virtual override {
        super.setUp();

        usdc = new MockERC20("USD Coin", "USDC", 6);
        weth = new MockWETH();
        venue = new PrefundedFameRouterVenue();
        router = new FameRouter(feeRecipient);
        router.setFeePpm(0);
        router.setVenueFamilyEnabled(FameRouterTypes.VenueFamily.UniswapV2, true);
        router.setVenueTargetEnabled(FameRouterTypes.VenueFamily.UniswapV2, address(venue), true);
        router.setVenueFamilyEnabled(FameRouterTypes.VenueFamily.NativeWrap, true);
        router.setVenueTargetEnabled(FameRouterTypes.VenueFamily.NativeWrap, address(weth), true);

        checkout = new FameMarketplaceCheckout(
            address(router), address(market), payable(address(fame)), address(usdc), address(weth)
        );
        market.setAuthorizedCheckout(address(checkout));

        fame.transfer(address(venue), 128 * fame.unit());
        weth.mint(address(venue), 1_000 ether);
        vm.deal(address(weth), 1_000 ether);
        usdc.mint(buyer, 1_000_000e6);
        weth.mint(buyer, 1_000 ether);
        vm.deal(buyer, 1_000 ether);

        vm.startPrank(buyer);
        usdc.approve(address(checkout), type(uint256).max);
        weth.approve(address(checkout), type(uint256).max);
        vm.stopPrank();
    }

    function _marketCharge() internal view returns (uint256) {
        return fame.unit() + market.premium();
    }

    function _singleLegRoute(address tokenIn, uint256 amountIn, uint256 legAmount, uint256 outputAmount)
        internal
        returns (FameRouterTypes.Route memory route)
    {
        venue.queueOutput(outputAmount);
        route.version = FameRouterTypes.SCHEMA_VERSION;
        route.tokenIn = tokenIn;
        route.tokenOut = address(fame);
        route.amountIn = amountIn;
        route.minAmountOutAfterFee = _marketCharge();
        route.recipient = address(checkout);
        route.deadline = block.timestamp + 1 hours;
        route.legs = new FameRouterTypes.Leg[](1);
        route.legs[0] = _v2Leg(tokenIn, address(fame), legAmount, outputAmount, FameRouterTypes.AmountMode.Exact);
    }

    function _nativeRoute(uint256 amountIn, uint256 wrappedAmount, uint256 outputAmount)
        internal
        returns (FameRouterTypes.Route memory route)
    {
        venue.queueOutput(outputAmount);
        route.version = FameRouterTypes.SCHEMA_VERSION;
        route.tokenIn = FameRouterTypes.NATIVE_ETH;
        route.tokenOut = address(fame);
        route.amountIn = amountIn;
        route.minAmountOutAfterFee = _marketCharge();
        route.recipient = address(checkout);
        route.deadline = block.timestamp + 1 hours;
        route.legs = new FameRouterTypes.Leg[](2);
        route.legs[0] = FameRouterTypes.Leg({
            tokenIn: FameRouterTypes.NATIVE_ETH,
            tokenOut: address(weth),
            venue: FameRouterTypes.VenueFamily.NativeWrap,
            amountMode: FameRouterTypes.AmountMode.Exact,
            amount: wrappedAmount,
            minAmountOut: 0,
            target: address(weth),
            data: ""
        });
        route.legs[1] =
            _v2Leg(address(weth), address(fame), wrappedAmount, outputAmount, FameRouterTypes.AmountMode.Exact);
    }

    function _intermediateResidueRoute(
        uint256 amountIn,
        uint256 intermediateOutput,
        uint256 intermediateSpend,
        uint256 fameOutput
    ) internal returns (FameRouterTypes.Route memory route) {
        venue.queueOutput(intermediateOutput);
        venue.queueOutput(fameOutput);
        route.version = FameRouterTypes.SCHEMA_VERSION;
        route.tokenIn = address(usdc);
        route.tokenOut = address(fame);
        route.amountIn = amountIn;
        route.minAmountOutAfterFee = _marketCharge();
        route.recipient = address(checkout);
        route.deadline = block.timestamp + 1 hours;
        route.legs = new FameRouterTypes.Leg[](2);
        route.legs[0] =
            _v2Leg(address(usdc), address(weth), amountIn, intermediateOutput, FameRouterTypes.AmountMode.Exact);
        route.legs[1] =
            _v2Leg(address(weth), address(fame), intermediateSpend, fameOutput, FameRouterTypes.AmountMode.Exact);
    }

    function _wethWithNativeResidueRoute(uint256 amountIn, uint256 unwrapAmount, uint256 swapAmount, uint256 fameOutput)
        internal
        returns (FameRouterTypes.Route memory route)
    {
        venue.queueOutput(fameOutput);
        route.version = FameRouterTypes.SCHEMA_VERSION;
        route.tokenIn = address(weth);
        route.tokenOut = address(fame);
        route.amountIn = amountIn;
        route.minAmountOutAfterFee = _marketCharge();
        route.recipient = address(checkout);
        route.deadline = block.timestamp + 1 hours;
        route.legs = new FameRouterTypes.Leg[](2);
        route.legs[0] = FameRouterTypes.Leg({
            tokenIn: address(weth),
            tokenOut: FameRouterTypes.NATIVE_ETH,
            venue: FameRouterTypes.VenueFamily.NativeWrap,
            amountMode: FameRouterTypes.AmountMode.Exact,
            amount: unwrapAmount,
            minAmountOut: 0,
            target: address(weth),
            data: ""
        });
        route.legs[1] = _v2Leg(address(weth), address(fame), swapAmount, fameOutput, FameRouterTypes.AmountMode.Exact);
    }

    function _v2Leg(
        address tokenIn,
        address tokenOut,
        uint256 amount,
        uint256 minAmountOut,
        FameRouterTypes.AmountMode mode
    ) internal view returns (FameRouterTypes.Leg memory leg) {
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
        leg = FameRouterTypes.Leg({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            venue: FameRouterTypes.VenueFamily.UniswapV2,
            amountMode: mode,
            amount: amount,
            minAmountOut: minAmountOut,
            target: address(venue),
            data: abi.encode(UniswapV2Adapter.Payload({path: path, deadline: block.timestamp + 1 hours}))
        });
    }
}
