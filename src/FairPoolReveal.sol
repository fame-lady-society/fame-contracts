// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibString} from "solady/utils/LibString.sol";
import {LibBitmap} from "solady/utils/LibBitmap.sol";
import {OwnableRoles} from "solady/auth/OwnableRoles.sol";
import {ITokenURIGenerator} from "./ITokenURIGenerator.sol";
import {ITokenEmitable} from "./ITokenEmitable.sol";
import "forge-std/console.sol";

/**
 * @title FairReveal
 * @notice A contract that returns metadata for an NFT. The NFT starts with unrevealed
 * metadata and can be revealed by an address with the REVEALER role. The reveal process
 * takes a random number (blockhash to start) and a salt to generate a hash.
 */

contract FairPoolReveal is OwnableRoles, ITokenURIGenerator {
    using LibBitmap for LibBitmap.Bitmap;
    using LibString for uint256;
    using LibString for string;

    struct RevealedChunk {
        uint16 startIndex;
        uint16 length;
    }
    struct Revealed {
        string baseUri;
        uint256 salt;
        uint16 revealedCount;
        uint256 seed;
        // Even length pairs of start index and length
        uint16[] chunks;
    }

    uint16 public startAtToken;
    uint16 public startingSize;
    uint16 public unrevealedTokensRemaining;
    LibBitmap.Bitmap private _revealedTokens;

    string private _tokenIdSalt;
    ITokenURIGenerator public upgradeableUriGenerator;
    ITokenEmitable public emitable;

    /**
     * @dev Used to read the order of the token ids
     */
    Revealed[] public _revealed;

    function revealedSize() external view returns (uint256) {
        return _revealed.length;
    }
    function revealedItem(
        uint256 index
    ) external view returns (Revealed memory) {
        return _revealed[index];
    }

    uint256 constant REVEALER = _ROLE_0;
    uint256 constant METADATA_UPDATER = _ROLE_1;

    constructor(
        address emitableAddress,
        address upgradeableUriGeneratorAddress,
        uint16 _startAtToken,
        uint16 totalTokens
    ) {
        upgradeableUriGenerator = ITokenURIGenerator(
            upgradeableUriGeneratorAddress
        );
        startAtToken = _startAtToken;
        highestTotalAvailableArt = 0;
        emitable = ITokenEmitable(emitableAddress);
        unrevealedTokensRemaining = totalTokens;
        startingSize = totalTokens;
        _initializeOwner(msg.sender);
        _grantRoles(msg.sender, REVEALER | METADATA_UPDATER);
    }

    error InvalidTokenId();
    /**
     * @dev Resolve the randomized tokenId from the input tokenId
     */
    function resolveTokenId(
        uint256 index
    )
        public
        view
        returns (string memory baseUri, uint256 tokenId, uint256 salt)
    {
        // We're going to walk through the revealed chunks to find the tokenId, counting from 0
        uint256 currentIndexOfTokenId = 0;
        // Walk through the revealed chunks to find the tokenId by counting lengths
        for (uint256 i = 0; i < _revealed.length; i++) {
            Revealed memory revealed = _revealed[i];
            uint256 chunkLength = revealed.chunks.length;

            for (uint256 j = 0; j < chunkLength; j += 2) {
                // where the chunk starts
                uint16 startIndex = revealed.chunks[j];
                // the length of the chunk
                uint16 length = revealed.chunks[j + 1];
                // If the index is within the range of the chunk, we have found the tokenId
                if (
                    index >= currentIndexOfTokenId &&
                    index < currentIndexOfTokenId + length
                ) {
                    baseUri = revealed.baseUri;
                    tokenId = startIndex + index - currentIndexOfTokenId;
                    salt = revealed.salt;
                    return (baseUri, tokenId, salt);
                }
                // Move the current index by the length of the chunk
                currentIndexOfTokenId += length;
            }
        }
        revert InvalidTokenId();
    }

    /**
     * @dev Returns the URI for a given token ID
     */
    function tokenURI(
        uint256 tokenId
    ) external view override returns (string memory) {
        if (tokenId < startAtToken) {
            console.log("tokenId < startAtToken");
            return upgradeableUriGenerator.tokenURI(tokenId);
        }
        // if this reverts, it means the tokenId is invalid and is unrevealed
        try this.resolveTokenId(tokenId - 1) returns (
            string memory baseUri,
            uint256 index,
            uint256 salt
        ) {
            // token is revealed
            uint256 saltedTokenId = uint256(
                keccak256(abi.encodePacked(index - startAtToken, salt))
            );
            return
                LibString.concat(baseUri, saltedTokenId.toString()).concat(
                    ".json"
                );
        } catch {
            console.log("tokenURI reverts");
            return upgradeableUriGenerator.tokenURI(tokenId);
        }
    }

    function findFirstSetNoRollover(
        uint16 startAtIndex,
        uint16 length,
        uint16 rollover
    ) internal view returns (uint16) {
        uint16 index = startAtIndex;
        while (
            !_revealedTokens.get(index) &&
            index < rollover &&
            index - startAtIndex < length
        ) {
            index++;
        }
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
    /**
     * @dev Finds the count unset bit in the bitmap after a given index, rolling over as needed
     * @param startAtIndex the index to start searching from
     * @param count the number of unset bits to find
     * @param rollover the maximum index to search to before rolling over
     */
    function findUnsetIndexRolling(
        uint16 startAtIndex,
        uint16 count,
        uint16 rollover
    ) internal view returns (uint16) {
        if (startAtIndex >= rollover) {
            revert OutOfRange();
        }
        // Start the search from the given index
        uint16 index = startAtIndex;
        uint16 checked = 0; // Counter to track the number of checked indices
        uint16 foundUnset = 0; // Counter for the number of unset bits found

        // Loop through the bitmap until the required number of unset bits are found
        while ((foundUnset == 0 || foundUnset < count) && checked < rollover) {
            // did we find an unset bit?
            if (!_revealedTokens.get(index)) {
                // yes, increment the counter
                foundUnset++;
                // Check if the required number of unset bits is found
                if (foundUnset == count) {
                    // Return the current index if the required number of unset bits is found
                    return index;
                }
            }

            // Increment the checked counter, to prevent an infinite loop
            checked++;
            // // Move to the next index
            index = (index + 1) % rollover;
        }
        // If not enough unset bits are found, revert
        if (foundUnset < count) {
            revert NotEnoughUnsetBits();
        }
        // This line should be unreachable, but included for completeness
        return index;
    }

    error BlockMustBeInFuture();
    error SizeCannotDecrease();
    uint16 private highestTotalAvailableArt;
    /**
     * @dev Reveals a set of tokens. Can only be called by an address with the REVEALER role.
     * The reveal process takes a random number (blockhash to start) and a salt to generate a hash.
     * The hash is used to determine the tokens to reveal.
     * The number of tokens to reveal must be less than or equal to the total number of tokens available to reveal
     * The total number of tokens available must be greater than or equal to the highest total number of tokens available in a prior reveal.
     * @param salt the salt to use in the reveal
     * @param reveals the number of tokens to reveal
     * @param totalAvailableArt the total number of tokens available in the reveal. this number between prior calls must always be greater than or equal the prior call
     * @param emitMetadata if true, the metadata update event will be emitted
     */
    function reveal(
        string calldata baseUri,
        uint256 salt,
        uint16 reveals,
        uint16 totalAvailableArt,
        bool emitMetadata
    ) external onlyRoles(REVEALER) {
        // Check if the new totalAvailableArt is less than the highest value seen
        if (totalAvailableArt < highestTotalAvailableArt) {
            revert SizeCannotDecrease();
        }

        // Update highestTotalAvailableArt if the new value is higher
        if (totalAvailableArt > highestTotalAvailableArt) {
            highestTotalAvailableArt = totalAvailableArt;
        }
        // The number of token ids available for this reveal
        uint16 revealSetSize = totalAvailableArt -
            (startingSize - unrevealedTokensRemaining);

        Revealed memory revealed;
        revealed.baseUri = baseUri;
        revealed.salt = salt;
        revealed.revealedCount = reveals;
        // Randao!
        revealed.seed = uint256(
            keccak256(abi.encodePacked(block.prevrandao, salt))
        );

        // Let's do some revealing, and keep track of the revealed count
        uint16 revealedCount = 0;
        // use hash to pick a start index mod unrevealedTokensRemaining
        // this is the part where we pick a starting location on the set of
        // available tokens that can reveal, and then look for the next available
        // slot
        uint16 startAtIndex = findUnsetIndexRolling(
            0,
            uint16(revealed.seed % uint256(revealSetSize)),
            totalAvailableArt
        );
        // updating state
        _revealed.push(revealed);

        while (revealedCount < reveals) {
            // find the length of the current set of unset bits that we are going to set
            uint16 endAtIndex = findFirstSetNoRollover(
                startAtIndex,
                reveals - revealedCount,
                totalAvailableArt
            );
            // length of the set of unset bits
            uint16 length = endAtIndex - startAtIndex;
            // length cannot be > reveals - revealed
            if (length > reveals - revealedCount) {
                length = reveals - revealedCount;
            }
            // set the bits
            _revealedTokens.setBatch(startAtIndex, length);
            // add the chunk to the revealed struct
            _revealed[_revealed.length - 1].chunks.push(startAtIndex);
            _revealed[_revealed.length - 1].chunks.push(length);
            // update the revealed count
            revealedCount += length;
            // Special cases tp continue the loop
            if (revealedCount < reveals) {
                // Are we going to look next or roll over?
                // Find the next unset bit
                startAtIndex = findFirstUnset(
                    endAtIndex >= totalAvailableArt ? 0 : endAtIndex,
                    totalAvailableArt
                );
                // Special case for when startAtIndex is the last index. We need to add a single
                // entry to chunks and start the next iteration at 0
                if (startAtIndex >= totalAvailableArt - 1) {
                    _revealed[_revealed.length - 1].chunks.push(startAtIndex);
                    _revealed[_revealed.length - 1].chunks.push(1);
                    _revealedTokens.set(startAtIndex);
                    revealedCount++;
                    startAtIndex = findUnsetIndexRolling(
                        0,
                        0,
                        totalAvailableArt
                    );
                }
            }
        }

        // Check if we can emit metadata
        if (address(emitable) != address(0) && emitMetadata) {
            // Emit metadata update for the revealed tokens
            emitable.emitBatchMetadataUpdate(
                uint256(startingSize - unrevealedTokensRemaining),
                uint256(startingSize - unrevealedTokensRemaining + reveals)
            );
        }

        unrevealedTokensRemaining -= reveals;
    }

    /**
     * @dev Returns if an underrlying token id (not the external facing token id, but the randomized one) has been used in a revealed token
     * @param tokenId the underlying token id
     * @return true if the token id has been revealed
     */
    function hasBeenRevealed(uint16 tokenId) external view returns (bool) {
        return _revealedTokens.get(tokenId);
    }

    /**
     * @dev Updates the salt for a revealed chunk. Can only be called by an address with the SALT_UPDATER role.
     * Intended to be used in cases where a reveal set needs to be fixed.
     * @param index the index of the revealed chunk to update
     * @param salt the new salt
     */
    function updateSalt(
        uint256 index,
        uint256 salt
    ) external onlyRoles(METADATA_UPDATER) {
        _revealed[index].salt = salt;
    }

    function updateBaseUri(
        uint256 index,
        string memory baseUri
    ) external onlyRoles(METADATA_UPDATER) {
        _revealed[index].baseUri = baseUri;
    }

    /**
     * @dev Updates the fallback uri generator, in cases where unrevealed tokens will be handled by a future contract
     * @param newUriGenerator the new uri generator
     */
    function updateUriGenerator(
        address newUriGenerator
    ) external onlyRoles(METADATA_UPDATER) {
        upgradeableUriGenerator = ITokenURIGenerator(newUriGenerator);
    }
}
