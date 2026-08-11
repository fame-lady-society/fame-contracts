// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {FameMarketplaceCheckout} from "../../src/FameMarketplaceCheckout.sol";
import {FameRouter} from "../../src/FameRouter.sol";
import {FameRouterTypes} from "../../src/router/FameRouterTypes.sol";
import {UniswapV2Adapter} from "../../src/router/adapters/UniswapV2Adapter.sol";
import {UniversalRouterAdapter} from "../../src/router/adapters/UniversalRouterAdapter.sol";
import {UniversalPoolArtMarketplaceTestBase} from "./UniversalPoolArtMarketplaceTestBase.sol";
import {MockERC20, MockWETH} from "../router/mocks/MockERC20.sol";
import {MockPermit2, MockRouter} from "../router/mocks/MockRouter.sol";
import {PrefundedFameRouterVenue} from "../mocks/PrefundedFameRouterVenue.sol";

abstract contract FameMarketplaceCheckoutTestBase is UniversalPoolArtMarketplaceTestBase {
    FameRouter internal router;
    FameMarketplaceCheckout internal checkout;
    MockERC20 internal usdc;
    MockWETH internal weth;
    PrefundedFameRouterVenue internal venue;
    MockRouter internal universalVenue;

    address internal constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    function setUp() public virtual override {
        super.setUp();

        usdc = new MockERC20("USD Coin", "USDC", 6);
        weth = new MockWETH();
        venue = new PrefundedFameRouterVenue();
        universalVenue = new MockRouter();
        vm.etch(PERMIT2, address(new MockPermit2()).code);
        router = new FameRouter(feeRecipient);
        router.setFeePpm(0);
        router.setVenueFamilyEnabled(FameRouterTypes.VenueFamily.UniswapV2, true);
        router.setVenueTargetEnabled(FameRouterTypes.VenueFamily.UniswapV2, address(venue), true);
        router.setVenueFamilyEnabled(FameRouterTypes.VenueFamily.NativeWrap, true);
        router.setVenueTargetEnabled(FameRouterTypes.VenueFamily.NativeWrap, address(weth), true);
        router.setVenueFamilyEnabled(FameRouterTypes.VenueFamily.UniswapV4, true);
        router.setVenueTargetEnabled(FameRouterTypes.VenueFamily.UniswapV4, address(universalVenue), true);

        checkout = new FameMarketplaceCheckout(
            address(router), address(market), payable(address(fame)), address(usdc), address(weth)
        );
        market.setAuthorizedCheckout(address(checkout));

        fame.transfer(address(venue), 128 * fame.unit());
        weth.mint(address(venue), 1_000 ether);
        usdc.mint(address(venue), 1_000_000e6);
        vm.deal(address(weth), 1_000 ether);
        vm.deal(address(universalVenue), 1_000 ether);
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

    function _redemptionRoute(address tokenOut, uint256 quotedFameInput, uint256 outputAmount)
        internal
        returns (FameRouterTypes.Route memory route)
    {
        route.version = FameRouterTypes.SCHEMA_VERSION;
        route.tokenIn = address(fame);
        route.tokenOut = tokenOut;
        route.amountIn = quotedFameInput;
        route.minAmountOutAfterFee = outputAmount;
        route.recipient = buyer;
        route.deadline = block.timestamp + 1 hours;
        route.legs = new FameRouterTypes.Leg[](1);

        if (tokenOut == FameRouterTypes.NATIVE_ETH) {
            universalVenue.queueOutput(outputAmount);
            route.legs[0] = FameRouterTypes.Leg({
                tokenIn: address(fame),
                tokenOut: tokenOut,
                venue: FameRouterTypes.VenueFamily.UniswapV4,
                amountMode: FameRouterTypes.AmountMode.All,
                amount: 0,
                minAmountOut: outputAmount,
                target: address(universalVenue),
                data: abi.encode(
                    UniversalRouterAdapter.V4SwapPayload({
                        tokenIn: address(fame),
                        tokenOut: tokenOut,
                        amountIn: 0,
                        minAmountOut: outputAmount,
                        currency0: address(fame),
                        currency1: tokenOut,
                        zeroForOne: true,
                        fee: 500,
                        tickSpacing: 0,
                        hooks: address(0),
                        hookData: "",
                        deadline: block.timestamp + 1 hours,
                        recipient: address(router),
                        payerIsUser: false
                    })
                )
            });
        } else {
            venue.queueOutput(outputAmount);
            route.legs[0] = _v2Leg(address(fame), tokenOut, 0, outputAmount, FameRouterTypes.AmountMode.All);
        }
    }

    function _redemptionViaWethToNativeRoute(uint256 quotedFameInput, uint256 outputAmount)
        internal
        returns (FameRouterTypes.Route memory route)
    {
        venue.queueOutput(outputAmount);
        route.version = FameRouterTypes.SCHEMA_VERSION;
        route.tokenIn = address(fame);
        route.tokenOut = FameRouterTypes.NATIVE_ETH;
        route.amountIn = quotedFameInput;
        route.minAmountOutAfterFee = outputAmount;
        route.recipient = buyer;
        route.deadline = block.timestamp + 1 hours;
        route.legs = new FameRouterTypes.Leg[](2);
        route.legs[0] = _v2Leg(address(fame), address(weth), 0, outputAmount, FameRouterTypes.AmountMode.All);
        route.legs[1] = FameRouterTypes.Leg({
            tokenIn: address(weth),
            tokenOut: FameRouterTypes.NATIVE_ETH,
            venue: FameRouterTypes.VenueFamily.NativeWrap,
            amountMode: FameRouterTypes.AmountMode.All,
            amount: 0,
            minAmountOut: 0,
            target: address(weth),
            data: ""
        });
    }

    function _splitRedemptionRoute(
        uint256 quotedFameInput,
        uint256 exactFameSpend,
        uint256 intermediateUsdc,
        uint256 finalWeth
    ) internal returns (FameRouterTypes.Route memory route) {
        venue.queueOutput(intermediateUsdc);
        venue.queueOutput(finalWeth);
        route.version = FameRouterTypes.SCHEMA_VERSION;
        route.tokenIn = address(fame);
        route.tokenOut = address(weth);
        route.amountIn = quotedFameInput;
        route.minAmountOutAfterFee = finalWeth;
        route.recipient = buyer;
        route.deadline = block.timestamp + 1 hours;
        route.legs = new FameRouterTypes.Leg[](2);
        route.legs[0] =
            _v2Leg(address(fame), address(usdc), exactFameSpend, intermediateUsdc, FameRouterTypes.AmountMode.Exact);
        route.legs[1] = _v2Leg(address(fame), address(weth), 0, finalWeth, FameRouterTypes.AmountMode.All);
    }

    function _mintSocietyTokens(address account, uint256 count) internal returns (uint256[] memory tokenIds) {
        fame.transfer(account, count * fame.unit());
        tokenIds = checkout.ownedSocietyTokenIds(account, 1, 889);
    }

    function _approveSocietyTokens(address account) internal {
        vm.prank(account);
        mirror.setApprovalForAll(address(checkout), true);
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
