// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

interface IGasliteDrop1155 {
    struct AirdropToken {
        uint256 tokenId;
        AirdropTokenAmount[] airdropAmounts;
    }

    struct AirdropTokenAmount {
        uint256 amount;
        address[] recipients;
    }

    /// @notice Airdrop ERC1155 tokens to a list of addresses
    /// @param tokenAddress The address of the ERC1155 contract
    /// @param airdropTokens The tokenIds and amounts to airdrop
    function airdropERC1155(
        address tokenAddress,
        AirdropToken[] calldata airdropTokens
    ) external payable;
}
