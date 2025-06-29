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

contract CreatorArtistMagic is
    OwnableRoles,
    ITokenURIGenerator,
    ITokenEmitable
{
    using LibString for uint256;
    using LibString for string;
    using LibMap for LibMap.Uint16Map;

    uint256 internal constant CREATOR = _ROLE_0;
    uint256 internal constant ART_POOL_START_INDEX = 265;
    uint256 internal constant ART_POOL_END_INDEX = 419;

    uint256 private artPoolNextIndex = ART_POOL_START_INDEX + 1;

    ITokenURIGenerator public childRenderer;
    // emit metadata and get DND404 storage data
    Fame public fame;

    // currentTokenId => artTokenId
    LibMap.Uint16Map internal artPool;
    mapping(uint256 => string) public artPoolUri;

    uint16 public startAtToken;

    error TokenNotOwned();
    error InvalidTokenId();
    error InvalidMetadata();
    error ArtPoolFull();
    error TokenNotInMintPool();
    error TokenNotInBurnPool();

    constructor(
        address _childRenderer,
        address payable _fame,
        uint16 _startAtToken
    ) {
        childRenderer = ITokenURIGenerator(_childRenderer);
        fame = Fame(_fame);
        startAtToken = _startAtToken;
        _initializeOwner(msg.sender);
    }

    // @dev take a token that the CREATOR owns and banish the metadata to the art pool.
    // Replace the token's metadata with a new one. Keep track of the next available
    // index in the art pool, and update the mapping of currentTokenId to artToken
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
        
        // Check if art pool is full
        if (artPoolNextIndex > ART_POOL_END_INDEX) {
            revert ArtPoolFull();
        }
        
        // Get the next available art pool index
        uint256 artTokenId = artPoolNextIndex++;
        
        // Map the token to the art pool token
        artPool.set(tokenIdToUpdate, uint16(artTokenId));
        
        // Set custom metadata URL
        artPoolUri[artTokenId] = newMetadataUrl;
        
        // Emit metadata update for the token
        fame.emitMetadataUpdate(tokenIdToUpdate);
    }

    // @dev take a token that the CREATOR owns and banish the metadata to the mint pool,
    // which are the tokens beyond which the FAME DN404 contract has never minted.
    // In order to determine where that starts, we will need to read the FAME DN404 contract
    // storage and do a little processing. See ./Fame.sol and ./FameMirror.sol for more details.
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
        (uint32 burnedPoolHead, uint32 burnedPoolTail, uint32 totalNFTSupply) = getDN404Storage();
        uint256 maxNFTSupply = getMaxNFTSupply();
        
        // Mint pool starts at totalNFTSupply + (burnedPoolTail - burnedPoolHead)
        uint256 mintPoolStart = uint256(totalNFTSupply) + uint256(burnedPoolTail - burnedPoolHead);
        
        // Verify tokenIdFromMintPool is in the mint pool (never been minted)
        // Mint pool = (mintPoolStart, maxNFTSupply]
        if (tokenIdFromMintPool <= mintPoolStart || tokenIdFromMintPool > maxNFTSupply) {
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
        
        // Map the token to the mint pool token
        artPool.set(tokenIdToUpdate, uint16(tokenIdFromMintPool));
        
        // Emit metadata update for the token
        fame.emitMetadataUpdate(tokenIdToUpdate);
    }

    // @dev take a token that the CREATOR owns and banish the metadata to the burn pool.
    // The burn pool is a special pool that is used to track tokens that have been burned
    // and are no longer in circulation. These would be the next tokens that the FAME DN404 contract
    // would mint. As long as the ownerOf of the tokenIdFromBurnPool is 0x0, and the tokenIdFromBurnPool
    // is less than mint pool start index, then we can do the swap.
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
        
        // Map the token to the burn pool token
        artPool.set(tokenIdToUpdate, uint16(tokenIdFromBurnPool));
        
        // Emit metadata update for the token
        fame.emitMetadataUpdate(tokenIdToUpdate);
    }

    function getTotalNFTSupply() public view returns (uint256) {
        // Use the exposed DN404 function selector for totalNFTSupply()
        (bool success, bytes memory data) = address(fame).staticcall(
            abi.encodeWithSelector(0xe2c79281)
        );
        require(success, "Failed to get total NFT supply");
        return abi.decode(data, (uint256));
    }

    function getMaxNFTSupply() public view returns (uint256) {
        // Maximum possible NFTs = totalSupply / unit
        return fame.totalSupply() / fame.unit();
    }

    // @dev Read DN404 storage to get burn pool information
    function getDN404Storage() public view returns (uint32 burnedPoolHead, uint32 burnedPoolTail, uint32 totalNFTSupply) {
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

    // @dev Get the burned pool head pointer
    function getBurnedPoolHead() public view returns (uint32) {
        (uint32 burnedPoolHead,,) = getDN404Storage();
        return burnedPoolHead;
    }

    // @dev Get the burned pool tail pointer  
    function getBurnedPoolTail() public view returns (uint32) {
        (, uint32 burnedPoolTail,) = getDN404Storage();
        return burnedPoolTail;
    }

    // @dev Get the total number of burned tokens in the pool
    function getBurnedPoolSize() public view returns (uint32) {
        (uint32 burnedPoolHead, uint32 burnedPoolTail,) = getDN404Storage();
        return burnedPoolTail - burnedPoolHead;
    }

    // @dev Get the actual mint pool start (accounts for burned tokens)
    function getMintPoolStart() public view returns (uint256) {
        (uint32 burnedPoolHead, uint32 burnedPoolTail, uint32 totalNFTSupply) = getDN404Storage();
        return uint256(totalNFTSupply) + uint256(burnedPoolTail - burnedPoolHead);
    }

    // @dev Read a specific burned token ID from the burned pool at the given index
    function getBurnedTokenAtIndex(uint32 poolIndex) public view returns (uint32) {
        (uint32 burnedPoolHead, uint32 burnedPoolTail,) = getDN404Storage();
        require(poolIndex >= burnedPoolHead && poolIndex < burnedPoolTail, "Index out of bounds");
        
        // DN404 burnedPool mapping is at slot 9 relative to base storage
        bytes32 baseSlot = bytes32(uint256(0xa20d6e21d0e5255308));
        bytes32 mapSlot = bytes32(uint256(baseSlot) + 9);
        
        // Calculate storage slot for burnedPool[poolIndex]
        // burnedPool uses packed storage: 8 uint32 values per slot
        bytes32 slot = bytes32(uint256(mapSlot) * (2**96) + poolIndex / 8);
        bytes32 data;
        
        assembly {
            data := sload(slot)
        }
        
        // Extract the uint32 value at the correct position within the slot
        uint256 offset = (poolIndex % 8) * 32; // 32 bits per uint32
        return uint32((uint256(data) >> offset) & 0xFFFFFFFF);
    }

    // @dev Get all burned token IDs (convenience method for debugging/inspection)
    function getAllBurnedTokens() public view returns (uint32[] memory) {
        (uint32 burnedPoolHead, uint32 burnedPoolTail,) = getDN404Storage();
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

    // @dev Check if a token ID exists in the burned pool
    function isTokenInBurnedPool(uint256 tokenId) public view returns (bool) {
        (uint32 burnedPoolHead, uint32 burnedPoolTail,) = getDN404Storage();
        
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
            bytes32 slot = bytes32(uint256(mapSlot) * (2**96) + i / 8);
            bytes32 data;
            
            assembly {
                data := sload(slot)
            }
            
            // Extract the uint32 value at the correct position within the slot
            uint256 offset = (i % 8) * 32; // 32 bits per uint32
            uint32 burnedTokenId = uint32((uint256(data) >> offset) & 0xFFFFFFFF);
            
            if (burnedTokenId == tokenId) {
                return true;
            }
        }
        
        return false;
    }

    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        // Check if token metadata is in art pool
        uint16 artTokenId = artPool.get(tokenId);
        if (artTokenId != 0) {
            string memory artUri = artPoolUri[artTokenId];
            if (bytes(artUri).length > 0) {
                return artUri;
            }
            return childRenderer.tokenURI(artTokenId);
        }
        
        return childRenderer.tokenURI(tokenId);
    }

    function emitMetadataUpdate(
        uint256 tokenId
    ) external override onlyRoles(CREATOR) {
        fame.emitMetadataUpdate(tokenId);
    }

    function emitBatchMetadataUpdate(
        uint256 start,
        uint256 end
    ) external override onlyRoles(CREATOR) {
        fame.emitBatchMetadataUpdate(start, end);
    }
}
