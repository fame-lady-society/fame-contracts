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
 * @notice A contract that allows creators to manage token metadata by banishing tokens to different pools
 * @dev This contract implements a metadata management system with three pools: art pool, mint pool, and burn pool
 * @dev The contract uses DN404 storage reading to interact with the underlying Fame contract
 */
contract CreatorArtistMagic is
    OwnableRoles,
    ITokenURIGenerator,
    ITokenEmitable
{
    using LibString for uint256;
    using LibString for string;
    using LibMap for LibMap.Uint16Map;

    uint256 internal constant CREATOR = _ROLE_0;
    uint256 internal constant RENDERER = _ROLE_0;
    uint256 internal constant ART_POOL_START_INDEX = 265;
    uint256 internal constant ART_POOL_END_INDEX = 419;

    uint256 private artPoolNextIndex = ART_POOL_START_INDEX + 1;

    ITokenURIGenerator public childRenderer;
    // emit metadata and get DND404 storage data
    Fame public fame;

    // Metadata registry design for robust swap-of-swaps
    // tokenId => metadataId (the swap layer)
    LibMap.Uint16Map internal tokenMetadata;
    // metadataId => metadata (the storage layer)
    mapping(uint256 => string) public metadataRegistry;

    // Metadata ID counter
    uint16 private nextMetadataId = 1;

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
     * @param _childRenderer Address of the child renderer contract
     * @param _fame Address of the Fame DN404 contract
     * @param _nextTokenId Starting token ID for the contract
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
     * @notice Banish a token's metadata to the art pool and replace it with new metadata
     * @dev Takes a token that the CREATOR owns and swaps its metadata with an unrevealed art pool slot
     * @dev The original metadata is preserved in the metadata registry, new metadata assigned to token
     * @param tokenIdToUpdate The token ID to update with new metadata
     * @param newMetadataUrl The new metadata URL to assign to the token
     */
    function banishToArtPool(
        uint256 tokenIdToUpdate,
        string memory newMetadataUrl
    ) external onlyRoles(CREATOR) {
        // Require non-empty metadata URL
        if (bytes(newMetadataUrl).length == 0) {
            revert InvalidMetadata();
        }

        FameMirror mirror = fame.fameMirror();

        // Verify CREATOR owns the token
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
     * @notice Banish a token's metadata to the end of the mint pool and replace it with new metadata
     * @dev Takes a token that the CREATOR owns and swaps its metadata with an unrevealed mint pool slot
     * @dev The original metadata is preserved in the metadata registry, new metadata assigned to token
     * @param tokenIdToUpdate The token ID to update with new metadata
     * @param newMetadataUrl The new metadata URL to assign to the token
     */
    function banishToEndOfMintPool(
        uint256 tokenIdToUpdate,
        string memory newMetadataUrl
    ) external onlyRoles(CREATOR) {
        // Require non-empty metadata URL
        if (bytes(newMetadataUrl).length == 0) {
            revert InvalidMetadata();
        }

        FameMirror mirror = fame.fameMirror();

        // Verify CREATOR owns the token
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
     * @notice Banish a token's metadata to the mint pool
     * @dev Takes a token that the CREATOR owns and banishes the metadata to the mint pool
     * @dev The mint pool contains tokens that have never been minted by the FAME DN404 contract
     * @param tokenIdToUpdate The token ID to update with mint pool metadata
     * @param tokenIdFromMintPool The token ID from the mint pool to use for metadata
     */
    function banishToMintPool(
        uint256 tokenIdToUpdate,
        uint256 tokenIdFromMintPool
    ) external onlyRoles(CREATOR) {
        FameMirror mirror = fame.fameMirror();

        // Verify CREATOR owns the token to update
        if (mirror.ownerOf(tokenIdToUpdate) != msg.sender) {
            revert TokenNotOwned();
        }

        // Get DN404 storage to calculate mint pool boundaries correctly
        (
            uint32 burnedPoolHead,
            uint32 burnedPoolTail,
            uint32 totalNFTSupply
        ) = getDN404Storage();
        uint256 maxNFTSupply = getMaxNFTSupply();

        // Mint pool starts at totalNFTSupply + (burnedPoolTail - burnedPoolHead)
        uint256 mintPoolStart = uint256(totalNFTSupply) +
            uint256(burnedPoolTail - burnedPoolHead);

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
     * @notice Banish a token's metadata to the burn pool
     * @dev Takes a token that the CREATOR owns and banishes the metadata to the burn pool
     * @dev The burn pool contains tokens that have been burned and are no longer in circulation
     * @param tokenIdToUpdate The token ID to update with burn pool metadata
     * @param tokenIdFromBurnPool The token ID from the burn pool to use for metadata
     */
    function banishToBurnPool(
        uint256 tokenIdToUpdate,
        uint256 tokenIdFromBurnPool
    ) external onlyRoles(CREATOR) {
        FameMirror mirror = fame.fameMirror();

        // Verify CREATOR owns the token to update
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
     * @notice Read DN404 storage to get burn pool information
     * @dev Reads the packed storage slot containing burn pool data
     * @return burnedPoolHead The head pointer of the burned pool
     * @return burnedPoolTail The tail pointer of the burned pool
     * @return totalNFTSupply The total number of NFTs that have been minted
     */
    function getDN404Storage()
        public
        view
        returns (
            uint32 burnedPoolHead,
            uint32 burnedPoolTail,
            uint32 totalNFTSupply
        )
    {
        // DN404 storage slot is at 0xa20d6e21d0e5255308
        bytes32 slot = bytes32(uint256(0xa20d6e21d0e5255308));
        bytes32 data;

        assembly {
            data := sload(slot)
        }

        // Extract packed data:
        // burnedPoolHead at bits 64-95 (32 bits)
        // burnedPoolTail at bits 96-127 (32 bits)
        // totalNFTSupply at bits 128-159 (32 bits)
        uint256 packedData = uint256(data);
        burnedPoolHead = uint32((packedData >> 64) & 0xFFFFFFFF);
        burnedPoolTail = uint32((packedData >> 96) & 0xFFFFFFFF);
        totalNFTSupply = uint32((packedData >> 128) & 0xFFFFFFFF);
    }

    /**
     * @notice Get the burned pool head pointer
     * @return The head pointer of the burned pool
     */
    function getBurnedPoolHead() public view returns (uint32) {
        (uint32 burnedPoolHead, , ) = getDN404Storage();
        return burnedPoolHead;
    }

    /**
     * @notice Get the burned pool tail pointer
     * @return The tail pointer of the burned pool
     */
    function getBurnedPoolTail() public view returns (uint32) {
        (, uint32 burnedPoolTail, ) = getDN404Storage();
        return burnedPoolTail;
    }

    /**
     * @notice Get the total number of burned tokens in the pool
     * @return The number of tokens in the burned pool
     */
    function getBurnedPoolSize() public view returns (uint32) {
        (uint32 burnedPoolHead, uint32 burnedPoolTail, ) = getDN404Storage();
        return burnedPoolTail - burnedPoolHead;
    }

    /**
     * @notice Get the actual mint pool start (accounts for burned tokens)
     * @return The starting index of the mint pool
     */
    function getMintPoolStart() public view returns (uint256) {
        (
            uint32 burnedPoolHead,
            uint32 burnedPoolTail,
            uint32 totalNFTSupply
        ) = getDN404Storage();
        return
            uint256(totalNFTSupply) + uint256(burnedPoolTail - burnedPoolHead);
    }

    function getMintPoolEnd() public view returns (uint256) {
        return nextTokenId;
    }

    /**
     * @notice Read a specific burned token ID from the burned pool at the given index
     * @param poolIndex The index within the burned pool to read from
     * @return The token ID at the specified index in the burned pool
     */
    function getBurnedTokenAtIndex(
        uint32 poolIndex
    ) public view returns (uint32) {
        (uint32 burnedPoolHead, uint32 burnedPoolTail, ) = getDN404Storage();
        require(
            poolIndex >= burnedPoolHead && poolIndex < burnedPoolTail,
            "Index out of bounds"
        );

        // DN404 burnedPool mapping is at slot 9 relative to base storage
        bytes32 baseSlot = bytes32(uint256(0xa20d6e21d0e5255308));
        bytes32 mapSlot = bytes32(uint256(baseSlot) + 9);

        // Calculate storage slot for burnedPool[poolIndex]
        // burnedPool uses packed storage: 8 uint32 values per slot
        bytes32 slot = bytes32(uint256(mapSlot) * (2 ** 96) + poolIndex / 8);
        bytes32 data;

        assembly {
            data := sload(slot)
        }

        // Extract the uint32 value at the correct position within the slot
        uint256 offset = (poolIndex % 8) * 32; // 32 bits per uint32
        return uint32((uint256(data) >> offset) & 0xFFFFFFFF);
    }

    /**
     * @notice Get all burned token IDs (convenience method for debugging/inspection)
     * @return An array containing all token IDs in the burned pool
     */
    function getAllBurnedTokens() public view returns (uint32[] memory) {
        (uint32 burnedPoolHead, uint32 burnedPoolTail, ) = getDN404Storage();
        uint32 poolSize = burnedPoolTail - burnedPoolHead;

        if (poolSize == 0) {
            return new uint32[](0);
        }

        uint32[] memory burnedTokens = new uint32[](poolSize);

        for (uint32 i = 0; i < poolSize; i++) {
            burnedTokens[i] = getBurnedTokenAtIndex(burnedPoolHead + i);
        }

        return burnedTokens;
    }

    /**
     * @notice Check if a token ID exists in the burned pool
     * @param tokenId The token ID to check
     * @return True if the token is in the burned pool, false otherwise
     */
    function isTokenInBurnedPool(uint256 tokenId) public view returns (bool) {
        (uint32 burnedPoolHead, uint32 burnedPoolTail, ) = getDN404Storage();

        // If burn pool is empty, token is not in it
        if (burnedPoolHead == burnedPoolTail) {
            return false;
        }

        // DN404 burnedPool mapping is at slot 9 relative to base storage
        bytes32 baseSlot = bytes32(uint256(0xa20d6e21d0e5255308));
        bytes32 mapSlot = bytes32(uint256(baseSlot) + 9);

        // Iterate through burned pool indices
        for (uint32 i = burnedPoolHead; i < burnedPoolTail; i++) {
            // Calculate storage slot for burnedPool[i]
            // burnedPool uses packed storage: 8 uint32 values per slot
            bytes32 slot = bytes32(uint256(mapSlot) * (2 ** 96) + i / 8);
            bytes32 data;

            assembly {
                data := sload(slot)
            }

            // Extract the uint32 value at the correct position within the slot
            uint256 offset = (i % 8) * 32; // 32 bits per uint32
            uint32 burnedTokenId = uint32(
                (uint256(data) >> offset) & 0xFFFFFFFF
            );

            if (burnedTokenId == tokenId) {
                return true;
            }
        }

        return false;
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
