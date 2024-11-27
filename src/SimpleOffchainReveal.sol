// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibString} from "solady/utils/LibString.sol";
import {ITokenURIGenerator} from "./ITokenURIGenerator.sol";

import {Ownable} from "solady/auth/Ownable.sol";

interface ITokemEmitable {
    function emitBatchMetadataUpdate(uint256 start, uint256 end) external;
    function emitMetadataUpdate(uint256 tokenId) external;
}

/**
 * @title FameSquadRemapper
 * @notice Moves tokens ids out of the way for the claim to fame musuem to be revealed
 */

contract SimpleOffchainReveal is ITokenURIGenerator, Ownable {
    using LibString for string;
    using LibString for uint256;

    ITokenURIGenerator public childRenderer;
    ITokemEmitable public tokenemEmitable;
    uint256 constant START_AT_TOKEN = 498;
    struct Batch {
        uint256 salt;
        uint256 startAtToken;
        uint256 length;
        string baseUri;
    }
    Batch[] public batches;

    constructor(address _childRenderer, address _tokenemEmitable) {
        childRenderer = ITokenURIGenerator(_childRenderer);
        tokenemEmitable = ITokemEmitable(_tokenemEmitable);
        _initializeOwner(msg.sender);
    }

    /**
     * @dev Returns the URI for a given token ID
     */
    function tokenURI(
        uint256 tokenId
    ) external view override returns (string memory) {
        if (tokenId < START_AT_TOKEN) {
            return childRenderer.tokenURI(tokenId);
        }
        uint256 batchesLength = batches.length;
        for (uint256 i = 0; i < batchesLength; i++) {
            Batch memory batch = batches[i];
            uint256 startAtToken = batch.startAtToken;
            if (
                tokenId >= startAtToken && tokenId < startAtToken + batch.length
            ) {
                uint256 saltedTokenId = uint256(
                    keccak256(
                        abi.encodePacked(tokenId - startAtToken, batch.salt)
                    )
                );
                return
                    batch.baseUri.concat(saltedTokenId.toString()).concat(
                        ".json"
                    );
            }
        }
        return childRenderer.tokenURI(tokenId);
    }

    function pushBatch(
        uint256 salt,
        uint256 length,
        string memory baseUri
    ) external onlyOwner {
        Batch memory batch = Batch(salt, maxTokenId() + 1, length, baseUri);
        batches.push(batch);
        // emit metadata if it exists, but ignore any errors
        if (address(tokenemEmitable) != address(0)) {
            if (batch.length == 1) {
                try
                    tokenemEmitable.emitMetadataUpdate(batch.startAtToken)
                {} catch {}
            } else {
                try
                    tokenemEmitable.emitBatchMetadataUpdate(
                        batch.startAtToken,
                        batch.startAtToken + batch.length - 1
                    )
                {} catch {}
            }
        }
    }

    function maxTokenId() public view returns (uint256) {
        uint256 batchesLength = batches.length;
        if (batchesLength == 0) {
            return START_AT_TOKEN - 1;
        }
        Batch memory lastBatch = batches[batchesLength - 1];
        return lastBatch.startAtToken + lastBatch.length - 1;
    }

    error NoBatchForTokenId();
    function offsetForTokenId(uint256 tokenId) public view returns (uint256) {
        uint256 batchesLength = batches.length;
        for (uint256 i = 0; i < batchesLength; i++) {
            Batch memory batch = batches[i];
            if (
                tokenId >= batch.startAtToken &&
                tokenId < batch.startAtToken + batch.length
            ) {
                return batch.startAtToken;
            }
        }
        revert NoBatchForTokenId();
    }
}
