// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibString} from "solady/utils/LibString.sol";
import {LibBitmap} from "solady/utils/LibBitmap.sol";
import {OwnableRoles} from "solady/auth/OwnableRoles.sol";
import {ITokenURIGenerator} from "./ITokenURIGenerator.sol";
import "forge-std/console.sol";

interface ITokemEmitable {
    function emitBatchMetadataUpdate(uint256 start, uint256 end) external;
    function emitMetadataUpdate(uint256 tokenId) external;
}

/**
 * @title FameSquadRemapper
 * @notice Moves tokens ids out of the way for the claim to fame musuem to be revealed
 */

contract FameSquadRemapper is OwnableRoles, ITokenURIGenerator {
    using LibBitmap for LibBitmap.Bitmap;
    using LibString for uint256;
    using LibString for string;

    ITokenURIGenerator public childRenderer;
    ITokemEmitable public emitable;

    uint256 constant METADATA_UPDATER = _ROLE_0;
    uint256 constant METADAT_EMIT = _ROLE_1;

    constructor(address emitableAddress, address _childRenderer) {
        emitable = ITokemEmitable(emitableAddress);
        childRenderer = ITokenURIGenerator(_childRenderer);
        _initializeOwner(msg.sender);
        _grantRoles(msg.sender, METADATA_UPDATER);
    }

    /**
     * @dev Returns the URI for a given token ID
     */
    function tokenURI(
        uint256 tokenId
    ) external view override returns (string memory) {
        // remap token ids 420 -> 488 to 265 -> 333
        if (tokenId >= 420 && tokenId <= 488) {
            return childRenderer.tokenURI(tokenId - 155);
        }
        // remap token ids 265 -> 419 to 733 -> 888
        if (tokenId >= 265 && tokenId <= 419) {
            return childRenderer.tokenURI(tokenId + 469);
        }
        // remap token ids 733 -> 888 to  265 -> 419
        if (tokenId >= 734 && tokenId <= 888) {
            return childRenderer.tokenURI(tokenId - 469);
        }
        return childRenderer.tokenURI(tokenId);
    }
}
