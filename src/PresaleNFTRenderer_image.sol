// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {LibString} from "solady/utils/LibString.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import "./PresaleNFTRenderer_interface.sol";

contract PresaleNFTRendererImage is IPresaleNFTRenderer_Render, Ownable {
    using LibString for uint256;
    using LibString for string;

    string private baseURI = "ipfs://QmQv1ZQ5";

    constructor(string memory _baseURI) {
        baseURI = _baseURI;
        _initializeOwner(msg.sender);
    }

    function render(uint256 tokenId) public view returns (string memory) {
        return baseURI.concat(tokenId.toString()).concat(".png");
    }

    function setBaseURI(string memory _baseURI) public onlyOwner {
        baseURI = _baseURI;
    }
}
