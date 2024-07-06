// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {ERC721} from "solady/tokens/ERC721.sol";
import {OwnableRoles} from "solady/auth/OwnableRoles.sol";
import {ITokenURIGenerator} from "./ITokenURIGenerator.sol";
import {IERC4906} from "./IERC4906.sol";

contract FameBasedNFT is ERC721, OwnableRoles, IERC4906 {
    ITokenURIGenerator public tokenURIGenerator;
    bool public isLocked = false;
    uint256 public totalSupply = 0;

    constructor(address uri) {
        tokenURIGenerator = ITokenURIGenerator(uri);
        _grantRoles(uri, _ROLE_3);
        _initializeOwner(msg.sender);
    }

    function name() public pure override returns (string memory) {
        return "Fame Based";
    }

    function symbol() public pure override returns (string memory) {
        return "FB";
    }

    /**
     * @notice Mint NFTs to the specified address
       @dev can only be called once
     * @param to The address to mint the NFTs to
     * @param count The number of NFTs to mint
     */
    function mint(address to, uint256 count) public onlyOwnerOrRoles(_ROLE_0) {
        uint256 tokenId = 1;
        while (tokenId <= count) {
            _mint(to, tokenId);
            tokenId++;
        }
        totalSupply += count;
    }

    /**
     * @dev Updates the renderer to a new render contract. Can only be called by an address with the UPDATE_RENDERER_ROLE. Emits an EIP4906 BatchMetadataUpdate event
     *
     * @param newRenderer the new renderer
     */
    function setRenderer(address newRenderer) public onlyOwnerOrRoles(_ROLE_1) {
        _removeRoles(address(tokenURIGenerator), _ROLE_3);
        tokenURIGenerator = ITokenURIGenerator(newRenderer);
        _grantRoles(newRenderer, _ROLE_3);
        emit BatchMetadataUpdate(1, totalSupply);
    }

    /**
     * @dev allows the renderer to emit a metadata update event when metadata changes
     *
     * @param tokenId the token ID to emit an update for
     */
    function emitMetadataUpdate(uint256 tokenId) public onlyRoles(_ROLE_3) {
        emit MetadataUpdate(tokenId);
    }

    function lock() public onlyOwnerOrRoles(_ROLE_2) {
        isLocked = true;
    }

    function unlock() public onlyOwnerOrRoles(_ROLE_2) {
        isLocked = false;
    }

    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        return tokenURIGenerator.tokenURI(tokenId);
    }

    error TokenTransferIsLocked();
    function setApprovalForAll(
        address operator,
        bool approved
    ) public override {
        if (isLocked) revert TokenTransferIsLocked();
        super.setApprovalForAll(operator, approved);
    }

    function _beforeTokenTransfer(
        address,
        address,
        uint256
    ) internal view override {
        if (isLocked) revert TokenTransferIsLocked();
    }
}
