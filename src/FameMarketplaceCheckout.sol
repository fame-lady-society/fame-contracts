// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {CreatorArtistMagic} from "./CreatorArtistMagic.sol";
import {Fame} from "./Fame.sol";
import {FameMirror} from "./FameMirror.sol";
import {UniversalPoolArtMarketplace} from "./UniversalPoolArtMarketplace.sol";
import {FameRouterTypes} from "./router/FameRouterTypes.sol";

interface IFameCheckoutRouter {
    function executeRoute(FameRouterTypes.Route calldata route) external payable returns (uint256 netAmountOut);
}

contract FameMarketplaceCheckout is ReentrancyGuard {
    using SafeTransferLib for address;

    address public immutable router;
    UniversalPoolArtMarketplace public immutable market;
    Fame public immutable fame;
    address public immutable usdc;
    address public immutable weth;

    struct AssetSnapshot {
        address asset;
        uint256 baseline;
    }

    struct PurchaseRequest {
        uint256 shellId;
        uint256 sourceId;
        bytes32 expectedArtworkHash;
        uint256 maxPremium;
        uint256 minBuyerMirrorBalanceAfter;
        bool poolPurchase;
    }

    struct SettlementAccounting {
        uint256 routerFameOutput;
        uint256 marketplaceFameCharge;
        uint256 fameRefund;
        uint256 inputRefund;
    }

    event AssetRefunded(address indexed buyer, address indexed asset, uint256 amount);
    event CheckoutSettled(
        address indexed buyer,
        address indexed inputAsset,
        uint256 indexed shellId,
        bytes32 routeHash,
        UniversalPoolArtMarketplace.FulfillmentPath fulfillmentPath,
        uint256 inputAmount,
        uint256 inputRefund,
        uint256 routerFameOutput,
        uint256 marketplaceFameCharge,
        uint256 fameRefund
    );

    error InvalidDependency(address dependency);
    error InvalidAssetConfiguration();
    error StackMismatch();
    error CheckoutSkipNFTDisabled();
    error BadRouteVersion(uint16 version);
    error EmptyRoute();
    error TooManyRouteLegs(uint256 legCount);
    error ZeroInputAmount();
    error UnsupportedInputAsset(address asset);
    error WrongOutputAsset(address actual, address expected);
    error WrongRouteRecipient(address actual, address expected);
    error DeadlineExpired(uint256 deadline, uint256 timestamp);
    error ProtectedOutputTooLow(uint256 protectedOutput, uint256 requiredOutput);
    error NativeValueMismatch(uint256 expected, uint256 actual);
    error UnexpectedNativeValue(uint256 actual);
    error MarketPaused();
    error CheckoutNotAuthorized(address configuredCheckout);
    error CheckoutIsFeeRecipient();
    error PremiumExceedsMaximum(uint256 currentPremium, uint256 maximumPremium);
    error UnavailableShell(uint256 shellId);
    error ArtworkMismatch(uint256 tokenId, bytes32 expected, bytes32 actual);
    error SourceEqualsShell(uint256 tokenId);
    error IneligiblePoolSource(uint256 sourceId);
    error AmbiguousPoolSource(uint256 sourceId);
    error InputTransferMismatch(uint256 expected, uint256 actual);
    error RouterOutputMismatch(uint256 reported, uint256 measured);
    error MarketplaceChargeMismatch(uint256 expected, uint256 actual);
    error AmbientBalanceConsumed(address asset, uint256 baseline, uint256 current);
    error RefundBalanceMismatch(address asset, uint256 expected, uint256 actual);
    error FameAccountingMismatch(uint256 routerOutput, uint256 marketplaceCharge, uint256 fameRefund);
    error MirrorBalanceChanged(uint256 baseline, uint256 current);

    constructor(address router_, address market_, address payable fame_, address usdc_, address weth_) {
        _requireContract(router_);
        _requireContract(market_);
        _requireContract(fame_);
        _requireContract(usdc_);
        _requireContract(weth_);
        if (
            router_ == market_ || usdc_ == weth_ || usdc_ == fame_ || weth_ == fame_ || usdc_ == router_
                || weth_ == router_
        ) {
            revert InvalidAssetConfiguration();
        }

        UniversalPoolArtMarketplace marketContract = UniversalPoolArtMarketplace(market_);
        Fame fameContract = Fame(fame_);
        if (
            address(marketContract.fame()) != fame_
                || address(marketContract.mirror()) != address(fameContract.fameMirror())
        ) {
            revert StackMismatch();
        }

        router = router_;
        market = marketContract;
        fame = fameContract;
        usdc = usdc_;
        weth = weth_;

        fameContract.setSkipNFT(true);
        if (!fameContract.getSkipNFT(address(this))) revert CheckoutSkipNFTDisabled();
    }

    receive() external payable {}

    function checkoutHeld(
        FameRouterTypes.Route calldata route,
        uint256 shellId,
        bytes32 expectedArtworkHash,
        uint256 maxPremium,
        uint256 minBuyerMirrorBalanceAfter
    )
        external
        payable
        nonReentrant
        returns (uint256 routerFameOutput, uint256 marketplaceFameCharge, uint256 fameRefund, uint256 inputRefund)
    {
        SettlementAccounting memory accounting = _checkout(
            route,
            PurchaseRequest({
                shellId: shellId,
                sourceId: 0,
                expectedArtworkHash: expectedArtworkHash,
                maxPremium: maxPremium,
                minBuyerMirrorBalanceAfter: minBuyerMirrorBalanceAfter,
                poolPurchase: false
            })
        );
        return
            (
                accounting.routerFameOutput,
                accounting.marketplaceFameCharge,
                accounting.fameRefund,
                accounting.inputRefund
            );
    }

    function checkoutPool(
        FameRouterTypes.Route calldata route,
        uint256 shellId,
        uint256 sourceId,
        bytes32 expectedArtworkHash,
        uint256 maxPremium,
        uint256 minBuyerMirrorBalanceAfter
    )
        external
        payable
        nonReentrant
        returns (uint256 routerFameOutput, uint256 marketplaceFameCharge, uint256 fameRefund, uint256 inputRefund)
    {
        SettlementAccounting memory accounting = _checkout(
            route,
            PurchaseRequest({
                shellId: shellId,
                sourceId: sourceId,
                expectedArtworkHash: expectedArtworkHash,
                maxPremium: maxPremium,
                minBuyerMirrorBalanceAfter: minBuyerMirrorBalanceAfter,
                poolPurchase: true
            })
        );
        return
            (
                accounting.routerFameOutput,
                accounting.marketplaceFameCharge,
                accounting.fameRefund,
                accounting.inputRefund
            );
    }

    function _checkout(FameRouterTypes.Route calldata route, PurchaseRequest memory request)
        private
        returns (SettlementAccounting memory accounting)
    {
        address buyer = msg.sender;
        UniversalPoolArtMarketplace.FulfillmentPath fulfillmentPath = _validatePurchase(request);
        _validateRoute(route, request.maxPremium);

        (AssetSnapshot[] memory snapshots, uint256 snapshotCount) = _snapshotRouteAssets(route);
        uint256 mirrorBaseline = market.mirror().balanceOf(address(this));

        accounting.routerFameOutput = _executeRoute(route, snapshots, snapshotCount, buyer);
        accounting.marketplaceFameCharge = _settleMarketplace(request, buyer);
        uint256[] memory refundAmounts;
        (accounting.fameRefund, accounting.inputRefund, refundAmounts) =
            _refundRouteAssets(route, snapshots, snapshotCount, buyer);

        uint256 mirrorAfter = market.mirror().balanceOf(address(this));
        if (mirrorAfter != mirrorBaseline) revert MirrorBalanceChanged(mirrorBaseline, mirrorAfter);
        if (accounting.routerFameOutput != accounting.marketplaceFameCharge + accounting.fameRefund) {
            revert FameAccountingMismatch(
                accounting.routerFameOutput, accounting.marketplaceFameCharge, accounting.fameRefund
            );
        }

        _emitRefunds(buyer, snapshots, snapshotCount, refundAmounts);
        _emitSettlement(route, request, fulfillmentPath, buyer, accounting);
    }

    function _emitSettlement(
        FameRouterTypes.Route calldata route,
        PurchaseRequest memory request,
        UniversalPoolArtMarketplace.FulfillmentPath fulfillmentPath,
        address buyer,
        SettlementAccounting memory accounting
    ) private {
        emit CheckoutSettled(
            buyer,
            route.tokenIn,
            request.shellId,
            keccak256(abi.encode(route)),
            fulfillmentPath,
            route.amountIn,
            accounting.inputRefund,
            accounting.routerFameOutput,
            accounting.marketplaceFameCharge,
            accounting.fameRefund
        );
    }

    function _executeRoute(
        FameRouterTypes.Route calldata route,
        AssetSnapshot[] memory snapshots,
        uint256 snapshotCount,
        address buyer
    ) private returns (uint256 routerFameOutput) {
        _fundRoute(route, snapshots, snapshotCount, buyer);
        uint256 fameBeforeRouter = fame.balanceOf(address(this));
        if (route.tokenIn != FameRouterTypes.NATIVE_ETH) {
            route.tokenIn.safeApproveWithRetry(router, route.amountIn);
        }
        uint256 reportedFameOutput = IFameCheckoutRouter(router)
        .executeRoute{value: route.tokenIn == FameRouterTypes.NATIVE_ETH ? route.amountIn : 0}(
            route
        );
        if (route.tokenIn != FameRouterTypes.NATIVE_ETH) {
            route.tokenIn.safeApproveWithRetry(router, 0);
        }

        uint256 fameAfterRouter = fame.balanceOf(address(this));
        routerFameOutput = fameAfterRouter > fameBeforeRouter ? fameAfterRouter - fameBeforeRouter : 0;
        if (reportedFameOutput != routerFameOutput) {
            revert RouterOutputMismatch(reportedFameOutput, routerFameOutput);
        }
        _requireSkipNFT();
    }

    function _settleMarketplace(PurchaseRequest memory request, address buyer)
        private
        returns (uint256 marketplaceFameCharge)
    {
        marketplaceFameCharge = _currentMarketplaceCharge(buyer, request.maxPremium);
        uint256 fameBeforeMarket = fame.balanceOf(address(this));
        address(fame).safeApproveWithRetry(address(market), marketplaceFameCharge);
        if (request.poolPurchase) {
            market.purchasePoolFor(
                buyer,
                request.shellId,
                request.sourceId,
                request.expectedArtworkHash,
                request.maxPremium,
                request.minBuyerMirrorBalanceAfter
            );
        } else {
            market.purchaseHeldFor(
                buyer,
                request.shellId,
                request.expectedArtworkHash,
                request.maxPremium,
                request.minBuyerMirrorBalanceAfter
            );
        }
        address(fame).safeApproveWithRetry(address(market), 0);

        uint256 fameAfterMarket = fame.balanceOf(address(this));
        uint256 measuredMarketCharge = fameBeforeMarket > fameAfterMarket ? fameBeforeMarket - fameAfterMarket : 0;
        if (measuredMarketCharge != marketplaceFameCharge) {
            revert MarketplaceChargeMismatch(marketplaceFameCharge, measuredMarketCharge);
        }
        _requireSkipNFT();
    }

    function _refundRouteAssets(
        FameRouterTypes.Route calldata route,
        AssetSnapshot[] memory snapshots,
        uint256 snapshotCount,
        address buyer
    ) private returns (uint256 fameRefund, uint256 inputRefund, uint256[] memory refundAmounts) {
        refundAmounts = new uint256[](snapshotCount);
        for (uint256 i; i < snapshotCount; ++i) {
            AssetSnapshot memory snapshot = snapshots[i];
            uint256 current = _assetBalance(snapshot.asset);
            if (current < snapshot.baseline) {
                revert AmbientBalanceConsumed(snapshot.asset, snapshot.baseline, current);
            }
            uint256 refund = current - snapshot.baseline;
            refundAmounts[i] = refund;
            if (snapshot.asset == route.tokenIn) inputRefund = refund;
            if (snapshot.asset == address(fame)) fameRefund = refund;
            _transferAsset(snapshot.asset, buyer, refund);
        }

        for (uint256 i; i < snapshotCount; ++i) {
            uint256 current = _assetBalance(snapshots[i].asset);
            if (current != snapshots[i].baseline) {
                revert RefundBalanceMismatch(snapshots[i].asset, snapshots[i].baseline, current);
            }
        }
        return (fameRefund, inputRefund, refundAmounts);
    }

    function _emitRefunds(
        address buyer,
        AssetSnapshot[] memory snapshots,
        uint256 snapshotCount,
        uint256[] memory refundAmounts
    ) private {
        for (uint256 i; i < snapshotCount; ++i) {
            if (refundAmounts[i] != 0) {
                emit AssetRefunded(buyer, snapshots[i].asset, refundAmounts[i]);
            }
        }
    }

    function _validateRoute(FameRouterTypes.Route calldata route, uint256 maxPremium) private view {
        if (route.version != FameRouterTypes.SCHEMA_VERSION) revert BadRouteVersion(route.version);
        if (route.amountIn == 0) revert ZeroInputAmount();
        if (route.legs.length == 0) revert EmptyRoute();
        if (route.legs.length > FameRouterTypes.MAX_ROUTE_LEGS) revert TooManyRouteLegs(route.legs.length);
        if (route.tokenIn != FameRouterTypes.NATIVE_ETH && route.tokenIn != usdc && route.tokenIn != weth) {
            revert UnsupportedInputAsset(route.tokenIn);
        }
        if (route.tokenOut != address(fame)) revert WrongOutputAsset(route.tokenOut, address(fame));
        if (route.recipient != address(this)) revert WrongRouteRecipient(route.recipient, address(this));
        if (block.timestamp > route.deadline) revert DeadlineExpired(route.deadline, block.timestamp);

        uint256 requiredOutput = fame.unit() + maxPremium;
        if (route.minAmountOutAfterFee < requiredOutput) {
            revert ProtectedOutputTooLow(route.minAmountOutAfterFee, requiredOutput);
        }
        if (route.tokenIn == FameRouterTypes.NATIVE_ETH) {
            if (msg.value != route.amountIn) revert NativeValueMismatch(route.amountIn, msg.value);
        } else if (msg.value != 0) {
            revert UnexpectedNativeValue(msg.value);
        }
    }

    function _validatePurchase(PurchaseRequest memory request)
        private
        view
        returns (UniversalPoolArtMarketplace.FulfillmentPath path)
    {
        if (market.paused()) revert MarketPaused();
        address configuredCheckout = market.authorizedCheckout();
        if (configuredCheckout != address(this)) revert CheckoutNotAuthorized(configuredCheckout);
        if (market.feeRecipient() == address(this)) revert CheckoutIsFeeRecipient();
        uint256 currentPremium = market.premium();
        if (currentPremium > request.maxPremium) {
            revert PremiumExceedsMaximum(currentPremium, request.maxPremium);
        }

        FameMirror mirror = market.mirror();
        if (mirror.ownerAt(request.shellId) != address(market)) revert UnavailableShell(request.shellId);

        if (!request.poolPurchase) {
            _requireArtwork(request.shellId, request.expectedArtworkHash);
            return UniversalPoolArtMarketplace.FulfillmentPath.Held;
        }
        if (request.sourceId == request.shellId) revert SourceEqualsShell(request.sourceId);
        _requireArtwork(request.sourceId, request.expectedArtworkHash);

        CreatorArtistMagic creatorMagic = market.creatorMagic();
        if (request.sourceId >= creatorMagic.artPoolStartIndex() && request.sourceId <= creatorMagic.artPoolEndIndex())
        {
            revert IneligiblePoolSource(request.sourceId);
        }
        bool mintEligible = creatorMagic.isTokenInMintPool(request.sourceId);
        bool burnEligible = creatorMagic.isTokenInBurnedPool(request.sourceId);
        if (mintEligible && burnEligible) revert AmbiguousPoolSource(request.sourceId);
        if (mintEligible) return UniversalPoolArtMarketplace.FulfillmentPath.MintPool;
        if (burnEligible) return UniversalPoolArtMarketplace.FulfillmentPath.BurnPool;
        revert IneligiblePoolSource(request.sourceId);
    }

    function _requireArtwork(uint256 tokenId, bytes32 expectedArtworkHash) private view {
        bytes32 actualArtworkHash = market.artworkHash(tokenId);
        if (actualArtworkHash != expectedArtworkHash) {
            revert ArtworkMismatch(tokenId, expectedArtworkHash, actualArtworkHash);
        }
    }

    function _currentMarketplaceCharge(address buyer, uint256 maxPremium) private view returns (uint256 charge) {
        uint256 currentPremium = market.premium();
        if (currentPremium > maxPremium) revert PremiumExceedsMaximum(currentPremium, maxPremium);
        address currentFeeRecipient = market.feeRecipient();
        if (currentFeeRecipient == address(this)) revert CheckoutIsFeeRecipient();
        charge = fame.unit();
        if (buyer != currentFeeRecipient) charge += currentPremium;
    }

    function _snapshotRouteAssets(FameRouterTypes.Route calldata route)
        private
        view
        returns (AssetSnapshot[] memory snapshots, uint256 count)
    {
        snapshots = new AssetSnapshot[](2 + route.legs.length * 2);
        uint256 nativeInput = route.tokenIn == FameRouterTypes.NATIVE_ETH ? route.amountIn : 0;
        count = _addSnapshot(snapshots, count, route.tokenIn, nativeInput);
        count = _addSnapshot(snapshots, count, route.tokenOut, nativeInput);
        for (uint256 i; i < route.legs.length; ++i) {
            count = _addSnapshot(snapshots, count, route.legs[i].tokenIn, nativeInput);
            count = _addSnapshot(snapshots, count, route.legs[i].tokenOut, nativeInput);
        }
    }

    function _addSnapshot(AssetSnapshot[] memory snapshots, uint256 count, address asset, uint256 nativeInput)
        private
        view
        returns (uint256)
    {
        for (uint256 i; i < count; ++i) {
            if (snapshots[i].asset == asset) return count;
        }
        uint256 baseline = _assetBalance(asset);
        if (asset == FameRouterTypes.NATIVE_ETH) baseline -= nativeInput;
        snapshots[count] = AssetSnapshot({asset: asset, baseline: baseline});
        return count + 1;
    }

    function _fundRoute(
        FameRouterTypes.Route calldata route,
        AssetSnapshot[] memory snapshots,
        uint256 snapshotCount,
        address buyer
    ) private {
        if (route.tokenIn == FameRouterTypes.NATIVE_ETH) return;
        uint256 beforeBalance = _snapshotBaseline(snapshots, snapshotCount, route.tokenIn);
        route.tokenIn.safeTransferFrom(buyer, address(this), route.amountIn);
        uint256 afterBalance = _assetBalance(route.tokenIn);
        uint256 received = afterBalance > beforeBalance ? afterBalance - beforeBalance : 0;
        if (received != route.amountIn) revert InputTransferMismatch(route.amountIn, received);
    }

    function _snapshotBaseline(AssetSnapshot[] memory snapshots, uint256 snapshotCount, address asset)
        private
        pure
        returns (uint256)
    {
        for (uint256 i; i < snapshotCount; ++i) {
            if (snapshots[i].asset == asset) return snapshots[i].baseline;
        }
        revert InvalidDependency(asset);
    }

    function _requireSkipNFT() private view {
        if (!fame.getSkipNFT(address(this))) revert CheckoutSkipNFTDisabled();
    }

    function _assetBalance(address asset) private view returns (uint256 balance) {
        if (asset == FameRouterTypes.NATIVE_ETH) return address(this).balance;
        (bool success, bytes memory data) = asset.staticcall(abi.encodeWithSelector(0x70a08231, address(this)));
        if (!success || data.length != 32) revert InvalidDependency(asset);
        balance = abi.decode(data, (uint256));
    }

    function _transferAsset(address asset, address to, uint256 amount) private {
        if (amount == 0) return;
        if (asset == FameRouterTypes.NATIVE_ETH) {
            SafeTransferLib.safeTransferETH(to, amount);
        } else {
            asset.safeTransfer(to, amount);
        }
    }

    function _requireContract(address dependency) private view {
        if (dependency == address(0) || dependency.code.length == 0) revert InvalidDependency(dependency);
    }
}
