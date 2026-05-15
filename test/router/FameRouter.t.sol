// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {FameRouter} from "../../src/FameRouter.sol";
import {FameRouterAccounting} from "../../src/router/FameRouterAccounting.sol";
import {FameRouterTypes} from "../../src/router/FameRouterTypes.sol";
import {AerodromeV2RouterAdapter} from "../../src/router/adapters/AerodromeV2RouterAdapter.sol";
import {SlipstreamAdapter} from "../../src/router/adapters/SlipstreamAdapter.sol";
import {SolidlyRouterAdapter} from "../../src/router/adapters/SolidlyRouterAdapter.sol";
import {UniversalRouterAdapter} from "../../src/router/adapters/UniversalRouterAdapter.sol";
import {UniswapV2Adapter} from "../../src/router/adapters/UniswapV2Adapter.sol";
import {IAerodromeV2Router} from "../../src/router/interfaces/IAerodromeV2Router.sol";
import {ISolidlyRouter} from "../../src/router/interfaces/ISolidlyRouter.sol";
import {MockERC20, MockWETH, RevertingBalanceToken, ShortBalanceToken, TransferTaxERC20} from "./mocks/MockERC20.sol";
import {MockPermit2, MockRouter, RescueAttemptingRouter} from "./mocks/MockRouter.sol";
import {ReentrantToken} from "./mocks/ReentrantToken.sol";

contract FameRouterTest is Test {
    event FeeRecipientUpdated(address indexed feeRecipient);
    event FeePpmUpdated(uint32 feePpm);
    event RouteExecuted(
        address indexed payer,
        address indexed recipient,
        address indexed tokenOut,
        bytes32 routeHash,
        uint16 schemaVersion,
        address tokenIn,
        uint256 amountIn,
        uint256 grossAmountOut,
        uint256 feeAmount,
        uint256 netAmountOut
    );
    event Rescue(address indexed asset, address indexed to, uint256 amount);

    struct RawLeg {
        address tokenIn;
        address tokenOut;
        uint8 venue;
        uint8 amountMode;
        uint256 amount;
        uint256 minAmountOut;
        address target;
        bytes data;
    }

    struct RawRoute {
        uint16 version;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 minAmountOutAfterFee;
        address recipient;
        uint256 deadline;
        RawLeg[] legs;
    }

    FameRouter private router;
    MockRouter private mockVenue;
    MockWETH private weth;
    MockERC20 private usdc;
    MockERC20 private fame;

    address private owner = address(0x1001);
    address private user = address(0x1002);
    address private recipient = address(0x1003);
    address private feeRecipient = address(0x1004);
    address private constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    function setUp() public {
        weth = new MockWETH();
        usdc = new MockERC20("USD Coin", "USDC", 6);
        fame = new MockERC20("Fame", "FAME", 18);
        mockVenue = new MockRouter();
        vm.etch(PERMIT2, address(new MockPermit2()).code);

        vm.prank(owner);
        router = new FameRouter(feeRecipient);

        vm.startPrank(owner);
        router.setVenueFamilyEnabled(FameRouterTypes.VenueFamily.UniswapV2, true);
        router.setVenueFamilyEnabled(FameRouterTypes.VenueFamily.Solidly, true);
        router.setVenueFamilyEnabled(FameRouterTypes.VenueFamily.Slipstream, true);
        router.setVenueFamilyEnabled(FameRouterTypes.VenueFamily.Slipstream2, true);
        router.setVenueFamilyEnabled(FameRouterTypes.VenueFamily.UniswapV3, true);
        router.setVenueFamilyEnabled(FameRouterTypes.VenueFamily.UniswapV4, true);
        router.setVenueFamilyEnabled(FameRouterTypes.VenueFamily.NativeWrap, true);
        router.setVenueFamilyEnabled(FameRouterTypes.VenueFamily.AerodromeV2, true);
        router.setVenueTargetEnabled(FameRouterTypes.VenueFamily.UniswapV2, address(mockVenue), true);
        router.setVenueTargetEnabled(FameRouterTypes.VenueFamily.Solidly, address(mockVenue), true);
        router.setVenueTargetEnabled(FameRouterTypes.VenueFamily.Slipstream, address(mockVenue), true);
        router.setVenueTargetEnabled(FameRouterTypes.VenueFamily.Slipstream2, address(mockVenue), true);
        router.setVenueTargetEnabled(FameRouterTypes.VenueFamily.UniswapV3, address(mockVenue), true);
        router.setVenueTargetEnabled(FameRouterTypes.VenueFamily.UniswapV4, address(mockVenue), true);
        router.setVenueTargetEnabled(FameRouterTypes.VenueFamily.NativeWrap, address(weth), true);
        router.setVenueTargetEnabled(FameRouterTypes.VenueFamily.AerodromeV2, address(mockVenue), true);
        vm.stopPrank();

        usdc.mint(user, 1_000_000e6);
        weth.mint(user, 1_000 ether);

        vm.startPrank(user);
        usdc.approve(address(router), type(uint256).max);
        weth.approve(address(router), type(uint256).max);
        vm.stopPrank();
    }

    function test_ExactInputRouteChargesDefaultFeeOnce() public {
        FameRouterTypes.Route memory route = _singleLegRoute(
            address(usdc), address(fame), 100e6, 997 ether, 1_000 ether, FameRouterTypes.AmountMode.Exact, 100e6
        );

        uint256 expectedFee =
            (1_000 ether * uint256(FameRouterTypes.DEFAULT_FEE_PPM)) / uint256(FameRouterTypes.FEE_DENOMINATOR);
        bytes32 expectedRouteHash = router.hashRoute(route);
        vm.expectEmit(true, true, true, true, address(router));
        emit RouteExecuted(
            user,
            recipient,
            address(fame),
            expectedRouteHash,
            FameRouterTypes.SCHEMA_VERSION,
            address(usdc),
            100e6,
            1_000 ether,
            expectedFee,
            1_000 ether - expectedFee
        );

        vm.prank(user);
        uint256 net = router.executeRoute(route);

        assertEq(net, 1_000 ether - expectedFee);
        assertEq(fame.balanceOf(feeRecipient), expectedFee);
        assertEq(fame.balanceOf(recipient), 1_000 ether - expectedFee);
        assertEq(usdc.balanceOf(address(router)), 0);
        assertEq(fame.balanceOf(address(router)), 0);
    }

    function test_SplitRouteChargesFeeOnceOnMergedOutput() public {
        FameRouterTypes.Route memory route;
        route.version = FameRouterTypes.SCHEMA_VERSION;
        route.tokenIn = address(usdc);
        route.tokenOut = address(fame);
        route.amountIn = 100e6;
        route.minAmountOutAfterFee = 1_990 ether;
        route.recipient = recipient;
        route.deadline = block.timestamp + 1;
        route.legs = new FameRouterTypes.Leg[](2);
        route.legs[0] = _leg(address(usdc), address(fame), 40e6, 1_000 ether, FameRouterTypes.AmountMode.Exact, 40e6);
        route.legs[1] = _leg(
            address(usdc),
            address(fame),
            FameRouterTypes.BPS_DENOMINATOR,
            1_000 ether,
            FameRouterTypes.AmountMode.BalanceBps,
            60e6
        );

        vm.prank(user);
        uint256 net = router.executeRoute(route);

        uint256 expectedFee =
            (2_000 ether * uint256(FameRouterTypes.DEFAULT_FEE_PPM)) / uint256(FameRouterTypes.FEE_DENOMINATOR);
        assertEq(net, 2_000 ether - expectedFee);
        assertEq(fame.balanceOf(feeRecipient), expectedFee);
        assertEq(fame.balanceOf(recipient), 2_000 ether - expectedFee);
        assertEq(usdc.balanceOf(address(router)), 0);
        assertEq(fame.balanceOf(address(router)), 0);
    }

    function test_AllModeConsumesOnlyRouteLocalInput() public {
        usdc.mint(address(router), 900e6);
        FameRouterTypes.Route memory route = _singleLegRoute(
            address(usdc), address(fame), 100e6, 997 ether, 1_000 ether, FameRouterTypes.AmountMode.All, 0
        );

        uint256 beforeUserUsdc = usdc.balanceOf(user);
        vm.prank(user);
        router.executeRoute(route);

        assertEq(usdc.balanceOf(address(mockVenue)), 100e6);
        assertEq(usdc.balanceOf(address(router)), 900e6);
        assertEq(usdc.balanceOf(user), beforeUserUsdc - 100e6);
    }

    function test_BalanceBpsConsumesOnlyRouteLocalInputAndRefundsRemainder() public {
        usdc.mint(address(router), 900e6);
        FameRouterTypes.Route memory route = _singleLegRoute(
            address(usdc), address(fame), 100e6, 0, 250 ether, FameRouterTypes.AmountMode.BalanceBps, 2_500
        );

        uint256 beforeUserUsdc = usdc.balanceOf(user);
        vm.prank(user);
        router.executeRoute(route);

        assertEq(usdc.balanceOf(address(mockVenue)), 25e6);
        assertEq(usdc.balanceOf(address(router)), 900e6);
        assertEq(usdc.balanceOf(user), beforeUserUsdc - 25e6);
    }

    function test_RouteRefundsUnusedInputDustToSender() public {
        FameRouterTypes.Route memory route = _singleLegRoute(
            address(usdc), address(fame), 100e6, 997 ether, 1_000 ether, FameRouterTypes.AmountMode.Exact, 40e6
        );

        uint256 beforeUserUsdc = usdc.balanceOf(user);
        vm.prank(user);
        router.executeRoute(route);

        assertEq(usdc.balanceOf(user), beforeUserUsdc - 40e6);
        assertEq(usdc.balanceOf(address(router)), 0);
    }

    function test_AmbientDonatedBalanceCannotSatisfyFinalMinimum() public {
        fame.mint(address(router), 500 ether);
        FameRouterTypes.Route memory route = _singleLegRoute(
            address(usdc), address(fame), 100e6, 1_490 ether, 1_000 ether, FameRouterTypes.AmountMode.Exact, 100e6
        );

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(FameRouter.FinalOutputTooLow.selector, 997_778_000_000_000_000_000, 1_490 ether)
        );
        router.executeRoute(route);

        assertEq(fame.balanceOf(address(router)), 500 ether);
    }

    function test_ExpiredRouteRevertsBeforePullingInput() public {
        FameRouterTypes.Route memory route = _singleLegRoute(
            address(usdc), address(fame), 100e6, 0, 1_000 ether, FameRouterTypes.AmountMode.Exact, 100e6
        );
        route.deadline = block.timestamp - 1;

        uint256 beforeUserUsdc = usdc.balanceOf(user);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(FameRouter.DeadlineExpired.selector, route.deadline, block.timestamp));
        router.executeRoute(route);
        assertEq(usdc.balanceOf(user), beforeUserUsdc);
    }

    function test_DisabledVenueRevertsBeforePullingInput() public {
        vm.prank(owner);
        router.setVenueFamilyEnabled(FameRouterTypes.VenueFamily.UniswapV2, false);

        FameRouterTypes.Route memory route = _singleLegRoute(
            address(usdc), address(fame), 100e6, 0, 1_000 ether, FameRouterTypes.AmountMode.Exact, 100e6
        );

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(FameRouter.VenueFamilyDisabled.selector, FameRouterTypes.VenueFamily.UniswapV2)
        );
        router.executeRoute(route);
    }

    function test_BalanceBpsCannotExceedDenominator() public {
        FameRouterTypes.Route memory route = _singleLegRoute(
            address(usdc), address(fame), 100e6, 0, 1_000 ether, FameRouterTypes.AmountMode.BalanceBps, 10_001
        );

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(FameRouterAccounting.BalanceBpsTooHigh.selector, 10_001));
        router.executeRoute(route);
    }

    function test_SchemaWireEnumOrdinalsMatchDocs() public pure {
        assertEq(uint8(FameRouterTypes.VenueFamily.Solidly), 0);
        assertEq(uint8(FameRouterTypes.VenueFamily.UniswapV2), 1);
        assertEq(uint8(FameRouterTypes.VenueFamily.Slipstream), 2);
        assertEq(uint8(FameRouterTypes.VenueFamily.Slipstream2), 3);
        assertEq(uint8(FameRouterTypes.VenueFamily.UniswapV3), 4);
        assertEq(uint8(FameRouterTypes.VenueFamily.UniswapV4), 5);
        assertEq(uint8(FameRouterTypes.VenueFamily.NativeWrap), 6);
        assertEq(uint8(FameRouterTypes.VenueFamily.AerodromeV2), 7);

        assertEq(uint8(FameRouterTypes.AmountMode.Exact), 0);
        assertEq(uint8(FameRouterTypes.AmountMode.BalanceBps), 1);
        assertEq(uint8(FameRouterTypes.AmountMode.All), 2);
    }

    function test_NextVenueOrdinalCannotBeDecodedFromSchemaRoute() public {
        FameRouterTypes.Route memory route = _singleLegRoute(
            address(usdc), address(fame), 100e6, 0, 1_000 ether, FameRouterTypes.AmountMode.Exact, 100e6
        );

        RawRoute memory rawRoute = _rawRouteWithVenueOrdinal(route, 8);

        (bool success, bytes memory returndata) =
            address(router).call(abi.encodeWithSelector(FameRouter.executeRoute.selector, rawRoute));
        assertFalse(success);
        assertEq(returndata.length, 0);
    }

    function test_NextAmountModeOrdinalCannotBeDecodedFromSchemaRoute() public {
        FameRouterTypes.Route memory route = _singleLegRoute(
            address(usdc), address(fame), 100e6, 0, 1_000 ether, FameRouterTypes.AmountMode.Exact, 100e6
        );

        RawRoute memory rawRoute = _rawRouteWithVenueAndAmountModeOrdinal(route, 1, 3);

        (bool success,) = address(router).call(abi.encodeWithSelector(FameRouter.executeRoute.selector, rawRoute));
        assertFalse(success);
    }

    function test_NonNativeInputRejectsMsgValue() public {
        FameRouterTypes.Route memory route = _singleLegRoute(
            address(usdc), address(fame), 100e6, 0, 1_000 ether, FameRouterTypes.AmountMode.Exact, 100e6
        );

        vm.deal(user, 1 ether);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(FameRouter.UnexpectedNativeValue.selector, 1 wei));
        router.executeRoute{value: 1 wei}(route);
    }

    function test_NativeInputRequiresExactMsgValue() public {
        FameRouterTypes.Route memory route = _singleLegRoute(
            FameRouterTypes.NATIVE_ETH,
            address(fame),
            1 ether,
            0,
            1_000 ether,
            FameRouterTypes.AmountMode.Exact,
            1 ether
        );

        vm.deal(user, 1 ether);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(FameRouter.NativeValueMismatch.selector, 1 ether, 0.9 ether));
        router.executeRoute{value: 0.9 ether}(route);
    }

    function test_NativeInputExecutesAndSettlesOutput() public {
        FameRouterTypes.Route memory route = _singleLegRoute(
            FameRouterTypes.NATIVE_ETH,
            address(fame),
            1 ether,
            997 ether,
            1_000 ether,
            FameRouterTypes.AmountMode.Exact,
            1 ether
        );

        vm.deal(user, 1 ether);
        vm.prank(user);
        router.executeRoute{value: 1 ether}(route);

        assertEq(address(router).balance, 0);
        assertGt(fame.balanceOf(recipient), 997 ether);
    }

    function test_Erc20InputCanSettleNativeEthOutputWithFee() public {
        FameRouterTypes.Route memory route = _singleLegRoute(
            address(usdc),
            FameRouterTypes.NATIVE_ETH,
            100e6,
            997_000_000_000_000_000,
            1 ether,
            FameRouterTypes.AmountMode.Exact,
            100e6
        );
        vm.deal(address(mockVenue), 1 ether);

        uint256 expectedFee =
            (1 ether * uint256(FameRouterTypes.DEFAULT_FEE_PPM)) / uint256(FameRouterTypes.FEE_DENOMINATOR);

        vm.prank(user);
        uint256 net = router.executeRoute(route);

        assertEq(net, 1 ether - expectedFee);
        assertEq(feeRecipient.balance, expectedFee);
        assertEq(recipient.balance, 1 ether - expectedFee);
        assertEq(address(router).balance, 0);
    }

    function test_NativeWrapExactEthToWethThenSwapSettlesFame() public {
        FameRouterTypes.Route memory route;
        route.version = FameRouterTypes.SCHEMA_VERSION;
        route.tokenIn = FameRouterTypes.NATIVE_ETH;
        route.tokenOut = address(fame);
        route.amountIn = 1 ether;
        route.minAmountOutAfterFee = 997 ether;
        route.recipient = recipient;
        route.deadline = block.timestamp + 1;
        route.legs = new FameRouterTypes.Leg[](2);
        route.legs[0] =
            _nativeWrapLeg(FameRouterTypes.NATIVE_ETH, address(weth), FameRouterTypes.AmountMode.Exact, 1 ether);
        route.legs[1] = _leg(address(weth), address(fame), 0, 1_000 ether, FameRouterTypes.AmountMode.All, 997 ether);

        uint256 expectedFee =
            (1_000 ether * uint256(FameRouterTypes.DEFAULT_FEE_PPM)) / uint256(FameRouterTypes.FEE_DENOMINATOR);

        vm.deal(user, 1 ether);
        vm.prank(user);
        uint256 net = router.executeRoute{value: 1 ether}(route);

        assertEq(net, 1_000 ether - expectedFee);
        assertEq(weth.balanceOf(address(router)), 0);
        assertEq(fame.balanceOf(address(router)), 0);
        assertEq(address(router).balance, 0);
        assertEq(fame.balanceOf(feeRecipient), expectedFee);
        assertEq(fame.balanceOf(recipient), 1_000 ether - expectedFee);
    }

    function test_NativeWrapAllWethToEthThenSettlesNativeOutput() public {
        fame.mint(user, 100 ether);
        vm.prank(user);
        fame.approve(address(router), type(uint256).max);
        vm.deal(address(weth), 1 ether);

        FameRouterTypes.Route memory route;
        route.version = FameRouterTypes.SCHEMA_VERSION;
        route.tokenIn = address(fame);
        route.tokenOut = FameRouterTypes.NATIVE_ETH;
        route.amountIn = 100 ether;
        route.minAmountOutAfterFee = 997_000_000_000_000_000;
        route.recipient = recipient;
        route.deadline = block.timestamp + 1;
        route.legs = new FameRouterTypes.Leg[](2);
        route.legs[0] =
            _leg(address(fame), address(weth), 100 ether, 1 ether, FameRouterTypes.AmountMode.Exact, 1 ether);
        route.legs[1] = _nativeWrapLeg(address(weth), FameRouterTypes.NATIVE_ETH, FameRouterTypes.AmountMode.All, 0);

        uint256 expectedFee =
            (1 ether * uint256(FameRouterTypes.DEFAULT_FEE_PPM)) / uint256(FameRouterTypes.FEE_DENOMINATOR);

        vm.prank(user);
        uint256 net = router.executeRoute(route);

        assertEq(net, 1 ether - expectedFee);
        assertEq(feeRecipient.balance, expectedFee);
        assertEq(recipient.balance, 1 ether - expectedFee);
        assertEq(weth.balanceOf(address(router)), 0);
        assertEq(address(router).balance, 0);
    }

    function test_NativeWrapBalanceBpsWrapsPartialInputAndRefundsRest() public {
        FameRouterTypes.Route memory route;
        route.version = FameRouterTypes.SCHEMA_VERSION;
        route.tokenIn = FameRouterTypes.NATIVE_ETH;
        route.tokenOut = address(fame);
        route.amountIn = 2 ether;
        route.minAmountOutAfterFee = 997 ether;
        route.recipient = recipient;
        route.deadline = block.timestamp + 1;
        route.legs = new FameRouterTypes.Leg[](2);
        route.legs[0] = _nativeWrapLeg(
            FameRouterTypes.NATIVE_ETH,
            address(weth),
            FameRouterTypes.AmountMode.BalanceBps,
            FameRouterTypes.BPS_DENOMINATOR / 2
        );
        route.legs[1] = _leg(address(weth), address(fame), 0, 1_000 ether, FameRouterTypes.AmountMode.All, 997 ether);

        uint256 beforeUserBalance = user.balance;
        vm.deal(user, 2 ether);
        vm.prank(user);
        router.executeRoute{value: 2 ether}(route);

        assertEq(user.balance, beforeUserBalance + 1 ether);
        assertEq(weth.balanceOf(address(router)), 0);
        assertEq(address(router).balance, 0);
    }

    function test_NativeWrapRejectsSingleLegStandaloneWrapBeforeFundsMove() public {
        FameRouterTypes.Route memory route;
        route.version = FameRouterTypes.SCHEMA_VERSION;
        route.tokenIn = FameRouterTypes.NATIVE_ETH;
        route.tokenOut = address(weth);
        route.amountIn = 1 ether;
        route.recipient = recipient;
        route.deadline = block.timestamp + 1;
        route.legs = new FameRouterTypes.Leg[](1);
        route.legs[0] =
            _nativeWrapLeg(FameRouterTypes.NATIVE_ETH, address(weth), FameRouterTypes.AmountMode.Exact, 1 ether);

        vm.deal(user, 1 ether);
        vm.prank(user);
        vm.expectRevert(FameRouter.StandaloneNativeWrapRoute.selector);
        router.executeRoute{value: 1 ether}(route);

        assertEq(weth.balanceOf(address(router)), 0);
        assertEq(address(router).balance, 0);
    }

    function test_NativeWrapRejectsAllWrapRouteBeforeFundsMove() public {
        FameRouterTypes.Route memory route;
        route.version = FameRouterTypes.SCHEMA_VERSION;
        route.tokenIn = address(weth);
        route.tokenOut = address(fame);
        route.amountIn = 1 ether;
        route.recipient = recipient;
        route.deadline = block.timestamp + 1;
        route.legs = new FameRouterTypes.Leg[](2);
        route.legs[0] =
            _nativeWrapLeg(address(weth), FameRouterTypes.NATIVE_ETH, FameRouterTypes.AmountMode.Exact, 1 ether);
        route.legs[1] = _nativeWrapLeg(FameRouterTypes.NATIVE_ETH, address(weth), FameRouterTypes.AmountMode.All, 0);

        uint256 beforeUserWeth = weth.balanceOf(user);
        vm.prank(user);
        vm.expectRevert(FameRouter.StandaloneNativeWrapRoute.selector);
        router.executeRoute(route);

        assertEq(weth.balanceOf(user), beforeUserWeth);
        assertEq(weth.balanceOf(address(router)), 0);
    }

    function test_NativeWrapRejectsNonEmptyPayloadBeforeFundsMove() public {
        FameRouterTypes.Route memory route = _nativeWrapThenSwapRoute();
        route.legs[0].data = hex"01";

        vm.deal(user, 1 ether);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(FameRouter.NativeWrapPayloadNotEmpty.selector, 0));
        router.executeRoute{value: 1 ether}(route);

        assertEq(weth.balanceOf(address(router)), 0);
    }

    function test_NativeWrapRejectsNonzeroMinAmountOutBeforeFundsMove() public {
        FameRouterTypes.Route memory route = _nativeWrapThenSwapRoute();
        route.legs[0].minAmountOut = 1 ether;

        vm.deal(user, 1 ether);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(FameRouter.NativeWrapMinAmountOutNotZero.selector, 0, 1 ether));
        router.executeRoute{value: 1 ether}(route);

        assertEq(weth.balanceOf(address(router)), 0);
    }

    function test_NativeWrapRejectsBadDirectionBeforeFundsMove() public {
        FameRouterTypes.Route memory route = _nativeWrapThenSwapRoute();
        route.legs[0].tokenIn = address(weth);
        route.legs[0].tokenOut = address(fame);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                FameRouter.BadNativeWrapDirection.selector, 0, address(weth), address(fame), address(weth)
            )
        );
        router.executeRoute(route);
    }

    function test_NativeWrapRejectsDisabledTargetBeforeFundsMove() public {
        vm.prank(owner);
        router.setVenueTargetEnabled(FameRouterTypes.VenueFamily.NativeWrap, address(weth), false);

        FameRouterTypes.Route memory route = _nativeWrapThenSwapRoute();

        vm.deal(user, 1 ether);
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                FameRouter.VenueTargetDisabled.selector, FameRouterTypes.VenueFamily.NativeWrap, address(weth)
            )
        );
        router.executeRoute{value: 1 ether}(route);

        assertEq(weth.balanceOf(address(router)), 0);
    }

    function test_NativeWrapUnwrapDoesNotApproveWethTarget() public {
        fame.mint(user, 100 ether);
        vm.prank(user);
        fame.approve(address(router), type(uint256).max);
        vm.deal(address(weth), 1 ether);

        FameRouterTypes.Route memory route;
        route.version = FameRouterTypes.SCHEMA_VERSION;
        route.tokenIn = address(fame);
        route.tokenOut = FameRouterTypes.NATIVE_ETH;
        route.amountIn = 100 ether;
        route.recipient = recipient;
        route.deadline = block.timestamp + 1;
        route.legs = new FameRouterTypes.Leg[](2);
        route.legs[0] =
            _leg(address(fame), address(weth), 100 ether, 1 ether, FameRouterTypes.AmountMode.Exact, 1 ether);
        route.legs[1] = _nativeWrapLeg(address(weth), FameRouterTypes.NATIVE_ETH, FameRouterTypes.AmountMode.All, 0);

        vm.prank(user);
        router.executeRoute(route);

        assertEq(weth.allowance(address(router), address(weth)), 0);
    }

    function test_NativeWrapUnwrapUsesComputedSpendAsEffectiveMinimum() public {
        fame.mint(user, 100 ether);
        vm.prank(user);
        fame.approve(address(router), type(uint256).max);
        vm.deal(address(weth), 1 ether);
        weth.setShortWithdraw(true);

        FameRouterTypes.Route memory route;
        route.version = FameRouterTypes.SCHEMA_VERSION;
        route.tokenIn = address(fame);
        route.tokenOut = FameRouterTypes.NATIVE_ETH;
        route.amountIn = 100 ether;
        route.recipient = recipient;
        route.deadline = block.timestamp + 1;
        route.legs = new FameRouterTypes.Leg[](2);
        route.legs[0] =
            _leg(address(fame), address(weth), 100 ether, 1 ether, FameRouterTypes.AmountMode.Exact, 1 ether);
        route.legs[1] = _nativeWrapLeg(address(weth), FameRouterTypes.NATIVE_ETH, FameRouterTypes.AmountMode.All, 0);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(FameRouter.LegOutputTooLow.selector, 1, 1 ether - 1, 1 ether));
        router.executeRoute(route);
    }

    function test_OwnerCanUpdateFeeWithinCapAndFeeRecipient() public {
        address newRecipient = address(0x4444);
        vm.startPrank(owner);
        vm.expectEmit(true, false, false, true, address(router));
        emit FeeRecipientUpdated(newRecipient);
        router.setFeeRecipient(newRecipient);
        vm.expectEmit(false, false, false, true, address(router));
        emit FeePpmUpdated(FameRouterTypes.MAX_FEE_PPM);
        router.setFeePpm(FameRouterTypes.MAX_FEE_PPM);
        vm.stopPrank();

        assertEq(router.feeRecipient(), newRecipient);
        assertEq(router.feePpm(), FameRouterTypes.MAX_FEE_PPM);
    }

    function test_SetFeeRecipientRejectsZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(FameRouter.ZeroAddress.selector);
        router.setFeeRecipient(address(0));
    }

    function test_NonOwnerCannotUseGovernanceOrRescueControls() public {
        vm.startPrank(user);
        vm.expectRevert(Ownable.Unauthorized.selector);
        router.setFeeRecipient(address(0x4444));
        vm.expectRevert(Ownable.Unauthorized.selector);
        router.setFeePpm(FameRouterTypes.MAX_FEE_PPM);
        vm.expectRevert(Ownable.Unauthorized.selector);
        router.setVenueFamilyEnabled(FameRouterTypes.VenueFamily.UniswapV2, false);
        vm.expectRevert(Ownable.Unauthorized.selector);
        router.setVenueTargetEnabled(FameRouterTypes.VenueFamily.UniswapV2, address(mockVenue), false);
        vm.expectRevert(Ownable.Unauthorized.selector);
        router.setV4HookDataHashEnabled(bytes32(uint256(1)), true);
        vm.expectRevert(Ownable.Unauthorized.selector);
        router.rescue(address(usdc), user, 1);
        vm.stopPrank();
    }

    function test_ConstructorRejectsZeroFeeRecipient() public {
        vm.expectRevert(FameRouter.ZeroAddress.selector);
        new FameRouter(address(0));
    }

    function test_FeeCapRejectsAboveMaximum() public {
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                FameRouter.FeeTooHigh.selector, FameRouterTypes.MAX_FEE_PPM + 1, FameRouterTypes.MAX_FEE_PPM
            )
        );
        router.setFeePpm(FameRouterTypes.MAX_FEE_PPM + 1);
    }

    function test_UniversalRouterRejectsRawExecutePayload() public {
        FameRouterTypes.Route memory route = _singleLegRoute(
            address(usdc), address(fame), 100e6, 0, 1_000 ether, FameRouterTypes.AmountMode.Exact, 100e6
        );
        route.legs[0].venue = FameRouterTypes.VenueFamily.UniswapV3;
        route.legs[0].data = abi.encodeWithSelector(bytes4(keccak256("execute(bytes,bytes[],uint256)")));

        vm.prank(user);
        vm.expectRevert(UniversalRouterAdapter.RawUniversalRouterCommandsDisabled.selector);
        router.executeRoute(route);
    }

    function test_TypedSolidlyAdapterExecutesRoutePayload() public {
        FameRouterTypes.Route memory route = _singleLegRoute(
            address(usdc), address(fame), 100e6, 997 ether, 1_000 ether, FameRouterTypes.AmountMode.Exact, 100e6
        );
        route.legs[0].venue = FameRouterTypes.VenueFamily.Solidly;
        route.legs[0].data = _solidlyPayload(address(usdc), address(fame));

        vm.prank(user);
        router.executeRoute(route);

        assertGt(fame.balanceOf(recipient), 997 ether);
    }

    function test_TypedAerodromeV2AdapterExecutesExplicitFactoryRoutePayload() public {
        FameRouterTypes.Route memory route = _singleLegRoute(
            address(usdc), address(fame), 100e6, 997 ether, 1_000 ether, FameRouterTypes.AmountMode.Exact, 100e6
        );
        route.legs[0].venue = FameRouterTypes.VenueFamily.AerodromeV2;
        route.legs[0].data = _aerodromeV2Payload(address(usdc), address(fame), address(0xFAc707));

        vm.prank(user);
        router.executeRoute(route);

        assertGt(fame.balanceOf(recipient), 997 ether);
    }

    function test_AerodromeV2RejectsNativeEth() public {
        FameRouterTypes.Route memory route = _singleLegRoute(
            FameRouterTypes.NATIVE_ETH,
            address(fame),
            1 ether,
            0,
            1_000 ether,
            FameRouterTypes.AmountMode.Exact,
            1 ether
        );
        route.legs[0].venue = FameRouterTypes.VenueFamily.AerodromeV2;
        route.legs[0].target = address(mockVenue);
        route.legs[0].data = _aerodromeV2Payload(FameRouterTypes.NATIVE_ETH, address(fame), address(0xFAc707));

        vm.deal(user, 1 ether);
        vm.prank(user);
        vm.expectRevert(AerodromeV2RouterAdapter.NativeEthUnsupported.selector);
        router.executeRoute{value: 1 ether}(route);
    }

    function test_AerodromeV2RejectsBadEndpointBeforeUsingAmbientBalance() public {
        fame.mint(address(router), 500 ether);
        FameRouterTypes.Route memory route = _singleLegRoute(
            address(usdc), address(fame), 100e6, 997 ether, 1_000 ether, FameRouterTypes.AmountMode.Exact, 100e6
        );
        route.legs[0].venue = FameRouterTypes.VenueFamily.AerodromeV2;
        route.legs[0].data = _aerodromeV2Payload(address(weth), address(fame), address(0xFAc707));

        vm.prank(user);
        vm.expectRevert(AerodromeV2RouterAdapter.InvalidRoute.selector);
        router.executeRoute(route);

        assertEq(fame.balanceOf(address(router)), 500 ether);
    }

    function test_AerodromeV2RejectsZeroFactory() public {
        FameRouterTypes.Route memory route = _singleLegRoute(
            address(usdc), address(fame), 100e6, 0, 1_000 ether, FameRouterTypes.AmountMode.Exact, 100e6
        );
        route.legs[0].venue = FameRouterTypes.VenueFamily.AerodromeV2;
        route.legs[0].data = _aerodromeV2Payload(address(usdc), address(fame), address(0));

        vm.prank(user);
        vm.expectRevert(AerodromeV2RouterAdapter.InvalidRoute.selector);
        router.executeRoute(route);
    }

    function test_AerodromeV2RejectsBrokenRouteContinuity() public {
        FameRouterTypes.Route memory route = _singleLegRoute(
            address(usdc), address(fame), 100e6, 0, 1_000 ether, FameRouterTypes.AmountMode.Exact, 100e6
        );
        route.legs[0].venue = FameRouterTypes.VenueFamily.AerodromeV2;

        IAerodromeV2Router.AerodromeRoute[] memory routes = new IAerodromeV2Router.AerodromeRoute[](2);
        routes[0] = IAerodromeV2Router.AerodromeRoute({
            from: address(usdc),
            to: address(weth),
            stable: false,
            factory: address(0xFAc707)
        });
        routes[1] = IAerodromeV2Router.AerodromeRoute({
            from: address(fame),
            to: address(fame),
            stable: false,
            factory: address(0xFAc707)
        });
        route.legs[0].data =
            abi.encode(AerodromeV2RouterAdapter.Payload({routes: routes, deadline: block.timestamp + 1}));

        vm.prank(user);
        vm.expectRevert(AerodromeV2RouterAdapter.InvalidRoute.selector);
        router.executeRoute(route);
    }

    function test_AerodromeV2DirectApprovalIsClearedAfterSuccessfulRoute() public {
        FameRouterTypes.Route memory route = _singleLegRoute(
            address(usdc), address(fame), 100e6, 0, 1_000 ether, FameRouterTypes.AmountMode.Exact, 100e6
        );
        route.legs[0].venue = FameRouterTypes.VenueFamily.AerodromeV2;
        route.legs[0].data = _aerodromeV2Payload(address(usdc), address(fame), address(0xFAc707));

        vm.prank(user);
        router.executeRoute(route);

        assertEq(usdc.allowance(address(router), address(mockVenue)), 0);
    }

    function test_DirectVenueApprovalIsClearedAfterSuccessfulRoute() public {
        FameRouterTypes.Route memory route = _singleLegRoute(
            address(usdc), address(fame), 100e6, 0, 1_000 ether, FameRouterTypes.AmountMode.Exact, 100e6
        );

        vm.prank(user);
        router.executeRoute(route);

        assertEq(usdc.allowance(address(router), address(mockVenue)), 0);
    }

    function test_Permit2ApprovalIsClearedAfterSuccessfulUniversalRouterRoute() public {
        FameRouterTypes.Route memory route = _singleLegRoute(
            address(usdc), address(fame), 100e6, 0, 1_000 ether, FameRouterTypes.AmountMode.Exact, 100e6
        );
        route.legs[0].venue = FameRouterTypes.VenueFamily.UniswapV3;
        route.legs[0].data = _v3Payload(address(usdc), address(fame));

        vm.prank(user);
        router.executeRoute(route);

        MockPermit2 permit2 = MockPermit2(PERMIT2);
        assertEq(usdc.allowance(address(router), PERMIT2), 0);
        assertEq(permit2.allowance(address(router), address(usdc), address(mockVenue)), 0);
    }

    function test_V4Permit2ApprovalIsClearedAfterSuccessfulUniversalRouterRoute() public {
        FameRouterTypes.Route memory route = _singleLegRoute(
            address(usdc), address(fame), 100e6, 0, 1_000 ether, FameRouterTypes.AmountMode.Exact, 100e6
        );
        route.legs[0].venue = FameRouterTypes.VenueFamily.UniswapV4;
        route.legs[0].data = _v4Payload(address(usdc), address(fame), 100e6, 100e6);

        vm.prank(user);
        router.executeRoute(route);

        MockPermit2 permit2 = MockPermit2(PERMIT2);
        assertEq(usdc.allowance(address(router), PERMIT2), 0);
        assertEq(permit2.allowance(address(router), address(usdc), address(mockVenue)), 0);
    }

    function test_TypedSlipstreamAdapterExecutesPathPayload() public {
        FameRouterTypes.Route memory route = _singleLegRoute(
            address(usdc), address(fame), 100e6, 997 ether, 1_000 ether, FameRouterTypes.AmountMode.Exact, 100e6
        );
        route.legs[0].venue = FameRouterTypes.VenueFamily.Slipstream;
        route.legs[0].data = _slipstreamPayload(address(usdc), address(fame), 100);

        vm.prank(user);
        router.executeRoute(route);

        assertGt(fame.balanceOf(recipient), 997 ether);
    }

    function test_SlipstreamRejectsWrongPathEndpointBeforeUsingAmbientBalance() public {
        fame.mint(address(router), 500 ether);
        FameRouterTypes.Route memory route = _singleLegRoute(
            address(usdc), address(fame), 100e6, 997 ether, 1_000 ether, FameRouterTypes.AmountMode.Exact, 100e6
        );
        route.legs[0].venue = FameRouterTypes.VenueFamily.Slipstream;
        route.legs[0].data = _slipstreamPayload(address(weth), address(fame), 100);

        vm.prank(user);
        vm.expectRevert(SlipstreamAdapter.InvalidPath.selector);
        router.executeRoute(route);

        assertEq(fame.balanceOf(address(router)), 500 ether);
    }

    function test_Slipstream2RejectsRouterConfigMismatch() public {
        FameRouterTypes.Route memory route = _singleLegRoute(
            address(usdc), address(fame), 100e6, 0, 1_000 ether, FameRouterTypes.AmountMode.Exact, 100e6
        );
        route.legs[0].venue = FameRouterTypes.VenueFamily.Slipstream2;
        route.legs[0].data = abi.encode(
            SlipstreamAdapter.Payload({
                router: address(0xBEEF),
                factory: address(0xFAc707),
                tokenIn: address(usdc),
                tokenOut: address(fame),
                tickSpacing: 100,
                sqrtPriceLimitX96: 0,
                deadline: block.timestamp + 1
            })
        );

        vm.prank(user);
        vm.expectRevert(SlipstreamAdapter.InvalidPath.selector);
        router.executeRoute(route);
    }

    function test_UniversalRouterRejectsExternalRecipient() public {
        FameRouterTypes.Route memory route = _singleLegRoute(
            address(usdc), address(fame), 100e6, 0, 1_000 ether, FameRouterTypes.AmountMode.Exact, 100e6
        );
        route.legs[0].venue = FameRouterTypes.VenueFamily.UniswapV3;
        route.legs[0].data = abi.encode(
            UniversalRouterAdapter.V3ExactInputPayload({
                path: abi.encodePacked(address(usdc), uint24(500), address(fame)),
                deadline: block.timestamp + 1,
                payerIsUser: true,
                recipient: recipient
            })
        );

        vm.prank(user);
        vm.expectRevert(UniversalRouterAdapter.InvalidUniversalRouterPayload.selector);
        router.executeRoute(route);
    }

    function test_UniversalRouterRejectsV4AmountMismatch() public {
        FameRouterTypes.Route memory route = _singleLegRoute(
            address(usdc), address(fame), 100e6, 0, 1_000 ether, FameRouterTypes.AmountMode.Exact, 100e6
        );
        route.legs[0].venue = FameRouterTypes.VenueFamily.UniswapV4;
        route.legs[0].data = _v4Payload(address(usdc), address(fame), 99e6, 0);

        vm.prank(user);
        vm.expectRevert(UniversalRouterAdapter.InvalidUniversalRouterPayload.selector);
        router.executeRoute(route);
    }

    function test_UniversalRouterV4AllowsPayloadZeroAmountForRouteLocalAll() public {
        FameRouterTypes.Route memory route =
            _singleLegRoute(address(usdc), address(fame), 100e6, 0, 1_000 ether, FameRouterTypes.AmountMode.All, 0);
        route.legs[0].venue = FameRouterTypes.VenueFamily.UniswapV4;
        route.legs[0].data = _v4Payload(address(usdc), address(fame), 0, 0);

        vm.prank(user);
        router.executeRoute(route);

        assertEq(usdc.balanceOf(address(mockVenue)), 100e6);
        assertEq(fame.balanceOf(address(router)), 0);
    }

    function test_UniversalRouterAcceptsAllowedV4HookData() public {
        FameRouterTypes.Route memory route = _singleLegRoute(
            address(usdc), address(fame), 100e6, 0, 1_000 ether, FameRouterTypes.AmountMode.Exact, 100e6
        );
        route.legs[0].venue = FameRouterTypes.VenueFamily.UniswapV4;
        bytes memory hookData = hex"01";
        route.legs[0].data = _v4PayloadWithHook(address(usdc), address(fame), 100e6, 100e6, address(0xBEEF), hookData);

        bytes32 hookDataKey = _v4HookDataKey(address(usdc), address(fame), 500, 0, address(0xBEEF), hookData);
        vm.prank(owner);
        router.setV4HookDataHashEnabled(hookDataKey, true);

        vm.prank(user);
        router.executeRoute(route);

        assertEq(mockVenue.lastV4HookData(), hookData);
    }

    function test_UniversalRouterRejectsUnapprovedV4HookData() public {
        FameRouterTypes.Route memory route = _singleLegRoute(
            address(usdc), address(fame), 100e6, 0, 1_000 ether, FameRouterTypes.AmountMode.Exact, 100e6
        );
        route.legs[0].venue = FameRouterTypes.VenueFamily.UniswapV4;
        bytes memory hookData = hex"01";
        route.legs[0].data = _v4PayloadWithHook(address(usdc), address(fame), 100e6, 100e6, address(0xBEEF), hookData);

        bytes32 hookDataKey = _v4HookDataKey(address(usdc), address(fame), 500, 0, address(0xBEEF), hookData);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(FameRouter.V4HookDataNotAllowed.selector, hookDataKey));
        router.executeRoute(route);
    }

    function test_RejectsBadRouteVersionBeforePullingInput() public {
        FameRouterTypes.Route memory route = _singleLegRoute(
            address(usdc), address(fame), 100e6, 0, 1_000 ether, FameRouterTypes.AmountMode.Exact, 100e6
        );
        route.version = 2;

        uint256 beforeUserUsdc = usdc.balanceOf(user);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(FameRouter.BadRouteVersion.selector, 2));
        router.executeRoute(route);
        assertEq(usdc.balanceOf(user), beforeUserUsdc);
    }

    function test_RejectsZeroRecipientBeforePullingInput() public {
        FameRouterTypes.Route memory route = _singleLegRoute(
            address(usdc), address(fame), 100e6, 0, 1_000 ether, FameRouterTypes.AmountMode.Exact, 100e6
        );
        route.recipient = address(0);

        uint256 beforeUserUsdc = usdc.balanceOf(user);
        vm.prank(user);
        vm.expectRevert(FameRouter.ZeroAddress.selector);
        router.executeRoute(route);
        assertEq(usdc.balanceOf(user), beforeUserUsdc);
    }

    function test_RejectsZeroAmountBeforePullingInput() public {
        FameRouterTypes.Route memory route = _singleLegRoute(
            address(usdc), address(fame), 100e6, 0, 1_000 ether, FameRouterTypes.AmountMode.Exact, 100e6
        );
        route.amountIn = 0;

        uint256 beforeUserUsdc = usdc.balanceOf(user);
        vm.prank(user);
        vm.expectRevert(FameRouter.ZeroAmountIn.selector);
        router.executeRoute(route);
        assertEq(usdc.balanceOf(user), beforeUserUsdc);
    }

    function test_RejectsEmptyRouteBeforePullingInput() public {
        FameRouterTypes.Route memory route = _singleLegRoute(
            address(usdc), address(fame), 100e6, 0, 1_000 ether, FameRouterTypes.AmountMode.Exact, 100e6
        );
        route.legs = new FameRouterTypes.Leg[](0);

        uint256 beforeUserUsdc = usdc.balanceOf(user);
        vm.prank(user);
        vm.expectRevert(FameRouter.EmptyRoute.selector);
        router.executeRoute(route);
        assertEq(usdc.balanceOf(user), beforeUserUsdc);
    }

    function test_RejectsTooManyLegsBeforePullingInput() public {
        FameRouterTypes.Route memory route = _singleLegRoute(
            address(usdc), address(fame), 100e6, 0, 1_000 ether, FameRouterTypes.AmountMode.Exact, 100e6
        );
        route.legs = new FameRouterTypes.Leg[](uint256(FameRouterTypes.MAX_ROUTE_LEGS) + 1);

        uint256 beforeUserUsdc = usdc.balanceOf(user);
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(FameRouter.TooManyLegs.selector, uint256(FameRouterTypes.MAX_ROUTE_LEGS) + 1)
        );
        router.executeRoute(route);
        assertEq(usdc.balanceOf(user), beforeUserUsdc);
    }

    function test_RejectsOversizedPayloadBeforePullingInput() public {
        FameRouterTypes.Route memory route = _singleLegRoute(
            address(usdc), address(fame), 100e6, 0, 1_000 ether, FameRouterTypes.AmountMode.Exact, 100e6
        );
        route.legs[0].data = new bytes(uint256(FameRouterTypes.MAX_PAYLOAD_BYTES) + 1);

        uint256 beforeUserUsdc = usdc.balanceOf(user);
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                FameRouter.PayloadTooLarge.selector, 0, uint256(FameRouterTypes.MAX_PAYLOAD_BYTES) + 1
            )
        );
        router.executeRoute(route);
        assertEq(usdc.balanceOf(user), beforeUserUsdc);
    }

    function test_RejectsDisabledTargetBeforePullingInput() public {
        FameRouterTypes.Route memory route = _singleLegRoute(
            address(usdc), address(fame), 100e6, 0, 1_000 ether, FameRouterTypes.AmountMode.Exact, 100e6
        );
        route.legs[0].target = address(0xBEEF);

        uint256 beforeUserUsdc = usdc.balanceOf(user);
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                FameRouter.VenueTargetDisabled.selector, FameRouterTypes.VenueFamily.UniswapV2, address(0xBEEF)
            )
        );
        router.executeRoute(route);
        assertEq(usdc.balanceOf(user), beforeUserUsdc);
    }

    function test_RejectsRouteThatNeverProducesFinalOutputBeforePullingInput() public {
        FameRouterTypes.Route memory route = _singleLegRoute(
            address(usdc), address(fame), 100e6, 0, 1_000 ether, FameRouterTypes.AmountMode.Exact, 100e6
        );
        route.tokenOut = address(weth);

        uint256 beforeUserUsdc = usdc.balanceOf(user);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(FameRouter.RouteNeverProducesOutput.selector, address(weth)));
        router.executeRoute(route);
        assertEq(usdc.balanceOf(user), beforeUserUsdc);
    }

    function test_RejectsSameAssetRoutesBeforePullingInput() public {
        FameRouterTypes.Route memory route = _singleLegRoute(
            address(usdc), address(fame), 100e6, 0, 1_000 ether, FameRouterTypes.AmountMode.Exact, 100e6
        );
        route.tokenOut = address(usdc);
        route.legs[0].tokenOut = address(usdc);

        uint256 beforeUserUsdc = usdc.balanceOf(user);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(FameRouter.SameAssetRouteUnsupported.selector, address(usdc)));
        router.executeRoute(route);
        assertEq(usdc.balanceOf(user), beforeUserUsdc);
    }

    function test_RejectsFinalOutputConsumedByLaterLegBeforePullingInput() public {
        FameRouterTypes.Route memory route;
        route.version = FameRouterTypes.SCHEMA_VERSION;
        route.tokenIn = address(usdc);
        route.tokenOut = address(fame);
        route.amountIn = 100e6;
        route.recipient = recipient;
        route.deadline = block.timestamp + 1;
        route.legs = new FameRouterTypes.Leg[](2);
        route.legs[0] = _leg(address(usdc), address(fame), 100e6, 1_000 ether, FameRouterTypes.AmountMode.Exact, 100e6);
        route.legs[1] = _leg(address(fame), address(weth), 1_000 ether, 1 ether, FameRouterTypes.AmountMode.All, 0);

        uint256 beforeUserUsdc = usdc.balanceOf(user);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(FameRouter.FinalOutputConsumed.selector, 1, address(fame)));
        router.executeRoute(route);
        assertEq(usdc.balanceOf(user), beforeUserUsdc);
    }

    function test_LegMinimumUsesActualBalanceDeltaNotReportedOutput() public {
        FameRouterTypes.Route memory route =
            _singleLegRoute(address(usdc), address(fame), 100e6, 0, 1 ether, FameRouterTypes.AmountMode.Exact, 100e6);
        route.legs[0].minAmountOut = 1_000 ether;

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(FameRouter.LegOutputTooLow.selector, 0, 1 ether, 1_000 ether));
        router.executeRoute(route);
    }

    function test_AmbientDonatedOutputCannotSatisfyLegMinimum() public {
        fame.mint(address(router), 1_000 ether);
        FameRouterTypes.Route memory route =
            _singleLegRoute(address(usdc), address(fame), 100e6, 0, 1 ether, FameRouterTypes.AmountMode.Exact, 100e6);
        route.legs[0].minAmountOut = 1_000 ether;

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(FameRouter.LegOutputTooLow.selector, 0, 1 ether, 1_000 ether));
        router.executeRoute(route);

        assertEq(fame.balanceOf(address(router)), 1_000 ether);
    }

    function test_BalanceOfRevertFailsClosedBeforePullingInput() public {
        RevertingBalanceToken badToken = new RevertingBalanceToken();
        FameRouterTypes.Route memory route = _singleLegRoute(
            address(badToken), address(fame), 100e6, 0, 1_000 ether, FameRouterTypes.AmountMode.Exact, 100e6
        );

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(FameRouter.BalanceReadFailed.selector, address(badToken), address(router))
        );
        router.executeRoute(route);
    }

    function test_ShortBalanceOfReturnFailsClosedBeforePullingInput() public {
        ShortBalanceToken badToken = new ShortBalanceToken();
        FameRouterTypes.Route memory route = _singleLegRoute(
            address(badToken), address(fame), 100e6, 0, 1_000 ether, FameRouterTypes.AmountMode.Exact, 100e6
        );

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(FameRouter.BalanceReadFailed.selector, address(badToken), address(router))
        );
        router.executeRoute(route);
    }

    function test_FinalTransferTaxedOutputMustDeliverMinimumToRecipient() public {
        TransferTaxERC20 taxed = new TransferTaxERC20("Taxed Fame", "tFAME", 18, 1_000);
        uint256 gross = 1_000 ether;
        uint256 fee = (gross * uint256(FameRouterTypes.DEFAULT_FEE_PPM)) / uint256(FameRouterTypes.FEE_DENOMINATOR);
        uint256 net = gross - fee;
        uint256 delivered = net - ((net * taxed.taxBps()) / FameRouterTypes.BPS_DENOMINATOR);

        FameRouterTypes.Route memory route =
            _singleLegRoute(address(usdc), address(taxed), 100e6, net, gross, FameRouterTypes.AmountMode.Exact, 100e6);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(FameRouter.FinalOutputTooLow.selector, delivered, net));
        router.executeRoute(route);
    }

    function test_ReentrantTokenCallbackCannotReenterExecuteRoute() public {
        ReentrantToken reentrant = new ReentrantToken();
        reentrant.mint(user, 100 ether);

        FameRouterTypes.Route memory route = _singleLegRoute(
            address(reentrant), address(fame), 100 ether, 0, 1_000 ether, FameRouterTypes.AmountMode.Exact, 100 ether
        );
        reentrant.arm(router, route);

        vm.prank(user);
        reentrant.approve(address(router), type(uint256).max);

        vm.prank(user);
        router.executeRoute(route);

        assertTrue(reentrant.attemptedReentry());
        assertEq(reentrant.balanceOf(address(router)), 0);
    }

    function test_ReentrantTokenCallbackCanRevertWholeRouteWithoutMovingBalances() public {
        ReentrantToken reentrant = new ReentrantToken();
        reentrant.mint(user, 100 ether);

        FameRouterTypes.Route memory route = _singleLegRoute(
            address(reentrant), address(fame), 100 ether, 0, 1_000 ether, FameRouterTypes.AmountMode.Exact, 100 ether
        );
        reentrant.arm(router, route);
        reentrant.setBubbleReentryFailure(true);

        vm.prank(user);
        reentrant.approve(address(router), type(uint256).max);

        vm.prank(user);
        vm.expectRevert();
        router.executeRoute(route);

        assertEq(reentrant.balanceOf(user), 100 ether);
        assertEq(reentrant.balanceOf(address(router)), 0);
        assertEq(fame.balanceOf(address(router)), 0);
        assertEq(fame.balanceOf(recipient), 0);
    }

    function test_RescueDuringExecutionGuardBlocksOwnerCallback() public {
        RescueAttemptingRouter rescueVenue = new RescueAttemptingRouter(feeRecipient);
        rescueVenue.configure();
        FameRouter rescueRouter = rescueVenue.router();

        uint256 beforeUserUsdc = usdc.balanceOf(user);
        usdc.mint(user, 100e6);
        beforeUserUsdc += 100e6;
        vm.prank(user);
        usdc.approve(address(rescueRouter), type(uint256).max);

        FameRouterTypes.Route memory route = _singleLegRoute(
            address(usdc), address(fame), 100e6, 0, 1_000 ether, FameRouterTypes.AmountMode.Exact, 100e6
        );
        route.legs[0].target = address(rescueVenue);

        vm.prank(user);
        vm.expectRevert(FameRouter.RescueDuringExecution.selector);
        rescueRouter.executeRoute(route);

        assertEq(usdc.balanceOf(user), beforeUserUsdc);
        assertEq(usdc.balanceOf(address(rescueRouter)), 0);
    }

    function test_OwnerCanRescueNonRouteBalances() public {
        usdc.mint(address(router), 10e6);

        vm.prank(owner);
        vm.expectEmit(true, true, false, true, address(router));
        emit Rescue(address(usdc), owner, 10e6);
        router.rescue(address(usdc), owner, 10e6);

        assertEq(usdc.balanceOf(owner), 10e6);
        assertEq(usdc.balanceOf(address(router)), 0);
    }

    function _nativeWrapThenSwapRoute() private returns (FameRouterTypes.Route memory route) {
        route.version = FameRouterTypes.SCHEMA_VERSION;
        route.tokenIn = FameRouterTypes.NATIVE_ETH;
        route.tokenOut = address(fame);
        route.amountIn = 1 ether;
        route.recipient = recipient;
        route.deadline = block.timestamp + 1;
        route.legs = new FameRouterTypes.Leg[](2);
        route.legs[0] =
            _nativeWrapLeg(FameRouterTypes.NATIVE_ETH, address(weth), FameRouterTypes.AmountMode.Exact, 1 ether);
        route.legs[1] = _leg(address(weth), address(fame), 0, 1_000 ether, FameRouterTypes.AmountMode.All, 0);
    }

    function _nativeWrapLeg(address tokenIn, address tokenOut, FameRouterTypes.AmountMode amountMode, uint256 amount)
        private
        view
        returns (FameRouterTypes.Leg memory leg)
    {
        leg.tokenIn = tokenIn;
        leg.tokenOut = tokenOut;
        leg.venue = FameRouterTypes.VenueFamily.NativeWrap;
        leg.amountMode = amountMode;
        leg.amount = amount;
        leg.minAmountOut = 0;
        leg.target = address(weth);
        leg.data = "";
    }

    function _singleLegRoute(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOutAfterFee,
        uint256 mockAmountOut,
        FameRouterTypes.AmountMode amountMode,
        uint256 legAmount
    ) private returns (FameRouterTypes.Route memory route) {
        route.version = FameRouterTypes.SCHEMA_VERSION;
        route.tokenIn = tokenIn;
        route.tokenOut = tokenOut;
        route.amountIn = amountIn;
        route.minAmountOutAfterFee = minAmountOutAfterFee;
        route.recipient = recipient;
        route.deadline = block.timestamp + 1;
        route.legs = new FameRouterTypes.Leg[](1);
        route.legs[0] = _leg(tokenIn, tokenOut, legAmount, mockAmountOut, amountMode, legAmount);
    }

    function _leg(
        address tokenIn,
        address tokenOut,
        uint256 amount,
        uint256 mockAmountOut,
        FameRouterTypes.AmountMode amountMode,
        uint256 minAmountOut
    ) private returns (FameRouterTypes.Leg memory leg) {
        mockVenue.queueOutput(mockAmountOut);
        leg.tokenIn = tokenIn;
        leg.tokenOut = tokenOut;
        leg.venue = tokenIn == FameRouterTypes.NATIVE_ETH || tokenOut == FameRouterTypes.NATIVE_ETH
            ? FameRouterTypes.VenueFamily.UniswapV4
            : FameRouterTypes.VenueFamily.UniswapV2;
        leg.amountMode = amountMode;
        leg.amount = amount;
        leg.minAmountOut = minAmountOut;
        leg.target = address(mockVenue);
        leg.data = leg.venue == FameRouterTypes.VenueFamily.UniswapV3
            ? _v3Payload(tokenIn, tokenOut)
            : leg.venue == FameRouterTypes.VenueFamily.UniswapV4
                ? _v4Payload(tokenIn, tokenOut, amount, minAmountOut)
                : _v2Payload(tokenIn, tokenOut);
    }

    function _v2Payload(address tokenIn, address tokenOut) private view returns (bytes memory) {
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
        return abi.encode(UniswapV2Adapter.Payload({path: path, deadline: block.timestamp + 1}));
    }

    function _solidlyPayload(address tokenIn, address tokenOut) private view returns (bytes memory) {
        ISolidlyRouter.Route[] memory routes = new ISolidlyRouter.Route[](1);
        routes[0] = ISolidlyRouter.Route({from: tokenIn, to: tokenOut, stable: false});
        return abi.encode(SolidlyRouterAdapter.Payload({routes: routes, deadline: block.timestamp + 1}));
    }

    function _aerodromeV2Payload(address tokenIn, address tokenOut, address factory)
        private
        view
        returns (bytes memory)
    {
        IAerodromeV2Router.AerodromeRoute[] memory routes = new IAerodromeV2Router.AerodromeRoute[](1);
        routes[0] =
            IAerodromeV2Router.AerodromeRoute({from: tokenIn, to: tokenOut, stable: false, factory: factory});
        return abi.encode(AerodromeV2RouterAdapter.Payload({routes: routes, deadline: block.timestamp + 1}));
    }

    function _slipstreamPayload(address tokenIn, address tokenOut, int24 tickSpacing)
        private
        view
        returns (bytes memory)
    {
        return abi.encode(
            SlipstreamAdapter.Payload({
                router: address(mockVenue),
                factory: address(0xFAc707),
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                tickSpacing: tickSpacing,
                sqrtPriceLimitX96: 0,
                deadline: block.timestamp + 1
            })
        );
    }

    function _v3Payload(address tokenIn, address tokenOut) private view returns (bytes memory) {
        bytes memory path = abi.encodePacked(tokenIn, uint24(500), tokenOut);
        return abi.encode(
            UniversalRouterAdapter.V3ExactInputPayload({
                path: path, deadline: block.timestamp + 1, payerIsUser: true, recipient: address(router)
            })
        );
    }

    function _v4Payload(address tokenIn, address tokenOut, uint256 amountIn, uint256 minAmountOut)
        private
        view
        returns (bytes memory)
    {
        return abi.encode(
            UniversalRouterAdapter.V4SwapPayload({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                amountIn: amountIn,
                minAmountOut: minAmountOut,
                currency0: tokenIn,
                currency1: tokenOut,
                zeroForOne: true,
                fee: 500,
                tickSpacing: 0,
                hooks: address(0),
                hookData: "",
                deadline: block.timestamp + 1,
                recipient: address(router),
                payerIsUser: false
            })
        );
    }

    function _v4PayloadWithHook(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address hooks,
        bytes memory hookData
    ) private view returns (bytes memory) {
        return abi.encode(
            UniversalRouterAdapter.V4SwapPayload({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                amountIn: amountIn,
                minAmountOut: minAmountOut,
                currency0: tokenIn,
                currency1: tokenOut,
                zeroForOne: true,
                fee: 500,
                tickSpacing: 0,
                hooks: hooks,
                hookData: hookData,
                deadline: block.timestamp + 1,
                recipient: address(router),
                payerIsUser: false
            })
        );
    }

    function _v4HookDataKey(
        address currency0,
        address currency1,
        uint24 fee,
        int24 tickSpacing,
        address hooks,
        bytes memory hookData
    ) private pure returns (bytes32) {
        return keccak256(abi.encode(currency0, currency1, fee, tickSpacing, hooks, keccak256(hookData)));
    }

    function _rawRouteWithVenueOrdinal(FameRouterTypes.Route memory route, uint8 venueOrdinal)
        private
        pure
        returns (RawRoute memory rawRoute)
    {
        rawRoute = _rawRouteWithVenueAndAmountModeOrdinal(route, venueOrdinal, uint8(route.legs[0].amountMode));
    }

    function _rawRouteWithVenueAndAmountModeOrdinal(
        FameRouterTypes.Route memory route,
        uint8 venueOrdinal,
        uint8 amountModeOrdinal
    ) private pure returns (RawRoute memory rawRoute) {
        rawRoute.version = route.version;
        rawRoute.tokenIn = route.tokenIn;
        rawRoute.tokenOut = route.tokenOut;
        rawRoute.amountIn = route.amountIn;
        rawRoute.minAmountOutAfterFee = route.minAmountOutAfterFee;
        rawRoute.recipient = route.recipient;
        rawRoute.deadline = route.deadline;
        rawRoute.legs = new RawLeg[](route.legs.length);

        for (uint256 i; i < route.legs.length; ++i) {
            FameRouterTypes.Leg memory leg = route.legs[i];
            rawRoute.legs[i] = RawLeg({
                tokenIn: leg.tokenIn,
                tokenOut: leg.tokenOut,
                venue: venueOrdinal,
                amountMode: amountModeOrdinal,
                amount: leg.amount,
                minAmountOut: leg.minAmountOut,
                target: leg.target,
                data: leg.data
            });
        }
    }
}
