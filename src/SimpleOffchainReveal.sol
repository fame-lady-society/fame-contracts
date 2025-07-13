// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibString} from "solady/utils/LibString.sol";
import {ITokenURIGenerator} from "./ITokenURIGenerator.sol";

import {OwnableRoles} from "solady/auth/OwnableRoles.sol";

interface ITokenEmitable {
    function emitBatchMetadataUpdate(uint256 start, uint256 end) external;
    function emitMetadataUpdate(uint256 tokenId) external;
}

/**
 * @title FameSquadRemapper
 * @notice Moves tokens ids out of the way for the claim to fame musuem to be revealed
 */

contract SimpleOffchainReveal is
    ITokenURIGenerator,
    OwnableRoles,
    ITokenEmitable
{
    using LibString for string;
    using LibString for uint256;

    uint256 public constant RENDERER = _ROLE_0;

    ITokenURIGenerator public childRenderer;
    ITokenEmitable public tokenEmitable;
    uint256 public startAtToken;
    struct Batch {
        uint256 salt;
        uint256 startAtToken;
        uint256 length;
        string baseUri;
    }
    Batch[] public batches;

    constructor(
        address _childRenderer,
        address _tokenEmitable,
        uint256 _startAtToken
    ) {
        childRenderer = ITokenURIGenerator(_childRenderer);
        tokenEmitable = ITokenEmitable(_tokenEmitable);
        startAtToken = _startAtToken;
        _initializeOwner(msg.sender);
        _grantRoles(_tokenEmitable, RENDERER);
    }

    /**
     * @dev Returns the URI for a given token ID
     */
    function tokenURI(
        uint256 tokenId
    ) external view override returns (string memory) {
        if (tokenId < startAtToken) {
            return childRenderer.tokenURI(tokenId);
        }
        uint256 batchesLength = batches.length;
        for (uint256 i = 0; i < batchesLength; i++) {
            Batch memory batch = batches[i];
            uint256 batchStartAtToken = batch.startAtToken;
            if (
                tokenId >= batchStartAtToken &&
                tokenId < batchStartAtToken + batch.length
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
        if (address(tokenEmitable) != address(0)) {
            if (batch.length == 1) {
                try
                    tokenEmitable.emitMetadataUpdate(batch.startAtToken)
                {} catch {}
            } else {
                try
                    tokenEmitable.emitBatchMetadataUpdate(
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
            return startAtToken - 1;
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

    function updateTokenEmitable(address _tokenEmitable) external onlyOwner {
        tokenEmitable = ITokenEmitable(_tokenEmitable);
        _grantRoles(_tokenEmitable, RENDERER);
    }

    function emitMetadataUpdate(
        uint256 tokenId
    ) external override onlyRoles(RENDERER) {
        tokenEmitable.emitMetadataUpdate(tokenId);
    }

    function emitBatchMetadataUpdate(
        uint256 start,
        uint256 end
    ) external override onlyRoles(RENDERER) {
        tokenEmitable.emitBatchMetadataUpdate(start, end);
    }
}
