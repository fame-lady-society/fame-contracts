// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {FameMarketplaceCheckout} from "../../src/FameMarketplaceCheckout.sol";
import {Fame} from "../../src/Fame.sol";
import {FameRouterTypes} from "../../src/router/FameRouterTypes.sol";
import {MockERC20} from "../router/mocks/MockERC20.sol";
import {IERC721Receiver} from "@openzeppelin5/contracts/token/ERC721/IERC721Receiver.sol";

interface IERC20CheckoutAccountingMock {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/// @dev Router fault double that transfers the measured output but reports a different value.
contract MismatchedOutputCheckoutRouter {
    Fame public immutable fame;
    address public immutable feeRecipient;
    uint256 public immutable actualOutput;
    uint256 public immutable reportedOutput;
    uint256 public executionCount;

    constructor(Fame fame_, address feeRecipient_, uint256 actualOutput_, uint256 reportedOutput_) {
        fame = fame_;
        feeRecipient = feeRecipient_;
        actualOutput = actualOutput_;
        reportedOutput = reportedOutput_;
    }

    function executeRoute(FameRouterTypes.Route calldata route) external payable returns (uint256) {
        ++executionCount;
        if (route.tokenIn != FameRouterTypes.NATIVE_ETH) {
            IERC20CheckoutAccountingMock(route.tokenIn).transferFrom(msg.sender, address(this), route.amountIn);
        }
        fame.transfer(route.recipient, actualOutput);
        return reportedOutput;
    }
}

/// @dev Returns success while retaining checkout's attempted refund.
contract StickyCheckoutRefundToken is MockERC20 {
    address public checkout;

    constructor() MockERC20("Sticky Refund", "STICK", 6) {}

    function setCheckout(address checkout_) external {
        checkout = checkout_;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        if (msg.sender == checkout) {
            emit Transfer(msg.sender, to, amount);
            return true;
        }
        return super.transfer(to, amount);
    }
}

/// @dev Donates FAME during the input-refund leg so final FAME accounting diverges.
contract FameDonatingCheckoutRefundToken is MockERC20 {
    Fame public immutable fame;
    address public checkout;
    uint256 public donation;

    constructor(Fame fame_) MockERC20("FAME Hook Refund", "HOOK", 6) {
        fame = fame_;
    }

    function arm(address checkout_, uint256 donation_) external {
        checkout = checkout_;
        donation = donation_;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        bool success = super.transfer(to, amount);
        if (msg.sender == checkout && donation != 0) fame.transfer(checkout, donation);
        return success;
    }
}

/// @dev Donates FAME back to checkout while receiving the purchased shell.
contract FameDonatingShellRecipient is IERC721Receiver {
    Fame public immutable fame;
    address public checkout;
    uint256 public donation;

    constructor(Fame fame_) {
        fame = fame_;
    }

    function arm(address checkout_, uint256 donation_) external {
        checkout = checkout_;
        donation = donation_;
    }

    function onERC721Received(address, address, uint256, bytes calldata) external returns (bytes4) {
        fame.transfer(checkout, donation);
        return IERC721Receiver.onERC721Received.selector;
    }
}

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
