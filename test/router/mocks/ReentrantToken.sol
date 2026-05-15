// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FameRouter} from "../../../src/FameRouter.sol";
import {FameRouterTypes} from "../../../src/router/FameRouterTypes.sol";
import {MockERC20} from "./MockERC20.sol";

contract ReentrantToken is MockERC20 {
    FameRouter public router;
    FameRouterTypes.Route private route;
    bool public attemptedReentry;
    bool public bubbleReentryFailure;

    constructor() MockERC20("Reentrant Token", "REENT", 18) {}

    function arm(FameRouter router_, FameRouterTypes.Route calldata route_) external {
        router = router_;
        route.version = route_.version;
        route.tokenIn = route_.tokenIn;
        route.tokenOut = route_.tokenOut;
        route.amountIn = route_.amountIn;
        route.minAmountOutAfterFee = route_.minAmountOutAfterFee;
        route.recipient = route_.recipient;
        route.deadline = route_.deadline;

        delete route.legs;
        for (uint256 i; i < route_.legs.length; ++i) {
            route.legs.push(route_.legs[i]);
        }
    }

    function setBubbleReentryFailure(bool bubble) external {
        bubbleReentryFailure = bubble;
    }

    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        if (!attemptedReentry && address(router) != address(0)) {
            attemptedReentry = true;
            try router.executeRoute(route) returns (uint256) {
                revert("REENTRY_SUCCEEDED");
            } catch (bytes memory reason) {
                if (bubbleReentryFailure) {
                    assembly {
                        revert(add(reason, 0x20), mload(reason))
                    }
                }
                if (reason.length != 4 || bytes4(reason) != 0xab143c06) revert("WRONG_REENTRY_REVERT");
            }
        }

        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            require(allowed >= amount, "ALLOWANCE");
            allowance[from][msg.sender] = allowed - amount;
        }
        _transfer(from, to, amount);
        return true;
    }
}
