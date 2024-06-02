// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./DN404Mirror.sol";
import {ITokenURIGenerator} from "./ITokenURIGenerator.sol";
import {IERC4906} from "./IERC4906.sol";

/**
 * @title FameMirror
 * @notice DN404 Mirror (NFT) contract that mirrors the fungible token contract.
 * This contract is used to mint NFTs for users who have accumulated a certain amount of fungible tokens.
 * Also Implements the EIP-5805 standard (ERC721Votes) and EIP-6372 standard (clock)
 */
contract FameMirror is DN404Mirror, IERC4906 {
    constructor(address _owner) DN404Mirror(_owner) {}

    error OnlyERC20CanCall();

    modifier onlyERC20() {
        if (msg.sender != address(_getDN404NFTStorage().baseERC20)) {
            revert OnlyERC20CanCall();
        }
        _;
    }

    function emitMetadataUpdate(uint256 tokenId) external onlyERC20 {
        emit MetadataUpdate(tokenId);
    }

    function emitBatchMetadataUpdate(
        uint256 fromTokenId,
        uint256 toTokenId
    ) external onlyERC20 {
        emit BatchMetadataUpdate(fromTokenId, toTokenId);
    }
}
