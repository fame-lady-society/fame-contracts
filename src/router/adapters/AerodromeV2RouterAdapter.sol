// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAerodromeV2Router} from "../interfaces/IAerodromeV2Router.sol";

library AerodromeV2RouterAdapter {
    error NativeEthUnsupported();
    error InvalidRoute();

    struct Payload {
        IAerodromeV2Router.AerodromeRoute[] routes;
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
        if (
            payload.routes.length == 0 || payload.routes[0].from != tokenIn
                || payload.routes[payload.routes.length - 1].to != tokenOut
        ) {
            revert InvalidRoute();
        }

        for (uint256 i; i < payload.routes.length; ++i) {
            if (
                payload.routes[i].from == address(0) || payload.routes[i].to == address(0)
                    || payload.routes[i].factory == address(0)
            ) {
                revert InvalidRoute();
            }
            if (i != 0 && payload.routes[i - 1].to != payload.routes[i].from) revert InvalidRoute();
        }

        uint256[] memory amounts = IAerodromeV2Router(target)
            .swapExactTokensForTokens(amountIn, minAmountOut, payload.routes, recipient, payload.deadline);
        return amounts[amounts.length - 1];
    }
}
