// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {FameMarketplaceCheckout} from "../../src/FameMarketplaceCheckout.sol";
import {FameRouterTypes} from "../../src/router/FameRouterTypes.sol";
import {MockERC20} from "../router/mocks/MockERC20.sol";

contract ReentrantFameMarketplaceCheckoutToken is MockERC20 {
    FameMarketplaceCheckout public checkout;
    FameRouterTypes.Route private _route;
    uint256 private _shellId;
    bytes32 private _artwork;
    uint256 private _maxPremium;

    bool public attemptedReentry;
    bool public blockedByGuard;

    constructor() MockERC20("Reentrant Checkout Token", "REENT", 18) {}

    function arm(
        FameMarketplaceCheckout checkout_,
        FameRouterTypes.Route calldata route_,
        uint256 shellId_,
        bytes32 artwork_,
        uint256 maxPremium_
    ) external {
        checkout = checkout_;
        _route.version = route_.version;
        _route.tokenIn = route_.tokenIn;
        _route.tokenOut = route_.tokenOut;
        _route.amountIn = route_.amountIn;
        _route.minAmountOutAfterFee = route_.minAmountOutAfterFee;
        _route.recipient = route_.recipient;
        _route.deadline = route_.deadline;
        delete _route.legs;
        for (uint256 i; i < route_.legs.length; ++i) {
            _route.legs.push(route_.legs[i]);
        }
        _shellId = shellId_;
        _artwork = artwork_;
        _maxPremium = maxPremium_;
    }

    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        if (!attemptedReentry && msg.sender == address(checkout)) {
            attemptedReentry = true;
            try checkout.checkoutHeld(_route, _shellId, _artwork, _maxPremium, 1) {
                revert("REENTRY_SUCCEEDED");
            } catch (bytes memory reason) {
                if (reason.length != 4 || bytes4(reason) != 0xab143c06) revert("WRONG_REENTRY_REVERT");
                blockedByGuard = true;
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
