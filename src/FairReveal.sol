// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibString} from "solady/utils/LibString.sol";
import {LibBitmap} from "solady/utils/LibBitmap.sol";
import {OwnableRoles} from "solady/auth/OwnableRoles.sol";
import {ITokenURIGenerator} from "./ITokenURIGenerator.sol";
import "forge-std/console.sol";

interface ITokemEmitable {
    function emitBatchMetadataUpdate(uint16 start, uint16 end) external;
    function emitMetadataUpdate(uint16 tokenId) external;
}

/**
 * @title FairReveal
 * @notice A contract that returns metadata for an NFT. The NFT starts with unrevealed
 * metadata and can be revealed by an address with the REVEALER role. The reveal process
 * takes a random number (blockhash to start) and a salt to generate a hash.
 */

contract FairReveal is OwnableRoles, ITokenURIGenerator {
    using LibBitmap for LibBitmap.Bitmap;
    using LibString for uint256;

    uint16 public startingSize;
    uint16 public unrevealedTokensRemaining;
    LibBitmap.Bitmap private _revealedTokens;

    string private _tokenIdSalt;
    string private _uri;
    string private _unresolvedUri;
    ITokemEmitable public emitable;

    struct RevealedChunk {
        uint16 startIndex;
        uint16 length;
    }
    struct Revealed {
        uint256 salt;
        uint16 revealedCount;
        uint256 seed;
        // Even length pairs of start index and length
        uint16[] chunks;
    }
    /**
     * @dev Used to read the order of the token ids
     */
    Revealed[] public _revealed;

    uint256 constant REVEALER = _ROLE_0;

    constructor(
        address emitableAddress,
        string memory uri,
        string memory unresolvedUri,
        uint16 totalTokens
    ) {
        highestTotalAvailableArt = 0;
        emitable = ITokemEmitable(emitableAddress);
        _uri = uri;
        _unresolvedUri = unresolvedUri;
        unrevealedTokensRemaining = totalTokens;
        startingSize = totalTokens;
        _initializeOwner(msg.sender);
        _grantRoles(msg.sender, REVEALER);
    }

    error InvalidTokenId();
    function resolveTokenId(
        uint256 index
    ) public view returns (uint256 tokenId, uint256 salt) {
        // console.log("resolveTokenId [index: %d]", index);
        // console.log("resolveTokenId [_revealed.length: %d]", _revealed.length);
        uint256 currentIndexOfTokenId = 0;
        // Walk through the revealed chunks to find the tokenId by counting lengths
        for (uint256 i = 0; i < _revealed.length; i++) {
            // console.log("resolveTokenId [i: %d]", i);
            Revealed memory revealed = _revealed[i];
            uint256 chunkLength = revealed.chunks.length;
            // console.log("resolveTokenId [chunkLength: %d]", chunkLength);
            for (uint256 j = 0; j < chunkLength; j += 2) {
                // console.log("resolveTokenId [j: %d]", j);
                uint16 startIndex = revealed.chunks[j];
                uint16 length = revealed.chunks[j + 1];
                // console.log(
                //     "resolveTokenId [startIndex: %d, length: %d]",
                //     startIndex,
                //     length
                // );
                if (
                    index >= currentIndexOfTokenId &&
                    index < currentIndexOfTokenId + length
                ) {
                    tokenId = startIndex + index - currentIndexOfTokenId;
                    salt = revealed.salt;
                    // console.log(
                    //     "resolveTokenId [tokenId: %d, salt: %d]",
                    //     tokenId,
                    //     salt
                    // );
                    return (tokenId, salt);
                }
                currentIndexOfTokenId += length;
                // console.log(
                //     "resolveTokenId [currentIndexOfTokenId: %d]",
                //     currentIndexOfTokenId
                // );
            }
        }
        revert InvalidTokenId();
    }

    function tokenURI(
        uint256 tokenId
    ) external view override returns (string memory) {
        try this.resolveTokenId(tokenId - 1) returns (
            uint256 index,
            uint256 salt
        ) {
            uint256 saltedTokenId = uint256(
                keccak256(abi.encodePacked(index, salt))
            );
            return LibString.concat(_uri, saltedTokenId.toString());
        } catch {
            return LibString.concat(_unresolvedUri, tokenId.toString());
        }
    }

    function findFirstSetNoRollover(
        uint16 startAtIndex,
        uint16 length,
        uint16 rollover
    ) internal view returns (uint16) {
        uint16 index = startAtIndex;
        console.log(
            "findFirstSetNoRollover:[length: %d, rollover: %d]",
            length,
            rollover
        );
        while (
            !_revealedTokens.get(index) &&
            index < rollover &&
            index - startAtIndex < length
        ) {
            index++;
        }
        console.log(
            "[findFirstSetNoRollover: %d, startAtIndex: %d]",
            index,
            startAtIndex
        );
        return index;
    }

    error AllBitsAreSet();
    error OutOfRange();
    function findFirstUnset(
        uint16 startAtIndex,
        uint16 rollover
    ) internal view returns (uint16) {
        if (startAtIndex >= startingSize) {
            revert OutOfRange();
        }
        uint16 index = startAtIndex;
        uint16 checked = 0; // Counter to track the number of checked indices
        while (_revealedTokens.get(index)) {
            index++;
            checked++;
            // Roll over the index back to zero if it reaches or exceeds startingSize
            if (index >= rollover) {
                index = 0;
            }
        }
        // If all bits are set, this condition will prevent an infinite loop
        if (checked >= rollover) {
            revert AllBitsAreSet();
        }
        return index;
    }

    error NotEnoughUnsetBits();
    function findFirstUnsetCounting(
        uint16 startAtIndex,
        uint16 count,
        uint16 rollover
    ) internal view returns (uint16) {
        if (startAtIndex >= rollover) {
            revert OutOfRange();
        }
        console.log(
            "findFirstUnsetCounting [startAtIndex: %d, count: %d]",
            startAtIndex,
            count
        );
        uint16 index = startAtIndex;
        uint16 checked = 0; // Counter to track the number of checked indices
        uint16 foundUnset = 0; // Counter for the number of unset bits found

        while (foundUnset < count && checked < rollover) {
            if (!_revealedTokens.get(index)) {
                foundUnset++;
                console.log(
                    "foundUnset [index: %d, index: %d]",
                    foundUnset,
                    index
                );
                if (foundUnset == count) {
                    // Return the current index if the required number of unset bits is found
                    return index;
                }
            }
            index++;
            checked++;
            // Roll over the index back to zero if it reaches or exceeds startingSize
            if (index >= rollover) {
                index = 0;
            }
        }
        // If not enough unset bits are found, revert
        if (foundUnset < count) {
            revert NotEnoughUnsetBits();
        }
        // This line is technically unreachable, but included for completeness
        return index;
    }

    error BlockMustBeInFuture();
    error SizeCannotDecrease();
    uint16 private highestTotalAvailableArt;
    function reveal(
        uint256 salt,
        uint16 reveals,
        uint16 totalAvailableArt
    ) external onlyRoles(REVEALER) {
        // Check if the new totalAvailableArt is less than the highest value seen
        if (totalAvailableArt < highestTotalAvailableArt) {
            revert SizeCannotDecrease();
        }

        // Update highestTotalAvailableArt if the new value is higher
        if (totalAvailableArt > highestTotalAvailableArt) {
            highestTotalAvailableArt = totalAvailableArt;
        }
        uint16 revealSetSize = totalAvailableArt -
            (startingSize - unrevealedTokensRemaining);
        console.log(
            "[revealSetSize: %d, reveals: %d, totalAvailableArt: %d]",
            revealSetSize,
            reveals,
            totalAvailableArt
        );
        Revealed memory revealed;
        revealed.salt = salt;
        revealed.revealedCount = reveals;
        revealed.seed = uint256(
            keccak256(abi.encodePacked(block.prevrandao, salt))
        );

        uint16 revealedCount = 0;
        // use hash to pick a start index mod unrevealedTokensRemaining
        uint16 startAtIndex = findFirstUnsetCounting(
            0,
            uint16(revealed.seed % uint256(revealSetSize)),
            totalAvailableArt
        );
        _revealed.push(revealed);
        while (revealedCount < reveals) {
            uint16 endAtIndex = findFirstSetNoRollover(
                startAtIndex + 1,
                reveals - revealedCount,
                totalAvailableArt
            );
            uint16 length = endAtIndex - startAtIndex;
            // length cannot be > reveals - revealed
            if (length > reveals - revealedCount) {
                length = reveals - revealedCount;
            }
            _revealedTokens.setBatch(startAtIndex, length);
            console.log("[startAtIndex: %d, length: %d]", startAtIndex, length);
            _revealed[_revealed.length - 1].chunks.push(startAtIndex);
            _revealed[_revealed.length - 1].chunks.push(length);
            revealedCount += length;
            if (revealedCount < reveals) {
                startAtIndex = findFirstUnset(
                    endAtIndex > totalAvailableArt ? 0 : endAtIndex,
                    totalAvailableArt
                );
            }
            console.log("[revealedCount: %d]", revealedCount);
        }

        if (address(emitable) != address(0)) {
            emitable.emitBatchMetadataUpdate(
                startingSize - unrevealedTokensRemaining,
                startingSize - unrevealedTokensRemaining + reveals
            );
        }

        unrevealedTokensRemaining -= reveals;
    }

    // TODO: EMIT METADATA after update
}
