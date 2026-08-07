// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {FameMarketplaceCheckout} from "../../src/FameMarketplaceCheckout.sol";
import {FameRouterTypes} from "../../src/router/FameRouterTypes.sol";
import {MockERC20} from "../router/mocks/MockERC20.sol";

/// @dev UniswapV2-style venue that reenters redeemSociety mid-swap.
contract ReentrantRedeemVenue {
    FameMarketplaceCheckout public checkout;
    FameRouterTypes.Route private _route;
    uint256[] private _tokenIds;
    uint256 public amountOut;
    bool public attemptedReentry;
    bool public blockedByGuard;

    error NoOutput();
    error TransferFailed();

    function arm(
        FameMarketplaceCheckout checkout_,
        FameRouterTypes.Route calldata route_,
        uint256[] calldata tokenIds_,
        uint256 amountOut_
    ) external {
        checkout = checkout_;
        _route = route_;
        delete _tokenIds;
        for (uint256 i; i < tokenIds_.length; ++i) {
            _tokenIds.push(tokenIds_[i]);
        }
        amountOut = amountOut_;
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256
    ) external returns (uint256[] memory amounts) {
        if (!attemptedReentry) {
            attemptedReentry = true;
            try checkout.redeemSociety(_route, _tokenIds) {
                revert("REDEEM_REENTRY_SUCCEEDED");
            } catch (bytes memory reason) {
                if (reason.length != 4 || bytes4(reason) != 0xab143c06) revert("WRONG_REENTRY_REVERT");
                blockedByGuard = true;
            }
        }

        if (amountOut < amountOutMin) revert NoOutput();
        if (!MockERC20(path[0]).transferFrom(msg.sender, address(this), amountIn)) revert TransferFailed();
        if (!MockERC20(path[path.length - 1]).transfer(to, amountOut)) revert TransferFailed();

        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        amounts[amounts.length - 1] = amountOut;
    }
}
