// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibMap} from "solady/utils/LibMap.sol";
import {LibString} from "solady/utils/LibString.sol";
import {LibBitmap} from "solady/utils/LibBitmap.sol";
import {OwnableRoles} from "solady/auth/OwnableRoles.sol";
import {ITokenURIGenerator} from "./ITokenURIGenerator.sol";
import {ITokenEmitable} from "./ITokenEmitable.sol";
import {Fame} from "./Fame.sol";
import {FameMirror} from "./FameMirror.sol";

/**
 * @title CreatorArtistMagic
 * @notice A contract that allows creators to manage token metadata by banishing tokens between different pools
 * @dev This contract implements a robust metadata management system with four distinct pools:
 *
 * **Art Pool** (tokenId 265-419):
 *   - Purpose: Explicitly managed pool for custom metadata swapping
 *   - State: Locked tokens that cannot be minted/burned
 *   - Operations: banishToArtPool() consumes art pool slots by incrementing artPoolNextIndex
 *
 * **Burn Pool**:
 *   - Purpose: Tokens that were minted but then burned
 *   - Criteria: ownerOf(tokenId) reverts + tokenId <= totalNFTSupply + not in art pool
 *   - Operations: banishToBurnPool() swaps metadata with burned tokens
 *
 * **Mint Pool**:
 *   - Purpose: Tokens with metadata that were never minted, available for swapping
 *   - Criteria: ownerOf(tokenId) reverts + tokenId > totalNFTSupply + tokenId < nextTokenId + not in art pool
 *   - Operations: banishToMintPool() swaps metadata with unminted tokens
 *
 * **End of Mint Pool**:
 *   - Purpose: Unrevealed metadata slots that can be consumed to create new metadata
 *   - Criteria: tokenId >= nextTokenId + ownerOf(tokenId) reverts + not in art pool
 *   - Operations: banishToEndOfMintPool() consumes by incrementing nextTokenId
 *
 * The contract uses ownerOf() revert patterns to detect token states without requiring
 * direct access to Fame contract's internal DN404 storage.
 */
contract CreatorArtistMagic is
    OwnableRoles,
    ITokenURIGenerator,
    ITokenEmitable
{
    using LibString for uint256;
    using LibString for string;
    using LibMap for LibMap.Uint16Map;

    uint256 internal constant RENDERER = _ROLE_0;
    uint256 internal constant CREATOR = _ROLE_1;
    uint256 internal constant BANISHER = _ROLE_2;
    uint256 internal constant ART_POOL_MANAGER = _ROLE_3;
    uint256 internal constant ART_POOL_START_INDEX = 265;
    uint256 internal constant ART_POOL_END_INDEX = 419;

    uint256 private artPoolNextIndex = ART_POOL_START_INDEX + 1;

    ITokenURIGenerator public childRenderer;
    // Interface to immutable Fame DN404 contract for token state queries
    Fame public fame;

    // Metadata registry design for robust swap-of-swaps
    // tokenId => metadataId (the swap layer)
    LibMap.Uint16Map internal tokenMetadata;
    // metadataId => metadata (the storage layer)
    mapping(uint256 => string) public metadataRegistry;

    // Metadata ID counter
    uint16 private nextMetadataId = 1;

    // Boundary between Mint Pool and End of Mint Pool
    // Tokens >= nextTokenId are in End of Mint Pool (unrevealed)
    // Tokens < nextTokenId (but > totalNFTSupply) are in Mint Pool (revealed but unminted)
    uint16 public nextTokenId;

    error TokenNotOwned();
    error InvalidTokenId();
    error InvalidMetadata();
    error ArtPoolFull();
    error MintPoolFull();
    error TokenNotInMintPool();
    error TokenNotInBurnPool();

    /**
     * @notice Constructor to initialize the contract
     * @param _childRenderer Address of the child renderer contract that provides metadata for revealed tokens
     * @param _fame Address of the Fame DN404 contract (immutable)
     * @param _nextTokenId Starting token ID where unrevealed metadata begins (End of Mint Pool start)
     *                     This defines the boundary between Mint Pool (< nextTokenId) and End of Mint Pool (>= nextTokenId)
     *                     Expected: childRenderer already contains revealed tokens (excluding art pool 265-419)
     *                     and nextTokenId marks where unrevealed/default metadata starts
     */
    constructor(
        address _childRenderer,
        address payable _fame,
        uint16 _nextTokenId
    ) {
        childRenderer = ITokenURIGenerator(_childRenderer);
        fame = Fame(_fame);
        nextTokenId = _nextTokenId;
        _initializeOwner(msg.sender);
        _grantRoles(_childRenderer, RENDERER);
    }

    /**
     * @notice Get or create a metadata ID for a token
     * @dev If token already has a metadataId, return it. Otherwise create new one from childRenderer
     * @param tokenId The token ID to get metadata ID for
     * @return The metadata ID for this token
     */
    function _getOrCreateMetadataId(uint256 tokenId) internal returns (uint16) {
        uint16 existingMetadataId = tokenMetadata.get(tokenId);
        if (existingMetadataId != 0) {
            return existingMetadataId;
        }

        // Create new metadata ID and store current metadata
        uint16 newMetadataId = nextMetadataId++;
        string memory currentMetadata = childRenderer.tokenURI(tokenId);
        metadataRegistry[newMetadataId] = currentMetadata;
        tokenMetadata.set(tokenId, newMetadataId);

        return newMetadataId;
    }

    /**
     * @notice Banish a token's metadata to the Art Pool and assign new custom metadata
     * @dev Consumes an Art Pool slot (265-419) by incrementing artPoolNextIndex
     * @dev Original metadata is preserved in registry, new custom metadata assigned to token
     * @dev Art Pool contains locked tokens that cannot be minted/burned
     * @param tokenIdToUpdate The token ID owned by CREATOR to update
     * @param newMetadataUrl The new custom metadata URL to assign
     */
    function banishToArtPool(
        uint256 tokenIdToUpdate,
        string memory newMetadataUrl
    ) external onlyRoles(ART_POOL_MANAGER | CREATOR) {
        // Require non-empty metadata URL
        if (bytes(newMetadataUrl).length == 0) {
            revert InvalidMetadata();
        }

        FameMirror mirror = fame.fameMirror();

        // Verify ART_POOL_MANAGER owns the token
        if (mirror.ownerOf(tokenIdToUpdate) != msg.sender) {
            revert TokenNotOwned();
        }

        // Check if art pool has room
        if (artPoolNextIndex > ART_POOL_END_INDEX) {
            revert ArtPoolFull();
        }

        // Get or create metadata ID for the token's current metadata (preserves it in registry)
        uint16 originalMetadataId = _getOrCreateMetadataId(tokenIdToUpdate);

        // Create new metadata ID for the new metadata
        uint16 newMetadataId = nextMetadataId++;
        metadataRegistry[newMetadataId] = newMetadataUrl;

        // Assign new metadata to the token
        tokenMetadata.set(tokenIdToUpdate, newMetadataId);

        // Increment art pool index to mark this swap operation
        artPoolNextIndex++;

        // The originalMetadataId now holds the banished metadata and can be referenced by other tokens

        // Emit metadata update for the token
        fame.emitMetadataUpdate(tokenIdToUpdate);
    }

    /**
     * @notice Banish a token's metadata to the End of Mint Pool and assign new metadata
     * @dev Consumes an End of Mint Pool slot (tokenId >= nextTokenId) by incrementing nextTokenId
     * @dev Original metadata is preserved in registry, new metadata assigned to token
     * @dev End of Mint Pool contains unrevealed tokens that were never minted
     * @param tokenIdToUpdate The token ID owned by CREATOR to update
     * @param newMetadataUrl The new metadata URL to assign to the consumed slot
     */
    function banishToEndOfMintPool(
        uint256 tokenIdToUpdate,
        string memory newMetadataUrl
    ) external onlyRoles(BANISHER | CREATOR) {
        // Require non-empty metadata URL
        if (bytes(newMetadataUrl).length == 0) {
            revert InvalidMetadata();
        }

        FameMirror mirror = fame.fameMirror();

        // Verify BANISHER owns the token
        if (mirror.ownerOf(tokenIdToUpdate) != msg.sender) {
            revert TokenNotOwned();
        }

        // Check if mint pool is full
        if (nextTokenId >= 888) {
            revert MintPoolFull();
        }

        // Get or create metadata ID for the token's current metadata (preserves it in registry)
        uint16 originalMetadataId = _getOrCreateMetadataId(tokenIdToUpdate);

        // Create new metadata ID for the new metadata
        uint16 newMetadataId = nextMetadataId++;
        metadataRegistry[newMetadataId] = newMetadataUrl;

        // Assign new metadata to the token
        tokenMetadata.set(tokenIdToUpdate, newMetadataId);

        // Increment nextTokenId to mark this swap operation
        nextTokenId++;

        // The originalMetadataId now holds the banished metadata and can be referenced by other tokens

        // Emit metadata update for the token
        fame.emitMetadataUpdate(tokenIdToUpdate);
    }

    /**
     * @notice Banish a token's metadata to the Mint Pool via bidirectional swap
     * @dev Swaps metadata between owned token and an unminted Mint Pool token
     * @dev Mint Pool contains tokens with metadata that were never minted:
     *      - ownerOf(tokenId) reverts (never existed)
     *      - tokenId > totalNFTSupply (never been minted)
     *      - tokenId < nextTokenId (has metadata from childRenderer)
     *      - tokenId not in art pool
     * @param tokenIdToUpdate The token ID owned by CREATOR to update
     * @param tokenIdFromMintPool The Mint Pool token ID to swap metadata with
     */
    function banishToMintPool(
        uint256 tokenIdToUpdate,
        uint256 tokenIdFromMintPool
    ) external onlyRoles(BANISHER | CREATOR) {
        FameMirror mirror = fame.fameMirror();

        // Verify BANISHER owns the token to update
        if (mirror.ownerOf(tokenIdToUpdate) != msg.sender) {
            revert TokenNotOwned();
        }

        // Mint pool starts after all minted tokens (including space for burned tokens)
        uint256 mintPoolStart = getTotalNFTSupply() + 1;

        // Verify tokenIdFromMintPool is in the mint pool (never been minted, has metadata)
        if (
            tokenIdFromMintPool < mintPoolStart ||
            tokenIdFromMintPool >= nextTokenId
        ) {
            revert TokenNotInMintPool();
        }

        // Additional verification: mint pool token should not have an owner
        try mirror.ownerOf(tokenIdFromMintPool) returns (address owner) {
            if (owner != address(0)) {
                revert TokenNotInMintPool();
            }
        } catch {
            // Token doesn't exist, which is expected for mint pool tokens
        }

        // Get or create metadata ID for the token's current metadata (preserves it in registry)
        uint16 sourceMetadataId = _getOrCreateMetadataId(tokenIdToUpdate);

        // Get or create metadata ID for the mint pool token's metadata
        uint16 targetMetadataId = _getOrCreateMetadataId(tokenIdFromMintPool);

        // Perform bidirectional swap
        tokenMetadata.set(tokenIdToUpdate, targetMetadataId);
        tokenMetadata.set(tokenIdFromMintPool, sourceMetadataId);

        // Emit metadata update for both tokens
        fame.emitMetadataUpdate(tokenIdToUpdate);
        fame.emitMetadataUpdate(tokenIdFromMintPool);
    }

    /**
     * @notice Banish a token's metadata to the Burn Pool via bidirectional swap
     * @dev Swaps metadata between owned token and a burned Burn Pool token
     * @dev Burn Pool contains tokens that were minted but then burned:
     *      - ownerOf(tokenId) reverts (because burned)
     *      - tokenId <= totalNFTSupply (was minted at some point)
     *      - tokenId not in art pool
     * @param tokenIdToUpdate The token ID owned by CREATOR to update
     * @param tokenIdFromBurnPool The Burn Pool token ID to swap metadata with
     */
    function banishToBurnPool(
        uint256 tokenIdToUpdate,
        uint256 tokenIdFromBurnPool
    ) external onlyRoles(BANISHER | CREATOR) {
        FameMirror mirror = fame.fameMirror();

        // Verify BANISHER owns the token to update
        if (mirror.ownerOf(tokenIdToUpdate) != msg.sender) {
            revert TokenNotOwned();
        }

        // Verify tokenIdFromBurnPool is actually in the burned pool
        if (!isTokenInBurnedPool(tokenIdFromBurnPool)) {
            revert TokenNotInBurnPool();
        }

        // Get or create metadata ID for the token's current metadata (preserves it in registry)
        uint16 sourceMetadataId = _getOrCreateMetadataId(tokenIdToUpdate);

        // Get or create metadata ID for the burn pool token's metadata
        uint16 targetMetadataId = _getOrCreateMetadataId(tokenIdFromBurnPool);

        // Perform bidirectional swap
        tokenMetadata.set(tokenIdToUpdate, targetMetadataId);
        tokenMetadata.set(tokenIdFromBurnPool, sourceMetadataId);

        // Emit metadata update for both tokens
        fame.emitMetadataUpdate(tokenIdToUpdate);
        fame.emitMetadataUpdate(tokenIdFromBurnPool);
    }

    /**
     * @notice Update the metadata for a token
     * @param tokenId The token ID to update
     * @param newMetadataUrl The new metadata URL to assign to the token
     */
    function updateMetadata(
        uint256 tokenId,
        string memory newMetadataUrl
    ) external onlyRoles(CREATOR) {
        // Require non-empty metadata URL
        if (bytes(newMetadataUrl).length == 0) {
            revert InvalidMetadata();
        }

        // Get or create metadata ID for the token's current metadata (preserves it in registry)
        uint16 originalMetadataId = _getOrCreateMetadataId(tokenId);

        // Create new metadata ID for the new metadata
        uint16 newMetadataId = nextMetadataId++;
        metadataRegistry[newMetadataId] = newMetadataUrl;

        // Assign new metadata to the token
        tokenMetadata.set(tokenId, newMetadataId);

        // Emit metadata update for the token
        fame.emitMetadataUpdate(tokenId);
    }

    /**
     * @notice Get the total NFT supply from the Fame contract
     * @return The total number of NFTs that have been minted
     */
    function getTotalNFTSupply() public view returns (uint256) {
        // Use the exposed DN404 function selector for totalNFTSupply()
        (bool success, bytes memory data) = address(fame).staticcall(
            abi.encodeWithSelector(0xe2c79281)
        );
        require(success, "Failed to get total NFT supply");
        return abi.decode(data, (uint256));
    }

    /**
     * @notice Get the maximum possible NFT supply
     * @return The maximum number of NFTs that can exist (totalSupply / unit)
     */
    function getMaxNFTSupply() public view returns (uint256) {
        // Maximum possible NFTs = totalSupply / unit
        return fame.totalSupply() / fame.unit();
    }

    /**
     * @notice Get the Mint Pool start boundary
     * @dev Mint Pool range: (totalNFTSupply, nextTokenId) - tokens with metadata but never minted
     * @return The starting index of the Mint Pool (totalNFTSupply + 1)
     */
    function getMintPoolStart() public view returns (uint256) {
        return getTotalNFTSupply() + 1;
    }

    /**
     * @notice Get the Mint Pool end boundary (exclusive)
     * @dev Also serves as the End of Mint Pool start boundary
     * @return The ending index of the Mint Pool (nextTokenId)
     */
    function getMintPoolEnd() public view returns (uint256) {
        return nextTokenId;
    }

    /**
     * @notice Check if a token ID exists in the Burn Pool
     * @dev Uses ownerOf() revert pattern to detect burned tokens
     * @dev Burn Pool criteria:
     *      - ownerOf(tokenId) reverts (because burned)
     *      - tokenId <= totalNFTSupply (was minted at some point)
     *      - tokenId not in art pool (265-419)
     * @param tokenId The token ID to check
     * @return True if the token is in the Burn Pool, false otherwise
     */
    function isTokenInBurnedPool(uint256 tokenId) public view returns (bool) {
        // Token must be within minted range
        if (tokenId == 0 || tokenId > getTotalNFTSupply()) {
            return false;
        }

        // Token must not be in art pool range
        if (tokenId >= ART_POOL_START_INDEX && tokenId <= ART_POOL_END_INDEX) {
            return false;
        }

        FameMirror mirror = fame.fameMirror();

        // If ownerOf reverts, token is burned
        try mirror.ownerOf(tokenId) returns (address) {
            return false; // Token has owner, not burned
        } catch {
            return true; // Token reverts, therefore burned
        }
    }

    /**
     * @notice Check if a token ID exists in the Mint Pool
     * @dev Mint Pool criteria:
     *      - ownerOf(tokenId) reverts (never existed)
     *      - tokenId > totalNFTSupply (never been minted)
     *      - tokenId < nextTokenId (has metadata from childRenderer)
     *      - tokenId not in art pool
     * @param tokenId The token ID to check
     * @return True if the token is in the Mint Pool, false otherwise
     */
    function isTokenInMintPool(uint256 tokenId) public view returns (bool) {
        uint256 totalSupply = getTotalNFTSupply();

        // Must be beyond minted range
        if (tokenId <= totalSupply) {
            return false;
        }

        // Must be within revealed range
        if (tokenId >= nextTokenId) {
            return false;
        }

        // Must not be in art pool (though in production this check is redundant)
        if (tokenId >= ART_POOL_START_INDEX && tokenId <= ART_POOL_END_INDEX) {
            return false;
        }

        FameMirror mirror = fame.fameMirror();

        // ownerOf must revert (token never existed)
        try mirror.ownerOf(tokenId) returns (address) {
            return false; // Token exists, not in mint pool
        } catch {
            return true; // Token never existed = valid for mint pool
        }
    }

    /**
     * @notice Check if a token ID exists in the End of Mint Pool
     * @dev End of Mint Pool criteria:
     *      - tokenId >= nextTokenId (unrevealed range)
     *      - ownerOf(tokenId) reverts (never existed)
     *      - tokenId not in art pool (in production, always true)
     * @param tokenId The token ID to check
     * @return True if the token is in the End of Mint Pool, false otherwise
     */
    function isTokenInEndOfMintPool(
        uint256 tokenId
    ) public view returns (bool) {
        // Must be in unrevealed range
        if (tokenId < nextTokenId) {
            return false;
        }

        // Must not be in art pool (in production, always true since nextTokenId > 419)
        if (tokenId >= ART_POOL_START_INDEX && tokenId <= ART_POOL_END_INDEX) {
            return false;
        }

        FameMirror mirror = fame.fameMirror();

        // ownerOf must revert (token never existed)
        try mirror.ownerOf(tokenId) returns (address) {
            return false; // Token exists, not in end of mint pool
        } catch {
            return true; // Token never existed = valid for end of mint pool
        }
    }

    /**
     * @notice Get the token URI for a given token ID
     * @dev Checks if the token has assigned metadata first, then falls back to child renderer
     * @param tokenId The token ID to get the URI for
     * @return The token URI string
     */
    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        // Check if token has assigned metadata in registry
        uint16 metadataId = tokenMetadata.get(tokenId);
        if (metadataId != 0) {
            string memory metadata = metadataRegistry[metadataId];
            if (bytes(metadata).length > 0) {
                return metadata;
            }
        }

        return childRenderer.tokenURI(tokenId);
    }

    /**
     * @notice Emit a metadata update event for a specific token
     * @param tokenId The token ID to emit the metadata update for
     */
    function emitMetadataUpdate(
        uint256 tokenId
    ) external override onlyRoles(CREATOR | RENDERER) {
        fame.emitMetadataUpdate(tokenId);
    }

    /**
     * @notice Emit a batch metadata update event for a range of tokens
     * @param start The starting token ID of the range
     * @param end The ending token ID of the range (inclusive)
     */
    function emitBatchMetadataUpdate(
        uint256 start,
        uint256 end
    ) external override onlyRoles(CREATOR | RENDERER) {
        fame.emitBatchMetadataUpdate(start, end);
    }

    /**
     * @notice Update the child renderer contract address
     * @param _childRenderer The new child renderer contract address
     */
    function updateChildRenderer(
        address _childRenderer
    ) external onlyRolesOrOwner(CREATOR) {
        childRenderer = ITokenURIGenerator(_childRenderer);
        _grantRoles(_childRenderer, RENDERER);
    }

    function artPoolStartIndex() public pure returns (uint256) {
        return ART_POOL_START_INDEX;
    }

    function artPoolEndIndex() public pure returns (uint256) {
        return ART_POOL_END_INDEX;
    }

    function artPoolNext() public view returns (uint256) {
        return artPoolNextIndex;
    }

    /**
     * @notice Get metadata for a specific metadata ID (for testing/compatibility)
     * @param metadataId The metadata ID to get metadata for
     * @return The metadata string
     */
    function getMetadataById(
        uint256 metadataId
    ) public view returns (string memory) {
        return metadataRegistry[metadataId];
    }

    /**
     * @notice Get the metadata ID assigned to a token (for testing/compatibility)
     * @param tokenId The token ID to get metadata ID for
     * @return The metadata ID (0 if not assigned)
     */
    function getTokenMetadataId(uint256 tokenId) public view returns (uint16) {
        return tokenMetadata.get(tokenId);
    }

    /**
     * @notice Get the next metadata ID that will be assigned
     * @return The next metadata ID
     */
    function getNextMetadataId() public view returns (uint16) {
        return nextMetadataId;
    }
}
