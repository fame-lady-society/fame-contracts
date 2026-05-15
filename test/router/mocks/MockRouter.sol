// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FameRouter} from "../../../src/FameRouter.sol";
import {FameRouterTypes} from "../../../src/router/FameRouterTypes.sol";
import {UniversalRouterAdapter} from "../../../src/router/adapters/UniversalRouterAdapter.sol";
import {IAerodromeV2Router} from "../../../src/router/interfaces/IAerodromeV2Router.sol";
import {IUniversalRouter} from "../../../src/router/interfaces/IUniversalRouter.sol";
import {ISlipstreamRouter} from "../../../src/router/interfaces/ISlipstreamRouter.sol";
import {ISolidlyRouter} from "../../../src/router/interfaces/ISolidlyRouter.sol";
import {IUniswapV2Router02} from "../../../src/router/interfaces/IUniswapV2Router02.sol";
import {MockERC20} from "./MockERC20.sol";

interface IMockPermit2 {
    function transferFrom(address from, address to, uint160 amount, address token) external;
}

contract MockRouter is IUniswapV2Router02, ISolidlyRouter, IAerodromeV2Router, ISlipstreamRouter, IUniversalRouter {
    error BadNativeInput(uint256 expected, uint256 actual);
    error NoQueuedOutput();

    address internal constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    uint256[] private queuedOutputs;
    uint256 private nextOutputIndex;
    bytes public lastV4HookData;

    receive() external payable {}

    function factory() external pure returns (address) {
        return address(0xFAc707);
    }

    function queueOutput(uint256 amountOut) external {
        queuedOutputs.push(amountOut);
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256
    ) external returns (uint256[] memory amounts) {
        MockERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        uint256 amountOut = _consumeOutput(amountOutMin);
        MockERC20(path[path.length - 1]).mint(to, amountOut);

        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        amounts[path.length - 1] = amountOut;
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        ISolidlyRouter.Route[] calldata routes,
        address to,
        uint256
    ) external returns (uint256[] memory amounts) {
        MockERC20(routes[0].from).transferFrom(msg.sender, address(this), amountIn);
        uint256 amountOut = _consumeOutput(amountOutMin);
        MockERC20(routes[routes.length - 1].to).mint(to, amountOut);

        amounts = new uint256[](routes.length + 1);
        amounts[0] = amountIn;
        amounts[amounts.length - 1] = amountOut;
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        IAerodromeV2Router.AerodromeRoute[] calldata routes,
        address to,
        uint256
    ) external returns (uint256[] memory amounts) {
        MockERC20(routes[0].from).transferFrom(msg.sender, address(this), amountIn);
        uint256 amountOut = _consumeOutput(amountOutMin);
        MockERC20(routes[routes.length - 1].to).mint(to, amountOut);

        amounts = new uint256[](routes.length + 1);
        amounts[0] = amountIn;
        amounts[amounts.length - 1] = amountOut;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut) {
        MockERC20(params.tokenIn).transferFrom(msg.sender, address(this), params.amountIn);
        amountOut = _consumeOutput(params.amountOutMinimum);
        MockERC20(params.tokenOut).mint(params.recipient, amountOut);
    }

    function execute(bytes calldata commands, bytes[] calldata inputs, uint256) external payable {
        if (commands[0] == 0x10) {
            _executeV4(inputs[0]);
            return;
        }

        (address recipient, uint256 amountIn, uint256 amountOutMin, bytes memory path,) =
            abi.decode(inputs[0], (address, uint256, uint256, bytes, bool));
        address tokenIn = _addressAt(path, 0);
        address tokenOut = _addressAt(path, path.length - 20);

        if (tokenIn == FameRouterTypes.NATIVE_ETH) {
            if (msg.value != amountIn) revert BadNativeInput(amountIn, msg.value);
        } else {
            IMockPermit2(PERMIT2).transferFrom(msg.sender, address(this), uint160(amountIn), tokenIn);
        }

        uint256 amountOut = _consumeOutput(amountOutMin);
        if (tokenOut == FameRouterTypes.NATIVE_ETH) {
            payable(recipient).transfer(amountOut);
        } else {
            MockERC20(tokenOut).mint(recipient, amountOut);
        }
    }

    function _executeV4(bytes calldata input) private {
        (, bytes[] memory params) = abi.decode(input, (bytes, bytes[]));
        UniversalRouterAdapter.V4ExactInputSingleParams memory swapParams =
            abi.decode(params[0], (UniversalRouterAdapter.V4ExactInputSingleParams));
        lastV4HookData = swapParams.hookData;
        (address settleCurrency,) = abi.decode(params[1], (address, uint256));
        (address takeCurrency,) = abi.decode(params[2], (address, uint256));
        address tokenIn = swapParams.zeroForOne ? swapParams.poolKey.currency0 : swapParams.poolKey.currency1;
        address tokenOut = swapParams.zeroForOne ? swapParams.poolKey.currency1 : swapParams.poolKey.currency0;
        require(settleCurrency == tokenIn && takeCurrency == tokenOut, "BAD_V4_PARAMS");
        address recipient = msg.sender;

        if (tokenIn == FameRouterTypes.NATIVE_ETH) {
            if (msg.value != swapParams.amountIn) revert BadNativeInput(swapParams.amountIn, msg.value);
        } else {
            IMockPermit2(PERMIT2).transferFrom(msg.sender, address(this), swapParams.amountIn, tokenIn);
        }

        uint256 amountOut = _consumeOutput(swapParams.amountOutMinimum);
        if (tokenOut == FameRouterTypes.NATIVE_ETH) {
            payable(recipient).transfer(amountOut);
        } else {
            MockERC20(tokenOut).mint(recipient, amountOut);
        }
    }

    function _consumeOutput(uint256) private returns (uint256 amountOut) {
        if (nextOutputIndex >= queuedOutputs.length) revert NoQueuedOutput();
        amountOut = queuedOutputs[nextOutputIndex++];
    }

    function _addressAt(bytes memory data, uint256 offset) private pure returns (address value) {
        assembly {
            value := shr(96, mload(add(add(data, 0x20), offset)))
        }
    }
}

contract MockPermit2 {
    mapping(address => mapping(address => mapping(address => uint160))) public allowance;

    function approve(address token, address spender, uint160 amount, uint48) external {
        allowance[msg.sender][token][spender] = amount;
    }

    function transferFrom(address from, address to, uint160 amount, address token) external {
        MockERC20(token).transferFrom(from, to, amount);
    }
}

contract RescueAttemptingRouter is IUniswapV2Router02 {
    FameRouter public immutable router;

    constructor(address feeRecipient) {
        router = new FameRouter(feeRecipient);
    }

    receive() external payable {}

    function configure() external {
        router.setVenueFamilyEnabled(FameRouterTypes.VenueFamily.UniswapV2, true);
        router.setVenueTargetEnabled(FameRouterTypes.VenueFamily.UniswapV2, address(this), true);
    }

    function swapExactTokensForTokens(uint256, uint256, address[] calldata path, address, uint256)
        external
        returns (uint256[] memory amounts)
    {
        router.rescue(path[0], address(this), 1);
        amounts = new uint256[](path.length);
    }
}
