// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IUniswapV2Router02} from "../../src/router/interfaces/IUniswapV2Router02.sol";

interface IERC20VenueAsset {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

contract PrefundedFameRouterVenue is IUniswapV2Router02 {
    uint256[] private _queuedOutputs;
    uint256 private _nextOutput;

    error NoQueuedOutput();
    error OutputBelowMinimum(uint256 output, uint256 minimum);
    error TransferFailed(address token);

    function queueOutput(uint256 amountOut) external {
        _queuedOutputs.push(amountOut);
    }

    function nextOutputIndex() external view returns (uint256) {
        return _nextOutput;
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256
    ) external returns (uint256[] memory amounts) {
        if (_nextOutput >= _queuedOutputs.length) revert NoQueuedOutput();
        uint256 amountOut = _queuedOutputs[_nextOutput++];
        if (amountOut < amountOutMin) revert OutputBelowMinimum(amountOut, amountOutMin);

        if (!IERC20VenueAsset(path[0]).transferFrom(msg.sender, address(this), amountIn)) {
            revert TransferFailed(path[0]);
        }
        if (!IERC20VenueAsset(path[path.length - 1]).transfer(to, amountOut)) {
            revert TransferFailed(path[path.length - 1]);
        }

        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        amounts[amounts.length - 1] = amountOut;
    }
}

contract ForceNativeDonation {
    constructor() payable {}

    function donate(address payable recipient) external {
        selfdestruct(recipient);
    }
}
