// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Vm} from "forge-std/Vm.sol";
import {ActivateBaseUniversalPoolArtMarketplace} from "../script/ActivateBaseUniversalPoolArtMarketplace.s.sol";
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

    enum OutputKind {
        Eth,
        Usdc,
        Weth
    }

    struct RedemptionContext {
        FameMarketplaceCheckout checkout;
        uint256[] selectedIds;
        uint256 donatedId;
        uint256 fundingCount;
    }

    struct ProviderBenchmarkContext {
        uint256 candidateCap;
        uint256 gasBudget;
        uint256 communityFee;
        uint256 payoutPerProvider;
        uint256 providerDust;
        uint256 configuredProviderFee;
        uint256 safeProviderCapacity;
        uint256 inventoryBefore;
        uint256 communityBefore;
        uint256 gasUsed;
        address[] providers;
        uint256[] providerBalancesBefore;
    }

    struct ReleaseLifecycleContext {
        UniversalPoolArtMarketplace market;
        FameMarketplaceCheckout checkout;
        ValidateBaseUniversalPoolArtMarketplace validator;
        uint256 communityFee;
        uint256 providerFee;
        uint256 activeProviderCap;
        uint256 minimumInventory;
    }

    struct ReleaseCheckoutContext {
        uint256 unit;
        bytes32 artwork;
        FameRouterTypes.Route route;
        uint256 providerBalanceBefore;
        uint256 communityBefore;
        uint256 buyerMirrorBalanceBefore;
        uint256 routerOutput;
        uint256 marketCharge;
        uint256 fameRefund;
        uint256 inputRefund;
        Vm.Log[] logs;
    }

    address internal constant EXPECTED_ROUTER = 0xAdefa5860389E8936ebf2977e1Fb4a365aA39636;
    address internal constant EXPECTED_USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address internal constant EXPECTED_WETH = 0x4200000000000000000000000000000000000006;
    address internal constant SOLIDLY_ROUTER = 0x2F87Bf58D5A9b2eFadE55Cdbd46153a0902be6FA;
    address internal constant AERODROME_V2_ROUTER = 0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43;
    address internal constant AERODROME_V2_FACTORY = 0x420DD381b31aEf6683db6B902084cB0FFECe40Da;
    address internal constant BENCHMARK_OVERFLOW_FUNDING_SOURCE = 0x58d1a0DD3F3F7962C61433a320A09183e3BDb592;
    address internal constant BATCH_PROVIDER = address(0xB0A8);
    bytes32 internal constant ROUTE_EXECUTED_TOPIC =
        keccak256("RouteExecuted(address,address,address,bytes32,uint16,address,uint256,uint256,uint256,uint256)");
    bytes32 internal constant CHECKOUT_SETTLED_TOPIC =
        keccak256("CheckoutSettled(address,address,uint256,bytes32,uint8,uint256,uint256,uint256,uint256,uint256)");
    bytes32 internal constant SOCIETY_REDEEMED_TOPIC =
        keccak256("SocietyRedeemed(address,address,bytes32,uint256,uint256,uint256,bytes32,uint256)");

    FameRouter internal router;
    IERC20CheckoutFork internal usdc;
    IWETHCheckoutFork internal weth;

    error NoSufficientUpperWitness(InputKind kind, uint256 lastAmountIn, uint256 lastAmountOut);

    function testLatestBaseReleaseLifecycleDeploysValidatesActivatesAndChecksOutFromDeployer() public {
        _selectLatestBaseFork();
        router = FameRouter(payable(vm.envAddress("BASE_FAME_ROUTER_ADDRESS")));
        usdc = IERC20CheckoutFork(vm.envAddress("BASE_USDC_ADDRESS"));
        weth = IWETHCheckoutFork(vm.envAddress("BASE_WETH_ADDRESS"));

        ReleaseLifecycleContext memory context;
        context.communityFee = vm.envUint("BASE_UNIVERSAL_MARKETPLACE_COMMUNITY_FEE");
        context.providerFee = vm.envUint("BASE_UNIVERSAL_MARKETPLACE_PROVIDER_FEE");
        context.activeProviderCap = vm.envUint("BASE_UNIVERSAL_MARKETPLACE_ACTIVE_PROVIDER_CAP");
        context.minimumInventory = vm.envUint("BASE_UNIVERSAL_MARKETPLACE_INVENTORY");
        assertEq(context.minimumInventory, 0, "release configuration must allow an empty launch");
        DeployBaseUniversalPoolArtMarketplace deployment = new DeployBaseUniversalPoolArtMarketplace();
        (context.market, context.checkout) = deployment.deployMarketplaceStack(
            fame,
            creatorMagic,
            DeployBaseUniversalPoolArtMarketplace.DeploymentConfig({
                router: address(router),
                usdc: address(usdc),
                weth: address(weth),
                communityFee: context.communityFee,
                providerFee: context.providerFee,
                feeRecipient: SAFE,
                owner: DEPLOYER,
                activeProviderCap: context.activeProviderCap,
                sender: DEPLOYER
            })
        );

        vm.prank(DEPLOYER);
        creatorMagic.grantRoles(address(context.market), BANISHER_ROLE);
        _assertEmptyReleaseState(context.market);

        context.validator = new ValidateBaseUniversalPoolArtMarketplace();
        _validateConfiguredReleaseStack(context, DEPLOYER, true);

        new ActivateBaseUniversalPoolArtMarketplace().activateMarketplace(context.market, context.checkout, DEPLOYER);
        _assertEmptyReleaseState(context.market);
        _validateConfiguredReleaseStack(context, DEPLOYER, false);

        FameRouterTypes.Route memory emptyRoute;
        uint256 emptyMarketPremium = context.market.premium();
        vm.expectRevert(abi.encodeWithSelector(FameMarketplaceCheckout.UnavailableShell.selector, uint256(1)));
        vm.prank(BUYER_ONE);
        context.checkout.checkoutHeld(emptyRoute, 1, bytes32(0), emptyMarketPremium, 0);

        uint256 unit = fame.unit();
        uint256 batchSize = context.market.MAX_INVENTORY_BATCH_SIZE();
        vm.prank(SAFE);
        fame.transfer(BATCH_PROVIDER, batchSize * unit);
        uint256[] memory tokenIds = _ownedTokenIds(BATCH_PROVIDER, batchSize);
        vm.startPrank(BATCH_PROVIDER);
        mirror.setApprovalForAll(address(context.market), true);
        context.market.depositInventoryBatch(tokenIds);
        vm.stopPrank();

        (uint256 providerUnits, uint256 indexPlusOne) = context.market.providerPosition(BATCH_PROVIDER);
        assertEq(providerUnits, batchSize, "batch provider units mismatch");
        assertEq(indexPlusOne, 1, "batch provider index mismatch");
        assertEq(context.market.activeProviderCount(), 1, "batch should consume one provider slot");
        assertEq(context.market.totalProviderUnits(), batchSize, "batch total units mismatch");
        _validateConfiguredReleaseStack(context, DEPLOYER, false);

        _executeAndAssertFirstPostLaunchCheckout(context, tokenIds[0], batchSize);
    }

    function _executeAndAssertFirstPostLaunchCheckout(
        ReleaseLifecycleContext memory context,
        uint256 shellId,
        uint256 batchSize
    ) internal {
        ReleaseCheckoutContext memory checkoutContext;
        checkoutContext.unit = fame.unit();
        checkoutContext.artwork = context.market.artworkHash(shellId);
        uint256 premium = context.market.premium();
        (checkoutContext.route,) =
            _findSufficientRoute(InputKind.Eth, 0.5 ether, context.checkout, checkoutContext.unit + premium);
        _fundAndApproveInput(BUYER_ONE, checkoutContext.route, address(context.checkout));
        checkoutContext.providerBalanceBefore = fame.balanceOf(BATCH_PROVIDER);
        checkoutContext.communityBefore = fame.balanceOf(SAFE);
        checkoutContext.buyerMirrorBalanceBefore = mirror.balanceOf(BUYER_ONE);
        vm.recordLogs();
        vm.prank(BUYER_ONE);
        (
            checkoutContext.routerOutput,
            checkoutContext.marketCharge,
            checkoutContext.fameRefund,
            checkoutContext.inputRefund
        ) =
            context.checkout.checkoutHeld{value: checkoutContext.route.amountIn}(
                checkoutContext.route,
                shellId,
                checkoutContext.artwork,
                premium,
                checkoutContext.buyerMirrorBalanceBefore + 1
            );
        checkoutContext.logs = vm.getRecordedLogs();

        assertEq(checkoutContext.marketCharge, checkoutContext.unit + premium, "market charge mismatch");
        assertEq(
            checkoutContext.routerOutput,
            checkoutContext.marketCharge + checkoutContext.fameRefund,
            "FAME reconciliation mismatch"
        );
        assertEq(checkoutContext.inputRefund, 0, "all-input route returned input residue");
        assertEq(
            fame.balanceOf(BATCH_PROVIDER) - checkoutContext.providerBalanceBefore,
            context.providerFee,
            "configured provider fee routing mismatch"
        );
        assertEq(
            fame.balanceOf(SAFE) - checkoutContext.communityBefore,
            context.communityFee + _routeFeeFromLogs(checkoutContext.logs, address(router)),
            "configured community fee routing mismatch"
        );
        assertEq(context.market.inventory(), batchSize, "checkout changed provider-backed inventory");
        assertEq(context.market.totalProviderUnits(), batchSize, "checkout changed provider units");
        assertEq(context.market.activeProviderCount(), 1, "checkout changed provider count");
        assertEq(mirror.ownerAt(shellId), BUYER_ONE, "post-launch shell recipient mismatch");
        assertEq(fame.balanceOf(address(context.checkout)), 0, "checkout retained FAME");
        assertEq(address(context.checkout).balance, 0, "checkout retained ETH");
        assertEq(usdc.balanceOf(address(context.checkout)), 0, "checkout retained USDC");
        assertEq(weth.balanceOf(address(context.checkout)), 0, "checkout retained WETH");
        assertEq(fame.allowance(address(context.checkout), address(context.market)), 0, "market allowance");
        assertEq(
            _purchaseEventCount(checkoutContext.logs, address(context.market)), 1, "ArtworkPurchased event mismatch"
        );
        assertEq(
            _eventCount(checkoutContext.logs, address(router), ROUTE_EXECUTED_TOPIC), 1, "RouteExecuted event mismatch"
        );
        assertEq(
            _eventCount(checkoutContext.logs, address(context.checkout), CHECKOUT_SETTLED_TOPIC),
            1,
            "CheckoutSettled event mismatch"
        );
    }

    function _assertEmptyReleaseState(UniversalPoolArtMarketplace market) internal view {
        assertEq(market.inventory(), 0, "empty release inventory mismatch");
        assertEq(market.activeProviderCount(), 0, "empty release provider count mismatch");
        assertEq(market.totalProviderUnits(), 0, "empty release provider units mismatch");
    }

    function _validateConfiguredReleaseStack(ReleaseLifecycleContext memory context, address owner, bool paused)
        internal
        view
    {
        context.validator
            .validateMarketplaceStack(
                fame,
                mirror,
                creatorMagic,
                context.market,
                context.checkout,
                EXPECTED_CHILD_RENDERER,
                ValidateBaseUniversalPoolArtMarketplace.MarketplaceExpectations({
                    owner: owner,
                    creatorMagicOwner: DEPLOYER,
                    feeRecipient: SAFE,
                    communityFee: context.communityFee,
                    providerFee: context.providerFee,
                    activeProviderCap: context.activeProviderCap,
                    minimumInventory: context.minimumInventory,
                    paused: paused
                }),
                ValidateBaseUniversalPoolArtMarketplace.CheckoutExpectations({
                        router: address(router),
                        usdc: address(usdc),
                        weth: address(weth),
                        routerFeeRecipient: vm.envAddress("BASE_FAME_ROUTER_FEE_RECIPIENT"),
                        routerFeePpm: vm.envUint("BASE_FAME_ROUTER_FEE_PPM")
                    })
            );
    }

    function testBenchmarkLatestBaseCandidateCapCheckoutMintsForEveryProviderPayout() public {
        _selectLatestBaseFork();
        router = FameRouter(payable(vm.envAddress("BASE_FAME_ROUTER_ADDRESS")));
        usdc = IERC20CheckoutFork(vm.envAddress("BASE_USDC_ADDRESS"));
        weth = IWETHCheckoutFork(vm.envAddress("BASE_WETH_ADDRESS"));
        ProviderBenchmarkContext memory context;
        context.candidateCap = vm.envUint("BASE_UNIVERSAL_MARKETPLACE_BENCHMARK_CANDIDATE_CAP");
        context.gasBudget = vm.envUint("BASE_UNIVERSAL_MARKETPLACE_CHECKOUT_GAS_BUDGET");
        context.communityFee = vm.envUint("BASE_UNIVERSAL_MARKETPLACE_COMMUNITY_FEE");
        context.payoutPerProvider = 1 ether;
        assertGt(context.candidateCap, 1, "benchmark candidate must exercise payout dust");
        context.providerDust = context.candidateCap - 1;
        context.configuredProviderFee = context.candidateCap * context.payoutPerProvider + context.providerDust;
        uint256 unit = fame.unit();
        context.safeProviderCapacity =
            _benchmarkSafeProviderCapacity(unit, context.payoutPerProvider, context.candidateCap);

        UniversalPoolArtMarketplace market;
        vm.prank(DEPLOYER, DEPLOYER);
        market = new UniversalPoolArtMarketplace(
            payable(address(fame)),
            address(creatorMagic),
            context.communityFee,
            context.configuredProviderFee,
            SAFE,
            DEPLOYER,
            context.candidateCap
        );
        FameMarketplaceCheckout checkout = new FameMarketplaceCheckout(
            address(router), address(market), payable(address(fame)), address(usdc), address(weth)
        );
        vm.prank(DEPLOYER);
        market.setAuthorizedCheckout(address(checkout));

        context.providers = new address[](context.candidateCap);
        context.providerBalancesBefore = new uint256[](context.candidateCap);
        for (uint256 i; i < context.candidateCap; ++i) {
            address provider = address(uint160(0xD000 + i));
            address fundingSource = i < context.safeProviderCapacity ? SAFE : BENCHMARK_OVERFLOW_FUNDING_SOURCE;
            context.providers[i] = provider;
            vm.prank(fundingSource);
            fame.transfer(provider, unit);
            uint256 tokenId = _ownedTokenAt(provider, 0);
            vm.startPrank(provider);
            mirror.approve(address(market), tokenId);
            market.depositInventory(tokenId);
            vm.stopPrank();
            vm.prank(fundingSource);
            fame.transfer(provider, unit - context.payoutPerProvider);
            context.providerBalancesBefore[i] = fame.balanceOf(provider);
            assertEq(mirror.balanceOf(provider), 0, "provider minted before benchmark payout");
        }

        uint256 shellId = _ownedTokenAt(address(market), 0);
        bytes32 artwork = market.artworkHash(shellId);
        uint256 maximumPremium = market.premium();
        (FameRouterTypes.Route memory route,) =
            _findSufficientRoute(InputKind.Eth, 0.5 ether, checkout, fame.unit() + maximumPremium);
        _fundAndApproveInput(BUYER_ONE, route, address(checkout));
        vm.prank(DEPLOYER);
        market.unpause();

        context.inventoryBefore = market.inventory();
        context.communityBefore = fame.balanceOf(SAFE);
        vm.recordLogs();
        uint256 gasBefore = gasleft();
        vm.prank(BUYER_ONE);
        checkout.checkoutHeld{value: route.amountIn}(route, shellId, artwork, maximumPremium, 0);
        context.gasUsed = gasBefore - gasleft();

        _assertBenchmarkProviderPayouts(
            market, context.providers, context.providerBalancesBefore, context.payoutPerProvider
        );
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 routerFee = _routeFeeFromLogs(logs, address(router));
        assertEq(
            fame.balanceOf(SAFE) - context.communityBefore,
            routerFee + context.communityFee + context.providerDust,
            "community allocation or provider dust mismatch"
        );
        assertTrue(_hasTopicFrom(logs, address(router), ROUTE_EXECUTED_TOPIC), "router settlement event missing");
        assertTrue(_hasTopicFrom(logs, address(market), ARTWORK_PURCHASED_TOPIC), "market settlement event missing");
        assertTrue(_hasTopicFrom(logs, address(checkout), CHECKOUT_SETTLED_TOPIC), "checkout settlement event missing");
        emit log_named_uint("candidate active-provider cap", context.candidateCap);
        emit log_named_uint("all-provider-auto-mint checkout gas", context.gasUsed);
        emit log_named_uint("Base block gas limit", block.gaslimit);
        assertEq(market.inventory(), context.inventoryBefore, "benchmark checkout changed inventory count");
        assertEq(fame.balanceOf(address(checkout)), 0, "benchmark checkout retained FAME");
        assertEq(fame.allowance(address(checkout), address(market)), 0, "benchmark checkout retained allowance");
        assertLt(context.gasUsed, context.gasBudget, "candidate-cap checkout exceeds configured gas budget");
        assertLt(context.gasUsed, (block.gaslimit * 8) / 10, "candidate-cap checkout lacks Base gas headroom");
    }

    function _benchmarkSafeProviderCapacity(uint256 unit, uint256 payoutPerProvider, uint256 candidateCap)
        internal
        view
        returns (uint256 safeProviderCapacity)
    {
        uint256 providerFunding = 2 * unit - payoutPerProvider;
        safeProviderCapacity = fame.balanceOf(SAFE) / providerFunding;
        uint256 overflowProviderCapacity = fame.balanceOf(BENCHMARK_OVERFLOW_FUNDING_SOURCE) / providerFunding;
        assertTrue(fame.getSkipNFT(BENCHMARK_OVERFLOW_FUNDING_SOURCE), "overflow funding source must skip NFTs");
        assertGe(
            safeProviderCapacity + overflowProviderCapacity,
            candidateCap,
            "live FAME sources cannot fund candidate provider count"
        );
    }

    function _hasTopicFrom(Vm.Log[] memory logs, address emitter, bytes32 topic) internal pure returns (bool) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == emitter && logs[i].topics[0] == topic) return true;
        }
        return false;
    }

    function _routeFeeFromLogs(Vm.Log[] memory logs, address emitter) internal pure returns (uint256 feeAmount) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == emitter && logs[i].topics[0] == ROUTE_EXECUTED_TOPIC) {
                (,,,,, feeAmount,) =
                    abi.decode(logs[i].data, (bytes32, uint16, address, uint256, uint256, uint256, uint256));
                return feeAmount;
            }
        }
        revert("router settlement event missing");
    }

    function _assertBenchmarkProviderPayouts(
        UniversalPoolArtMarketplace market,
        address[] memory providers,
        uint256[] memory providerBalancesBefore,
        uint256 payoutPerProvider
    ) internal view {
        for (uint256 i; i < providers.length; ++i) {
            assertEq(mirror.balanceOf(providers[i]), 1, "provider payout did not trigger exactly one DN404 mint");
            assertEq(
                fame.balanceOf(providers[i]) - providerBalancesBefore[i],
                payoutPerProvider,
                "provider received wrong weighted payout"
            );
            (uint256 units,) = market.providerPosition(providers[i]);
            assertEq(units, 1, "checkout changed provider position");
        }
    }

    function testLatestBaseRedeemsOneSocietyForEth() public {
        _assertLatestBaseRedemption(OutputKind.Eth, 1, false);
    }

    function testLatestBaseRedeemsOneSocietyForWeth() public {
        _assertLatestBaseRedemption(OutputKind.Weth, 1, false);
    }

    function testLatestBaseRedeemsOneSocietyForUsdc() public {
        _assertLatestBaseRedemption(OutputKind.Usdc, 1, false);
    }

    function testLatestBaseRedeemsMultipleSocietyAndDirectDonationBonus() public {
        _assertLatestBaseRedemption(OutputKind.Usdc, 3, true);
    }

    function testLatestBaseRedeemsThirtyTwoSocietyWithinGasLimit() public {
        uint256 gasUsed = _assertLatestBaseRedemption(OutputKind.Weth, 32, false);
        emit log_named_uint("32-ID redemption gas", gasUsed);
        emit log_named_uint("Base block gas limit", block.gaslimit);
        assertLt(gasUsed, (block.gaslimit * 8) / 10, "32-ID redemption lacks Base gas headroom");
    }

    function testLatestBaseRedemptionOverFloorRestoresSelectedNft() public {
        RedemptionContext memory context = _prepareLatestBaseRedemption(1, false);
        FameRouterTypes.Route memory route = _buildRedemptionRoute(OutputKind.Weth, fame.unit(), BUYER_ONE);
        uint256 quotedOutput;
        (route, quotedOutput) = _protectRedemptionRoute(context, OutputKind.Weth, route);
        route.minAmountOutAfterFee = quotedOutput + 1;

        vm.expectRevert(abi.encodeWithSelector(FameRouter.FinalOutputTooLow.selector, quotedOutput, quotedOutput + 1));
        vm.prank(BUYER_ONE);
        context.checkout.redeemSociety(route, context.selectedIds);

        assertEq(mirror.ownerAt(context.selectedIds[0]), BUYER_ONE, "failed redemption did not restore selected NFT");
        assertEq(fame.balanceOf(address(context.checkout)), 0, "failed redemption retained FAME");
        assertEq(mirror.balanceOf(address(context.checkout)), 0, "failed redemption retained Society NFT");
        assertEq(fame.allowance(address(context.checkout), address(router)), 0, "failed redemption retained allowance");
    }

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
        market.setCommunityFee(quotedPremium + 1);

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
            DeployBaseUniversalPoolArtMarketplace.DeploymentConfig({
                router: address(router),
                usdc: address(usdc),
                weth: address(weth),
                communityFee: EXPECTED_PREMIUM,
                providerFee: 0,
                feeRecipient: SAFE,
                owner: DEPLOYER,
                activeProviderCap: 16,
                sender: DEPLOYER
            })
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
                owner: DEPLOYER,
                creatorMagicOwner: DEPLOYER,
                feeRecipient: SAFE,
                communityFee: EXPECTED_PREMIUM,
                providerFee: 0,
                activeProviderCap: 16,
                minimumInventory: 1,
                paused: true
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

    function _assertLatestBaseRedemption(OutputKind kind, uint256 tokenCount, bool donateBonus)
        private
        returns (uint256 gasUsed)
    {
        RedemptionContext memory context = _prepareLatestBaseRedemption(tokenCount, donateBonus);
        uint256 quotedInput = tokenCount * fame.unit();
        FameRouterTypes.Route memory route = _buildRedemptionRoute(kind, quotedInput, BUYER_ONE);
        (route,) = _protectRedemptionRoute(context, kind, route);
        uint256 outputBefore = _redemptionOutputBalance(kind, BUYER_ONE);
        vm.recordLogs();
        uint256 gasBefore = gasleft();
        vm.prank(BUYER_ONE);
        (uint256 actualInput, uint256 netOutput) = context.checkout.redeemSociety(route, context.selectedIds);
        gasUsed = gasBefore - gasleft();
        _assertLatestBaseRedemptionSettlement(context, kind, outputBefore, actualInput, netOutput, vm.getRecordedLogs());
    }

    function _protectRedemptionRoute(
        RedemptionContext memory context,
        OutputKind kind,
        FameRouterTypes.Route memory route
    ) private returns (FameRouterTypes.Route memory protectedRoute, uint256 quotedOutput) {
        uint256 snapshot = vm.snapshot();
        vm.prank(BUYER_ONE);
        (, quotedOutput) = context.checkout.redeemSociety(route, context.selectedIds);
        assertTrue(vm.revertToAndDelete(snapshot), "redemption quote state restore failed");

        uint256 protectedOutput = (quotedOutput * 99) / 100;
        if (protectedOutput == 0) protectedOutput = 1;
        route.minAmountOutAfterFee = protectedOutput;
        uint256 protectedLegIndex = kind == OutputKind.Eth ? 0 : route.legs.length - 1;
        route.legs[protectedLegIndex].minAmountOut = protectedOutput;
        return (route, quotedOutput);
    }

    function _prepareLatestBaseRedemption(uint256 tokenCount, bool donateBonus)
        private
        returns (RedemptionContext memory context)
    {
        (, context.checkout) = _deployCheckoutStack();
        context.fundingCount = tokenCount + (donateBonus ? 1 : 0);
        uint256[] memory fundedIds = _fundSocietyTokens(BUYER_ONE, context.fundingCount, context.checkout);
        assertEq(context.checkout.ownedSocietyTokenIds(BUYER_ONE, 1, 889), fundedIds, "full owner projection mismatch");

        context.selectedIds = new uint256[](tokenCount);
        for (uint256 i; i < tokenCount; ++i) {
            context.selectedIds[i] = fundedIds[i];
        }

        if (donateBonus) {
            context.donatedId = fundedIds[context.fundingCount - 1];
            vm.prank(BUYER_ONE);
            mirror.transferFrom(BUYER_ONE, address(context.checkout), context.donatedId);
            assertEq(
                fame.balanceOf(address(context.checkout)), fame.unit(), "direct donation did not become bonus FAME"
            );
        }

        vm.prank(BUYER_ONE);
        mirror.setApprovalForAll(address(context.checkout), true);
    }

    function _assertLatestBaseRedemptionSettlement(
        RedemptionContext memory context,
        OutputKind kind,
        uint256 outputBefore,
        uint256 actualInput,
        uint256 netOutput,
        Vm.Log[] memory logs
    ) private view {
        assertEq(actualInput, context.fundingCount * fame.unit(), "redemption did not consume complete FAME inventory");
        assertGt(netOutput, 0, "redemption output missing");
        assertEq(_redemptionOutputBalance(kind, BUYER_ONE) - outputBefore, netOutput, "recipient output mismatch");
        assertEq(fame.balanceOf(address(context.checkout)), 0, "checkout retained redemption FAME");
        assertEq(mirror.balanceOf(address(context.checkout)), 0, "checkout retained Society NFTs");
        assertEq(fame.allowance(address(context.checkout), address(router)), 0, "router FAME allowance not cleared");
        assertEq(context.checkout.ownedSocietyTokenIds(BUYER_ONE, 1, 889).length, 0, "redeemed IDs remained owned");
        for (uint256 i; i < context.selectedIds.length; ++i) {
            assertEq(mirror.ownerAt(context.selectedIds[i]), address(0));
        }
        if (context.donatedId != 0) assertEq(mirror.ownerAt(context.donatedId), address(0));
        assertEq(_eventCount(logs, address(router), ROUTE_EXECUTED_TOPIC), 1, "RouteExecuted event mismatch");
        assertEq(
            _eventCount(logs, address(context.checkout), SOCIETY_REDEEMED_TOPIC), 1, "SocietyRedeemed event mismatch"
        );
    }

    function _fundSocietyTokens(address account, uint256 tokenCount, FameMarketplaceCheckout checkout)
        private
        returns (uint256[] memory tokenIds)
    {
        assertFalse(fame.getSkipNFT(account), "redemption fixture account unexpectedly skips NFTs");
        tokenIds = new uint256[](tokenCount);
        uint256 found;
        for (uint256 tokenId = 1; tokenId <= 888 && found < tokenCount; ++tokenId) {
            address owner = mirror.ownerAt(tokenId);
            if (owner == address(0) || owner == account || owner == address(checkout.market())) continue;
            vm.prank(owner);
            mirror.transferFrom(owner, account, tokenId);
            tokenIds[found++] = tokenId;
        }
        assertEq(found, tokenCount, "redemption fixture did not find enough transferable Society NFTs");
    }

    function _buildRedemptionRoute(OutputKind kind, uint256 amountIn, address recipient)
        private
        view
        returns (FameRouterTypes.Route memory route)
    {
        route.version = FameRouterTypes.SCHEMA_VERSION;
        route.tokenIn = address(fame);
        route.tokenOut = kind == OutputKind.Eth
            ? FameRouterTypes.NATIVE_ETH
            : kind == OutputKind.Usdc ? address(usdc) : address(weth);
        route.amountIn = amountIn;
        route.minAmountOutAfterFee = 1;
        route.recipient = recipient;
        route.deadline = block.timestamp + 20 minutes;

        if (kind == OutputKind.Weth) {
            route.legs = new FameRouterTypes.Leg[](1);
            route.legs[0] = _solidlyFameToWethLeg();
            return route;
        }

        route.legs = new FameRouterTypes.Leg[](2);
        route.legs[0] = _solidlyFameToWethLeg();
        route.legs[1] = kind == OutputKind.Eth ? _nativeWethToEthLeg() : _aerodromeWethToUsdcLeg();
    }

    function _redemptionOutputBalance(OutputKind kind, address account) private view returns (uint256) {
        if (kind == OutputKind.Eth) return account.balance;
        if (kind == OutputKind.Usdc) return usdc.balanceOf(account);
        return weth.balanceOf(account);
    }

    function _solidlyFameToWethLeg() private view returns (FameRouterTypes.Leg memory leg) {
        ISolidlyRouter.Route[] memory routes = new ISolidlyRouter.Route[](1);
        routes[0] = ISolidlyRouter.Route({from: address(fame), to: address(weth), stable: false});
        leg = FameRouterTypes.Leg({
            tokenIn: address(fame),
            tokenOut: address(weth),
            venue: FameRouterTypes.VenueFamily.Solidly,
            amountMode: FameRouterTypes.AmountMode.All,
            amount: 0,
            minAmountOut: 1,
            target: SOLIDLY_ROUTER,
            data: abi.encode(SolidlyRouterAdapter.Payload({routes: routes, deadline: block.timestamp + 20 minutes}))
        });
    }

    function _aerodromeWethToUsdcLeg() private view returns (FameRouterTypes.Leg memory leg) {
        IAerodromeV2Router.AerodromeRoute[] memory routes = new IAerodromeV2Router.AerodromeRoute[](1);
        routes[0] = IAerodromeV2Router.AerodromeRoute({
            from: address(weth), to: address(usdc), stable: false, factory: AERODROME_V2_FACTORY
        });
        leg = FameRouterTypes.Leg({
            tokenIn: address(weth),
            tokenOut: address(usdc),
            venue: FameRouterTypes.VenueFamily.AerodromeV2,
            amountMode: FameRouterTypes.AmountMode.All,
            amount: 0,
            minAmountOut: 1,
            target: AERODROME_V2_ROUTER,
            data: abi.encode(AerodromeV2RouterAdapter.Payload({routes: routes, deadline: block.timestamp + 20 minutes}))
        });
    }

    function _nativeWethToEthLeg() private view returns (FameRouterTypes.Leg memory leg) {
        leg = FameRouterTypes.Leg({
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
