// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ValidateFameRouterBase} from "../../script/ValidateFameRouterBase.s.sol";
import {FameRouter} from "../../src/FameRouter.sol";
import {FameRouterTypes} from "../../src/router/FameRouterTypes.sol";
import {AerodromeV2RouterAdapter} from "../../src/router/adapters/AerodromeV2RouterAdapter.sol";
import {SlipstreamAdapter} from "../../src/router/adapters/SlipstreamAdapter.sol";
import {SolidlyRouterAdapter} from "../../src/router/adapters/SolidlyRouterAdapter.sol";
import {UniversalRouterAdapter} from "../../src/router/adapters/UniversalRouterAdapter.sol";
import {UniswapV2Adapter} from "../../src/router/adapters/UniswapV2Adapter.sol";
import {IPermit2} from "../../src/router/interfaces/IPermit2.sol";
import {IAerodromeV2Router} from "../../src/router/interfaces/IAerodromeV2Router.sol";
import {ISlipstreamRouter} from "../../src/router/interfaces/ISlipstreamRouter.sol";
import {ISolidlyRouter} from "../../src/router/interfaces/ISolidlyRouter.sol";
import {IUniversalRouter} from "../../src/router/interfaces/IUniversalRouter.sol";
import {IUniswapV2Router02} from "../../src/router/interfaces/IUniswapV2Router02.sol";
import {IWETH9} from "../../src/router/interfaces/IWETH9.sol";
import {FameRouterFixtureManifest} from "./fixtures/FameRouterFixtureManifest.sol";
import {FameRouterSolverFixtureManifest} from "./fixtures/FameRouterSolverFixtureManifest.sol";

interface IERC20Fork {
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface IBasePoolMetadata {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function factory() external view returns (address);
    function stable() external view returns (bool);
    function tickSpacing() external view returns (int24);
    function fee() external view returns (uint24);
}

interface IV4StateView {
    function getSlot0(bytes32 poolId)
        external
        view
        returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee);
}

interface IAerodromeV2FactoryFork {
    function getPool(address tokenA, address tokenB, bool stable) external view returns (address);
    function getFee(address pool, bool stable) external view returns (uint256);
    function isPool(address pool) external view returns (bool);
}

contract FameRouterForkBaseTest is Test {
    address private constant FEE_RECIPIENT = address(0x1004);
    address private constant USER = address(0x1002);
    address private constant RECIPIENT = address(0x1003);
    address private constant GENERATED_ROUTER = address(0xF00D);
    address private constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address private constant BASE_WETH = 0x4200000000000000000000000000000000000006;

    struct ForkRouteFixture {
        address tokenIn;
        address tokenOut;
        address target;
        address factory;
        bool stable;
        int24 tickSpacing;
        uint24 fee;
        address currency0;
        address currency1;
        address hooks;
        address[] path;
        bool[] stablePath;
        uint256 amountIn;
        uint256 legMinAmountOut;
        uint256 minAmountOutAfterFee;
        uint256 fundingAmountIn;
    }

    function test_BaseForkLaunchGateRequiresPinnedBlockAndRpc() public {
        if (!FameRouterFixtureManifest.isLaunchable()) {
            vm.skip(true);
        }

        assertGt(FameRouterFixtureManifest.pinnedBaseBlock(), 0);

        string memory rpc = vm.envOr("BASE_RPC", string(""));
        if (bytes(rpc).length == 0) {
            revert("BASE_RPC required for launchable pinned fork gate");
        }

        uint256 forkId = vm.createSelectFork(rpc, FameRouterFixtureManifest.pinnedBaseBlock());

        assertEq(vm.activeFork(), forkId);
        assertEq(block.chainid, 8453);
        assertEq(block.number, FameRouterFixtureManifest.pinnedBaseBlock());
    }

    function test_PinnedBaseForkPoolMetadataMatchesManifest() public {
        _selectPinnedBaseForkOrSkip();

        string memory poolsJson = vm.readFile("test/router/fixtures/base-v1-pools.json");
        uint256 poolCount = _jsonArrayLength(poolsJson, ".pools");
        assertEq(poolCount, FameRouterFixtureManifest.poolFixtureCount());

        for (uint256 i; i < poolCount; ++i) {
            string memory key = string.concat(".pools[", vm.toString(i), "]");
            string memory venue = vm.parseJsonString(poolsJson, string.concat(key, ".venue"));

            if (_hasKey(poolsJson, key, "router")) {
                _assertCode(vm.parseJsonAddress(poolsJson, string.concat(key, ".router")));
            }
            if (_hasKey(poolsJson, key, "factory")) {
                _assertCode(vm.parseJsonAddress(poolsJson, string.concat(key, ".factory")));
            }

            if (_stringEq(venue, "uniswap-v4")) {
                _assertUniswapV4PoolMetadata(poolsJson, key);
            } else {
                _assertErc20PoolMetadata(poolsJson, key, venue);
            }
        }
    }

    function test_PinnedBaseForkValidationScriptPoolMetadataPasses() public {
        _selectPinnedBaseForkOrSkip();

        new ValidateFameRouterBase().validateLivePoolMetadata();
    }

    function test_PinnedBaseForkUniswapV2FameBuyExecutes() public {
        _selectPinnedBaseForkOrSkip();

        ForkRouteFixture memory fixture = _loadUniswapV2RouteFixture("uniswap-v2-fame-buy", true);

        FameRouter router = new FameRouter(FEE_RECIPIENT);
        router.setVenueFamilyEnabled(FameRouterTypes.VenueFamily.UniswapV2, true);
        router.setVenueTargetEnabled(FameRouterTypes.VenueFamily.UniswapV2, fixture.target, true);

        vm.deal(USER, fixture.amountIn);
        vm.startPrank(USER);
        IWETH9(fixture.tokenIn).deposit{value: fixture.amountIn}();
        IERC20Fork(fixture.tokenIn).approve(address(router), fixture.amountIn);

        FameRouterTypes.Route memory route;
        route.version = FameRouterTypes.SCHEMA_VERSION;
        route.tokenIn = fixture.tokenIn;
        route.tokenOut = fixture.tokenOut;
        route.amountIn = fixture.amountIn;
        route.minAmountOutAfterFee = fixture.minAmountOutAfterFee;
        route.recipient = RECIPIENT;
        route.deadline = block.timestamp + 1 hours;
        route.legs = new FameRouterTypes.Leg[](1);
        route.legs[0] = FameRouterTypes.Leg({
            tokenIn: fixture.tokenIn,
            tokenOut: fixture.tokenOut,
            venue: FameRouterTypes.VenueFamily.UniswapV2,
            amountMode: FameRouterTypes.AmountMode.Exact,
            amount: fixture.amountIn,
            minAmountOut: fixture.legMinAmountOut,
            target: fixture.target,
            data: _uniswapV2PathPayload(fixture.tokenIn, fixture.tokenOut, route.deadline)
        });

        uint256 beforeFeeRecipient = IERC20Fork(fixture.tokenOut).balanceOf(FEE_RECIPIENT);
        uint256 netOut = router.executeRoute(route);
        vm.stopPrank();

        uint256 feePaid = _assetBalance(fixture.tokenOut, FEE_RECIPIENT) - beforeFeeRecipient;
        uint256 grossOut = netOut + feePaid;
        assertGt(netOut, 0);
        assertEq(feePaid, (grossOut * uint256(FameRouterTypes.DEFAULT_FEE_PPM)) / FameRouterTypes.FEE_DENOMINATOR);
        assertEq(IERC20Fork(fixture.tokenIn).balanceOf(address(router)), 0);
        assertEq(IERC20Fork(fixture.tokenOut).balanceOf(address(router)), 0);
        assertEq(IERC20Fork(fixture.tokenOut).balanceOf(RECIPIENT), netOut);
        assertGt(feePaid, 0);
    }

    function test_PinnedBaseForkUniswapV2FameSellExecutes() public {
        _selectPinnedBaseForkOrSkip();

        ForkRouteFixture memory fixture = _loadUniswapV2RouteFixture("uniswap-v2-fame-sell", false);
        uint256 acquiredFame = _acquireFameThroughUniswapV2(
            USER, fixture.target, fixture.tokenOut, fixture.tokenIn, fixture.fundingAmountIn
        );
        assertEq(acquiredFame, fixture.amountIn);

        deployCodeTo("FameRouter.sol:FameRouter", abi.encode(FEE_RECIPIENT), GENERATED_ROUTER);
        FameRouter router = FameRouter(payable(GENERATED_ROUTER));
        router.setVenueFamilyEnabled(FameRouterTypes.VenueFamily.UniswapV2, true);
        router.setVenueTargetEnabled(FameRouterTypes.VenueFamily.UniswapV2, fixture.target, true);

        vm.startPrank(USER);
        IERC20Fork(fixture.tokenIn).approve(address(router), acquiredFame);

        FameRouterTypes.Route memory route;
        route.version = FameRouterTypes.SCHEMA_VERSION;
        route.tokenIn = fixture.tokenIn;
        route.tokenOut = fixture.tokenOut;
        route.amountIn = fixture.amountIn;
        route.minAmountOutAfterFee = fixture.minAmountOutAfterFee;
        route.recipient = RECIPIENT;
        route.deadline = block.timestamp + 1 hours;
        route.legs = new FameRouterTypes.Leg[](1);
        route.legs[0] = FameRouterTypes.Leg({
            tokenIn: fixture.tokenIn,
            tokenOut: fixture.tokenOut,
            venue: FameRouterTypes.VenueFamily.UniswapV2,
            amountMode: FameRouterTypes.AmountMode.Exact,
            amount: fixture.amountIn,
            minAmountOut: fixture.legMinAmountOut,
            target: fixture.target,
            data: _uniswapV2PathPayload(fixture.tokenIn, fixture.tokenOut, route.deadline)
        });

        uint256 beforeFeeRecipient = IERC20Fork(fixture.tokenOut).balanceOf(FEE_RECIPIENT);
        uint256 netOut = router.executeRoute(route);
        vm.stopPrank();

        uint256 feePaid = IERC20Fork(fixture.tokenOut).balanceOf(FEE_RECIPIENT) - beforeFeeRecipient;
        uint256 grossOut = netOut + feePaid;
        assertGt(netOut, 0);
        assertEq(feePaid, (grossOut * uint256(FameRouterTypes.DEFAULT_FEE_PPM)) / FameRouterTypes.FEE_DENOMINATOR);
        assertEq(IERC20Fork(fixture.tokenIn).balanceOf(address(router)), 0);
        assertEq(IERC20Fork(fixture.tokenOut).balanceOf(address(router)), 0);
        assertEq(IERC20Fork(fixture.tokenOut).balanceOf(RECIPIENT), netOut);
        assertGt(feePaid, 0);
    }

    function test_PinnedBaseForkAerodromeV2UsdcWethExecutes() public {
        _selectPinnedBaseForkOrSkip();

        _executeAerodromeV2RouteFixture("aerodrome-v2-usdc-weth-buy");
    }

    function test_PinnedBaseForkAerodromeV2WrongFactoryFailsClosed() public {
        _selectPinnedBaseForkOrSkip();

        ForkRouteFixture memory fixture = _loadAerodromeV2RouteFixture("aerodrome-v2-usdc-weth-buy");
        FameRouter router = new FameRouter(FEE_RECIPIENT);
        router.setVenueFamilyEnabled(FameRouterTypes.VenueFamily.AerodromeV2, true);
        router.setVenueTargetEnabled(FameRouterTypes.VenueFamily.AerodromeV2, fixture.target, true);

        deal(fixture.tokenIn, USER, fixture.amountIn);
        vm.startPrank(USER);
        IERC20Fork(fixture.tokenIn).approve(address(router), fixture.amountIn);

        fixture.factory = address(0xDEAD);
        FameRouterTypes.Route memory route = _singleLegForkRoute(
            fixture, FameRouterTypes.VenueFamily.AerodromeV2, _aerodromeV2Payload(fixture, block.timestamp + 1 hours)
        );

        vm.expectRevert();
        router.executeRoute(route);
        vm.stopPrank();

        assertEq(_assetBalance(fixture.tokenIn, address(router)), 0);
        assertEq(_assetBalance(fixture.tokenOut, address(router)), 0);
    }

    function test_PinnedBaseForkSolidlyWethFameBuyExecutes() public {
        _selectPinnedBaseForkOrSkip();

        _executeSolidlyRouteFixture("solidly-weth-fame-buy", true);
    }

    function test_PinnedBaseForkSolidlyWethFameSellExecutes() public {
        _selectPinnedBaseForkOrSkip();

        _executeSolidlyRouteFixture("solidly-weth-fame-sell", false);
    }

    function test_PinnedBaseForkSolidlyUsdcFrxUsdFameBuyExecutes() public {
        _selectPinnedBaseForkOrSkip();

        _executeSolidlyRouteFixture("solidly-usdc-frxusd-fame-buy", true);
    }

    function test_PinnedBaseForkSolidlyUsdcScaleFameBuyExecutes() public {
        _selectPinnedBaseForkOrSkip();

        _executeSolidlyRouteFixture("solidly-usdc-scale-fame-buy", true);
    }

    function test_PinnedBaseForkSlipstreamBasedflickFameBuyExecutes() public {
        _selectPinnedBaseForkOrSkip();

        _executeSlipstreamRouteFixture(
            "slipstream-basedflick-fame-buy", true, "aerodrome-slipstream", FameRouterTypes.VenueFamily.Slipstream
        );
    }

    function test_PinnedBaseForkSlipstreamBasedflickFameSellExecutes() public {
        _selectPinnedBaseForkOrSkip();

        _executeSlipstreamRouteFixture(
            "slipstream-basedflick-fame-sell", false, "aerodrome-slipstream", FameRouterTypes.VenueFamily.Slipstream
        );
    }

    function test_PinnedBaseForkSlipstream2MsUsdMsEthBuyExecutes() public {
        _selectPinnedBaseForkOrSkip();

        _executeSlipstreamRouteFixture(
            "slipstream2-msusd-mseth-buy", true, "aerodrome-slipstream2", FameRouterTypes.VenueFamily.Slipstream2
        );
    }

    function test_PinnedBaseForkSlipstream2MsUsdMsEthSellExecutes() public {
        _selectPinnedBaseForkOrSkip();

        _executeSlipstreamRouteFixture(
            "slipstream2-msusd-mseth-sell", false, "aerodrome-slipstream2", FameRouterTypes.VenueFamily.Slipstream2
        );
    }

    function test_PinnedBaseForkSlipstream2MsUsdUsdcCBuyExecutes() public {
        _selectPinnedBaseForkOrSkip();

        _executeSlipstreamRouteFixture(
            "slipstream2-msusd-usdc-c-buy", true, "aerodrome-slipstream2", FameRouterTypes.VenueFamily.Slipstream2
        );
    }

    function test_PinnedBaseForkSlipstream2MsUsdUsdcCSellExecutes() public {
        _selectPinnedBaseForkOrSkip();

        _executeSlipstreamRouteFixture(
            "slipstream2-msusd-usdc-c-sell", false, "aerodrome-slipstream2", FameRouterTypes.VenueFamily.Slipstream2
        );
    }

    function test_PinnedBaseForkUniswapV3ZoraUsdcBuyExecutes() public {
        _selectPinnedBaseForkOrSkip();

        _executeUniversalRouteFixture(
            "uniswap-v3-zora-usdc-buy", true, "uniswap-v3", FameRouterTypes.VenueFamily.UniswapV3
        );
    }

    function test_PinnedBaseForkUniswapV3ZoraUsdcSellExecutes() public {
        _selectPinnedBaseForkOrSkip();

        _executeUniversalRouteFixture(
            "uniswap-v3-zora-usdc-sell", false, "uniswap-v3", FameRouterTypes.VenueFamily.UniswapV3
        );
    }

    function test_PinnedBaseForkUniswapV3ZoraWethBuyExecutes() public {
        _selectPinnedBaseForkOrSkip();

        _executeUniversalRouteFixture(
            "uniswap-v3-zora-weth-buy", true, "uniswap-v3", FameRouterTypes.VenueFamily.UniswapV3
        );
    }

    function test_PinnedBaseForkUniswapV3ZoraWethSellExecutes() public {
        _selectPinnedBaseForkOrSkip();

        _executeUniversalRouteFixture(
            "uniswap-v3-zora-weth-sell", false, "uniswap-v3", FameRouterTypes.VenueFamily.UniswapV3
        );
    }

    function test_PinnedBaseForkUniswapV4BasedflickZoraBuyExecutes() public {
        _selectPinnedBaseForkOrSkip();

        _executeUniversalRouteFixture(
            "uniswap-v4-basedflick-zora-buy", true, "uniswap-v4", FameRouterTypes.VenueFamily.UniswapV4
        );
    }

    function test_PinnedBaseForkUniswapV4BasedflickZoraSellExecutes() public {
        _selectPinnedBaseForkOrSkip();

        _executeUniversalRouteFixture(
            "uniswap-v4-basedflick-zora-sell", false, "uniswap-v4", FameRouterTypes.VenueFamily.UniswapV4
        );
    }

    function test_PinnedBaseForkUniswapV4ZoraEthNativeExecutes() public {
        _selectPinnedBaseForkOrSkip();

        _executeUniversalRouteFixture(
            "uniswap-v4-zora-eth-native", true, "uniswap-v4", FameRouterTypes.VenueFamily.UniswapV4
        );
    }

    function test_PinnedBaseForkCoveredRouteTableExecutesEveryRoute() public {
        _selectPinnedBaseForkOrSkip();

        for (uint256 i; i < FameRouterFixtureManifest.routeExecutionCoverageCount(); ++i) {
            string memory routeId = FameRouterFixtureManifest.routeExecutionCoverageId(i);
            if (_stringEq(routeId, "solidly-weth-fame-buy")) {
                test_PinnedBaseForkSolidlyWethFameBuyExecutes();
            } else if (_stringEq(routeId, "solidly-weth-fame-sell")) {
                test_PinnedBaseForkSolidlyWethFameSellExecutes();
            } else if (_stringEq(routeId, "solidly-usdc-frxusd-fame-buy")) {
                test_PinnedBaseForkSolidlyUsdcFrxUsdFameBuyExecutes();
            } else if (_stringEq(routeId, "solidly-usdc-scale-fame-buy")) {
                test_PinnedBaseForkSolidlyUsdcScaleFameBuyExecutes();
            } else if (_stringEq(routeId, "slipstream-basedflick-fame-buy")) {
                test_PinnedBaseForkSlipstreamBasedflickFameBuyExecutes();
            } else if (_stringEq(routeId, "slipstream-basedflick-fame-sell")) {
                test_PinnedBaseForkSlipstreamBasedflickFameSellExecutes();
            } else if (_stringEq(routeId, "slipstream2-msusd-mseth-buy")) {
                test_PinnedBaseForkSlipstream2MsUsdMsEthBuyExecutes();
            } else if (_stringEq(routeId, "slipstream2-msusd-mseth-sell")) {
                test_PinnedBaseForkSlipstream2MsUsdMsEthSellExecutes();
            } else if (_stringEq(routeId, "slipstream2-msusd-usdc-c-buy")) {
                test_PinnedBaseForkSlipstream2MsUsdUsdcCBuyExecutes();
            } else if (_stringEq(routeId, "slipstream2-msusd-usdc-c-sell")) {
                test_PinnedBaseForkSlipstream2MsUsdUsdcCSellExecutes();
            } else if (_stringEq(routeId, "uniswap-v3-zora-usdc-buy")) {
                test_PinnedBaseForkUniswapV3ZoraUsdcBuyExecutes();
            } else if (_stringEq(routeId, "uniswap-v3-zora-usdc-sell")) {
                test_PinnedBaseForkUniswapV3ZoraUsdcSellExecutes();
            } else if (_stringEq(routeId, "uniswap-v3-zora-weth-buy")) {
                test_PinnedBaseForkUniswapV3ZoraWethBuyExecutes();
            } else if (_stringEq(routeId, "uniswap-v3-zora-weth-sell")) {
                test_PinnedBaseForkUniswapV3ZoraWethSellExecutes();
            } else if (_stringEq(routeId, "uniswap-v4-basedflick-zora-buy")) {
                test_PinnedBaseForkUniswapV4BasedflickZoraBuyExecutes();
            } else if (_stringEq(routeId, "uniswap-v4-basedflick-zora-sell")) {
                test_PinnedBaseForkUniswapV4BasedflickZoraSellExecutes();
            } else if (_stringEq(routeId, "uniswap-v4-zora-eth-native")) {
                test_PinnedBaseForkUniswapV4ZoraEthNativeExecutes();
            } else if (_stringEq(routeId, "uniswap-v2-fame-buy")) {
                test_PinnedBaseForkUniswapV2FameBuyExecutes();
            } else if (_stringEq(routeId, "uniswap-v2-fame-sell")) {
                test_PinnedBaseForkUniswapV2FameSellExecutes();
            } else if (_stringEq(routeId, "aerodrome-v2-usdc-weth-buy")) {
                test_PinnedBaseForkAerodromeV2UsdcWethExecutes();
            } else {
                revert("UNSUPPORTED_COVERED_ROUTE_ID");
            }
        }
    }

    function test_PinnedBaseForkGeneratedSolverRouteTableExecutesEveryRoute() public {
        for (uint256 i; i < FameRouterSolverFixtureManifest.routeArtifactCount(); ++i) {
            _selectPinnedBaseForkOrSkip();
            assertEq(FameRouterSolverFixtureManifest.pinnedBaseBlock(), block.number);
            _executeGeneratedSolverRoute(FameRouterSolverFixtureManifest.routeArtifactId(i));
        }
    }

    function _executeGeneratedSolverRoute(string memory routeId) private {
        string memory json = vm.readFile("test/router/fixtures/base-v1-solver-routes.json");
        string memory routeKey = _findFixtureKey(json, ".routes", routeId);
        FameRouterTypes.Route memory route = _loadGeneratedRoute(json, string.concat(routeKey, ".route"));
        bytes memory abiEncodedRoute = vm.parseJsonBytes(json, string.concat(routeKey, ".abiEncodedRoute"));
        bytes32 routeHash = vm.parseJsonBytes32(json, string.concat(routeKey, ".routeHash"));

        assertEq(keccak256(abiEncodedRoute), routeHash);
        assertEq(keccak256(abi.encode(route)), routeHash);
        assertEq(keccak256(abi.encode(route)), keccak256(abiEncodedRoute));
        assertGt(route.deadline, block.timestamp);

        deployCodeTo("FameRouter.sol:FameRouter", abi.encode(FEE_RECIPIENT), GENERATED_ROUTER);
        FameRouter router = FameRouter(payable(GENERATED_ROUTER));
        _enableGeneratedRouteTargets(router);
        _assertGeneratedRouteTargetsAllowed(route);
        _assertGeneratedNativeWrapTargetsCanonical(route);

        uint256 callValue = _fundGeneratedRoute(route, json, routeKey);

        vm.startPrank(USER);
        if (route.tokenIn != FameRouterTypes.NATIVE_ETH) {
            IERC20Fork(route.tokenIn).approve(address(router), route.amountIn);
        }
        uint256 beforeFeeRecipient = _assetBalance(route.tokenOut, FEE_RECIPIENT);
        uint256 beforeRecipient = _assetBalance(route.tokenOut, route.recipient);
        uint256 netOut = router.executeRoute{value: callValue}(route);
        vm.stopPrank();

        uint256 feePaid = _assetBalance(route.tokenOut, FEE_RECIPIENT) - beforeFeeRecipient;
        uint256 grossOut = netOut + feePaid;
        assertGt(netOut, 0);
        assertEq(feePaid, (grossOut * uint256(FameRouterTypes.DEFAULT_FEE_PPM)) / FameRouterTypes.FEE_DENOMINATOR);
        assertEq(_assetBalance(route.tokenOut, route.recipient) - beforeRecipient, netOut);
        _assertGeneratedRouteAssetsZero(route, address(router));
    }

    function _enableGeneratedRouteTargets(FameRouter router) private {
        for (uint256 i; i < FameRouterSolverFixtureManifest.requiredVenueTargetCount(); ++i) {
            FameRouterSolverFixtureManifest.Target memory target =
                FameRouterSolverFixtureManifest.requiredVenueTarget(i);
            router.setVenueFamilyEnabled(target.family, true);
            router.setVenueTargetEnabled(target.family, target.target, true);
        }
    }

    function _assertGeneratedRouteTargetsAllowed(FameRouterTypes.Route memory route) private pure {
        for (uint256 i; i < route.legs.length; ++i) {
            bool allowed;
            for (uint256 j; j < FameRouterSolverFixtureManifest.requiredVenueTargetCount(); ++j) {
                FameRouterSolverFixtureManifest.Target memory target =
                    FameRouterSolverFixtureManifest.requiredVenueTarget(j);
                if (target.family == route.legs[i].venue && target.target == route.legs[i].target) {
                    allowed = true;
                    break;
                }
            }
            assertTrue(allowed);
        }
    }

    function _assertGeneratedNativeWrapTargetsCanonical(FameRouterTypes.Route memory route) private {
        for (uint256 i; i < route.legs.length; ++i) {
            if (route.legs[i].venue != FameRouterTypes.VenueFamily.NativeWrap) continue;
            assertEq(route.legs[i].target, BASE_WETH);
            _assertCode(route.legs[i].target);

            uint256 beforeWeth = IERC20Fork(BASE_WETH).balanceOf(USER);
            vm.deal(USER, USER.balance + 1 wei);
            vm.startPrank(USER);
            IWETH9(BASE_WETH).deposit{value: 1 wei}();
            IWETH9(BASE_WETH).withdraw(1 wei);
            vm.stopPrank();
            assertEq(IERC20Fork(BASE_WETH).balanceOf(USER), beforeWeth);
        }
    }

    function _fundGeneratedRoute(FameRouterTypes.Route memory route, string memory json, string memory routeKey)
        private
        returns (uint256 callValue)
    {
        string memory fundingType = vm.parseJsonString(json, string.concat(routeKey, ".funding.type"));
        if (_stringEq(fundingType, "deal-erc20")) {
            deal(route.tokenIn, USER, route.amountIn);
            return 0;
        }
        if (_stringEq(fundingType, "native-weth-wrap")) {
            vm.deal(USER, route.amountIn);
            vm.startPrank(USER);
            IWETH9(route.tokenIn).deposit{value: route.amountIn}();
            vm.stopPrank();
            return 0;
        }
        if (_stringEq(fundingType, "native-eth")) {
            vm.deal(USER, route.amountIn);
            return route.amountIn;
        }
        if (_stringEq(fundingType, "acquire-via-route")) {
            string memory fundingRouteId = vm.parseJsonString(json, string.concat(routeKey, ".funding.routeId"));
            uint256 fundingAmountIn = _jsonUintString(json, string.concat(routeKey, ".funding.amountIn"));
            uint256 expectedAmountOut = _jsonUintString(json, string.concat(routeKey, ".funding.expectedAmountOut"));
            if (_stringEq(fundingRouteId, "slipstream-basedflick-fame-buy")) {
                ForkRouteFixture memory fixture =
                    _loadSlipstreamRouteFixture(fundingRouteId, true, "aerodrome-slipstream");
                uint256 acquired = _acquireFameThroughSlipstream(
                    USER, fixture.target, fixture.tokenIn, fixture.tokenOut, fundingAmountIn, fixture.tickSpacing
                );
                assertEq(acquired, expectedAmountOut);
                assertEq(acquired, route.amountIn);
                return 0;
            }
            revert("UNSUPPORTED_GENERATED_ACQUIRE_ROUTE");
        }
        revert("UNSUPPORTED_GENERATED_FUNDING");
    }

    function _loadGeneratedRoute(string memory json, string memory key)
        private
        view
        returns (FameRouterTypes.Route memory route)
    {
        route.version = uint16(vm.parseJsonUint(json, string.concat(key, ".version")));
        route.tokenIn = vm.parseJsonAddress(json, string.concat(key, ".tokenIn"));
        route.tokenOut = vm.parseJsonAddress(json, string.concat(key, ".tokenOut"));
        route.amountIn = _jsonUintString(json, string.concat(key, ".amountIn"));
        route.minAmountOutAfterFee = _jsonUintString(json, string.concat(key, ".minAmountOutAfterFee"));
        route.recipient = vm.parseJsonAddress(json, string.concat(key, ".recipient"));
        route.deadline = _jsonUintString(json, string.concat(key, ".deadline"));

        uint256 legCount = _jsonArrayLength(json, string.concat(key, ".legs"));
        route.legs = new FameRouterTypes.Leg[](legCount);
        for (uint256 i; i < legCount; ++i) {
            string memory legKey = string.concat(key, ".legs[", vm.toString(i), "]");
            route.legs[i] = FameRouterTypes.Leg({
                tokenIn: vm.parseJsonAddress(json, string.concat(legKey, ".tokenIn")),
                tokenOut: vm.parseJsonAddress(json, string.concat(legKey, ".tokenOut")),
                venue: FameRouterTypes.VenueFamily(
                    uint8(vm.parseJsonUint(json, string.concat(legKey, ".venueOrdinal")))
                ),
                amountMode: FameRouterTypes.AmountMode(
                    uint8(vm.parseJsonUint(json, string.concat(legKey, ".amountModeOrdinal")))
                ),
                amount: _jsonUintString(json, string.concat(legKey, ".amount")),
                minAmountOut: _jsonUintString(json, string.concat(legKey, ".minAmountOut")),
                target: vm.parseJsonAddress(json, string.concat(legKey, ".target")),
                data: vm.parseJsonBytes(json, string.concat(legKey, ".data"))
            });
        }
    }

    function _assertGeneratedRouteAssetsZero(FameRouterTypes.Route memory route, address router) private view {
        _assertGeneratedAssetZero(route.tokenIn, router);
        _assertGeneratedAssetZero(route.tokenOut, router);
        for (uint256 i; i < route.legs.length; ++i) {
            _assertGeneratedAssetZero(route.legs[i].tokenIn, router);
            _assertGeneratedAssetZero(route.legs[i].tokenOut, router);
        }
    }

    function _assertGeneratedAssetZero(address asset, address router) private view {
        assertEq(_assetBalance(asset, router), 0);
    }

    function _executeSolidlyRouteFixture(string memory routeId, bool buy) private {
        ForkRouteFixture memory fixture = _loadSolidlyRouteFixture(routeId, buy);
        if (!buy) {
            uint256 acquiredFame = _acquireFameThroughSolidly(
                USER, fixture.target, fixture.tokenOut, fixture.tokenIn, fixture.fundingAmountIn, fixture.stable
            );
            assertEq(acquiredFame, fixture.amountIn);
        }

        FameRouter router = new FameRouter(FEE_RECIPIENT);
        router.setVenueFamilyEnabled(FameRouterTypes.VenueFamily.Solidly, true);
        router.setVenueTargetEnabled(FameRouterTypes.VenueFamily.Solidly, fixture.target, true);

        if (buy && _stringEq(_fundingType(routeId), "native-weth-wrap")) {
            vm.deal(USER, fixture.amountIn);
            vm.startPrank(USER);
            IWETH9(fixture.tokenIn).deposit{value: fixture.amountIn}();
        } else if (buy && _stringEq(_fundingType(routeId), "deal-erc20")) {
            deal(fixture.tokenIn, USER, fixture.amountIn);
            vm.startPrank(USER);
        } else {
            vm.startPrank(USER);
        }
        IERC20Fork(fixture.tokenIn).approve(address(router), fixture.amountIn);

        FameRouterTypes.Route memory route = _singleLegForkRoute(
            fixture, FameRouterTypes.VenueFamily.Solidly, _solidlyPayload(fixture, block.timestamp + 1 hours)
        );

        uint256 beforeFeeRecipient = IERC20Fork(fixture.tokenOut).balanceOf(FEE_RECIPIENT);
        uint256 netOut = router.executeRoute(route);
        vm.stopPrank();

        _assertRouteSettledWithFee(fixture, address(router), netOut, beforeFeeRecipient);
    }

    function _executeSlipstreamRouteFixture(
        string memory routeId,
        bool buy,
        string memory venue,
        FameRouterTypes.VenueFamily venueFamily
    ) private {
        ForkRouteFixture memory fixture = _loadSlipstreamRouteFixture(routeId, buy, venue);
        if (!buy) {
            uint256 acquiredFame = _acquireFameThroughSlipstream(
                USER, fixture.target, fixture.tokenOut, fixture.tokenIn, fixture.fundingAmountIn, fixture.tickSpacing
            );
            assertEq(acquiredFame, fixture.amountIn);
        }

        FameRouter router = new FameRouter(FEE_RECIPIENT);
        router.setVenueFamilyEnabled(venueFamily, true);
        router.setVenueTargetEnabled(venueFamily, fixture.target, true);

        if (buy && _stringEq(_fundingType(routeId), "deal-erc20")) {
            deal(fixture.tokenIn, USER, fixture.amountIn);
        }

        vm.startPrank(USER);
        IERC20Fork(fixture.tokenIn).approve(address(router), fixture.amountIn);

        FameRouterTypes.Route memory route =
            _singleLegForkRoute(fixture, venueFamily, _slipstreamPayload(fixture, block.timestamp + 1 hours));

        uint256 beforeFeeRecipient = IERC20Fork(fixture.tokenOut).balanceOf(FEE_RECIPIENT);
        uint256 netOut = router.executeRoute(route);
        vm.stopPrank();

        _assertRouteSettledWithFee(fixture, address(router), netOut, beforeFeeRecipient);
    }

    function _executeAerodromeV2RouteFixture(string memory routeId) private {
        ForkRouteFixture memory fixture = _loadAerodromeV2RouteFixture(routeId);

        FameRouter router = new FameRouter(FEE_RECIPIENT);
        router.setVenueFamilyEnabled(FameRouterTypes.VenueFamily.AerodromeV2, true);
        router.setVenueTargetEnabled(FameRouterTypes.VenueFamily.AerodromeV2, fixture.target, true);

        deal(fixture.tokenIn, USER, fixture.amountIn);

        vm.startPrank(USER);
        IERC20Fork(fixture.tokenIn).approve(address(router), fixture.amountIn);

        FameRouterTypes.Route memory route = _singleLegForkRoute(
            fixture, FameRouterTypes.VenueFamily.AerodromeV2, _aerodromeV2Payload(fixture, block.timestamp + 1 hours)
        );

        uint256 beforeFeeRecipient = IERC20Fork(fixture.tokenOut).balanceOf(FEE_RECIPIENT);
        uint256 netOut = router.executeRoute(route);
        vm.stopPrank();

        _assertRouteSettledWithFee(fixture, address(router), netOut, beforeFeeRecipient);
    }

    function _executeUniversalRouteFixture(
        string memory routeId,
        bool buy,
        string memory venue,
        FameRouterTypes.VenueFamily venueFamily
    ) private {
        ForkRouteFixture memory fixture = _loadUniversalRouteFixture(routeId, buy, venue);
        if (!buy) {
            uint256 acquired = _acquireOutputThroughUniversalFundingRoute(routeId, venue, venueFamily);
            assertEq(acquired, fixture.amountIn);
        }

        FameRouter router = new FameRouter(FEE_RECIPIENT);
        router.setVenueFamilyEnabled(venueFamily, true);
        router.setVenueTargetEnabled(venueFamily, fixture.target, true);

        uint256 callValue;
        string memory fundingType = _fundingType(routeId);
        if (buy && _stringEq(fundingType, "native-eth")) {
            vm.deal(USER, fixture.amountIn);
            callValue = fixture.amountIn;
        } else if (buy && _stringEq(fundingType, "native-weth-wrap")) {
            vm.deal(USER, fixture.amountIn);
            vm.startPrank(USER);
            IWETH9(fixture.tokenIn).deposit{value: fixture.amountIn}();
            vm.stopPrank();
        } else if (buy && _stringEq(fundingType, "deal-erc20")) {
            deal(fixture.tokenIn, USER, fixture.amountIn);
        }

        vm.startPrank(USER);
        if (fixture.tokenIn != FameRouterTypes.NATIVE_ETH) {
            IERC20Fork(fixture.tokenIn).approve(address(router), fixture.amountIn);
        }

        bytes memory payload = venueFamily == FameRouterTypes.VenueFamily.UniswapV3
            ? _universalV3Payload(fixture, address(router), block.timestamp + 1 hours)
            : _universalV4Payload(fixture, address(router), block.timestamp + 1 hours);
        FameRouterTypes.Route memory route = _singleLegForkRoute(fixture, venueFamily, payload);

        uint256 beforeFeeRecipient = _assetBalance(fixture.tokenOut, FEE_RECIPIENT);
        uint256 netOut = router.executeRoute{value: callValue}(route);
        vm.stopPrank();

        _assertRouteSettledWithFee(fixture, address(router), netOut, beforeFeeRecipient);
    }

    function _assertErc20PoolMetadata(string memory poolsJson, string memory key, string memory venue) private view {
        address pool = vm.parseJsonAddress(poolsJson, string.concat(key, ".pool"));
        address token0 = vm.parseJsonAddress(poolsJson, string.concat(key, ".token0"));
        address token1 = vm.parseJsonAddress(poolsJson, string.concat(key, ".token1"));
        IBasePoolMetadata metadata = IBasePoolMetadata(pool);

        _assertCode(pool);
        _assertCode(token0);
        _assertCode(token1);
        assertEq(metadata.token0(), token0);
        assertEq(metadata.token1(), token1);

        if (_hasKey(poolsJson, key, "factory")) {
            assertEq(metadata.factory(), vm.parseJsonAddress(poolsJson, string.concat(key, ".factory")));
        }
        if (_stringEq(venue, "solidly") || _stringEq(venue, "aerodrome-v2")) {
            assertEq(metadata.stable(), vm.parseJsonBool(poolsJson, string.concat(key, ".stable")));
        }
        if (_stringEq(venue, "aerodrome-v2")) {
            address factory = vm.parseJsonAddress(poolsJson, string.concat(key, ".factory"));
            bool stable = vm.parseJsonBool(poolsJson, string.concat(key, ".stable"));
            IAerodromeV2FactoryFork aerodromeFactory = IAerodromeV2FactoryFork(factory);
            assertEq(aerodromeFactory.getPool(token0, token1, stable), pool);
            assertTrue(aerodromeFactory.isPool(pool));
            assertEq(aerodromeFactory.getFee(pool, stable), vm.parseJsonUint(poolsJson, string.concat(key, ".feeBps")));
        }
        if (
            _stringEq(venue, "aerodrome-slipstream") || _stringEq(venue, "aerodrome-slipstream2")
                || _stringEq(venue, "uniswap-v3")
        ) {
            assertEq(metadata.tickSpacing(), vm.parseJsonInt(poolsJson, string.concat(key, ".tickSpacing")));
        }
        if (_stringEq(venue, "uniswap-v3")) {
            assertEq(metadata.fee(), uint24(vm.parseJsonUint(poolsJson, string.concat(key, ".fee"))));
        }
    }

    function _assertUniswapV4PoolMetadata(string memory poolsJson, string memory key) private view {
        address poolManager = vm.parseJsonAddress(poolsJson, string.concat(key, ".poolManager"));
        address stateView = vm.parseJsonAddress(poolsJson, string.concat(key, ".stateView"));
        address currency0 = vm.parseJsonAddress(poolsJson, string.concat(key, ".currency0"));
        address currency1 = vm.parseJsonAddress(poolsJson, string.concat(key, ".currency1"));
        address hooks = vm.parseJsonAddress(poolsJson, string.concat(key, ".hooks"));
        uint24 fee = uint24(vm.parseJsonUint(poolsJson, string.concat(key, ".fee")));
        int24 tickSpacing = int24(vm.parseJsonInt(poolsJson, string.concat(key, ".tickSpacing")));
        bytes32 poolId = vm.parseJsonBytes32(poolsJson, string.concat(key, ".poolId"));
        bytes32 derivedPoolId = keccak256(abi.encode(currency0, currency1, fee, tickSpacing, hooks));

        assertEq(poolId, derivedPoolId);
        _assertCode(poolManager);
        _assertCode(stateView);
        if (currency0 != address(0)) _assertCode(currency0);
        if (currency1 != address(0)) _assertCode(currency1);
        if (hooks != address(0)) _assertCode(hooks);

        (uint160 sqrtPriceX96,,,) = IV4StateView(stateView).getSlot0(poolId);
        assertGt(sqrtPriceX96, 0);
    }

    function _uniswapV2PathPayload(address tokenIn, address tokenOut, uint256 deadline)
        private
        pure
        returns (bytes memory)
    {
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
        return abi.encode(UniswapV2Adapter.Payload({path: path, deadline: deadline}));
    }

    function _solidlyPayload(ForkRouteFixture memory fixture, uint256 deadline) private pure returns (bytes memory) {
        ISolidlyRouter.Route[] memory routes = new ISolidlyRouter.Route[](fixture.stablePath.length);
        for (uint256 i; i < fixture.stablePath.length; ++i) {
            routes[i] =
                ISolidlyRouter.Route({from: fixture.path[i], to: fixture.path[i + 1], stable: fixture.stablePath[i]});
        }
        return abi.encode(SolidlyRouterAdapter.Payload({routes: routes, deadline: deadline}));
    }

    function _slipstreamPayload(ForkRouteFixture memory fixture, uint256 deadline) private pure returns (bytes memory) {
        return abi.encode(
            SlipstreamAdapter.Payload({
                router: fixture.target,
                factory: fixture.factory,
                tokenIn: fixture.tokenIn,
                tokenOut: fixture.tokenOut,
                tickSpacing: fixture.tickSpacing,
                sqrtPriceLimitX96: 0,
                deadline: deadline
            })
        );
    }

    function _aerodromeV2Payload(ForkRouteFixture memory fixture, uint256 deadline)
        private
        pure
        returns (bytes memory)
    {
        IAerodromeV2Router.AerodromeRoute[] memory routes = new IAerodromeV2Router.AerodromeRoute[](1);
        routes[0] = IAerodromeV2Router.AerodromeRoute({
            from: fixture.tokenIn,
            to: fixture.tokenOut,
            stable: fixture.stable,
            factory: fixture.factory
        });
        return abi.encode(AerodromeV2RouterAdapter.Payload({routes: routes, deadline: deadline}));
    }

    function _universalV3Payload(ForkRouteFixture memory fixture, address recipient, uint256 deadline)
        private
        pure
        returns (bytes memory)
    {
        return abi.encode(
            UniversalRouterAdapter.V3ExactInputPayload({
                path: abi.encodePacked(fixture.tokenIn, fixture.fee, fixture.tokenOut),
                deadline: deadline,
                payerIsUser: true,
                recipient: recipient
            })
        );
    }

    function _universalV4Payload(ForkRouteFixture memory fixture, address recipient, uint256 deadline)
        private
        pure
        returns (bytes memory)
    {
        bool zeroForOne = fixture.currency0 == fixture.tokenIn;
        return abi.encode(
            UniversalRouterAdapter.V4SwapPayload({
                tokenIn: fixture.tokenIn,
                tokenOut: fixture.tokenOut,
                amountIn: fixture.amountIn,
                minAmountOut: fixture.legMinAmountOut,
                currency0: fixture.currency0,
                currency1: fixture.currency1,
                zeroForOne: zeroForOne,
                fee: fixture.fee,
                tickSpacing: fixture.tickSpacing,
                hooks: fixture.hooks,
                hookData: "",
                deadline: deadline,
                recipient: recipient,
                payerIsUser: false
            })
        );
    }

    function _singleLegForkRoute(
        ForkRouteFixture memory fixture,
        FameRouterTypes.VenueFamily venue,
        bytes memory payload
    ) private view returns (FameRouterTypes.Route memory route) {
        route.version = FameRouterTypes.SCHEMA_VERSION;
        route.tokenIn = fixture.tokenIn;
        route.tokenOut = fixture.tokenOut;
        route.amountIn = fixture.amountIn;
        route.minAmountOutAfterFee = fixture.minAmountOutAfterFee;
        route.recipient = RECIPIENT;
        route.deadline = block.timestamp + 1 hours;
        route.legs = new FameRouterTypes.Leg[](1);
        route.legs[0] = FameRouterTypes.Leg({
            tokenIn: fixture.tokenIn,
            tokenOut: fixture.tokenOut,
            venue: venue,
            amountMode: FameRouterTypes.AmountMode.Exact,
            amount: fixture.amountIn,
            minAmountOut: fixture.legMinAmountOut,
            target: fixture.target,
            data: payload
        });
    }

    function _assertRouteSettledWithFee(
        ForkRouteFixture memory fixture,
        address router,
        uint256 netOut,
        uint256 beforeFeeRecipient
    ) private view {
        uint256 feePaid = IERC20Fork(fixture.tokenOut).balanceOf(FEE_RECIPIENT) - beforeFeeRecipient;
        uint256 grossOut = netOut + feePaid;
        assertGt(netOut, 0);
        assertEq(feePaid, (grossOut * uint256(FameRouterTypes.DEFAULT_FEE_PPM)) / FameRouterTypes.FEE_DENOMINATOR);
        assertEq(_assetBalance(fixture.tokenIn, router), 0);
        assertEq(_assetBalance(fixture.tokenOut, router), 0);
        assertEq(_assetBalance(fixture.tokenOut, RECIPIENT), netOut);
        assertGt(feePaid, 0);
    }

    function _loadUniswapV2RouteFixture(string memory routeId, bool buy)
        private
        view
        returns (ForkRouteFixture memory fixture)
    {
        string memory routesJson = vm.readFile("test/router/fixtures/base-v1-routes.json");
        string memory poolsJson = vm.readFile("test/router/fixtures/base-v1-pools.json");
        string memory routeKey = _findFixtureKey(routesJson, ".routes", routeId);
        string[] memory poolIds = vm.parseJsonStringArray(routesJson, string.concat(routeKey, ".poolIds"));
        assertEq(poolIds.length, 1);
        assertEq(poolIds[0], "uniswap-v2-fame-direct");
        assertEq(vm.parseJsonString(routesJson, string.concat(routeKey, ".minimumPolicy")), "pinned-fork-smoke-minimum");

        string memory poolKey = _findFixtureKey(poolsJson, ".pools", poolIds[0]);
        fixture.tokenIn = vm.parseJsonAddress(routesJson, string.concat(routeKey, ".tokenIn"));
        fixture.tokenOut = vm.parseJsonAddress(routesJson, string.concat(routeKey, ".tokenOut"));
        fixture.target = vm.parseJsonAddress(poolsJson, string.concat(poolKey, ".router"));
        fixture.amountIn = _jsonUintString(routesJson, string.concat(routeKey, ".amountIn"));
        fixture.legMinAmountOut = _jsonUintString(routesJson, string.concat(routeKey, ".legMinAmountOut"));
        fixture.minAmountOutAfterFee = _jsonUintString(routesJson, string.concat(routeKey, ".minAmountOutAfterFee"));

        if (buy) {
            assertEq(fixture.tokenIn, vm.parseJsonAddress(poolsJson, string.concat(poolKey, ".token0")));
            assertEq(fixture.tokenOut, vm.parseJsonAddress(poolsJson, string.concat(poolKey, ".token1")));
            assertEq(vm.parseJsonString(routesJson, string.concat(routeKey, ".funding.type")), "native-weth-wrap");
            assertEq(_jsonUintString(routesJson, string.concat(routeKey, ".funding.amount")), fixture.amountIn);
        } else {
            assertEq(fixture.tokenIn, vm.parseJsonAddress(poolsJson, string.concat(poolKey, ".token1")));
            assertEq(fixture.tokenOut, vm.parseJsonAddress(poolsJson, string.concat(poolKey, ".token0")));
            assertEq(vm.parseJsonString(routesJson, string.concat(routeKey, ".funding.type")), "acquire-via-route");
            assertEq(vm.parseJsonString(routesJson, string.concat(routeKey, ".funding.routeId")), "uniswap-v2-fame-buy");
            fixture.fundingAmountIn = _jsonUintString(routesJson, string.concat(routeKey, ".funding.amountIn"));
        }
    }

    function _loadSolidlyRouteFixture(string memory routeId, bool buy)
        private
        view
        returns (ForkRouteFixture memory fixture)
    {
        string memory routesJson = vm.readFile("test/router/fixtures/base-v1-routes.json");
        string memory poolsJson = vm.readFile("test/router/fixtures/base-v1-pools.json");
        string memory routeKey = _findFixtureKey(routesJson, ".routes", routeId);
        string[] memory poolIds = vm.parseJsonStringArray(routesJson, string.concat(routeKey, ".poolIds"));
        assertGt(poolIds.length, 0);
        assertEq(vm.parseJsonString(routesJson, string.concat(routeKey, ".minimumPolicy")), "pinned-fork-smoke-minimum");

        fixture.tokenIn = vm.parseJsonAddress(routesJson, string.concat(routeKey, ".tokenIn"));
        fixture.tokenOut = vm.parseJsonAddress(routesJson, string.concat(routeKey, ".tokenOut"));
        fixture.amountIn = _jsonUintString(routesJson, string.concat(routeKey, ".amountIn"));
        fixture.legMinAmountOut = _jsonUintString(routesJson, string.concat(routeKey, ".legMinAmountOut"));
        fixture.minAmountOutAfterFee = _jsonUintString(routesJson, string.concat(routeKey, ".minAmountOutAfterFee"));
        fixture.path = new address[](poolIds.length + 1);
        fixture.stablePath = new bool[](poolIds.length);
        fixture.path[0] = fixture.tokenIn;

        for (uint256 i; i < poolIds.length; ++i) {
            string memory poolKey = _findFixtureKey(poolsJson, ".pools", poolIds[i]);
            address poolRouter = vm.parseJsonAddress(poolsJson, string.concat(poolKey, ".router"));
            address token0 = vm.parseJsonAddress(poolsJson, string.concat(poolKey, ".token0"));
            address token1 = vm.parseJsonAddress(poolsJson, string.concat(poolKey, ".token1"));

            if (i == 0) {
                fixture.target = poolRouter;
            } else {
                assertEq(poolRouter, fixture.target);
            }

            fixture.stablePath[i] = vm.parseJsonBool(poolsJson, string.concat(poolKey, ".stable"));
            if (fixture.path[i] == token0) {
                fixture.path[i + 1] = token1;
            } else if (fixture.path[i] == token1) {
                fixture.path[i + 1] = token0;
            } else {
                revert("SOLIDLY_POOL_PATH_DISCONNECTED");
            }
        }

        assertEq(fixture.path[poolIds.length], fixture.tokenOut);
        fixture.stable = fixture.stablePath[0];

        string memory fundingType = vm.parseJsonString(routesJson, string.concat(routeKey, ".funding.type"));
        if (buy && _stringEq(fundingType, "native-weth-wrap")) {
            assertEq(_jsonUintString(routesJson, string.concat(routeKey, ".funding.amount")), fixture.amountIn);
        } else if (buy && _stringEq(fundingType, "deal-erc20")) {
            assertEq(_jsonUintString(routesJson, string.concat(routeKey, ".funding.amount")), fixture.amountIn);
            assertGt(bytes(vm.parseJsonString(routesJson, string.concat(routeKey, ".funding.justification"))).length, 0);
        } else if (!buy && _stringEq(fundingType, "acquire-via-route")) {
            assertEq(
                vm.parseJsonString(routesJson, string.concat(routeKey, ".funding.routeId")), "solidly-weth-fame-buy"
            );
            fixture.fundingAmountIn = _jsonUintString(routesJson, string.concat(routeKey, ".funding.amountIn"));
        } else {
            revert("UNSUPPORTED_SOLIDLY_FUNDING");
        }
    }

    function _loadSlipstreamRouteFixture(string memory routeId, bool buy, string memory venue)
        private
        view
        returns (ForkRouteFixture memory fixture)
    {
        string memory routesJson = vm.readFile("test/router/fixtures/base-v1-routes.json");
        string memory poolsJson = vm.readFile("test/router/fixtures/base-v1-pools.json");
        string memory routeKey = _findFixtureKey(routesJson, ".routes", routeId);
        string[] memory poolIds = vm.parseJsonStringArray(routesJson, string.concat(routeKey, ".poolIds"));
        assertEq(poolIds.length, 1);
        assertEq(vm.parseJsonString(routesJson, string.concat(routeKey, ".minimumPolicy")), "pinned-fork-smoke-minimum");

        string memory poolKey = _findFixtureKey(poolsJson, ".pools", poolIds[0]);
        assertEq(vm.parseJsonString(poolsJson, string.concat(poolKey, ".venue")), venue);

        fixture.tokenIn = vm.parseJsonAddress(routesJson, string.concat(routeKey, ".tokenIn"));
        fixture.tokenOut = vm.parseJsonAddress(routesJson, string.concat(routeKey, ".tokenOut"));
        fixture.target = vm.parseJsonAddress(poolsJson, string.concat(poolKey, ".router"));
        fixture.factory = vm.parseJsonAddress(poolsJson, string.concat(poolKey, ".factory"));
        fixture.tickSpacing = int24(vm.parseJsonInt(poolsJson, string.concat(poolKey, ".tickSpacing")));
        fixture.amountIn = _jsonUintString(routesJson, string.concat(routeKey, ".amountIn"));
        fixture.legMinAmountOut = _jsonUintString(routesJson, string.concat(routeKey, ".legMinAmountOut"));
        fixture.minAmountOutAfterFee = _jsonUintString(routesJson, string.concat(routeKey, ".minAmountOutAfterFee"));

        if (buy) {
            assertEq(vm.parseJsonString(routesJson, string.concat(routeKey, ".funding.type")), "deal-erc20");
            assertEq(_jsonUintString(routesJson, string.concat(routeKey, ".funding.amount")), fixture.amountIn);
            assertGt(bytes(vm.parseJsonString(routesJson, string.concat(routeKey, ".funding.justification"))).length, 0);
        } else {
            assertEq(vm.parseJsonString(routesJson, string.concat(routeKey, ".funding.type")), "acquire-via-route");
            assertGt(bytes(vm.parseJsonString(routesJson, string.concat(routeKey, ".funding.routeId"))).length, 0);
            fixture.fundingAmountIn = _jsonUintString(routesJson, string.concat(routeKey, ".funding.amountIn"));
        }
    }

    function _loadAerodromeV2RouteFixture(string memory routeId)
        private
        view
        returns (ForkRouteFixture memory fixture)
    {
        string memory routesJson = vm.readFile("test/router/fixtures/base-v1-routes.json");
        string memory poolsJson = vm.readFile("test/router/fixtures/base-v1-pools.json");
        string memory routeKey = _findFixtureKey(routesJson, ".routes", routeId);
        string[] memory poolIds = vm.parseJsonStringArray(routesJson, string.concat(routeKey, ".poolIds"));
        assertEq(poolIds.length, 1);
        assertEq(vm.parseJsonString(routesJson, string.concat(routeKey, ".minimumPolicy")), "pinned-fork-smoke-minimum");

        string memory poolKey = _findFixtureKey(poolsJson, ".pools", poolIds[0]);
        assertEq(vm.parseJsonString(poolsJson, string.concat(poolKey, ".venue")), "aerodrome-v2");

        fixture.tokenIn = vm.parseJsonAddress(routesJson, string.concat(routeKey, ".tokenIn"));
        fixture.tokenOut = vm.parseJsonAddress(routesJson, string.concat(routeKey, ".tokenOut"));
        fixture.target = vm.parseJsonAddress(poolsJson, string.concat(poolKey, ".router"));
        fixture.factory = vm.parseJsonAddress(poolsJson, string.concat(poolKey, ".factory"));
        fixture.stable = vm.parseJsonBool(poolsJson, string.concat(poolKey, ".stable"));
        fixture.amountIn = _jsonUintString(routesJson, string.concat(routeKey, ".amountIn"));
        fixture.legMinAmountOut = _jsonUintString(routesJson, string.concat(routeKey, ".legMinAmountOut"));
        fixture.minAmountOutAfterFee = _jsonUintString(routesJson, string.concat(routeKey, ".minAmountOutAfterFee"));

        address token0 = vm.parseJsonAddress(poolsJson, string.concat(poolKey, ".token0"));
        address token1 = vm.parseJsonAddress(poolsJson, string.concat(poolKey, ".token1"));
        assertTrue(
            (fixture.tokenIn == token0 && fixture.tokenOut == token1)
                || (fixture.tokenIn == token1 && fixture.tokenOut == token0)
        );

        assertEq(vm.parseJsonString(routesJson, string.concat(routeKey, ".funding.type")), "deal-erc20");
        assertEq(_jsonUintString(routesJson, string.concat(routeKey, ".funding.amount")), fixture.amountIn);
        assertGt(bytes(vm.parseJsonString(routesJson, string.concat(routeKey, ".funding.justification"))).length, 0);
    }

    function _loadUniversalRouteFixture(string memory routeId, bool buy, string memory venue)
        private
        view
        returns (ForkRouteFixture memory fixture)
    {
        string memory routesJson = vm.readFile("test/router/fixtures/base-v1-routes.json");
        string memory poolsJson = vm.readFile("test/router/fixtures/base-v1-pools.json");
        string memory routeKey = _findFixtureKey(routesJson, ".routes", routeId);
        string[] memory poolIds = vm.parseJsonStringArray(routesJson, string.concat(routeKey, ".poolIds"));
        assertEq(poolIds.length, 1);
        assertEq(vm.parseJsonString(routesJson, string.concat(routeKey, ".minimumPolicy")), "pinned-fork-smoke-minimum");

        string memory poolKey = _findFixtureKey(poolsJson, ".pools", poolIds[0]);
        assertEq(vm.parseJsonString(poolsJson, string.concat(poolKey, ".venue")), venue);

        fixture.tokenIn = vm.parseJsonAddress(routesJson, string.concat(routeKey, ".tokenIn"));
        fixture.tokenOut = vm.parseJsonAddress(routesJson, string.concat(routeKey, ".tokenOut"));
        fixture.target = vm.parseJsonAddress(poolsJson, string.concat(poolKey, ".router"));
        fixture.amountIn = _jsonUintString(routesJson, string.concat(routeKey, ".amountIn"));
        fixture.legMinAmountOut = _jsonUintString(routesJson, string.concat(routeKey, ".legMinAmountOut"));
        fixture.minAmountOutAfterFee = _jsonUintString(routesJson, string.concat(routeKey, ".minAmountOutAfterFee"));

        if (_stringEq(venue, "uniswap-v3")) {
            fixture.fee = uint24(vm.parseJsonUint(poolsJson, string.concat(poolKey, ".fee")));
        } else {
            fixture.currency0 = vm.parseJsonAddress(poolsJson, string.concat(poolKey, ".currency0"));
            fixture.currency1 = vm.parseJsonAddress(poolsJson, string.concat(poolKey, ".currency1"));
            fixture.fee = uint24(vm.parseJsonUint(poolsJson, string.concat(poolKey, ".fee")));
            fixture.tickSpacing = int24(vm.parseJsonInt(poolsJson, string.concat(poolKey, ".tickSpacing")));
            fixture.hooks = vm.parseJsonAddress(poolsJson, string.concat(poolKey, ".hooks"));
            bool zeroForOne = fixture.currency0 == fixture.tokenIn;
            assertEq(zeroForOne ? fixture.currency1 : fixture.currency0, fixture.tokenOut);
        }

        string memory fundingType = vm.parseJsonString(routesJson, string.concat(routeKey, ".funding.type"));
        if (buy && _stringEq(fundingType, "native-eth")) {
            assertEq(fixture.tokenIn, FameRouterTypes.NATIVE_ETH);
            assertEq(_jsonUintString(routesJson, string.concat(routeKey, ".funding.amount")), fixture.amountIn);
        } else if (buy && _stringEq(fundingType, "native-weth-wrap")) {
            assertEq(_jsonUintString(routesJson, string.concat(routeKey, ".funding.amount")), fixture.amountIn);
        } else if (buy && _stringEq(fundingType, "deal-erc20")) {
            assertEq(_jsonUintString(routesJson, string.concat(routeKey, ".funding.amount")), fixture.amountIn);
            assertGt(bytes(vm.parseJsonString(routesJson, string.concat(routeKey, ".funding.justification"))).length, 0);
        } else if (!buy && _stringEq(fundingType, "acquire-via-route")) {
            assertGt(bytes(vm.parseJsonString(routesJson, string.concat(routeKey, ".funding.routeId"))).length, 0);
            fixture.fundingAmountIn = _jsonUintString(routesJson, string.concat(routeKey, ".funding.amountIn"));
        } else {
            revert("UNSUPPORTED_UNIVERSAL_FUNDING");
        }
    }

    function _acquireFameThroughUniswapV2(
        address user,
        address target,
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) private returns (uint256 amountOut) {
        vm.deal(user, amountIn);
        vm.startPrank(user);
        IWETH9(tokenIn).deposit{value: amountIn}();
        IERC20Fork(tokenIn).approve(target, amountIn);
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
        uint256 beforeOut = IERC20Fork(tokenOut).balanceOf(user);
        IUniswapV2Router02(target).swapExactTokensForTokens(amountIn, 1, path, user, block.timestamp + 1 hours);
        amountOut = IERC20Fork(tokenOut).balanceOf(user) - beforeOut;
        vm.stopPrank();
    }

    function _acquireFameThroughSolidly(
        address user,
        address target,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        bool stable
    ) private returns (uint256 amountOut) {
        vm.deal(user, amountIn);
        vm.startPrank(user);
        IWETH9(tokenIn).deposit{value: amountIn}();
        IERC20Fork(tokenIn).approve(target, amountIn);
        ISolidlyRouter.Route[] memory routes = new ISolidlyRouter.Route[](1);
        routes[0] = ISolidlyRouter.Route({from: tokenIn, to: tokenOut, stable: stable});
        uint256 beforeOut = IERC20Fork(tokenOut).balanceOf(user);
        ISolidlyRouter(target).swapExactTokensForTokens(amountIn, 1, routes, user, block.timestamp + 1 hours);
        amountOut = IERC20Fork(tokenOut).balanceOf(user) - beforeOut;
        vm.stopPrank();
    }

    function _acquireFameThroughSlipstream(
        address user,
        address target,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        int24 tickSpacing
    ) private returns (uint256 amountOut) {
        deal(tokenIn, user, amountIn);
        vm.startPrank(user);
        IERC20Fork(tokenIn).approve(target, amountIn);
        uint256 beforeOut = IERC20Fork(tokenOut).balanceOf(user);
        ISlipstreamRouter(target)
            .exactInputSingle(
                ISlipstreamRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                tickSpacing: tickSpacing,
                recipient: user,
                deadline: block.timestamp + 1 hours,
                amountIn: amountIn,
                amountOutMinimum: 1,
                sqrtPriceLimitX96: 0
            })
            );
        amountOut = IERC20Fork(tokenOut).balanceOf(user) - beforeOut;
        vm.stopPrank();
    }

    function _acquireOutputThroughUniversalFundingRoute(
        string memory fundedRouteId,
        string memory venue,
        FameRouterTypes.VenueFamily venueFamily
    ) private returns (uint256 amountOut) {
        string memory routeId = _fundingRouteId(fundedRouteId);
        ForkRouteFixture memory fixture = _loadUniversalRouteFixture(routeId, true, venue);
        uint256 beforeOut = _assetBalance(fixture.tokenOut, USER);

        uint256 callValue;
        string memory fundingType = _fundingType(routeId);
        if (_stringEq(fundingType, "native-eth")) {
            vm.deal(USER, fixture.amountIn);
            callValue = fixture.amountIn;
        } else if (_stringEq(fundingType, "native-weth-wrap")) {
            vm.deal(USER, fixture.amountIn);
            vm.startPrank(USER);
            IWETH9(fixture.tokenIn).deposit{value: fixture.amountIn}();
            vm.stopPrank();
        } else if (_stringEq(fundingType, "deal-erc20")) {
            deal(fixture.tokenIn, USER, fixture.amountIn);
        } else {
            revert("UNSUPPORTED_UNIVERSAL_ACQUISITION_FUNDING");
        }

        vm.startPrank(USER);
        if (fixture.tokenIn != FameRouterTypes.NATIVE_ETH) {
            IERC20Fork(fixture.tokenIn).approve(PERMIT2, fixture.amountIn);
            IPermit2(PERMIT2)
                .approve(fixture.tokenIn, fixture.target, uint160(fixture.amountIn), uint48(block.timestamp));
        }

        bytes memory commands = new bytes(1);
        bytes[] memory inputs = new bytes[](1);
        if (venueFamily == FameRouterTypes.VenueFamily.UniswapV3) {
            commands[0] = 0x00;
            inputs[0] = abi.encode(
                USER,
                fixture.amountIn,
                uint256(1),
                abi.encodePacked(fixture.tokenIn, fixture.fee, fixture.tokenOut),
                true
            );
        } else {
            commands[0] = 0x10;
            inputs[0] = _v4UniversalRouterInput(fixture, 1);
        }
        IUniversalRouter(fixture.target).execute{value: callValue}(commands, inputs, block.timestamp + 1 hours);
        if (fixture.tokenIn != FameRouterTypes.NATIVE_ETH) {
            IPermit2(PERMIT2).approve(fixture.tokenIn, fixture.target, 0, uint48(block.timestamp));
            IERC20Fork(fixture.tokenIn).approve(PERMIT2, 0);
        }
        vm.stopPrank();

        amountOut = _assetBalance(fixture.tokenOut, USER) - beforeOut;
    }

    function _v4UniversalRouterInput(ForkRouteFixture memory fixture, uint256 minAmountOut)
        private
        pure
        returns (bytes memory)
    {
        bytes memory actions = new bytes(3);
        actions[0] = 0x06;
        actions[1] = 0x0c;
        actions[2] = 0x0f;
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            UniversalRouterAdapter.V4ExactInputSingleParams({
                poolKey: UniversalRouterAdapter.V4PoolKey({
                    currency0: fixture.currency0,
                    currency1: fixture.currency1,
                    fee: fixture.fee,
                    tickSpacing: fixture.tickSpacing,
                    hooks: fixture.hooks
                }),
                zeroForOne: fixture.currency0 == fixture.tokenIn,
                amountIn: uint128(fixture.amountIn),
                amountOutMinimum: uint128(minAmountOut),
                hookData: ""
            })
        );
        params[1] = abi.encode(fixture.tokenIn, fixture.amountIn);
        params[2] = abi.encode(fixture.tokenOut, minAmountOut);
        return abi.encode(actions, params);
    }

    function _selectPinnedBaseForkOrSkip() private {
        string memory rpc = vm.envOr("BASE_RPC", string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true);
        }

        uint256 pinnedBlock = FameRouterFixtureManifest.pinnedBaseBlock();
        assertGt(pinnedBlock, 0);
        vm.createSelectFork(rpc, pinnedBlock);
        assertEq(block.chainid, 8453);
        assertEq(block.number, pinnedBlock);
    }

    function _assertCode(address target) private view {
        assertGt(target.code.length, 0);
    }

    function _jsonArrayLength(string memory json, string memory key) private view returns (uint256 count) {
        while (vm.keyExistsJson(json, string.concat(key, "[", vm.toString(count), "]"))) {
            ++count;
        }
    }

    function _findFixtureKey(string memory json, string memory arrayKey, string memory id)
        private
        view
        returns (string memory)
    {
        uint256 count = _jsonArrayLength(json, arrayKey);
        for (uint256 i; i < count; ++i) {
            string memory key = string.concat(arrayKey, "[", vm.toString(i), "]");
            if (_stringEq(vm.parseJsonString(json, string.concat(key, ".id")), id)) {
                return key;
            }
        }
        revert("FIXTURE_ID_NOT_FOUND");
    }

    function _jsonUintString(string memory json, string memory key) private pure returns (uint256) {
        return vm.parseUint(vm.parseJsonString(json, key));
    }

    function _fundingType(string memory routeId) private view returns (string memory) {
        string memory routesJson = vm.readFile("test/router/fixtures/base-v1-routes.json");
        string memory routeKey = _findFixtureKey(routesJson, ".routes", routeId);
        return vm.parseJsonString(routesJson, string.concat(routeKey, ".funding.type"));
    }

    function _fundingRouteId(string memory routeId) private view returns (string memory) {
        string memory routesJson = vm.readFile("test/router/fixtures/base-v1-routes.json");
        string memory routeKey = _findFixtureKey(routesJson, ".routes", routeId);
        return vm.parseJsonString(routesJson, string.concat(routeKey, ".funding.routeId"));
    }

    function _assetBalance(address asset, address account) private view returns (uint256) {
        if (asset == FameRouterTypes.NATIVE_ETH) return account.balance;
        return IERC20Fork(asset).balanceOf(account);
    }

    function _hasKey(string memory json, string memory objectKey, string memory field) private view returns (bool) {
        return vm.keyExistsJson(json, string.concat(objectKey, ".", field));
    }

    function _stringEq(string memory a, string memory b) private pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }
}
