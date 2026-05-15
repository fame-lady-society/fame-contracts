// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ISlipstreamRouter} from "../interfaces/ISlipstreamRouter.sol";

library SlipstreamAdapter {
    error NativeEthUnsupported();
    error InvalidPath();

    struct Payload {
        address router;
        address factory;
        address tokenIn;
        address tokenOut;
        int24 tickSpacing;
        uint160 sqrtPriceLimitX96;
        uint256 deadline;
    }

    function execute(
        address target,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient,
        bytes calldata data,
        uint256 callValue
    ) internal returns (uint256) {
        if (callValue != 0 || tokenIn == address(0) || tokenOut == address(0)) {
            revert NativeEthUnsupported();
        }

        Payload memory payload = abi.decode(data, (Payload));
        if (payload.router != target || payload.factory == address(0)) {
            revert InvalidPath();
        }
        if (payload.tokenIn != tokenIn || payload.tokenOut != tokenOut || payload.tickSpacing == 0) {
            revert InvalidPath();
        }
        if (ISlipstreamRouter(target).factory() != payload.factory) {
            revert InvalidPath();
        }

        return ISlipstreamRouter(target)
            .exactInputSingle(
                ISlipstreamRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                tickSpacing: payload.tickSpacing,
                recipient: recipient,
                deadline: payload.deadline,
                amountIn: amountIn,
                amountOutMinimum: minAmountOut,
                sqrtPriceLimitX96: payload.sqrtPriceLimitX96
            })
            );
    }
}
