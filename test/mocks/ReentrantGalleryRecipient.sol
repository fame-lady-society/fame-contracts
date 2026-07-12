// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ClosedLoopGallerySwap} from "../../src/ClosedLoopGallerySwap.sol";

contract ReentrantGalleryRecipient {
    bytes4 private constant ERC721_RECEIVED = 0x150b7a02;

    enum Attack {
        None,
        Fill,
        List,
        Unlist,
        SetPremium,
        RotateArt,
        SetFeeRecipient,
        GrantOperatorRole,
        TransferOwnership,
        WithdrawFees,
        RescueERC721
    }

    ClosedLoopGallerySwap public gallery;
    Attack public attack;
    uint256 public tokenId;
    uint256 public premium;
    address public feeRecipient;
    bool public attackSucceeded;
    bytes public attackRevertData;

    function configure(
        ClosedLoopGallerySwap gallery_,
        Attack attack_,
        uint256 tokenId_,
        uint256 premium_,
        address feeRecipient_
    ) external {
        gallery = gallery_;
        attack = attack_;
        tokenId = tokenId_;
        premium = premium_;
        feeRecipient = feeRecipient_;
        attackSucceeded = false;
        delete attackRevertData;
    }

    function onERC721Received(address, address, uint256 receivedTokenId, bytes calldata) external returns (bytes4) {
        if (attack == Attack.None) return ERC721_RECEIVED;

        if (attack == Attack.Fill) {
            try gallery.fill(tokenId, address(this)) {
                attackSucceeded = true;
            } catch (bytes memory reason) {
                attackRevertData = reason;
            }
        } else if (attack == Attack.List) {
            try gallery.list(receivedTokenId, premium) {
                attackSucceeded = true;
            } catch (bytes memory reason) {
                attackRevertData = reason;
            }
        } else if (attack == Attack.Unlist) {
            try gallery.unlist(tokenId) {
                attackSucceeded = true;
            } catch (bytes memory reason) {
                attackRevertData = reason;
            }
        } else if (attack == Attack.SetPremium) {
            try gallery.setPremium(tokenId, premium) {
                attackSucceeded = true;
            } catch (bytes memory reason) {
                attackRevertData = reason;
            }
        } else if (attack == Attack.RotateArt) {
            try gallery.rotateToArtPool(tokenId, "reentrant-metadata") {
                attackSucceeded = true;
            } catch (bytes memory reason) {
                attackRevertData = reason;
            }
        } else if (attack == Attack.SetFeeRecipient) {
            try gallery.setFeeRecipient(feeRecipient) {
                attackSucceeded = true;
            } catch (bytes memory reason) {
                attackRevertData = reason;
            }
        } else if (attack == Attack.GrantOperatorRole) {
            try gallery.grantRoles(feeRecipient, gallery.roleOperator()) {
                attackSucceeded = true;
            } catch (bytes memory reason) {
                attackRevertData = reason;
            }
        } else if (attack == Attack.TransferOwnership) {
            try gallery.transferOwnership(feeRecipient) {
                attackSucceeded = true;
            } catch (bytes memory reason) {
                attackRevertData = reason;
            }
        } else if (attack == Attack.WithdrawFees) {
            try gallery.withdrawAccruedFees(feeRecipient, premium) {
                attackSucceeded = true;
            } catch (bytes memory reason) {
                attackRevertData = reason;
            }
        } else if (attack == Attack.RescueERC721) {
            try gallery.rescueERC721(msg.sender, feeRecipient, receivedTokenId) {
                attackSucceeded = true;
            } catch (bytes memory reason) {
                attackRevertData = reason;
            }
        }

        return ERC721_RECEIVED;
    }
}
