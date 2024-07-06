// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Ownable} from "solady/auth/Ownable.sol";
import {LibString} from "solady/utils/LibString.sol";
import "./Compiler.sol";
import {Base64} from "solady/utils/Base64.sol";
import "./PresaleNFTRenderer_interface.sol";

contract PresaleNFTRendererAnimationUrl is IPresaleNFTRenderer_Render, Ownable {
    using Base64 for bytes;
    using LibString for string;
    IDataChunkCompiler private compiler;
    address[9] private threeAddresses;

    // Addresses in this order:
    // 0: DataChunkCompiler
    // 1: ThreeJSChunk1
    // 2: ThreeJSChunk2
    // 3: ThreeJSChunk3
    // 4: ThreeJSChunk4
    // 5: ThreeJSChunk5
    // 6: ThreeJSChunk6
    // 7: ThreeJSChunk7
    // 8: ThreeJSChunk8
    // 9: ThreeJSChunk9
    constructor(address[10] memory _addresses) {
        compiler = IDataChunkCompiler(_addresses[0]);
        threeAddresses[0] = _addresses[1];
        threeAddresses[1] = _addresses[2];
        threeAddresses[2] = _addresses[3];
        threeAddresses[3] = _addresses[4];
        threeAddresses[4] = _addresses[5];
        threeAddresses[5] = _addresses[6];
        threeAddresses[6] = _addresses[7];
        threeAddresses[7] = _addresses[8];
        threeAddresses[8] = _addresses[9];
        _initializeOwner(msg.sender);
    }

    function render(uint256) public view returns (string memory) {
        return
            bytes(
                compiler
                    .HTML_HEAD()
                    .concat(
                        compiler
                            .BEGIN_SCRIPT_DATA_COMPRESSED()
                            .concat(compileThreejs())
                            .concat(compiler.END_SCRIPT_DATA_COMPRESSED())
                    )
                    .concat(
                        // should be the output of compiling the html and base64 encoding it
                        ""
                    )
            ).encode();
    }

    function compileThreejs() internal view returns (string memory) {
        return
            compiler.compile9(
                threeAddresses[0],
                threeAddresses[1],
                threeAddresses[2],
                threeAddresses[3],
                threeAddresses[4],
                threeAddresses[5],
                threeAddresses[6],
                threeAddresses[7],
                threeAddresses[8]
            );
    }
}
