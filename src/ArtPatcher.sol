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

contract ArtPatcher is ITokenURIGenerator {
    using LibString for string;

    ITokenURIGenerator public childRenderer;

    string constant URI = "https://gateway.irys.xyz/pVCz-f3gIsy1VH9fl1S6CCKM-eL40l_0W9Z2PFwpD9w/";

    constructor(address _childRenderer) {
        childRenderer = ITokenURIGenerator(_childRenderer);
    }

    /**
     * @dev Returns the URI for a given token ID
     */
    function tokenURI(
        uint256 tokenId
    ) external view override returns (string memory) {
        if (tokenId == 85) {
            return URI.concat("85.json");
        } else if (tokenId == 189) {
            return URI.concat("189.json");
        } else if (tokenId == 215) {
            return URI.concat("215.json");
        }
        return childRenderer.tokenURI(tokenId);
    }
}
