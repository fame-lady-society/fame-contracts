// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @dev Test scaffold for FameRouter custody tests.
/// Production schema version 1 route targets are real venue targets selected by VenueFamily, not this generic hook.
interface IRouterLegExecutor {
    function executeLeg(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient,
        bytes calldata data
    ) external payable returns (uint256 amountOut);
}
