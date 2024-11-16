// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibString} from "solady/utils/LibString.sol";
import {ITokenURIGenerator} from "./ITokenURIGenerator.sol";

/**
 * @title FameSquadRemapper
 * @notice Moves tokens ids out of the way for the claim to fame musuem to be revealed
 */

contract ArtPatcherSept2024 is ITokenURIGenerator {
    using LibString for string;
    using LibString for uint256;

    ITokenURIGenerator public childRenderer;

    string constant URI =
        "https://gateway.irys.xyz/cdLU-LeBdJzpWnXeoaBAPaXn-2xeTbYFnktzoHtitmo/";

    constructor(address _childRenderer) {
        childRenderer = ITokenURIGenerator(_childRenderer);
    }

    /**
     * @dev Returns the URI for a given token ID
     */
    function tokenURI(
        uint256 tokenId
    ) external view override returns (string memory) {
        if (tokenId == 491) {
            return
                "https://gateway.irys.xyz/TVjZpV8PWOgVfQHdRRuJDaxQ8EL-KlvyU04YVCW7kNw";
        }
        return childRenderer.tokenURI(tokenId);
    }
}
