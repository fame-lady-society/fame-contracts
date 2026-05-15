// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "solady/auth/Ownable.sol";
import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {FameRouterAccounting} from "./router/FameRouterAccounting.sol";
import {FameRouterTypes} from "./router/FameRouterTypes.sol";
import {AerodromeV2RouterAdapter} from "./router/adapters/AerodromeV2RouterAdapter.sol";
import {SolidlyRouterAdapter} from "./router/adapters/SolidlyRouterAdapter.sol";
import {SlipstreamAdapter} from "./router/adapters/SlipstreamAdapter.sol";
import {UniversalRouterAdapter} from "./router/adapters/UniversalRouterAdapter.sol";
import {UniswapV2Adapter} from "./router/adapters/UniswapV2Adapter.sol";
import {IWETH9} from "./router/interfaces/IWETH9.sol";

contract FameRouter is Ownable, ReentrancyGuard {
    using FameRouterAccounting for FameRouterTypes.AmountMode;

    address public constant DEFAULT_FEE_RECIPIENT = 0xC952C53D8B63919e372caa2E6FEe605ee24E4D3D;

    address public feeRecipient;
    uint32 public feePpm;

    mapping(FameRouterTypes.VenueFamily => bool) public venueFamilyEnabled;
    mapping(FameRouterTypes.VenueFamily => mapping(address => bool)) public venueTargetEnabled;
    mapping(bytes32 => bool) public v4HookDataHashEnabled;

    bool private _executing;

    struct AssetSnapshot {
        address asset;
        uint256 baseline;
    }

    event FeeRecipientUpdated(address indexed feeRecipient);
    event FeePpmUpdated(uint32 feePpm);
    event VenueFamilyEnabled(FameRouterTypes.VenueFamily indexed family, bool enabled);
    event VenueTargetEnabled(FameRouterTypes.VenueFamily indexed family, address indexed target, bool enabled);
    event V4HookDataHashEnabled(bytes32 indexed hookDataKey, bool enabled);
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

    error BadRouteVersion(uint16 version);
    error DeadlineExpired(uint256 deadline, uint256 timestamp);
    error EmptyRoute();
    error TooManyLegs(uint256 legCount);
    error PayloadTooLarge(uint256 index, uint256 length);
    error ZeroAddress();
    error ZeroAmountIn();
    error NativeValueMismatch(uint256 expected, uint256 actual);
    error UnexpectedNativeValue(uint256 actual);
    error VenueFamilyDisabled(FameRouterTypes.VenueFamily family);
    error VenueTargetDisabled(FameRouterTypes.VenueFamily family, address target);
    error V4HookDataNotAllowed(bytes32 hookDataKey);
    error RouteNeverProducesOutput(address tokenOut);
    error SameAssetRouteUnsupported(address asset);
    error FinalOutputConsumed(uint256 index, address tokenOut);
    error LegOutputTooLow(uint256 index, uint256 produced, uint256 minimum);
    error FinalOutputTooLow(uint256 netAmountOut, uint256 minimum);
    error FeeTooHigh(uint32 requested, uint32 maximum);
    error RescueDuringExecution();
    error BalanceReadFailed(address token, address account);
    error NativeWrapPayloadNotEmpty(uint256 index);
    error NativeWrapMinAmountOutNotZero(uint256 index, uint256 minAmountOut);
    error BadNativeWrapDirection(uint256 index, address tokenIn, address tokenOut, address target);
    error StandaloneNativeWrapRoute();

    constructor(address initialFeeRecipient) payable {
        if (initialFeeRecipient == address(0)) revert ZeroAddress();

        _initializeOwner(msg.sender);
        feeRecipient = initialFeeRecipient;
        feePpm = FameRouterTypes.DEFAULT_FEE_PPM;

        emit FeeRecipientUpdated(initialFeeRecipient);
        emit FeePpmUpdated(FameRouterTypes.DEFAULT_FEE_PPM);
    }

    receive() external payable {}

    function executeRoute(FameRouterTypes.Route calldata route)
        external
        payable
        nonReentrant
        returns (uint256 netAmountOut)
    {
        bytes32 submittedRouteHash = hashRoute(route);
        _validateRouteHeader(route);
        _validateMsgValue(route);

        AssetSnapshot[] memory snapshots = _snapshotRouteAssets(route);

        if (route.tokenIn != FameRouterTypes.NATIVE_ETH) {
            SafeTransferLib.safeTransferFrom(route.tokenIn, msg.sender, address(this), route.amountIn);
        }

        _executing = true;
        for (uint256 i; i < route.legs.length; ++i) {
            _executeLeg(route.legs[i], i, snapshots);
        }
        _executing = false;

        uint256 grossAmountOut = _routeLocalBalance(route.tokenOut, snapshots);
        uint256 feeAmount = FameRouterAccounting.feeAmount(grossAmountOut, feePpm);
        netAmountOut = grossAmountOut - feeAmount;
        if (netAmountOut < route.minAmountOutAfterFee) {
            revert FinalOutputTooLow(netAmountOut, route.minAmountOutAfterFee);
        }

        if (feeAmount != 0) {
            _transferAsset(route.tokenOut, feeRecipient, feeAmount);
        }
        netAmountOut = _transferFinalOutput(route.tokenOut, route.recipient, netAmountOut, route.minAmountOutAfterFee);
        _refundRouteLocalLeftovers(snapshots, msg.sender);

        emit RouteExecuted(
            msg.sender,
            route.recipient,
            route.tokenOut,
            submittedRouteHash,
            route.version,
            route.tokenIn,
            route.amountIn,
            grossAmountOut,
            feeAmount,
            netAmountOut
        );
    }

    function hashRoute(FameRouterTypes.Route calldata route) public pure returns (bytes32) {
        return keccak256(abi.encode(route));
    }

    function setFeeRecipient(address newFeeRecipient) external onlyOwner {
        if (newFeeRecipient == address(0)) revert ZeroAddress();
        feeRecipient = newFeeRecipient;
        emit FeeRecipientUpdated(newFeeRecipient);
    }

    function setFeePpm(uint32 newFeePpm) external onlyOwner {
        if (newFeePpm > FameRouterTypes.MAX_FEE_PPM) {
            revert FeeTooHigh(newFeePpm, FameRouterTypes.MAX_FEE_PPM);
        }
        feePpm = newFeePpm;
        emit FeePpmUpdated(newFeePpm);
    }

    function setVenueFamilyEnabled(FameRouterTypes.VenueFamily family, bool enabled) external onlyOwner {
        venueFamilyEnabled[family] = enabled;
        emit VenueFamilyEnabled(family, enabled);
    }

    function setVenueTargetEnabled(FameRouterTypes.VenueFamily family, address target, bool enabled)
        external
        onlyOwner
    {
        if (target == address(0)) revert ZeroAddress();
        venueTargetEnabled[family][target] = enabled;
        emit VenueTargetEnabled(family, target, enabled);
    }

    function setV4HookDataHashEnabled(bytes32 hookDataKey, bool enabled) external onlyOwner {
        v4HookDataHashEnabled[hookDataKey] = enabled;
        emit V4HookDataHashEnabled(hookDataKey, enabled);
    }

    function rescue(address asset, address to, uint256 amount) external onlyOwner {
        if (_executing) revert RescueDuringExecution();
        _rescue(asset, to, amount);
    }

    function _rescue(address asset, address to, uint256 amount) private nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        _transferAsset(asset, to, amount);
        emit Rescue(asset, to, amount);
    }

    function _validateRouteHeader(FameRouterTypes.Route calldata route) private view {
        if (route.version != FameRouterTypes.SCHEMA_VERSION) revert BadRouteVersion(route.version);
        if (block.timestamp > route.deadline) revert DeadlineExpired(route.deadline, block.timestamp);
        if (route.recipient == address(0)) revert ZeroAddress();
        if (route.amountIn == 0) revert ZeroAmountIn();
        if (route.legs.length == 0) revert EmptyRoute();
        if (route.legs.length > FameRouterTypes.MAX_ROUTE_LEGS) revert TooManyLegs(route.legs.length);
        if (route.tokenIn == route.tokenOut) revert SameAssetRouteUnsupported(route.tokenIn);

        bool producesFinalToken;
        bool hasNonNativeWrapLeg;
        for (uint256 i; i < route.legs.length; ++i) {
            FameRouterTypes.Leg calldata leg = route.legs[i];
            if (leg.data.length > FameRouterTypes.MAX_PAYLOAD_BYTES) revert PayloadTooLarge(i, leg.data.length);
            if (!venueFamilyEnabled[leg.venue]) revert VenueFamilyDisabled(leg.venue);
            if (!venueTargetEnabled[leg.venue][leg.target]) revert VenueTargetDisabled(leg.venue, leg.target);
            if (leg.venue == FameRouterTypes.VenueFamily.NativeWrap) {
                _validateNativeWrapLeg(leg, i);
            } else {
                hasNonNativeWrapLeg = true;
            }
            if (producesFinalToken && leg.tokenIn == route.tokenOut) revert FinalOutputConsumed(i, route.tokenOut);
            if (leg.tokenOut == route.tokenOut) producesFinalToken = true;
        }

        if (!hasNonNativeWrapLeg) revert StandaloneNativeWrapRoute();
        if (!producesFinalToken) revert RouteNeverProducesOutput(route.tokenOut);
    }

    function _validateNativeWrapLeg(FameRouterTypes.Leg calldata leg, uint256 index) private pure {
        if (leg.data.length != 0) revert NativeWrapPayloadNotEmpty(index);
        if (leg.minAmountOut != 0) revert NativeWrapMinAmountOutNotZero(index, leg.minAmountOut);

        bool wraps = leg.tokenIn == FameRouterTypes.NATIVE_ETH && leg.tokenOut == leg.target;
        bool unwraps = leg.tokenIn == leg.target && leg.tokenOut == FameRouterTypes.NATIVE_ETH;
        if (!wraps && !unwraps) {
            revert BadNativeWrapDirection(index, leg.tokenIn, leg.tokenOut, leg.target);
        }
    }

    function _validateMsgValue(FameRouterTypes.Route calldata route) private view {
        if (route.tokenIn == FameRouterTypes.NATIVE_ETH) {
            if (msg.value != route.amountIn) revert NativeValueMismatch(route.amountIn, msg.value);
        } else if (msg.value != 0) {
            revert UnexpectedNativeValue(msg.value);
        }
    }

    function _executeLeg(FameRouterTypes.Leg calldata leg, uint256 index, AssetSnapshot[] memory snapshots) private {
        uint256 available = _routeLocalBalance(leg.tokenIn, snapshots);
        uint256 amountIn = leg.amountMode.spendAmount(leg.amount, available, leg.tokenIn);
        uint256 beforeOut = _routeLocalBalance(leg.tokenOut, snapshots);

        if (_usesDirectAllowance(leg)) {
            SafeTransferLib.safeApproveWithRetry(leg.tokenIn, leg.target, amountIn);
        }

        _dispatch(leg, amountIn);

        if (_usesDirectAllowance(leg)) {
            SafeTransferLib.safeApproveWithRetry(leg.tokenIn, leg.target, 0);
        }

        uint256 afterOut = _routeLocalBalance(leg.tokenOut, snapshots);
        uint256 produced = afterOut > beforeOut ? afterOut - beforeOut : 0;
        uint256 minimum = _legMinimumAmountOut(leg, amountIn);
        if (produced < minimum) {
            revert LegOutputTooLow(index, produced, minimum);
        }
    }

    function _usesDirectAllowance(FameRouterTypes.Leg calldata leg) private pure returns (bool) {
        return leg.tokenIn != FameRouterTypes.NATIVE_ETH && !_usesPermit2(leg.venue)
            && leg.venue != FameRouterTypes.VenueFamily.NativeWrap;
    }

    function _usesPermit2(FameRouterTypes.VenueFamily venue) private pure returns (bool) {
        return venue == FameRouterTypes.VenueFamily.UniswapV3 || venue == FameRouterTypes.VenueFamily.UniswapV4;
    }

    function _legMinimumAmountOut(FameRouterTypes.Leg calldata leg, uint256 amountIn) private pure returns (uint256) {
        if (leg.venue == FameRouterTypes.VenueFamily.NativeWrap) return amountIn;
        return leg.minAmountOut;
    }

    function _dispatch(FameRouterTypes.Leg calldata leg, uint256 amountIn) private returns (uint256 amountOut) {
        uint256 callValue = leg.tokenIn == FameRouterTypes.NATIVE_ETH ? amountIn : 0;

        if (leg.venue == FameRouterTypes.VenueFamily.NativeWrap) {
            amountOut = _dispatchNativeWrap(leg, amountIn);
        } else if (leg.venue == FameRouterTypes.VenueFamily.Solidly) {
            amountOut = SolidlyRouterAdapter.execute(
                leg.target, leg.tokenIn, leg.tokenOut, amountIn, leg.minAmountOut, address(this), leg.data, callValue
            );
        } else if (leg.venue == FameRouterTypes.VenueFamily.AerodromeV2) {
            amountOut = AerodromeV2RouterAdapter.execute(
                leg.target, leg.tokenIn, leg.tokenOut, amountIn, leg.minAmountOut, address(this), leg.data, callValue
            );
        } else if (leg.venue == FameRouterTypes.VenueFamily.UniswapV2) {
            amountOut = UniswapV2Adapter.execute(
                leg.target, leg.tokenIn, leg.tokenOut, amountIn, leg.minAmountOut, address(this), leg.data, callValue
            );
        } else if (
            leg.venue == FameRouterTypes.VenueFamily.Slipstream || leg.venue == FameRouterTypes.VenueFamily.Slipstream2
        ) {
            amountOut = SlipstreamAdapter.execute(
                leg.target, leg.tokenIn, leg.tokenOut, amountIn, leg.minAmountOut, address(this), leg.data, callValue
            );
        } else if (leg.venue == FameRouterTypes.VenueFamily.UniswapV3) {
            amountOut = UniversalRouterAdapter.executeV3(
                leg.target, leg.tokenIn, leg.tokenOut, amountIn, leg.minAmountOut, address(this), leg.data, callValue
            );
        } else if (leg.venue == FameRouterTypes.VenueFamily.UniswapV4) {
            (UniversalRouterAdapter.V4SwapPayload memory payload, bool hasHookData, bytes32 hookDataKey) =
                UniversalRouterAdapter.decodeV4Payload(leg.data);
            if (hasHookData && !v4HookDataHashEnabled[hookDataKey]) {
                revert V4HookDataNotAllowed(hookDataKey);
            }
            amountOut = UniversalRouterAdapter.executeDecodedV4(
                leg.target, leg.tokenIn, leg.tokenOut, amountIn, leg.minAmountOut, address(this), payload, callValue
            );
        } else {
            revert VenueFamilyDisabled(leg.venue);
        }
    }

    function _dispatchNativeWrap(FameRouterTypes.Leg calldata leg, uint256 amountIn)
        private
        returns (uint256 amountOut)
    {
        if (leg.tokenIn == FameRouterTypes.NATIVE_ETH) {
            IWETH9(leg.target).deposit{value: amountIn}();
        } else {
            IWETH9(leg.target).withdraw(amountIn);
        }
        amountOut = amountIn;
    }

    function _snapshotRouteAssets(FameRouterTypes.Route calldata route)
        private
        view
        returns (AssetSnapshot[] memory snapshots)
    {
        address[] memory assets = new address[](2 + route.legs.length * 2);
        uint256 count;
        count = _addAsset(assets, count, route.tokenIn);
        count = _addAsset(assets, count, route.tokenOut);

        for (uint256 i; i < route.legs.length; ++i) {
            count = _addAsset(assets, count, route.legs[i].tokenIn);
            count = _addAsset(assets, count, route.legs[i].tokenOut);
        }

        snapshots = new AssetSnapshot[](count);
        for (uint256 i; i < count; ++i) {
            uint256 baseline = _assetBalance(assets[i]);
            if (assets[i] == FameRouterTypes.NATIVE_ETH && route.tokenIn == FameRouterTypes.NATIVE_ETH) {
                baseline -= route.amountIn;
            }
            snapshots[i] = AssetSnapshot({asset: assets[i], baseline: baseline});
        }
    }

    function _addAsset(address[] memory assets, uint256 count, address asset) private pure returns (uint256) {
        for (uint256 i; i < count; ++i) {
            if (assets[i] == asset) return count;
        }
        assets[count] = asset;
        return count + 1;
    }

    function _refundRouteLocalLeftovers(AssetSnapshot[] memory snapshots, address to) private {
        for (uint256 i; i < snapshots.length; ++i) {
            uint256 local = _routeLocalBalance(snapshots[i].asset, snapshots);
            if (local != 0) {
                _transferAsset(snapshots[i].asset, to, local);
            }
        }
    }

    function _routeLocalBalance(address asset, AssetSnapshot[] memory snapshots) private view returns (uint256) {
        uint256 baseline = _baseline(asset, snapshots);
        uint256 current = _assetBalance(asset);
        return current > baseline ? current - baseline : 0;
    }

    function _baseline(address asset, AssetSnapshot[] memory snapshots) private pure returns (uint256) {
        for (uint256 i; i < snapshots.length; ++i) {
            if (snapshots[i].asset == asset) return snapshots[i].baseline;
        }
        return 0;
    }

    function _assetBalance(address asset) private view returns (uint256) {
        if (asset == FameRouterTypes.NATIVE_ETH) return address(this).balance;
        return _erc20BalanceOf(asset, address(this));
    }

    function _transferAsset(address asset, address to, uint256 amount) private {
        if (amount == 0) return;
        if (asset == FameRouterTypes.NATIVE_ETH) {
            SafeTransferLib.safeTransferETH(to, amount);
        } else {
            SafeTransferLib.safeTransfer(asset, to, amount);
        }
    }

    function _transferFinalOutput(address asset, address recipient, uint256 amount, uint256 minimum)
        private
        returns (uint256 delivered)
    {
        if (asset == FameRouterTypes.NATIVE_ETH) {
            _transferAsset(asset, recipient, amount);
            return amount;
        }

        uint256 beforeRecipient = _erc20BalanceOf(asset, recipient);
        _transferAsset(asset, recipient, amount);
        uint256 afterRecipient = _erc20BalanceOf(asset, recipient);
        delivered = afterRecipient > beforeRecipient ? afterRecipient - beforeRecipient : 0;
        if (delivered < minimum) revert FinalOutputTooLow(delivered, minimum);
    }

    function _erc20BalanceOf(address token, address account) private view returns (uint256 balance) {
        (bool success, bytes memory data) = token.staticcall(abi.encodeWithSelector(0x70a08231, account));
        if (!success || data.length != 32) revert BalanceReadFailed(token, account);
        balance = abi.decode(data, (uint256));
    }
}
