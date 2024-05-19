// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// v2 factory on sepolia
// 0xB7f907f7A9eBC822a80BD25E224be42Ce0A698A0

import {Ownable} from "@openzeppelin5/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin5/contracts/token/ERC20/IERC20.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {INonfungiblePositionManager} from "./v3-periphery/INonfungiblePositionManager.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";

contract FameLauncher is Ownable {
    using FixedPointMathLib for uint256;

    IUniswapV2Factory public uniswapV2Factory;
    IUniswapV2Pair public v2Pair;

    IUniswapV3Factory public uniswapV3Factory;
    IUniswapV3Pool public v3Pool;
    INonfungiblePositionManager public nonfungiblePositionManager;

    IERC20 public tokenA;
    IERC20 public tokenB;

    constructor(
        address _tokenA,
        address _tokenB,
        address _uniswapV2Factory,
        address _uniswapV3Factory,
        address _nonfungiblePositionManager
    ) Ownable(msg.sender) {
        tokenA = IERC20(_tokenA);
        tokenB = IERC20(_tokenB);
        uniswapV2Factory = IUniswapV2Factory(_uniswapV2Factory);
        uniswapV3Factory = IUniswapV3Factory(_uniswapV3Factory);
        nonfungiblePositionManager = INonfungiblePositionManager(
            _nonfungiblePositionManager
        );
    }

    function createV2Pair() internal returns (address pair) {
        return uniswapV2Factory.createPair(address(tokenA), address(tokenB));
    }

    function createV2Liquidity()
        external
        payable
        onlyOwner
        returns (uint liquidity)
    {
        v2Pair = IUniswapV2Pair(createV2Pair());

        // add liquidity using all tokens in the contract
        uint256 amountA = tokenA.balanceOf(address(this));
        uint256 amountB = tokenB.balanceOf(address(this));

        // transfer the tokens to the pair
        tokenA.transfer(address(v2Pair), amountA);
        tokenB.transfer(address(v2Pair), amountB);

        // add liquidity
        liquidity = IUniswapV2Pair(v2Pair).mint(address(this));
    }

    function createV3Pool() internal returns (address pool) {
        return
            uniswapV3Factory.createPool(address(tokenA), address(tokenB), 3000);
    }

    function createV3Liquidity(
        uint160 sqrtPriceX96,
        uint256 postSaleAmountA
    ) external payable onlyOwner {
        v3Pool = IUniswapV3Pool(createV3Pool());
        v3Pool.initialize(sqrtPriceX96);

        // Calculate the current tick based on sqrtPriceX96
        int24 tick = getTickFromSqrtPriceX96(sqrtPriceX96);

        // Set tickLower and tickUpper to be around the current tick
        int24 tickSpacing = uniswapV3Factory.feeAmountTickSpacing(3000); // Example tick spacing, adjust based on your pool settings
        int24 tickLower = (tick / tickSpacing) * tickSpacing - tickSpacing;
        int24 tickUpper = (tick / tickSpacing) * tickSpacing + tickSpacing;

        tokenA.approve(address(nonfungiblePositionManager), postSaleAmountA);

        nonfungiblePositionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: address(tokenA),
                token1: address(tokenB),
                fee: 3000,
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: postSaleAmountA,
                amount1Desired: 0,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp
            })
        );
    }

    function getTickFromSqrtPriceX96(
        uint160 sqrtPriceX96
    ) internal pure returns (int24 tick) {
        // Calculate the tick based on sqrtPriceX96
        uint256 ratio = uint256(sqrtPriceX96) << 32;
        tick = int24((int256(ratio.log2()) - (1 << 96)) / (1 << 64));
    }
}
