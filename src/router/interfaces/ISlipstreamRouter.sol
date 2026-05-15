// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ISlipstreamRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        int24 tickSpacing;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function factory() external view returns (address);

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);
}
