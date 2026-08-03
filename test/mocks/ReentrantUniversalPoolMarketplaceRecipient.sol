// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC721Receiver} from "@openzeppelin5/contracts/token/ERC721/IERC721Receiver.sol";
import {UniversalPoolArtMarketplace} from "../../src/UniversalPoolArtMarketplace.sol";
import {FameMirror} from "../../src/FameMirror.sol";
import {Fame} from "../../src/Fame.sol";

contract ReentrantUniversalPoolMarketplaceRecipient {
    enum Action {
        None,
        ReenterPurchase,
        SetPremium,
        SetAuthorizedCheckout,
        TransferOwnership,
        Forward,
        Reject,
        ReenterWithdrawal
    }

    UniversalPoolArtMarketplace public market;
    Action public action;
    address public forwardTo;
    bytes32 public expectedArtworkHash;
    uint256 public observedTokenId;
    bytes32 public observedArtworkHash;
    bool public attemptedActionSucceeded;
    bytes public attemptedActionRevertData;

    function configure(
        UniversalPoolArtMarketplace market_,
        Action action_,
        address forwardTo_,
        bytes32 expectedArtworkHash_
    ) external {
        market = market_;
        action = action_;
        forwardTo = forwardTo_;
        expectedArtworkHash = expectedArtworkHash_;
        observedTokenId = 0;
        observedArtworkHash = bytes32(0);
        attemptedActionSucceeded = false;
        delete attemptedActionRevertData;
    }

    function deposit(FameMirror mirror, UniversalPoolArtMarketplace market_, uint256 tokenId) external {
        mirror.approve(address(market_), tokenId);
        market_.depositInventory(tokenId);
    }

    function setSkipNFT(Fame fame, bool status) external {
        fame.setSkipNFT(status);
    }

    function withdrawFree() external returns (uint256 tokenId) {
        return market.withdrawInventory();
    }

    function withdrawSelected(Fame fame, uint256 tokenId, uint256 maxPremium) external {
        fame.approve(address(market), maxPremium);
        market.withdrawInventorySelected(tokenId, maxPremium);
    }

    function onERC721Received(address, address, uint256 tokenId, bytes calldata) external returns (bytes4) {
        observedTokenId = tokenId;
        observedArtworkHash = market.artworkHash(tokenId);

        if (action == Action.ReenterPurchase) {
            try market.purchaseHeld(tokenId, expectedArtworkHash, type(uint256).max, 0, address(this)) {
                attemptedActionSucceeded = true;
            } catch (bytes memory reason) {
                attemptedActionRevertData = reason;
            }
        } else if (action == Action.SetPremium) {
            try market.setCommunityFee(1) {
                attemptedActionSucceeded = true;
            } catch (bytes memory reason) {
                attemptedActionRevertData = reason;
            }
        } else if (action == Action.SetAuthorizedCheckout) {
            try market.setAuthorizedCheckout(forwardTo) {
                attemptedActionSucceeded = true;
            } catch (bytes memory reason) {
                attemptedActionRevertData = reason;
            }
        } else if (action == Action.TransferOwnership) {
            try market.transferOwnership(forwardTo) {
                attemptedActionSucceeded = true;
            } catch (bytes memory reason) {
                attemptedActionRevertData = reason;
            }
        } else if (action == Action.Forward) {
            FameMirror(payable(msg.sender)).safeTransferFrom(address(this), forwardTo, tokenId);
        } else if (action == Action.Reject) {
            return bytes4(0);
        } else if (action == Action.ReenterWithdrawal) {
            try market.withdrawInventory() {
                attemptedActionSucceeded = true;
            } catch (bytes memory reason) {
                attemptedActionRevertData = reason;
            }
        }

        return IERC721Receiver.onERC721Received.selector;
    }
}
