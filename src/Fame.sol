// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./DN404.sol";
import "./FameMirror.sol";
import {ITokenURIGenerator} from "./ITokenURIGenerator.sol";
import {LibString} from "solady/utils/LibString.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {OwnableRoles} from "solady/auth/OwnableRoles.sol";

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

    uint256 private constant _STAKE_BIT = 1 << 0;

    uint256 internal constant RENDERER = 1 << 0;

    function roleRenderer() public pure returns (uint256) {
        return RENDERER;
    }

    uint256 internal constant METADATA = 1 << 1;

    function roleMetadata() public pure returns (uint256) {
        return METADATA;
    }

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
        FameMirror fameMirror = FameMirror(
            payable(_getDN404Storage().mirrorERC721)
        );
        fameMirror.updateVotingUnits(from, to, id);

        // if stake bit is set then deny transfer
        // if (_getAux(id) & _STAKE_BIT != 0) {
        //     revert NoTransferWhenStaked();
        // }
    }

    function _canBurnNFT(uint256 id) internal view override returns (bool) {
        return _getTokenAux(id) & _STAKE_BIT == 0;
    }

    /**
     *
     */
    function _addToBurnedPool(
        uint256 totalNFTSupplyAfterBurn,
        uint256 totalSupplyAfterBurn
    ) internal pure override returns (bool) {
        // Silence unused variable compiler warning.
        totalSupplyAfterBurn = totalNFTSupplyAfterBurn;
        return true;
    }

    /// @dev Returns the auxiliary data for `owner`.
    /// Minting, transferring, burning the tokens of `owner` will not change the auxiliary data.
    /// Auxiliary data can be set for any address, even if it does not have any tokens.
    function _getTokenAux(
        uint256 tokenId
    ) internal view virtual returns (uint256) {
        return _getDN404Storage().tokenData[tokenId];
    }

    /// @dev Set the auxiliary data for `owner` to `value`.
    /// Minting, transferring, burning the tokens of `owner` will not change the auxiliary data.
    /// Auxiliary data can be set for any address, even if it does not have any tokens.
    function _setTokenAux(uint256 tokenId, uint256 tokenData) internal virtual {
        _getDN404Storage().tokenData[tokenId] = tokenData;
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

    error NotOwner();
    function stake(uint256[] calldata tokenIds) public {
        FameMirror fameMirror = FameMirror(
            payable(_getDN404Storage().mirrorERC721)
        );
        uint256 length = tokenIds.length;
        for (uint256 i = 0; i < length; i++) {
            if (fameMirror.ownerOf(tokenIds[i]) != msg.sender) {
                revert NotOwner();
            }
            _setTokenAux(tokenIds[i], _STAKE_BIT | _getTokenAux(tokenIds[i]));
        }
    }

    function unstake(uint256[] calldata tokenIds) public {
        FameMirror fameMirror = FameMirror(
            payable(_getDN404Storage().mirrorERC721)
        );
        uint256 length = tokenIds.length;
        for (uint256 i = 0; i < length; i++) {
            if (fameMirror.ownerOf(tokenIds[i]) != msg.sender) {
                revert NotOwner();
            }
            _setTokenAux(tokenIds[i], _getTokenAux(tokenIds[i]) & ~_STAKE_BIT);
        }
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
        // emit BatchMetadataUpdate(1, 888);
    }
}
