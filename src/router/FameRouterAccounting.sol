// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FameRouterTypes} from "./FameRouterTypes.sol";

library FameRouterAccounting {
    error BalanceBpsTooHigh(uint256 bps);
    error InsufficientRouteBalance(address token, uint256 requested, uint256 available);
    error ZeroSpend(address token);

    function spendAmount(FameRouterTypes.AmountMode mode, uint256 amount, uint256 available, address token)
        internal
        pure
        returns (uint256 spend)
    {
        if (mode == FameRouterTypes.AmountMode.Exact) {
            spend = amount;
        } else if (mode == FameRouterTypes.AmountMode.BalanceBps) {
            if (amount > FameRouterTypes.BPS_DENOMINATOR) {
                revert BalanceBpsTooHigh(amount);
            }
            spend = (available * amount) / FameRouterTypes.BPS_DENOMINATOR;
        } else {
            spend = available;
        }

        if (spend == 0) revert ZeroSpend(token);
        if (spend > available) revert InsufficientRouteBalance(token, spend, available);
    }

    function feeAmount(uint256 amountOut, uint32 feePpm) internal pure returns (uint256) {
        return (amountOut * feePpm) / FameRouterTypes.FEE_DENOMINATOR;
    }
}
