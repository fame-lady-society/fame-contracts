// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// v2 factory on sepolia
// 0xB7f907f7A9eBC822a80BD25E224be42Ce0A698A0

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

contract FameLauncher is Ownable {
    IUniswapV2Factory public uniswapV2Factory;
    IUniswapV2Pair public v2Pair;

    IUniswapV3Factory public uniswapV3Factory;
    IUniswapV3Pool public v3Pool;

    IERC20 public tokenA;
    IERC20 public tokenB;

    constructor(
        address _tokenA,
        address _tokenB,
        address _uniswapV2Factory,
        address _uniswapV3Factory
    ) Ownable(msg.sender) {
        tokenA = IERC20(_tokenA);
        tokenB = IERC20(_tokenB);
        uniswapV2Factory = IUniswapV2Factory(_uniswapV2Factory);
        uniswapV3Factory = IUniswapV3Factory(_uniswapV3Factory);
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

    function createV3Liquidity()
        external
        payable
        onlyOwner
        returns (uint liquidity)
    {
        v3Pool = IUniswapV3Pool(createV3Pool());

        // add liquidity using all tokens in the contract
        uint256 amountA = tokenA.balanceOf(address(this));
        uint256 amountB = tokenB.balanceOf(address(this));

        // transfer the tokens to the pool
        tokenA.transfer(address(v3Pool), amountA);
        tokenB.transfer(address(v3Pool), amountB);

        // add liquidity
        liquidity = IUniswapV3Pool(v3Pool).mint(address(this));
    }
}
