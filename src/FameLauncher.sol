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
import {TickMath} from "./v3-core/TickMath.sol";

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

    function createV3Pool() internal returns (address pool) {
        return
            uniswapV3Factory.createPool(address(tokenA), address(tokenB), 3000);
    }

    function getV3TickSpacing() public view returns (int24 tickSpacing) {
        return uniswapV3Factory.feeAmountTickSpacing(3000);
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

    function initializeV3Pool(uint160 sqrtPriceX96) external onlyOwner {
        // v3Pool = IUniswapV3Pool(createV3Pool());
        // v3Pool.initialize(sqrtPriceX96);
        v3Pool = IUniswapV3Pool(
            nonfungiblePositionManager.createAndInitializePoolIfNecessary(
                address(tokenA),
                address(tokenB),
                3000,
                sqrtPriceX96
            )
        );
    }

    function createV3Liquidity(
        uint256 postSaleAmountA,
        uint256 postSaleAmountB,
        int24 tickLower,
        int24 tickUpper
    )
        external
        payable
        onlyOwner
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        if (postSaleAmountA > 0) {
            tokenA.approve(
                address(nonfungiblePositionManager),
                postSaleAmountA
            );
        }
        if (postSaleAmountB > 0) {
            tokenB.approve(
                address(nonfungiblePositionManager),
                postSaleAmountB
            );
        }

        return
            nonfungiblePositionManager.mint(
                INonfungiblePositionManager.MintParams({
                    token0: address(tokenA),
                    token1: address(tokenB),
                    fee: 3000,
                    tickLower: tickLower,
                    tickUpper: tickUpper,
                    amount0Desired: postSaleAmountA,
                    amount1Desired: postSaleAmountB,
                    amount0Min: 0,
                    amount1Min: 0,
                    recipient: address(this),
                    deadline: block.timestamp
                })
            );
    }

    function getTickFromSqrtPriceX96(
        uint160 sqrtPriceX96
    ) external pure returns (int24 tick) {
        return TickMath.getTickAtSqrtRatio(sqrtPriceX96);
    }
}
