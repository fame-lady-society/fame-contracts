// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Ownable} from "solady/auth/Ownable.sol";
import "./Compiler.sol";
import "./ITokenURIGenerator.sol";
import "./PresaleNFTRenderer_interface.sol";

contract PresaleNFTRendererMetadata is ITokenURIGenerator, Ownable {
    IDataChunkCompiler private compiler;
    IPresaleNFTRenderer_Render public animationUrlMetadata;
    IPresaleNFTRenderer_Render public imageMetadata;

    constructor(
        address _compiler,
        address _animationUrlMetadata,
        address _imageMetadata
    ) {
        imageMetadata = IPresaleNFTRenderer_Render(_imageMetadata);
        compiler = IDataChunkCompiler(_compiler);
        animationUrlMetadata = IPresaleNFTRenderer_Render(
            _animationUrlMetadata
        );
    }

    function setAnimationUrlMetadata(
        address _animationUrlMetadata
    ) public onlyOwner {
        animationUrlMetadata = IPresaleNFTRenderer_Render(
            _animationUrlMetadata
        );
    }

    function setImageMetadata(address _imageMetadata) public onlyOwner {
        imageMetadata = IPresaleNFTRenderer_Render(_imageMetadata);
    }

    function tokenURI(uint256 tokenId) public view returns (string memory) {
        return
            string.concat(
                compiler.BEGIN_JSON(),
                string.concat(
                    compiler.BEGIN_METADATA_VAR("animation_url", false),
                    animationUrlMetadata.render(tokenId),
                    compiler.END_METADATA_VAR(false)
                ),
                string.concat(
                    compiler.BEGIN_METADATA_VAR("image", false),
                    imageMetadata.render(tokenId),
                    compiler.END_METADATA_VAR(false)
                ),
                string.concat(
                    compiler.BEGIN_METADATA_VAR("name", false),
                    "Pre%20Fame%22" // no trailing comma for last element
                ),
                compiler.END_JSON()
            );
    }
}
