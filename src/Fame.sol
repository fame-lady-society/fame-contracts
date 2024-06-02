// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./DN404.sol";
import "./FameMirror.sol";
import {ITokenURIGenerator} from "./ITokenURIGenerator.sol";
import {LibString} from "solady/utils/LibString.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {OwnableRoles} from "solady/auth/OwnableRoles.sol";
import {IBurnedPoolManager} from "./IBurnedPoolManager.sol";

/**
 * @title SimpleDN404
 * @notice Sample DN404 contract that demonstrates the owner selling fungible tokens.
 * When a user has at least one base unit (10^18) amount of tokens, they will automatically receive an NFT.
 * NFTs are minted as an address accumulates each base unit amount of tokens.
 */
contract Fame is DN404, OwnableRoles {
    using LibString for uint256;
    string private _name;
    string private _symbol;
    string private _baseURI;

    uint256 internal constant RENDERER = _ROLE_0;

    function roleRenderer() public pure returns (uint256) {
        return RENDERER;
    }

    uint256 internal constant METADATA = _ROLE_1;

    function roleMetadata() public pure returns (uint256) {
        return METADATA;
    }

    uint256 internal constant BURN_POOL_MANAGER = _ROLE_2;

    function roleBurnPoolManager() public pure returns (uint256) {
        return BURN_POOL_MANAGER;
    }

    // The proxy owner role for managing roles
    uint256 internal constant ADMIN = _ROLE_255;

    IBurnedPoolManager public burnedPoolManager;
    ITokenURIGenerator public renderer;

    constructor(
        string memory name_,
        string memory symbol_,
        address initialSupplyOwner
    ) {
        _initializeOwner(msg.sender);

        _name = name_;
        _symbol = symbol_;

        address mirror = address(new FameMirror(msg.sender));
        _initializeDN404(888 * _unit(), initialSupplyOwner, mirror);
    }

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    /// @dev Amount of token balance that is equal to one NFT.
    function _unit() internal view virtual override returns (uint256) {
        return 1_000_000 * 10 ** 18;
    }

    /// @dev Amount of token balance that is equal to one NFT.
    function unit() public view returns (uint256) {
        return _unit();
    }

    function withdraw() public onlyOwner {
        SafeTransferLib.safeTransferAllETH(msg.sender);
    }

    error NoTransferWhenStaked();

    /// @dev Hook that is called after any NFT token transfers, including minting and burning.
    function _afterNFTTransfer(
        address from,
        address to,
        uint256 id
    ) internal override {
        // nothing rn
    }

    /**
     *
     */
    function _addToBurnedPool(
        uint256 totalNFTSupplyAfterBurn,
        uint256 totalSupplyAfterBurn
    ) internal view override returns (bool) {
        if (address(burnedPoolManager) != address(0)) {
            return
                burnedPoolManager.addToBurnedPool(
                    totalNFTSupplyAfterBurn,
                    totalSupplyAfterBurn
                );
        }
        return true;
    }

    function setBurnedPoolManager(
        address newBurnedPoolManager
    ) public onlyRoles(BURN_POOL_MANAGER) {
        burnedPoolManager = IBurnedPoolManager(newBurnedPoolManager);
    }

    /**
     * @dev Returns the URI for a given token ID
     *
     * @param tokenId the tokens ID to retrieve metadata for
     */
    function _tokenURI(
        uint256 tokenId
    ) internal view override returns (string memory result) {
        if (address(renderer) == address(0) && bytes(_baseURI).length != 0) {
            result = string(abi.encodePacked(_baseURI, tokenId.toString()));
        } else {
            result = renderer.tokenURI(tokenId);
        }
    }

    function setBaseURI(string calldata baseURI_) public onlyRoles(METADATA) {
        _baseURI = baseURI_;
    }

    /**
     * @dev Updates the renderer to a new render contract. Can only be called by an address with the UPDATE_RENDERER_ROLE. Emits an EIP4906 BatchMetadataUpdate event
     *
     * @param newRenderer the new renderer
     */
    function setRenderer(address newRenderer) public onlyRoles(METADATA) {
        _removeRoles(address(renderer), RENDERER);
        renderer = ITokenURIGenerator(newRenderer);
        if (address(renderer) != address(0))
            _grantRoles(address(renderer), RENDERER);
    }

    function emitMetadataUpdate(uint256 tokenId) external onlyRoles(RENDERER) {
        fameMirror().emitMetadataUpdate(tokenId);
    }

    function emitBatchMetadataUpdate(
        uint256 fromTokenId,
        uint256 toTokenId
    ) external onlyRoles(RENDERER) {
        fameMirror().emitBatchMetadataUpdate(fromTokenId, toTokenId);
    }

    function fameMirror() public view returns (FameMirror) {
        return FameMirror(payable(_getDN404Storage().mirrorERC721));
    }

    /// @dev Allows the ADMIN to grant `user` `roles`.
    /// If the `user` already has a role, then it will be an no-op for the role.
    function grantRoles(
        address user,
        uint256 roles
    ) public payable override onlyRoles(ADMIN) {
        _grantRoles(user, roles);
    }

    /// @dev Allows the ADMIN to remove `user` `roles`.
    /// If the `user` does not have a role, then it will be an no-op for the role.
    function revokeRoles(
        address user,
        uint256 roles
    ) public payable override onlyRoles(ADMIN) {
        _removeRoles(user, roles);
    }
}
