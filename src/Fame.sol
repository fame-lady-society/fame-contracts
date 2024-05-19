// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./DN404.sol";
import "./FameMirror.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {LibString} from "solady/utils/LibString.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

/**
 * @title SimpleDN404
 * @notice Sample DN404 contract that demonstrates the owner selling fungible tokens.
 * When a user has at least one base unit (10^18) amount of tokens, they will automatically receive an NFT.
 * NFTs are minted as an address accumulates each base unit amount of tokens.
 */
contract Fame is DN404, Ownable {
    string private _name;
    string private _symbol;
    string private _baseURI;

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

    function _tokenURI(
        uint256 tokenId
    ) internal view override returns (string memory result) {
        if (bytes(_baseURI).length != 0) {
            result = string(
                abi.encodePacked(_baseURI, LibString.toString(tokenId))
            );
        }
    }

    /// @dev Amount of token balance that is equal to one NFT.
    function _unit() internal view virtual override returns (uint256) {
        return 1_000_000 * 10 ** 18;
    }

    function setBaseURI(string calldata baseURI_) public onlyOwner {
        _baseURI = baseURI_;
    }

    function withdraw() public onlyOwner {
        SafeTransferLib.safeTransferAllETH(msg.sender);
    }

    /// @dev Hook that is called after any NFT token transfers, including minting and burning.
    function _afterNFTTransfer(
        address from,
        address to,
        uint256 id
    ) internal override {
        FameMirror(_getDN404Storage().mirrorERC721).updateVotingUnits(
            from,
            to,
            id
        );
    }
}
