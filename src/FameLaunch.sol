// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FameLauncher} from "./FameLauncher.sol";
import {Fame} from "./Fame.sol";
import {INonfungiblePositionManager} from "./v3-periphery/INonfungiblePositionManager.sol";
import {TickMath} from "./v3-core/TickMath.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

interface IWETH {
    function deposit() external payable;
    function transfer(address to, uint value) external returns (bool);
    function withdraw(uint) external;
}

contract FameLaunch {
    constructor() {}

    function launch(
        address payable fame,
        address weth,
        address _uniswapV2Factory,
        address _uniswapV3Factory,
        address _nonfungiblePositionManager
    ) external payable {
        bool isTokenALower = fame < weth;
        address token0 = isTokenALower ? fame : weth;
        address token1 = isTokenALower ? weth : fame;

        FameLauncher fameLauncher = new FameLauncher(
            token0,
            token1,
            _uniswapV2Factory,
            _uniswapV3Factory,
            _nonfungiblePositionManager
        );

        IUniswapV2Pair v2Pair = IUniswapV2Pair(fameLauncher.createV2Pair());
        IWETH(weth).deposit{value: msg.value}();

        IWETH(weth).transfer(address(v2Pair), msg.value);
        Fame(fame).transfer(address(v2Pair), 177_600_000 ether);

        // launch v2
        fameLauncher.v2Pair().transfer(
            address(0),
            fameLauncher.createV2Liquidity()
        );

        // launch v3 post sale
        uint160 price = isTokenALower
            ? sqrtPriceX96(888_000_000 ether, msg.value)
            : sqrtPriceX96(msg.value, 888_000_000 ether);
        fameLauncher.initializeV3Pool(price);

        Fame(fame).transfer(address(fameLauncher), 100_000_000 ether);
        int24 tick = TickMath.getTickAtSqrtRatio(price);
        int24 tickSpacing = fameLauncher.getV3TickSpacing();
        int24 tickBoundary = isTokenALower
            ? tick + 2 * tickSpacing
            : tick - 2 * tickSpacing;
        (uint256 tokenId, , , ) = isTokenALower
            ? fameLauncher.createV3Liquidity(
                100_000_000 ether,
                0 ether,
                tick + tickSpacing,
                tickBoundary
            )
            : fameLauncher.createV3Liquidity(
                0 ether,
                100_000_000 ether,
                tickBoundary,
                tick - tickSpacing
            );
        // (uint256 tokenId, , , ) = fameLauncher.createV3Liquidity(
        //     isTokenALower ? 100_000_000 ether : 0 ether,
        //     isTokenALower ? 0 ether : 100_000_000 ether,
        //     isTokenALower ? tick + tickSpacing : tickBoundary,
        //     isTokenALower ? tickBoundary : tick - tickSpacing
        // );

        // transfer fame to the sender
        INonfungiblePositionManager(_nonfungiblePositionManager)
            .safeTransferFrom(address(this), msg.sender, tokenId);

        Fame(fame).transfer(address(fameLauncher), 166_400_000 ether);
        (tokenId, , , ) = isTokenALower
            ? fameLauncher.createV3Liquidity(
                166_400_000 ether,
                0 ether,
                tickBoundary,
                887220
            )
            : fameLauncher.createV3Liquidity(
                0 ether,
                166_400_000 ether,
                -887220,
                tickBoundary
            );
        // (tokenId, , , ) = fameLauncher.createV3Liquidity(
        //     isTokenALower ? 166_400_000 ether : 0 ether,
        //     isTokenALower ? 0 ether : 166_400_000 ether,
        //     isTokenALower ? tickBoundary : -887220,
        //     isTokenALower ? -887220 : tickBoundary
        // );

        INonfungiblePositionManager(_nonfungiblePositionManager)
            .safeTransferFrom(address(this), msg.sender, tokenId);
    }

    function sqrtPriceX96(
        uint256 amountToken0,
        uint256 amountToken1
    ) internal pure returns (uint160) {
        // Calculate ratio
        uint256 ratio = (amountToken1 * 1e18) / amountToken0; // Multiplied by 1e18 to maintain precision

        // Calculate square root of the ratio
        uint256 sqrtRatio = sqrt(ratio);

        // Scale by 2^96
        uint256 s = (sqrtRatio * 2 ** 96) / 1e9; // Divided by 1e9 to adjust for the precision multiplier

        return
            TickMath.getSqrtRatioAtTick(
                (TickMath.getTickAtSqrtRatio(uint160(s)) / 60) * 60
            );
    }

    // Babylonian Method for square root
    function sqrt(uint y) internal pure returns (uint z) {
        if (y > 3) {
            z = y;
            uint x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    // ERC721Receiver
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
