GIT // SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {LibString} from "solady/utils/LibString.sol";
import {FameMirror} from "../src/FameMirror.sol";
import {DN404} from "../src/DN404.sol";
import {DN404Mirror} from "../src/DN404Mirror.sol";
import {Fame} from "../src/Fame.sol";
import {StubBalanceOf} from "./mocks/StubBalanceOf.sol";
import {FameSquadRemapper} from "../src/FameSquadRemapper.sol";
import {EchoMetadata} from "./mocks/EchoMetadata.sol";

contract FameSquadRemapperTest is Test {
    using LibString for string;
    using LibString for uint256;

    FameSquadRemapper public remapper;
    EchoMetadata public echoMetadata;

    function setUp() public {
        echoMetadata = new EchoMetadata();
        remapper = new FameSquadRemapper(address(0), address(echoMetadata));
    }

    function test_Low() public view {
        for (uint256 i = 0; i <= 264; i++) {
            assertEq(remapper.tokenURI(i), i.toString());
        }
    }

    function test_RevealedRemap() public {
        assertEq(remapper.tokenURI(265), "734");
        assertEq(remapper.tokenURI(419), "888");
        for (uint256 i = 265; i <= 419; i++) {
            assertEq(remapper.tokenURI(i), (i + 469).toString());
        }
    }

    function test_Mid() public view {
        assertEq(remapper.tokenURI(420), "265");
        assertEq(remapper.tokenURI(488), "333");
        for (uint256 i = 420; i <= 488; i++) {
            assertEq(remapper.tokenURI(i), (i - 155).toString());
        }
    }

    function test_High() public view {
        assertEq(remapper.tokenURI(734), "265");
        assertEq(remapper.tokenURI(888), "419");
        for (uint256 i = 734; i <= 888; i++) {
            assertEq(remapper.tokenURI(i), (i - 469).toString());
        }
    }
}
