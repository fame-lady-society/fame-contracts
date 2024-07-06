// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

interface IPresaleNFTRenderer_Render {
    function render(uint256 tokenId) external view returns (string memory);
}
