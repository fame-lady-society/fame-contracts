// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IAerodromeV2Router {
    struct AerodromeRoute {
        address from;
        address to;
        bool stable;
        address factory;
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        AerodromeRoute[] calldata routes,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}
