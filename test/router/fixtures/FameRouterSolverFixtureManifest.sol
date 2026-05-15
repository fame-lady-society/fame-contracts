// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FameRouterTypes} from "../../../src/router/FameRouterTypes.sol";

library FameRouterSolverFixtureManifest {
    struct Target {
        FameRouterTypes.VenueFamily family;
        address target;
    }

    uint256 internal constant PINNED_BASE_BLOCK = 45884844;
    bytes32 internal constant SOLVER_ROUTES_JSON_HASH = 0x900560ab3f958077116f7233e58324bb22a516c31b22d1eb0371d234b05727e7;
    bytes32 internal constant GAP_MATRIX_JSON_HASH = 0xc146a7d493e04607797a00a451f85ddc55d0f6bd90ea079a6fe47d22a8b7a449;
    bytes32 internal constant PARITY_VECTORS_JSON_HASH = 0xcc492b93e1ed350182b2e1a503713415d3eff0db10ed04fdf66767f6d3ddfd6c;
    bytes32 internal constant CREATOR_COIN_CATALOG_JSON_HASH = 0x5ccc653c30133961ba7f0f1c762e02bdda344e8a371e2d69bcd9187387a29fb5;

    function pinnedBaseBlock() internal pure returns (uint256) {
        return PINNED_BASE_BLOCK;
    }

    function solverRoutesJsonHash() internal pure returns (bytes32) {
        return SOLVER_ROUTES_JSON_HASH;
    }

    function gapMatrixJsonHash() internal pure returns (bytes32) {
        return GAP_MATRIX_JSON_HASH;
    }

    function parityVectorsJsonHash() internal pure returns (bytes32) {
        return PARITY_VECTORS_JSON_HASH;
    }

    function creatorCoinCatalogJsonHash() internal pure returns (bytes32) {
        return CREATOR_COIN_CATALOG_JSON_HASH;
    }

    function creatorCoinCatalogEntryCount() internal pure returns (uint256) {
        return 1;
    }

    function routeArtifactCount() internal pure returns (uint256) {
        return 10;
    }

    function routeArtifactId(uint256 index) internal pure returns (string memory) {
        if (index == 0) return "solver-eth-weth-fame";
        if (index == 1) return "solver-eth-zora-basedflick-fame";
        if (index == 2) return "solver-fame-basedflick-zora-eth";
        if (index == 3) return "solver-fame-basedflick-zora-usdc";
        if (index == 4) return "solver-fame-basedflick-zora-weth";
        if (index == 5) return "solver-fame-weth-eth";
        if (index == 6) return "solver-usdc-aerodrome-weth-fame";
        if (index == 7) return "solver-usdc-split-frxusd-merge-fame";
        if (index == 8) return "solver-usdc-zora-basedflick-fame";
        if (index == 9) return "solver-weth-split-fame";
        revert("NO_SOLVER_ROUTE_ARTIFACT");
    }

    function requiredVenueTargetCount() internal pure returns (uint256) {
        return 7;
    }

    function requiredVenueTarget(uint256 index) internal pure returns (Target memory) {
        if (index == 0) return Target(FameRouterTypes.VenueFamily.AerodromeV2, 0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43);
        if (index == 1) return Target(FameRouterTypes.VenueFamily.NativeWrap, 0x4200000000000000000000000000000000000006);
        if (index == 2) return Target(FameRouterTypes.VenueFamily.Slipstream, 0xBE6D8f0d05cC4be24d5167a3eF062215bE6D18a5);
        if (index == 3) return Target(FameRouterTypes.VenueFamily.Solidly, 0x2F87Bf58D5A9b2eFadE55Cdbd46153a0902be6FA);
        if (index == 4) return Target(FameRouterTypes.VenueFamily.UniswapV2, 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24);
        if (index == 5) return Target(FameRouterTypes.VenueFamily.UniswapV3, 0x6fF5693b99212Da76ad316178A184AB56D299b43);
        if (index == 6) return Target(FameRouterTypes.VenueFamily.UniswapV4, 0x6fF5693b99212Da76ad316178A184AB56D299b43);
        revert("NO_SOLVER_REQUIRED_TARGET");
    }

    function requiredV4HookDataKeyCount() internal pure returns (uint256) {
        return 0;
    }

    function requiredV4HookDataKey(uint256 index) internal pure returns (bytes32) {
        index;
        revert("NO_SOLVER_REQUIRED_V4_HOOK_DATA_KEY");
    }
}
