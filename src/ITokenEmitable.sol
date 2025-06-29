// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ITokenEmitable {
    function emitBatchMetadataUpdate(uint256 start, uint256 end) external;
    function emitMetadataUpdate(uint256 tokenId) external;
}
