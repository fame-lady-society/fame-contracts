// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Vm} from "forge-std/Vm.sol";
import {DeployBaseUniversalPoolArtMarketplace} from "../script/DeployBaseUniversalPoolArtMarketplace.s.sol";
import {ValidateBaseUniversalPoolArtMarketplace} from "../script/ValidateBaseUniversalPoolArtMarketplace.s.sol";
import {FameMarketplaceCheckout} from "../src/FameMarketplaceCheckout.sol";
import {FameRouter} from "../src/FameRouter.sol";
import {UniversalPoolArtMarketplace} from "../src/UniversalPoolArtMarketplace.sol";
import {FameRouterTypes} from "../src/router/FameRouterTypes.sol";
import {AerodromeV2RouterAdapter} from "../src/router/adapters/AerodromeV2RouterAdapter.sol";
import {SolidlyRouterAdapter} from "../src/router/adapters/SolidlyRouterAdapter.sol";
import {IAerodromeV2Router} from "../src/router/interfaces/IAerodromeV2Router.sol";
import {ISolidlyRouter} from "../src/router/interfaces/ISolidlyRouter.sol";
import {UniversalPoolArtMarketplaceForkBaseTestBase} from "./UniversalPoolArtMarketplaceForkBase.t.sol";

interface IERC20CheckoutFork {
    function approve(address spender, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
}

interface IWETHCheckoutFork is IERC20CheckoutFork {
    function deposit() external payable;
}

contract FameMarketplaceCheckoutForkBaseTest is UniversalPoolArtMarketplaceForkBaseTestBase {
    enum InputKind {
        Eth,
        Usdc,
        Weth
    }

    address internal constant EXPECTED_ROUTER = 0xAdefa5860389E8936ebf2977e1Fb4a365aA39636;
    address internal constant EXPECTED_USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address internal constant EXPECTED_WETH = 0x4200000000000000000000000000000000000006;
    address internal constant SOLIDLY_ROUTER = 0x2F87Bf58D5A9b2eFadE55Cdbd46153a0902be6FA;
    address internal constant AERODROME_V2_ROUTER = 0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43;
    address internal constant AERODROME_V2_FACTORY = 0x420DD381b31aEf6683db6B902084cB0FFECe40Da;
    bytes32 internal constant ROUTE_EXECUTED_TOPIC =
        keccak256("RouteExecuted(address,address,address,bytes32,uint16,address,uint256,uint256,uint256,uint256)");
    bytes32 internal constant CHECKOUT_SETTLED_TOPIC =
        keccak256("CheckoutSettled(address,address,uint256,bytes32,uint8,uint256,uint256,uint256,uint256,uint256)");

    FameRouter internal router;
    IERC20CheckoutFork internal usdc;
    IWETHCheckoutFork internal weth;

    error NoSufficientUpperWitness(InputKind kind, uint256 lastAmountIn, uint256 lastAmountOut);

    function testLatestBaseEthHeldCheckoutUsesDeployedRouterAndRefundsFame() public {
        (UniversalPoolArtMarketplace market, FameMarketplaceCheckout checkout) = _deployCheckoutStack();
        uint256 shellId = _ownedTokenAt(address(market), 0);
        bytes32 artwork = market.artworkHash(shellId);
        uint256 maximumPremium = market.premium();
        (FameRouterTypes.Route memory route, uint256 quotedOutput) =
            _findSufficientRoute(InputKind.Eth, 0.5 ether, checkout, fame.unit() + maximumPremium);

        _fundAndApproveInput(BUYER_ONE, route, address(checkout));
        uint256 feeRecipientBefore = fame.balanceOf(SAFE);
        vm.recordLogs();
        vm.prank(BUYER_ONE);
        (uint256 routerOutput, uint256 marketCharge, uint256 fameRefund, uint256 inputRefund) =
            checkout.checkoutHeld{value: route.amountIn}(route, shellId, artwork, maximumPremium, 0);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(routerOutput, quotedOutput, "same-state quote/output drift");
        _assertSettlement(market, checkout, route, shellId, routerOutput, marketCharge, fameRefund, inputRefund, logs);
        assertEq(mirror.ownerAt(shellId), BUYER_ONE, "held shell recipient mismatch");
        assertGt(fame.balanceOf(SAFE) - feeRecipientBefore, maximumPremium, "router fee was not routed");
    }

    function testLatestBaseUsdcMintPoolCheckoutUsesDeployedRouter() public {
        (UniversalPoolArtMarketplace market, FameMarketplaceCheckout checkout) = _deployCheckoutStack();
        uint256 shellId = _ownedTokenAt(address(market), 0);
        uint256 sourceId = _findMintPoolToken();
        bytes32 artwork = market.artworkHash(sourceId);
        uint256 maximumPremium = market.premium();
        (FameRouterTypes.Route memory route, uint256 quotedOutput) =
            _findSufficientRoute(InputKind.Usdc, 1_000e6, checkout, fame.unit() + maximumPremium);

        _fundAndApproveInput(BUYER_ONE, route, address(checkout));
        vm.recordLogs();
        vm.prank(BUYER_ONE);
        (uint256 routerOutput, uint256 marketCharge, uint256 fameRefund, uint256 inputRefund) =
            checkout.checkoutPool(route, shellId, sourceId, artwork, maximumPremium, 0);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(routerOutput, quotedOutput, "same-state quote/output drift");
        _assertSettlement(market, checkout, route, shellId, routerOutput, marketCharge, fameRefund, inputRefund, logs);
        assertEq(mirror.ownerAt(shellId), BUYER_ONE, "Mint shell recipient mismatch");
        assertEq(market.artworkHash(shellId), artwork, "Mint artwork mismatch");
    }

    function testLatestBaseWethBurnPoolCheckoutUsesDeployedRouter() public {
        (UniversalPoolArtMarketplace market, FameMarketplaceCheckout checkout) = _deployCheckoutStack();
        uint256 shellId = _ownedTokenAt(address(market), 0);
        uint256 sourceId = _findBurnPoolToken();
        bytes32 artwork = market.artworkHash(sourceId);
        uint256 maximumPremium = market.premium();
        (FameRouterTypes.Route memory route, uint256 quotedOutput) =
            _findSufficientRoute(InputKind.Weth, 0.5 ether, checkout, fame.unit() + maximumPremium);

        _fundAndApproveInput(BUYER_ONE, route, address(checkout));
        vm.recordLogs();
        vm.prank(BUYER_ONE);
        (uint256 routerOutput, uint256 marketCharge, uint256 fameRefund, uint256 inputRefund) =
            checkout.checkoutPool(route, shellId, sourceId, artwork, maximumPremium, 0);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(routerOutput, quotedOutput, "same-state quote/output drift");
        _assertSettlement(market, checkout, route, shellId, routerOutput, marketCharge, fameRefund, inputRefund, logs);
        assertEq(mirror.ownerAt(shellId), BUYER_ONE, "Burn shell recipient mismatch");
        assertEq(market.artworkHash(shellId), artwork, "Burn artwork mismatch");
    }

    function testLatestBasePremiumRaceRevertsBeforeBuyerFunding() public {
        (UniversalPoolArtMarketplace market, FameMarketplaceCheckout checkout) = _deployCheckoutStack();
        uint256 shellId = _ownedTokenAt(address(market), 0);
        bytes32 artwork = market.artworkHash(shellId);
        uint256 quotedPremium = market.premium();
        (FameRouterTypes.Route memory route,) =
            _findSufficientRoute(InputKind.Usdc, 1_000e6, checkout, fame.unit() + quotedPremium);
        _fundAndApproveInput(BUYER_ONE, route, address(checkout));
        uint256 buyerBefore = usdc.balanceOf(BUYER_ONE);

        vm.prank(DEPLOYER);
        market.setPremium(quotedPremium + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                FameMarketplaceCheckout.PremiumExceedsMaximum.selector, quotedPremium + 1, quotedPremium
            )
        );
        vm.prank(BUYER_ONE);
        checkout.checkoutHeld(route, shellId, artwork, quotedPremium, 0);

        assertEq(usdc.balanceOf(BUYER_ONE), buyerBefore, "premium race consumed buyer input");
        assertEq(usdc.balanceOf(address(checkout)), 0, "premium race left checkout residue");
    }

    function testLatestBaseHeldContentionRejectsSecondBuyerBeforeFunding() public {
        (UniversalPoolArtMarketplace market, FameMarketplaceCheckout checkout) = _deployCheckoutStack();
        uint256 shellId = _ownedTokenAt(address(market), 0);
        bytes32 artwork = market.artworkHash(shellId);
        uint256 maximumPremium = market.premium();
        (FameRouterTypes.Route memory route,) =
            _findSufficientRoute(InputKind.Eth, 0.5 ether, checkout, fame.unit() + maximumPremium);

        _fundAndApproveInput(BUYER_ONE, route, address(checkout));
        vm.prank(BUYER_ONE);
        checkout.checkoutHeld{value: route.amountIn}(route, shellId, artwork, maximumPremium, 0);

        _fundAndApproveInput(BUYER_TWO, route, address(checkout));
        uint256 buyerTwoBefore = BUYER_TWO.balance;
        vm.expectRevert(abi.encodeWithSelector(FameMarketplaceCheckout.UnavailableShell.selector, shellId));
        vm.prank(BUYER_TWO);
        checkout.checkoutHeld{value: route.amountIn}(route, shellId, artwork, maximumPremium, 0);

        assertEq(BUYER_TWO.balance, buyerTwoBefore, "contention consumed second buyer input");
        assertEq(mirror.ownerAt(shellId), BUYER_ONE, "contention changed first settlement");
    }

    function testLatestBaseExpiredQuoteRevertsBeforeBuyerFunding() public {
        (UniversalPoolArtMarketplace market, FameMarketplaceCheckout checkout) = _deployCheckoutStack();
        uint256 shellId = _ownedTokenAt(address(market), 0);
        bytes32 artwork = market.artworkHash(shellId);
        uint256 maximumPremium = market.premium();
        (FameRouterTypes.Route memory route,) =
            _findSufficientRoute(InputKind.Weth, 0.5 ether, checkout, fame.unit() + maximumPremium);
        _fundAndApproveInput(BUYER_ONE, route, address(checkout));
        uint256 buyerBefore = weth.balanceOf(BUYER_ONE);

        vm.warp(route.deadline + 1);
        vm.expectRevert(
            abi.encodeWithSelector(FameMarketplaceCheckout.DeadlineExpired.selector, route.deadline, block.timestamp)
        );
        vm.prank(BUYER_ONE);
        checkout.checkoutHeld(route, shellId, artwork, maximumPremium, 0);

        assertEq(weth.balanceOf(BUYER_ONE), buyerBefore, "expired quote consumed buyer input");
        assertEq(weth.balanceOf(address(checkout)), 0, "expired quote left checkout residue");
    }

    function _deployCheckoutStack()
        private
        returns (UniversalPoolArtMarketplace market, FameMarketplaceCheckout checkout)
    {
        _selectLatestBaseFork();

        router = FameRouter(payable(vm.envAddress("BASE_FAME_ROUTER_ADDRESS")));
        usdc = IERC20CheckoutFork(vm.envAddress("BASE_USDC_ADDRESS"));
        weth = IWETHCheckoutFork(vm.envAddress("BASE_WETH_ADDRESS"));
        assertEq(address(router), EXPECTED_ROUTER, "router address drift");
        assertEq(address(usdc), EXPECTED_USDC, "USDC address drift");
        assertEq(address(weth), EXPECTED_WETH, "WETH address drift");

        DeployBaseUniversalPoolArtMarketplace deployScript = new DeployBaseUniversalPoolArtMarketplace();
        (market, checkout) = deployScript.deployMarketplaceStack(
            fame,
            creatorMagic,
            address(router),
            address(usdc),
            address(weth),
            EXPECTED_PREMIUM,
            SAFE,
            DEPLOYER,
            DEPLOYER
        );
        _seedOneShellMarket(market);

        ValidateBaseUniversalPoolArtMarketplace validator = new ValidateBaseUniversalPoolArtMarketplace();
        validator.validateMarketplaceStack(
            fame,
            mirror,
            creatorMagic,
            market,
            checkout,
            EXPECTED_CHILD_RENDERER,
            ValidateBaseUniversalPoolArtMarketplace.MarketplaceExpectations({
                owner: DEPLOYER, feeRecipient: SAFE, premium: EXPECTED_PREMIUM, inventory: 1, paused: true
            }),
            ValidateBaseUniversalPoolArtMarketplace.CheckoutExpectations({
                router: address(router),
                usdc: address(usdc),
                weth: address(weth),
                routerFeeRecipient: SAFE,
                routerFeePpm: FameRouterTypes.DEFAULT_FEE_PPM
            })
        );

        vm.prank(DEPLOYER);
        market.unpause();
    }

    function _findSufficientRoute(
        InputKind kind,
        uint256 initialAmountIn,
        FameMarketplaceCheckout checkout,
        uint256 requiredOutput
    ) private returns (FameRouterTypes.Route memory route, uint256 quotedOutput) {
        uint256 amountIn = initialAmountIn;
        uint256 lastOutput;
        for (uint256 attempt; attempt < 8; ++attempt) {
            route = _buildRoute(kind, amountIn, address(checkout), 1);
            uint256 snapshot = vm.snapshot();
            _fundAndApproveInput(BUYER_ONE, route, address(router));
            vm.prank(BUYER_ONE);
            quotedOutput = router.executeRoute{value: kind == InputKind.Eth ? amountIn : 0}(route);
            assertTrue(vm.revertToAndDelete(snapshot), "quote state restore failed");
            lastOutput = quotedOutput;
            if (quotedOutput >= requiredOutput) {
                route.minAmountOutAfterFee = requiredOutput;
                return (route, quotedOutput);
            }
            amountIn *= 2;
        }
        revert NoSufficientUpperWitness(kind, amountIn / 2, lastOutput);
    }

    function _buildRoute(InputKind kind, uint256 amountIn, address recipient, uint256 minimumOutput)
        private
        view
        returns (FameRouterTypes.Route memory route)
    {
        route.version = FameRouterTypes.SCHEMA_VERSION;
        route.tokenIn =
            kind == InputKind.Eth ? FameRouterTypes.NATIVE_ETH : kind == InputKind.Usdc ? address(usdc) : address(weth);
        route.tokenOut = address(fame);
        route.amountIn = amountIn;
        route.minAmountOutAfterFee = minimumOutput;
        route.recipient = recipient;
        route.deadline = block.timestamp + 20 minutes;

        if (kind == InputKind.Eth) {
            route.legs = new FameRouterTypes.Leg[](2);
            route.legs[0] = FameRouterTypes.Leg({
                tokenIn: FameRouterTypes.NATIVE_ETH,
                tokenOut: address(weth),
                venue: FameRouterTypes.VenueFamily.NativeWrap,
                amountMode: FameRouterTypes.AmountMode.Exact,
                amount: amountIn,
                minAmountOut: 0,
                target: address(weth),
                data: ""
            });
            route.legs[1] = _solidlyWethToFameLeg();
            return route;
        }

        if (kind == InputKind.Usdc) {
            route.legs = new FameRouterTypes.Leg[](2);
            route.legs[0] = _aerodromeUsdcToWethLeg();
            route.legs[1] = _solidlyWethToFameLeg();
            return route;
        }

        route.legs = new FameRouterTypes.Leg[](1);
        route.legs[0] = _solidlyWethToFameLeg();
    }

    function _aerodromeUsdcToWethLeg() private view returns (FameRouterTypes.Leg memory leg) {
        IAerodromeV2Router.AerodromeRoute[] memory routes = new IAerodromeV2Router.AerodromeRoute[](1);
        routes[0] = IAerodromeV2Router.AerodromeRoute({
            from: address(usdc), to: address(weth), stable: false, factory: AERODROME_V2_FACTORY
        });
        leg = FameRouterTypes.Leg({
            tokenIn: address(usdc),
            tokenOut: address(weth),
            venue: FameRouterTypes.VenueFamily.AerodromeV2,
            amountMode: FameRouterTypes.AmountMode.All,
            amount: 0,
            minAmountOut: 1,
            target: AERODROME_V2_ROUTER,
            data: abi.encode(AerodromeV2RouterAdapter.Payload({routes: routes, deadline: block.timestamp + 20 minutes}))
        });
    }

    function _solidlyWethToFameLeg() private view returns (FameRouterTypes.Leg memory leg) {
        ISolidlyRouter.Route[] memory routes = new ISolidlyRouter.Route[](1);
        routes[0] = ISolidlyRouter.Route({from: address(weth), to: address(fame), stable: false});
        leg = FameRouterTypes.Leg({
            tokenIn: address(weth),
            tokenOut: address(fame),
            venue: FameRouterTypes.VenueFamily.Solidly,
            amountMode: FameRouterTypes.AmountMode.All,
            amount: 0,
            minAmountOut: 1,
            target: SOLIDLY_ROUTER,
            data: abi.encode(SolidlyRouterAdapter.Payload({routes: routes, deadline: block.timestamp + 20 minutes}))
        });
    }

    function _fundAndApproveInput(address buyer, FameRouterTypes.Route memory route, address spender) private {
        if (route.tokenIn == FameRouterTypes.NATIVE_ETH) {
            vm.deal(buyer, route.amountIn);
            return;
        }
        if (route.tokenIn == address(weth)) {
            vm.deal(buyer, route.amountIn);
            vm.prank(buyer);
            weth.deposit{value: route.amountIn}();
        } else {
            deal(route.tokenIn, buyer, route.amountIn);
        }
        vm.prank(buyer);
        IERC20CheckoutFork(route.tokenIn).approve(spender, route.amountIn);
    }

    function _assertSettlement(
        UniversalPoolArtMarketplace market,
        FameMarketplaceCheckout checkout,
        FameRouterTypes.Route memory route,
        uint256 shellId,
        uint256 routerOutput,
        uint256 marketCharge,
        uint256 fameRefund,
        uint256 inputRefund,
        Vm.Log[] memory logs
    ) private view {
        assertEq(marketCharge, fame.unit() + market.premium(), "market charge mismatch");
        assertEq(routerOutput, marketCharge + fameRefund, "FAME reconciliation mismatch");
        assertGt(fameRefund, 0, "upper witness should produce a FAME refund");
        assertEq(inputRefund, 0, "all-input route returned input residue");
        assertEq(market.inventory(), 1, "one-shell inventory drift");
        assertEq(fame.balanceOf(address(checkout)), 0, "checkout retained FAME");
        assertEq(address(checkout).balance, 0, "checkout retained ETH");
        assertEq(usdc.balanceOf(address(checkout)), 0, "checkout retained USDC");
        assertEq(weth.balanceOf(address(checkout)), 0, "checkout retained WETH");
        if (route.tokenIn != FameRouterTypes.NATIVE_ETH) {
            assertEq(
                IERC20CheckoutFork(route.tokenIn).allowance(address(checkout), address(router)), 0, "router allowance"
            );
        }
        assertEq(fame.allowance(address(checkout), address(market)), 0, "market allowance");
        assertEq(_purchaseEventCount(logs, address(market)), 1, "ArtworkPurchased event mismatch");
        assertEq(_eventCount(logs, address(router), ROUTE_EXECUTED_TOPIC), 1, "RouteExecuted event mismatch");
        assertEq(_eventCount(logs, address(checkout), CHECKOUT_SETTLED_TOPIC), 1, "CheckoutSettled event mismatch");
        assertGt(shellId, 0);
    }

    function _eventCount(Vm.Log[] memory logs, address emitter, bytes32 topic) private pure returns (uint256 count) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == emitter && logs[i].topics.length != 0 && logs[i].topics[0] == topic) ++count;
        }
    }
}
