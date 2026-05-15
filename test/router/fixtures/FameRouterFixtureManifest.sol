// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FameRouterTypes} from "../../../src/router/FameRouterTypes.sol";

library FameRouterFixtureManifest {
    uint256 internal constant PINNED_BASE_BLOCK = 45_884_844;
    bytes32 internal constant POOLS_JSON_HASH = 0x0e6d99303e09c7aba6e4de2b4b20d9b0909fef717ab051b134c52e295b6de531;
    bytes32 internal constant ROUTES_JSON_HASH = 0xcb6934fe75f4f56ccdfd2ce4b3c127d93e2cf25d651ebff47d470727b4437c27;
    bytes32 internal constant SNAPSHOT_HASH = 0x956774c7440cd09745a9763b19e89902a7be867f3b722a44e6dbb32cc8e44328;

    function pinnedBaseBlock() internal pure returns (uint256) {
        return PINNED_BASE_BLOCK;
    }

    function snapshotHash() internal pure returns (bytes32) {
        return SNAPSHOT_HASH;
    }

    function poolsJsonHash() internal pure returns (bytes32) {
        return POOLS_JSON_HASH;
    }

    function routesJsonHash() internal pure returns (bytes32) {
        return ROUTES_JSON_HASH;
    }

    function poolFixtureCount() internal pure returns (uint256) {
        return 20;
    }

    function routeFixtureCount() internal pure returns (uint256) {
        return 20;
    }

    function poolMetadataCoverageCount() internal pure returns (uint256) {
        return 20;
    }

    function routeExecutionCoverageCount() internal pure returns (uint256) {
        return 20;
    }

    function routeExecutionCoverageId(uint256 index) internal pure returns (string memory) {
        if (index == 0) return "solidly-weth-fame-buy";
        if (index == 1) return "solidly-weth-fame-sell";
        if (index == 2) return "solidly-usdc-frxusd-fame-buy";
        if (index == 3) return "solidly-usdc-scale-fame-buy";
        if (index == 4) return "slipstream-basedflick-fame-buy";
        if (index == 5) return "slipstream-basedflick-fame-sell";
        if (index == 6) return "slipstream2-msusd-mseth-buy";
        if (index == 7) return "slipstream2-msusd-mseth-sell";
        if (index == 8) return "slipstream2-msusd-usdc-c-buy";
        if (index == 9) return "slipstream2-msusd-usdc-c-sell";
        if (index == 10) return "uniswap-v2-fame-buy";
        if (index == 11) return "uniswap-v2-fame-sell";
        if (index == 12) return "aerodrome-v2-usdc-weth-buy";
        if (index == 13) return "uniswap-v3-zora-usdc-buy";
        if (index == 14) return "uniswap-v3-zora-usdc-sell";
        if (index == 15) return "uniswap-v3-zora-weth-buy";
        if (index == 16) return "uniswap-v3-zora-weth-sell";
        if (index == 17) return "uniswap-v4-basedflick-zora-buy";
        if (index == 18) return "uniswap-v4-basedflick-zora-sell";
        if (index == 19) return "uniswap-v4-zora-eth-native";
        revert("NO_ROUTE_EXECUTION_COVERAGE");
    }

    function requiredVenueTargetCount() internal pure returns (uint256) {
        return 8;
    }

    function requiredVenueFamily(uint256 index) internal pure returns (FameRouterTypes.VenueFamily) {
        if (index == 0) return FameRouterTypes.VenueFamily.Solidly;
        if (index == 1) return FameRouterTypes.VenueFamily.UniswapV2;
        if (index == 2) return FameRouterTypes.VenueFamily.Slipstream;
        if (index == 3) return FameRouterTypes.VenueFamily.Slipstream2;
        if (index == 4) return FameRouterTypes.VenueFamily.UniswapV3;
        if (index == 5) return FameRouterTypes.VenueFamily.UniswapV4;
        if (index == 6) return FameRouterTypes.VenueFamily.NativeWrap;
        if (index == 7) return FameRouterTypes.VenueFamily.AerodromeV2;
        revert("NO_REQUIRED_VENUE_TARGET");
    }

    function requiredVenueTarget(uint256 index) internal pure returns (address) {
        if (index == 0) return address(bytes20(hex"2f87bf58d5a9b2efade55cdbd46153a0902be6fa"));
        if (index == 1) return address(bytes20(hex"4752ba5dbc23f44d87826276bf6fd6b1c372ad24"));
        if (index == 2) return address(bytes20(hex"be6d8f0d05cc4be24d5167a3ef062215be6d18a5"));
        if (index == 3) return address(bytes20(hex"cbbb8035cac7d4b3ca7abb74cf7bdf900215ce0d"));
        if (index == 4) return address(bytes20(hex"6ff5693b99212da76ad316178a184ab56d299b43"));
        if (index == 5) return address(bytes20(hex"6ff5693b99212da76ad316178a184ab56d299b43"));
        if (index == 6) return 0x4200000000000000000000000000000000000006;
        if (index == 7) return address(bytes20(hex"cf77a3ba9a5ca399b7c97c74d54e5b1beb874e43"));
        revert("NO_REQUIRED_VENUE_TARGET");
    }

    function pendingLaunchBlockingFixtureCount() internal pure returns (uint256) {
        return pendingLaunchBlockingPoolCount() + pendingLaunchBlockingRouteCount();
    }

    function pendingLaunchBlockingPoolCount() internal pure returns (uint256) {
        return 0;
    }

    function pendingLaunchBlockingRouteCount() internal pure returns (uint256) {
        return 0;
    }

    function isLaunchable() internal pure returns (bool) {
        return pinnedBaseBlock() != 0 && poolFixtureCount() != 0 && routeFixtureCount() != 0
            && poolMetadataCoverageCount() == poolFixtureCount() && routeExecutionCoverageCount() == routeFixtureCount()
            && requiredVenueTargetCount() != 0 && pendingLaunchBlockingFixtureCount() == 0;
    }
}
