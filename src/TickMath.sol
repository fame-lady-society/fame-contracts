// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library TickMath {
    // int24 internal constant MIN_TICK = -887272;
    // int24 internal constant MAX_TICK = 887272;
    // /// @notice Calculates the tick value based on sqrtPriceX96
    // /// @param sqrtPriceX96 The sqrt price as a Q64.96 value
    // /// @return tick The tick value
    // function getTick(int24 sqrtPriceX96) internal pure returns (int24 tick) {
    //     require(sqrtPriceX96 > 0, "S");
    //     int256 ratio = int256(uint256(sqrtPriceX96) << 32); // Fixed-point arithmetic
    //     tick = int24((log_1_0001(ratio) - (1 << 32)) / (1 << 32));
    // }
    // /// @notice Calculates log base 1.0001 of the ratio using fixed-point arithmetic
    // /// @param ratio The price ratio
    // /// @return log_1_0001 The logarithm base 1.0001 of the ratio
    // function log_1_0001(int256 ratio) internal pure returns (int256) {
    //     int256 log = 0;
    //     while (ratio > 10 ** 18) {
    //         ratio /= 10 ** 18;
    //         log += 1 << 96;
    //     }
    //     while (ratio < 10 ** 18) {
    //         ratio *= 10 ** 18;
    //         log -= 1 << 96;
    //     }
    //     return log + int256(int128(ABDKMath64x64.ln(ratio)));
    // }
}
