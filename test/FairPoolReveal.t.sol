// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import "forge-std/console.sol";
import {Bitmap} from "./utils/Bitmap.sol";
import {LibString} from "solady/utils/LibString.sol";
import {FairReveal} from "../src/FairReveal.sol";
import {FairPoolReveal} from "../src/FairPoolReveal.sol";
import {ArtPatcher} from "../src/ArtPatcher.sol";
import {FameSquadRemapper} from "../src/FameSquadRemapper.sol";

contract FairPoolRevealTest is Test {
    using LibString for uint256;
    using LibString for string;
    FairReveal public fairReveal;
    FairPoolReveal public fairPoolReveal;
    ArtPatcher public artPatcher;
    FameSquadRemapper public fameSquadRemapper;

    function setUp() public {
        fairReveal = new FairReveal(address(0), "unrevealed://", 888);

        fameSquadRemapper = new FameSquadRemapper(
            address(0),
            address(fairReveal)
        );
        artPatcher = new ArtPatcher(address(fameSquadRemapper));
        fairPoolReveal = new FairPoolReveal(
            address(0),
            address(artPatcher),
            488,
            888
        );
    }

    function test_Reveal1() public {
        fairReveal.reveal("foo://", 0, 332, 333);
        vm.prevrandao(bytes32(uint256(0)));
        fairPoolReveal.reveal("foo://", 0, 487, 487, true);
        vm.prevrandao(bytes32(uint256(3)));
        fairPoolReveal.reveal("foo://", 0, 10, 497, true);

        (, uint256 tokenId, uint256 salt) = fairPoolReveal.resolveTokenId(487);
        assertEq(tokenId, 495);
        uint256 saltedTokenId = uint256(
            keccak256(abi.encodePacked(tokenId, salt))
        );
        string memory expectedUri = LibString
            .concat("foo://", saltedTokenId.toString())
            .concat(".json");
        assertEq(fairPoolReveal.tokenURI(488), expectedUri);
    }
}
