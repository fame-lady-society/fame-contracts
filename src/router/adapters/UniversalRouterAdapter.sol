// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IUniversalRouter} from "../interfaces/IUniversalRouter.sol";
import {IPermit2} from "../interfaces/IPermit2.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

library UniversalRouterAdapter {
    error RawUniversalRouterCommandsDisabled();
    error InvalidUniversalRouterPayload();

    bytes1 internal constant COMMAND_V3_SWAP_EXACT_IN = 0x00;
    bytes1 internal constant COMMAND_V4_SWAP = 0x10;
    address internal constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    bytes1 internal constant ACTION_V4_SWAP_EXACT_IN_SINGLE = 0x06;
    bytes1 internal constant ACTION_V4_SETTLE_ALL = 0x0c;
    bytes1 internal constant ACTION_V4_TAKE_ALL = 0x0f;

    struct V4PoolKey {
        address currency0;
        address currency1;
        uint24 fee;
        int24 tickSpacing;
        address hooks;
    }

    struct V4ExactInputSingleParams {
        V4PoolKey poolKey;
        bool zeroForOne;
        uint128 amountIn;
        uint128 amountOutMinimum;
        bytes hookData;
    }

    struct V3ExactInputPayload {
        bytes path;
        uint256 deadline;
        bool payerIsUser;
        address recipient;
    }

    struct V4SwapPayload {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 minAmountOut;
        address currency0;
        address currency1;
        bool zeroForOne;
        uint24 fee;
        int24 tickSpacing;
        address hooks;
        bytes hookData;
        uint256 deadline;
        address recipient;
        bool payerIsUser;
    }

    function executeV3(
        address target,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient,
        bytes calldata data,
        uint256 callValue
    ) internal returns (uint256) {
        _rejectRawExecute(data);
        V3ExactInputPayload memory payload = abi.decode(data, (V3ExactInputPayload));
        if (tokenIn == address(0) || tokenOut == address(0)) revert InvalidUniversalRouterPayload();
        if (!payload.payerIsUser || payload.recipient != recipient) {
            revert InvalidUniversalRouterPayload();
        }
        if (amountIn > type(uint160).max) revert InvalidUniversalRouterPayload();
        _validateV3Path(payload.path, tokenIn, tokenOut);

        _approvePermit2(tokenIn, target, amountIn);

        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(recipient, amountIn, minAmountOut, payload.path, true);
        IUniversalRouter(target).execute{value: callValue}(
            _singleCommand(COMMAND_V3_SWAP_EXACT_IN), inputs, payload.deadline
        );
        _clearPermit2(tokenIn, target);
        return 0;
    }

    function executeV4(
        address target,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient,
        bytes calldata data,
        uint256 callValue
    ) internal returns (uint256) {
        (V4SwapPayload memory payload,,) = decodeV4Payload(data);
        return executeDecodedV4(target, tokenIn, tokenOut, amountIn, minAmountOut, recipient, payload, callValue);
    }

    function executeDecodedV4(
        address target,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient,
        V4SwapPayload memory payload,
        uint256 callValue
    ) internal returns (uint256) {
        if (
            payload.payerIsUser || payload.recipient != recipient || payload.tokenIn != tokenIn
                || payload.tokenOut != tokenOut || payload.minAmountOut != minAmountOut
                || (payload.amountIn != 0 && payload.amountIn != amountIn)
        ) {
            revert InvalidUniversalRouterPayload();
        }
        if (amountIn > type(uint128).max || minAmountOut > type(uint128).max) revert InvalidUniversalRouterPayload();
        _validateV4Pool(payload, tokenIn, tokenOut);
        if (tokenIn != address(0)) {
            if (amountIn > type(uint160).max) revert InvalidUniversalRouterPayload();
            _approvePermit2(tokenIn, target, amountIn);
        }

        bytes[] memory inputs = new bytes[](1);
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            V4ExactInputSingleParams({
                poolKey: V4PoolKey({
                    currency0: payload.currency0,
                    currency1: payload.currency1,
                    fee: payload.fee,
                    tickSpacing: payload.tickSpacing,
                    hooks: payload.hooks
                }),
                zeroForOne: payload.zeroForOne,
                amountIn: uint128(amountIn),
                amountOutMinimum: uint128(minAmountOut),
                hookData: payload.hookData
            })
        );
        params[1] = abi.encode(tokenIn, amountIn);
        params[2] = abi.encode(tokenOut, minAmountOut);
        inputs[0] = abi.encode(_v4ExactInputSingleActions(), params);
        IUniversalRouter(target).execute{value: callValue}(_singleCommand(COMMAND_V4_SWAP), inputs, payload.deadline);
        if (tokenIn != address(0)) _clearPermit2(tokenIn, target);
        return 0;
    }

    function decodeV4Payload(bytes calldata data)
        internal
        pure
        returns (V4SwapPayload memory payload, bool hasHookData, bytes32 key)
    {
        _rejectRawExecute(data);
        payload = abi.decode(data, (V4SwapPayload));
        (hasHookData, key) = _v4HookDataKey(payload);
    }

    function _rejectRawExecute(bytes calldata data) private pure {
        if (data.length >= 4 && bytes4(data[:4]) == IUniversalRouter.execute.selector) {
            revert RawUniversalRouterCommandsDisabled();
        }
    }

    function _validateV3Path(bytes memory path, address tokenIn, address tokenOut) private pure {
        if (path.length < 43 || (path.length - 20) % 23 != 0) revert InvalidUniversalRouterPayload();
        if (_addressAt(path, 0) != tokenIn || _addressAt(path, path.length - 20) != tokenOut) {
            revert InvalidUniversalRouterPayload();
        }
    }

    function _approvePermit2(address token, address spender, uint256 amount) private {
        SafeTransferLib.safeApproveWithRetry(token, PERMIT2, amount);
        IPermit2(PERMIT2).approve(token, spender, uint160(amount), uint48(block.timestamp));
    }

    function _clearPermit2(address token, address spender) private {
        IPermit2(PERMIT2).approve(token, spender, 0, uint48(block.timestamp));
        SafeTransferLib.safeApproveWithRetry(token, PERMIT2, 0);
    }

    function _validateV4Pool(V4SwapPayload memory payload, address tokenIn, address tokenOut) private pure {
        if (payload.currency0 == payload.currency1) {
            revert InvalidUniversalRouterPayload();
        }
        if (payload.zeroForOne) {
            if (payload.currency0 != tokenIn || payload.currency1 != tokenOut) revert InvalidUniversalRouterPayload();
        } else {
            if (payload.currency1 != tokenIn || payload.currency0 != tokenOut) revert InvalidUniversalRouterPayload();
        }
        if (payload.fee == 0 && payload.tickSpacing == 0) revert InvalidUniversalRouterPayload();
    }

    function _v4ExactInputSingleActions() private pure returns (bytes memory actions) {
        actions = new bytes(3);
        actions[0] = ACTION_V4_SWAP_EXACT_IN_SINGLE;
        actions[1] = ACTION_V4_SETTLE_ALL;
        actions[2] = ACTION_V4_TAKE_ALL;
    }

    function v4HookDataKey(bytes calldata data) internal pure returns (bool hasHookData, bytes32 key) {
        V4SwapPayload memory payload;
        (payload, hasHookData, key) = decodeV4Payload(data);
    }

    function _v4HookDataKey(V4SwapPayload memory payload) private pure returns (bool hasHookData, bytes32 key) {
        hasHookData = payload.hookData.length != 0;
        if (!hasHookData) return (false, bytes32(0));
        key = keccak256(
            abi.encode(
                payload.currency0,
                payload.currency1,
                payload.fee,
                payload.tickSpacing,
                payload.hooks,
                keccak256(payload.hookData)
            )
        );
    }

    function _singleCommand(bytes1 command) private pure returns (bytes memory commands) {
        commands = new bytes(1);
        commands[0] = command;
    }

    function _addressAt(bytes memory data, uint256 offset) private pure returns (address value) {
        assembly {
            value := shr(96, mload(add(add(data, 0x20), offset)))
        }
    }
}
