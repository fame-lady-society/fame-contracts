// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {FameMirror} from "../src/FameMirror.sol";
import {Fame} from "../src/Fame.sol";
import {FameLauncher} from "../src/FameLauncher.sol";
import {IERC20} from "@openzeppelin5/contracts/token/ERC20/IERC20.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {LiquidityAmounts} from "../src/v3-periphery/LiquidityAmounts.sol";
import {SqrtPriceMath} from "../src/v3-core/SqrtPriceMath.sol";
import {TickMath} from "../src/v3-core/TickMath.sol";
import {LibString} from "solady/utils/LibString.sol";
import {Math} from "@openzeppelin5/contracts/utils/math/Math.sol";
import {ISwapRouter02} from "../src/swap-router-contracts/ISwapRouter02.sol";
import "../src/v3-core/FullMath.sol";
import {MockBalanceOf} from "./mocks/MockBalanceOf.sol";
import "@uniswap/v3-core/contracts/libraries/FixedPoint96.sol";
import "forge-std/console.sol";

interface IWETH {
    function deposit() external payable;
    function transfer(address to, uint value) external returns (bool);
    function withdraw(uint) external;
}

contract FameLauncherTest is Test {
    MockBalanceOf public mockBalanceOf;
    Fame public fame;
    Fame public fame1;
    FameLauncher public fameLauncher;
    FameLauncher public fameLauncher1;
    IWETH weth = IWETH(0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9);
    ISwapRouter02 public swapRouter =
        ISwapRouter02(0x3bFA4769FB09eefC5a80d6E87c3B9C650f7Ae48E);
    using LibString for uint256;

    // function toBytes(uint256 x) internal returns (bytes32 b) {
    //     b = new bytes32(32);
    //     assembly {
    //         mstore(add(b, 32), x)
    //     }
    // }

    function setUp() public {
        mockBalanceOf = new MockBalanceOf();
        // salt is a bytes32
        uint256 salt = 0x1;
        fame = new Fame{salt: bytes32(abi.encodePacked(salt))}(
            "Fame",
            "FAME",
            address(mockBalanceOf)
        );
        salt = 0x2;
        fame1 = new Fame{salt: bytes32(abi.encodePacked(salt))}(
            "Fame",
            "FAME",
            address(mockBalanceOf)
        );
        fameLauncher = new FameLauncher(
            address(fame),
            address(weth),
            0xB7f907f7A9eBC822a80BD25E224be42Ce0A698A0, // v2 factory on sepolia
            0x0227628f3F023bb0B980b67D528571c95c6DaC1c, // v3 factory on sepolia
            0x1238536071E1c677A632429e3655c799b22cDA52 //  v3 nonfungiblePositionManager on sepolia
        );

        fameLauncher1 = new FameLauncher(
            address(weth),
            address(fame1),
            0xB7f907f7A9eBC822a80BD25E224be42Ce0A698A0, // v2 factory on sepolia
            0x0227628f3F023bb0B980b67D528571c95c6DaC1c, // v3 factory on sepolia
            0x1238536071E1c677A632429e3655c799b22cDA52 //  v3 nonfungiblePositionManager on sepolia
        );
    }

    function test_LaunchV2Liquidity() public {
        // Wrap 8 ETH to WETH
        weth.deposit{value: 8 ether}();

        // create liquidity
        address v2Pair = fameLauncher.createV2Pair();
        IWETH(weth).transfer(v2Pair, 8 ether);
        Fame(fame).transfer(v2Pair, 177_600_000 ether);
        uint liquidity = fameLauncher.createV2Liquidity();
        assertEq(liquidity, 37693500766047188681023);
    }

    function test_InitializeV3Pool() public {
        uint160 price = sqrtPriceX96(888_000_000 ether, 8 ether);

        fameLauncher.initializeV3Pool(price);
        assert(fameLauncher.v3Pool() != IUniswapV3Pool(address(0)));
        assert(fameLauncher.v3Pool().token0() == address(fame));
        assertEq(fameLauncher.v3Pool().liquidity(), 0);
    }

    function test_LaunchV3LiquidityPostSale() public {
        uint160 price = sqrtPriceX96(888_000_000 ether, 8 ether);
        fameLauncher.initializeV3Pool(price);
        fame.transfer(address(fameLauncher), 100_000_000 ether);

        // Calculate the current tick based on sqrtPriceX96
        int24 tick = TickMath.getTickAtSqrtRatio(price);

        // Set tickLower and tickUpper to be around the current tick
        int24 tickSpacing = fameLauncher.getV3TickSpacing();

        // get current tick
        int24 tickLower = tick + tickSpacing;
        int24 tickUpper = tick + 2 * tickSpacing;

        (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        ) = fameLauncher.createV3Liquidity(
                100_000_000 ether,
                0 ether,
                tickLower,
                tickUpper
            );

        assertEq(tokenId, 15896);
        assertEq(liquidity, 3184596500010477641151432);
        assertEq(amount0, 99999999999999999999983010);
        assertEq(amount1, 0);

        assertEq(fameLauncher.v3Pool().liquidity(), 0);
    }

    function test_LaunchV3LiquidityPostSale1() public {
        uint160 price = sqrtPriceX96(8 ether, 888_000_000 ether);
        fameLauncher1.initializeV3Pool(price);
        fame1.transfer(address(fameLauncher1), 100_000_000 ether);

        // Calculate the current tick based on sqrtPriceX96
        int24 tick = TickMath.getTickAtSqrtRatio(price);

        // Set tickLower and tickUpper to be around the current tick
        int24 tickSpacing = fameLauncher1.getV3TickSpacing();

        // get current tick
        int24 tickUpper = tick - tickSpacing;
        int24 tickLower = tick - 2 * tickSpacing;

        (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        ) = fameLauncher1.createV3Liquidity(
                0 ether,
                100_000_000 ether,
                tickLower,
                tickUpper
            );

        assertEq(tokenId, 15896);
        assertEq(liquidity, 3184596500010477641152027);
        assertEq(amount0, 0);
        assertEq(amount1, 99999999999999999999999992);

        assertEq(fameLauncher1.v3Pool().liquidity(), 0);
    }

    function test_v3LiquidityAmount() public view {
        uint160 price = sqrtPriceX96(888_000_000 ether, 8 ether);
        int24 tickSpacing = fameLauncher.getV3TickSpacing();
        int24 tick = TickMath.getTickAtSqrtRatio(price);
        int24 tickUpper = tick + 2 * tickSpacing;
        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(tickUpper);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(TickMath.MAX_TICK);
        assertEq(
            LiquidityAmounts.getLiquidityForAmounts(
                price,
                sqrtRatioAX96,
                sqrtRatioBX96,
                100_000_000 ether,
                0
            ),
            9567655433000195384683
        );
    }

    function test_LaunchV3LiquidityRest() public {
        uint160 price = sqrtPriceX96(888_000_000 ether, 8 ether);
        fameLauncher.initializeV3Pool(price);
        fame.transfer(address(fameLauncher), 100_000_000 ether);

        // Calculate the current tick based on sqrtPriceX96
        int24 tick = TickMath.getTickAtSqrtRatio(price);

        // Set tickLower and tickUpper to be around the current tick
        int24 tickSpacing = fameLauncher.getV3TickSpacing();
        int24 tickUpper = tick + 2 * tickSpacing;

        (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        ) = fameLauncher.createV3Liquidity(
                100_000_000 ether,
                0 ether,
                tickUpper,
                887220
            );

        assertEq(tokenId, 15896);
        assertEq(liquidity, 9567655433000195384683);
        assertEq(amount0, 99999999999999999999992903);
        assertEq(amount1, 0);

        assertEq(
            fame.balanceOf(address(fameLauncher.v3Pool())),
            99999999999999999999992903
        );
        assertEq(
            IERC20(0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9).balanceOf(
                address(fameLauncher.v3Pool())
            ),
            0 ether
        );
    }

    function test_LaunchV3Liquidity1Rest() public {
        uint160 price = sqrtPriceX96(8 ether, 888_000_000 ether);
        fameLauncher1.initializeV3Pool(price);
        fame1.transfer(address(fameLauncher1), 100_000_000 ether);

        // Calculate the current tick based on sqrtPriceX96
        int24 tick = TickMath.getTickAtSqrtRatio(price);

        // Set tickLower and tickUpper to be around the current tick
        int24 tickSpacing = fameLauncher1.getV3TickSpacing();
        int24 tickUpper = tick - 2 * tickSpacing;

        (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        ) = fameLauncher1.createV3Liquidity(
                0 ether,
                100_000_000 ether,
                -887220,
                tickUpper
            );

        assertEq(tokenId, 15896);
        assertEq(liquidity, 9567655433000195384683);
        assertEq(amount0, 0);
        assertEq(amount1, 99999999999999999999992912);

        assertEq(
            fame1.balanceOf(address(fameLauncher1.v3Pool())),
            99999999999999999999992912
        );
        assertEq(
            IERC20(0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9).balanceOf(
                address(fameLauncher1.v3Pool())
            ),
            0 ether
        );
    }

    function test_v3SwapTallSale() public {
        uint160 price = sqrtPriceX96(177_600_000 ether, 8.88 ether);
        fameLauncher.initializeV3Pool(price);
        // fame.transfer(address(fameLauncher), 100_000_000 ether);

        // Calculate the current tick based on sqrtPriceX96
        int24 tick = TickMath.getTickAtSqrtRatio(price);

        // Set tickLower and tickUpper to be around the current tick
        int24 tickSpacing = fameLauncher.getV3TickSpacing();
        int24 tickLower = tick + tickSpacing;
        int24 tickUpper = tick + 2 * tickSpacing;

        fame.transfer(address(fameLauncher), 100_000_000 ether);
        fameLauncher.createV3Liquidity(
            100_000_000 ether,
            0 ether,
            tickLower,
            tickUpper
        );

        fame.transfer(address(fameLauncher), 66_000_000 ether);
        fameLauncher.createV3Liquidity(
            66_000_000 ether,
            0 ether,
            tick + tickSpacing,
            887220
        );

        weth.deposit{value: 100 ether}();
        console.log(
            "Market Cap before swap: %s",
            toFixedPoint((sqrtPriceX96ToUint(price, 18) * 888_000_000), 18, 2)
        );
        // Create recipient
        address recipient = address(111);

        (int256 amount0, int256 amount1, uint160 afterPrice) = swapFor(
            recipient,
            false,
            1 ether
        );
        console.log(
            "Market Cap after: %sE. Received %sM fame",
            toFixedPoint(
                (sqrtPriceX96ToUint(afterPrice, 18) * 888_000_000),
                18,
                2
            ),
            toFixedPoint(uint256(uint256(-amount0)), 24, 2)
        );
        assertEq(amount0, -19807336199992096179662213);
        assertEq(amount1, 1000000000000000000);
        assertEq(IERC20(address(weth)).balanceOf(address(111)), 0);

        (amount0, , afterPrice) = swapFor(recipient, false, 1 ether);
        console.log(
            "Market Cap after: %sE. Received %sM fame",
            toFixedPoint(
                (sqrtPriceX96ToUint(afterPrice, 18) * 888_000_000),
                18,
                2
            ),
            toFixedPoint(uint256(uint256(-amount0)), 24, 2)
        );
        (amount0, , afterPrice) = swapFor(recipient, false, 1 ether);
        console.log(
            "Market Cap after: %sE. Received %sM fame",
            toFixedPoint(
                (sqrtPriceX96ToUint(afterPrice, 18) * 888_000_000),
                18,
                2
            ),
            toFixedPoint(uint256(uint256(-amount0)), 24, 2)
        );
        (amount0, , afterPrice) = swapFor(recipient, false, 1 ether);
        console.log(
            "Market Cap after: %sE. Received %sM fame",
            toFixedPoint(
                (sqrtPriceX96ToUint(afterPrice, 18) * 888_000_000),
                18,
                2
            ),
            toFixedPoint(uint256(uint256(-amount0)), 24, 2)
        );
        (amount0, , afterPrice) = swapFor(recipient, false, 1 ether);
        console.log(
            "Market Cap after: %sE. Received %sM fame",
            toFixedPoint(
                (sqrtPriceX96ToUint(afterPrice, 18) * 888_000_000),
                18,
                2
            ),
            toFixedPoint(uint256(uint256(-amount0)), 24, 2)
        );
        (amount0, , afterPrice) = swapFor(recipient, false, 1 ether);
        console.log(
            "Market Cap after: %sE. Received %sM fame",
            toFixedPoint(
                (sqrtPriceX96ToUint(afterPrice, 18) * 888_000_000),
                18,
                2
            ),
            toFixedPoint(uint256(uint256(-amount0)), 24, 2)
        );
        (amount0, , afterPrice) = swapFor(recipient, false, 1 ether);
    }

    function test_v3SwapWideSale() public {
        uint160 price = sqrtPriceX96(177_600_000 ether, 8.88 ether);
        fameLauncher.initializeV3Pool(price);
        // fame.transfer(address(fameLauncher), 100_000_000 ether);

        // Calculate the current tick based on sqrtPriceX96
        int24 tick = TickMath.getTickAtSqrtRatio(price);

        // Set tickLower and tickUpper to be around the current tick
        int24 tickSpacing = fameLauncher.getV3TickSpacing();

        fame.transfer(address(fameLauncher), 266_000_000 ether);
        fameLauncher.createV3Liquidity(
            266_000_000 ether,
            0 ether,
            tick + tickSpacing,
            887220
        );

        weth.deposit{value: 100 ether}();

        console.log(
            "Market Cap before swap: %s",
            toFixedPoint((sqrtPriceX96ToUint(price, 18) * 888_000_000), 18, 2)
        );
        // Create recipient
        address recipient = address(111);

        (int256 amount0, int256 amount1, uint160 afterPrice) = swapFor(
            recipient,
            false,
            1 ether
        );
        console.log(
            "Market Cap after: %sE. Received %sM fame",
            toFixedPoint(
                (sqrtPriceX96ToUint(afterPrice, 18) * 888_000_000),
                18,
                2
            ),
            toFixedPoint(uint256(uint256(-amount0)), 24, 2)
        );
        assertEq(amount0, -18444791069501469753412107);
        assertEq(amount1, 1000000000000000000);
        assertEq(IERC20(address(weth)).balanceOf(address(111)), 0);

        (amount0, , afterPrice) = swapFor(recipient, false, 1 ether);
        console.log(
            "Market Cap after: %sE. Received %sM fame",
            toFixedPoint(
                (sqrtPriceX96ToUint(afterPrice, 18) * 888_000_000),
                18,
                2
            ),
            toFixedPoint(uint256(uint256(-amount0)), 24, 2)
        );
        (amount0, , afterPrice) = swapFor(recipient, false, 1 ether);
        console.log(
            "Market Cap after: %sE. Received %sM fame",
            toFixedPoint(
                (sqrtPriceX96ToUint(afterPrice, 18) * 888_000_000),
                18,
                2
            ),
            toFixedPoint(uint256(uint256(-amount0)), 24, 2)
        );
        (amount0, , afterPrice) = swapFor(recipient, false, 1 ether);
        console.log(
            "Market Cap after: %sE. Received %sM fame",
            toFixedPoint(
                (sqrtPriceX96ToUint(afterPrice, 18) * 888_000_000),
                18,
                2
            ),
            toFixedPoint(uint256(uint256(-amount0)), 24, 2)
        );
        (amount0, , afterPrice) = swapFor(recipient, false, 1 ether);
        console.log(
            "Market Cap after: %sE. Received %sM fame",
            toFixedPoint(
                (sqrtPriceX96ToUint(afterPrice, 18) * 888_000_000),
                18,
                2
            ),
            toFixedPoint(uint256(uint256(-amount0)), 24, 2)
        );
        (amount0, , afterPrice) = swapFor(recipient, false, 1 ether);
        console.log(
            "Market Cap after: %sE. Received %sM fame",
            toFixedPoint(
                (sqrtPriceX96ToUint(afterPrice, 18) * 888_000_000),
                18,
                2
            ),
            toFixedPoint(uint256(uint256(-amount0)), 24, 2)
        );
        (amount0, , afterPrice) = swapFor(recipient, false, 1 ether);
    }

    function test_v3SSwapRouter() public {
        uint160 price = sqrtPriceX96(177_600_000 ether, 8.88 ether);
        fameLauncher.initializeV3Pool(price);
        // fame.transfer(address(fameLauncher), 100_000_000 ether);

        // Calculate the current tick based on sqrtPriceX96
        int24 tick = TickMath.getTickAtSqrtRatio(price);

        // Set tickLower and tickUpper to be around the current tick
        int24 tickSpacing = fameLauncher.getV3TickSpacing();
        int24 tickLower = tick + tickSpacing;
        int24 tickUpper = tick + 2 * tickSpacing;

        fame.transfer(address(fameLauncher), 100_000_000 ether);
        fameLauncher.createV3Liquidity(
            100_000_000 ether,
            0 ether,
            tickLower,
            tickUpper
        );

        fame.transfer(address(fameLauncher), 66_000_000 ether);
        fameLauncher.createV3Liquidity(
            66_000_000 ether,
            0 ether,
            tick + tickSpacing,
            887220
        );

        weth.deposit{value: 100 ether}();
        console.log(
            "Market Cap before swap: %s",
            toFixedPoint((sqrtPriceX96ToUint(price, 18) * 888_000_000), 18, 2)
        );
        // Create recipient
        address recipient = address(111);
        weth.transfer(recipient, 1 ether);
        vm.prank(recipient);
        IERC20(address(weth)).approve(address(swapRouter), 1 ether);

        ISwapRouter02.ExactInputSingleParams memory params = ISwapRouter02
            .ExactInputSingleParams({
                tokenIn: address(weth),
                tokenOut: address(fame),
                fee: 3000,
                recipient: recipient,
                amountIn: 1 ether,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        vm.prank(recipient);
        swapRouter.exactInputSingle(params);

        assertEq(IERC20(address(weth)).balanceOf(address(111)), 0);
        assertEq(fame.balanceOf(address(111)), 19807336199992096179662213);
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

    function getPriceToken0InToken1(
        uint160 _sqrtPriceX96
    ) public pure returns (uint256) {
        // Ensure sqrtPriceX96 is greater than zero
        require(_sqrtPriceX96 > 0, "sqrtPriceX96 must be greater than 0");

        // Convert sqrtPriceX96 to the price ratio using FullMath for precise division
        uint256 priceRatio = FullMath.mulDiv(
            uint256(_sqrtPriceX96),
            uint256(_sqrtPriceX96),
            FixedPoint96.Q96
        );

        // Ensure price ratio is greater than zero
        require(priceRatio > 0, "Price ratio must be greater than 0");

        // Calculate the price of token0 in terms of token1 using 1e18 for precision
        uint256 priceToken0InToken1 = FullMath.mulDiv(
            1,
            FixedPoint96.Q96,
            priceRatio
        );

        return priceToken0InToken1;
    }

    function calculateMarketCap(
        uint160 _sqrtPriceX96,
        uint256 totalSupplyToken0
    ) public pure returns (uint256 marketCapToken0InToken1) {
        uint256 priceToken0InToken1 = getPriceToken0InToken1(_sqrtPriceX96);

        // Calculate the market cap of token0 in terms of token1
        marketCapToken0InToken1 = priceToken0InToken1 * totalSupplyToken0;

        return marketCapToken0InToken1;
    }

    function getPrice(
        uint160 sqrtRatioX96,
        uint dec0,
        uint dec1
    ) external pure returns (uint256 price) {
        uint256 dec = dec1 <= dec0 ? (18 - dec1) + dec0 : dec0;
        uint256 numerator1 = uint256(sqrtRatioX96) * uint256(sqrtRatioX96);
        uint256 numerator2 = 10 ** dec;
        price = FullMath.mulDiv(numerator1, numerator2, 1 << 192);
    }

    function sqrtPriceX96ToUint(
        uint160 _sqrtPriceX96,
        uint8 decimalsToken0
    ) internal pure returns (uint256) {
        uint256 numerator1 = uint256(_sqrtPriceX96) * uint256(_sqrtPriceX96);
        uint256 numerator2 = 10 ** decimalsToken0;
        return FullMath.mulDiv(numerator1, numerator2, 1 << 192);
    }

    function uniswapV3SwapCallback(
        int256,
        int256 amount1Delta,
        bytes calldata
    ) external {
        IERC20(0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9).transferFrom(
            address(111),
            msg.sender,
            uint256(amount1Delta)
        );
    }

    /**
     * @dev Convert a uint256 to a fixed point string representation
     * @param value The value to convert
     * @param percision The integer percision
     * @param afterDecimals The number of digits after the decimal point
     * @return The fixed point string representation
     */
    function toFixedPoint(
        uint256 value,
        uint256 percision,
        uint256 afterDecimals
    ) public pure returns (string memory) {
        uint256 integer = value / 10 ** percision;
        uint256 fraction = value % 10 ** percision;
        // now trim the fraction to afterDecimals
        uint256 trimmed = fraction / 10 ** (percision - afterDecimals);
        uint256 length = Math.log10(trimmed) + 1;
        string memory trimemdStr = trimmed.toString();
        // padLeft with zeros
        for (uint256 i = 0; i < afterDecimals - length; i++) {
            trimemdStr = string(abi.encodePacked("0", trimemdStr));
        }
        return string(abi.encodePacked(integer.toString(), ".", trimemdStr));
    }

    function swapFor(
        address recipient,
        bool zeroForOne,
        int256 amount
    ) public returns (int256 amount0, int256 amount1, uint160 afterPrice) {
        IUniswapV3Pool pool = fameLauncher.v3Pool();
        bytes memory emptyBytes;

        if (!zeroForOne) {
            weth.deposit{value: uint256(amount)}();
            IERC20(address(weth)).transfer(recipient, uint256(amount));
            // approve as recipient
            vm.prank(recipient);
            IERC20(address(weth)).approve(address(this), uint256(amount));
        }

        (amount0, amount1) = pool.swap(
            recipient,
            zeroForOne,
            amount,
            zeroForOne
                ? TickMath.MIN_SQRT_RATIO + 1
                : TickMath.MAX_SQRT_RATIO - 1,
            emptyBytes
        );

        (afterPrice, , , , , , ) = pool.slot0();
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
