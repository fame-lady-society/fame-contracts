// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IUniswapV2Router02} from "../interfaces/IUniswapV2Router02.sol";

library UniswapV2Adapter {
    error NativeEthUnsupported();
    error InvalidPath();

    struct Payload {
        address[] path;
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
        if (payload.path.length < 2 || payload.path[0] != tokenIn || payload.path[payload.path.length - 1] != tokenOut)
        {
            revert InvalidPath();
        }

        uint256[] memory amounts = IUniswapV2Router02(target)
            .swapExactTokensForTokens(amountIn, minAmountOut, payload.path, recipient, payload.deadline);
        return amounts[amounts.length - 1];
    }
}
