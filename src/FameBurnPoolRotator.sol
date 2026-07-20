// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Fame} from "./Fame.sol";
import {FameMirror} from "./FameMirror.sol";

/// @notice Exchanges one Society NFT for a requested token from FAME's FIFO
/// burn pool.
contract FameBurnPoolRotator {
    Fame public immutable fame;
    FameMirror public immutable mirror;

    error TargetNotReached();

    constructor(Fame fame_) {
        fame = fame_;
        mirror = fame_.fameMirror();
    }

    function rotateTo(uint256 offeredId, uint256 targetId, uint256 maxRotations, address recipient) external {
        mirror.transferFrom(msg.sender, address(this), offeredId);

        for (uint256 i; i < maxRotations; ++i) {
            fame.setSkipNFT(true);
            fame.transfer(address(this), 1);

            fame.setSkipNFT(false);
            fame.transfer(address(this), 1);

            if (mirror.ownerAt(targetId) == address(this)) {
                mirror.safeTransferFrom(address(this), recipient, targetId);
                return;
            }
        }

        revert TargetNotReached();
    }
}
