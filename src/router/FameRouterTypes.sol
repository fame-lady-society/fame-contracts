// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library FameRouterTypes {
    uint16 internal constant SCHEMA_VERSION = 1;
    uint8 internal constant MAX_ROUTE_LEGS = 16;
    uint16 internal constant MAX_PAYLOAD_BYTES = 2048;
    uint16 internal constant BPS_DENOMINATOR = 10_000;
    uint32 internal constant FEE_DENOMINATOR = 1_000_000;
    uint32 internal constant DEFAULT_FEE_PPM = 2222;
    uint32 internal constant MAX_FEE_PPM = 10_000;

    address internal constant NATIVE_ETH = address(0);

    enum VenueFamily {
        Solidly,
        UniswapV2,
        Slipstream,
        Slipstream2,
        UniswapV3,
        UniswapV4,
        NativeWrap,
        AerodromeV2
    }

    enum AmountMode {
        Exact,
        BalanceBps,
        All
    }

    struct Leg {
        address tokenIn;
        address tokenOut;
        VenueFamily venue;
        AmountMode amountMode;
        uint256 amount;
        uint256 minAmountOut;
        address target;
        bytes data;
    }

    struct Route {
        uint16 version;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 minAmountOutAfterFee;
        address recipient;
        uint256 deadline;
        Leg[] legs;
    }
}
