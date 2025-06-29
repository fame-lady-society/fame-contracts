// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC1155} from "solady/tokens/ERC1155.sol";
import {LibString} from "solady/utils/LibString.sol";
import {OwnableRoles} from "solady/auth/OwnableRoles.sol";
import {ERC2981} from "@openzeppelin5/contracts/token/common/ERC2981.sol";

interface IERC4906 {
    event MetadataUpdate(uint256 indexed tokenId);
    event BatchMetadataUpdate(uint256 indexed fromTokenId, uint256 indexed toTokenId);
}

contract FAMEusMagazineReissue is ERC1155, OwnableRoles, ERC2981, IERC4906 {
    using LibString for uint256;
    using LibString for string;

    string public name = "FAMEUS Magazine";
    string public symbol = "FAMEUS";

    mapping(uint256 => string) private _tokenURIs;
    string private _baseURI;

    uint256 internal constant MINTER = 1 << 0;
    uint256 internal constant METADATA = 1 << 1; 
    uint256 internal constant TREASURER = 1 << 2;

    function roleMinter() public pure returns (uint256) {
        return MINTER;
    }

    function roleMetadata() public pure returns (uint256) {
        return METADATA;
    }

    function roleTreasurer() public pure returns (uint256) {
        return TREASURER;
    }

    constructor() {
        _initializeOwner(msg.sender);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC1155, ERC2981) returns (bool) {
        return 
            // ERC165: 0x01ffc9a7, ERC1155: 0xd9b67a26, ERC1155MetadataURI: 0x0e89341c
            // IERC4906: 0x49064906
            ERC1155.supportsInterface(interfaceId) ||
            ERC2981.supportsInterface(interfaceId) ||
            interfaceId == type(IERC4906).interfaceId;
    }

    function uri(uint256 id) public view override returns (string memory) {
        string storage tokenUri = _tokenURIs[id];
        if (bytes(tokenUri).length > 0) {
            return tokenUri;
        }
        return _baseURI.concat(id.toString());
    }

    function setTokenURI(uint256 id, string memory _uri) public onlyRolesOrOwner(METADATA) {
        _tokenURIs[id] = _uri;
        emit URI(_uri, id);
        emit MetadataUpdate(id);
    }

    function setBaseURI(string memory baseURI) public onlyRolesOrOwner(METADATA) {
        _baseURI = baseURI;
        emit BatchMetadataUpdate(0, type(uint256).max);
    }

    function mint(
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) public onlyRolesOrOwner(MINTER) {
        _mint(to, id, amount, data);
    }

    error InvalidReceiverAddress();

    function setDefaultRoyalty(
        address receiver,
        uint96 royaltyFraction
    ) public onlyRolesOrOwner(TREASURER) {
        if (receiver == address(0)) revert InvalidReceiverAddress();
        _setDefaultRoyalty(receiver, royaltyFraction);
    }

    function setTokenRoyalty(
        uint256 id,
        address receiver,
        uint96 royaltyFraction
    ) public onlyRolesOrOwner(TREASURER) {
        if (receiver == address(0)) revert InvalidReceiverAddress();
        _setTokenRoyalty(id, receiver, royaltyFraction);
    }

    function withdraw() public onlyRolesOrOwner(TREASURER) {
        payable(msg.sender).transfer(address(this).balance);
    }

    error TransferFailed();

    function withdrawTo(address payable receiver) public onlyRolesOrOwner(TREASURER) {
        if (receiver == address(0)) revert InvalidReceiverAddress();
        bool success = receiver.send(address(this).balance);
        if (!success) revert TransferFailed();
    }
}
