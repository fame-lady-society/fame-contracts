// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {FameRouterTypes} from "../../src/router/FameRouterTypes.sol";
import {FameRouterFixtureManifest} from "./fixtures/FameRouterFixtureManifest.sol";

contract FameRouterFixtureCoverageTest is Test {
    string private constant POOLS_PATH = "test/router/fixtures/base-v1-pools.json";
    string private constant ROUTES_PATH = "test/router/fixtures/base-v1-routes.json";

    struct RouteFixtureForCoverage {
        string id;
        string[] poolIds;
    }

    function test_ManifestRecordsLaunchableFrozenSnapshotGate() public pure {
        assertEq(FameRouterFixtureManifest.poolFixtureCount(), 20);
        assertEq(FameRouterFixtureManifest.routeFixtureCount(), 20);
        assertEq(FameRouterFixtureManifest.poolMetadataCoverageCount(), 20);
        assertEq(FameRouterFixtureManifest.routeExecutionCoverageCount(), 20);
        assertEq(FameRouterFixtureManifest.requiredVenueTargetCount(), 8);
        assertEq(uint8(FameRouterFixtureManifest.requiredVenueFamily(6)), uint8(FameRouterTypes.VenueFamily.NativeWrap));
        assertEq(FameRouterFixtureManifest.requiredVenueTarget(6), 0x4200000000000000000000000000000000000006);
        assertEq(
            uint8(FameRouterFixtureManifest.requiredVenueFamily(7)), uint8(FameRouterTypes.VenueFamily.AerodromeV2)
        );
        assertEq(
            FameRouterFixtureManifest.requiredVenueTarget(7),
            address(bytes20(hex"cf77a3ba9a5ca399b7c97c74d54e5b1beb874e43"))
        );
        assertEq(FameRouterFixtureManifest.pendingLaunchBlockingPoolCount(), 0);
        assertEq(FameRouterFixtureManifest.pendingLaunchBlockingRouteCount(), 0);
        assertEq(FameRouterFixtureManifest.pendingLaunchBlockingFixtureCount(), 0);
        assertEq(FameRouterFixtureManifest.pinnedBaseBlock(), 45_884_844);
        assertTrue(FameRouterFixtureManifest.isLaunchable());
    }

    function test_ManifestHashesMatchFixtureJsonFiles() public view {
        uint256 pinnedBlock = FameRouterFixtureManifest.pinnedBaseBlock();
        bytes32 poolsHash = keccak256(bytes(vm.readFile(POOLS_PATH)));
        bytes32 routesHash = keccak256(bytes(vm.readFile(ROUTES_PATH)));

        assertEq(FameRouterFixtureManifest.poolsJsonHash(), poolsHash);
        assertEq(FameRouterFixtureManifest.routesJsonHash(), routesHash);
        assertEq(
            FameRouterFixtureManifest.snapshotHash(), keccak256(abi.encodePacked(pinnedBlock, poolsHash, routesHash))
        );
    }

    function test_ManifestCountsMatchFixtureJsonContent() public view {
        string memory poolsJson = vm.readFile(POOLS_PATH);
        string memory routesJson = vm.readFile(ROUTES_PATH);
        uint256 poolsPinnedBlock = _jsonPinnedBaseBlock(poolsJson);
        uint256 routesPinnedBlock = _jsonPinnedBaseBlock(routesJson);

        string[] memory pendingPools = abi.decode(vm.parseJson(poolsJson, ".pendingLaunchBlockingPools"), (string[]));
        string[] memory pendingRoutes = abi.decode(vm.parseJson(routesJson, ".pendingLaunchBlockingRoutes"), (string[]));
        uint256 poolCount = _jsonArrayLength(poolsJson, ".pools");
        uint256 routeCount = _jsonArrayLength(routesJson, ".routes");

        assertEq(FameRouterFixtureManifest.poolFixtureCount(), poolCount);
        assertEq(FameRouterFixtureManifest.routeFixtureCount(), routeCount);
        assertEq(FameRouterFixtureManifest.pendingLaunchBlockingPoolCount(), pendingPools.length);
        assertEq(FameRouterFixtureManifest.pendingLaunchBlockingRouteCount(), pendingRoutes.length);
        assertEq(FameRouterFixtureManifest.pinnedBaseBlock(), poolsPinnedBlock);
        assertEq(FameRouterFixtureManifest.pinnedBaseBlock(), routesPinnedBlock);
    }

    function test_CoverageTablesRepresentEveryFixtureForLaunch() public pure {
        assertEq(FameRouterFixtureManifest.poolMetadataCoverageCount(), FameRouterFixtureManifest.poolFixtureCount());
        assertEq(FameRouterFixtureManifest.routeExecutionCoverageCount(), FameRouterFixtureManifest.routeFixtureCount());
        assertTrue(FameRouterFixtureManifest.isLaunchable());
    }

    function test_RoutePoolReferencesMustExistInPoolFixtures() public pure {
        string[] memory poolIds = new string[](1);
        poolIds[0] = "known-pool";
        RouteFixtureForCoverage[] memory routes = new RouteFixtureForCoverage[](1);
        routes[0].id = "known-route";
        routes[0].poolIds = new string[](1);
        routes[0].poolIds[0] = "known-pool";

        assertTrue(_routePoolReferencesAreKnown(poolIds, routes));

        routes[0].poolIds[0] = "missing-pool";
        assertFalse(_routePoolReferencesAreKnown(poolIds, routes));
    }

    function test_ActualRoutePoolReferencesExistInPoolFixtures() public view {
        string memory poolsJson = vm.readFile(POOLS_PATH);
        string memory routesJson = vm.readFile(ROUTES_PATH);
        uint256 poolCount = _jsonArrayLength(poolsJson, ".pools");
        uint256 routeCount = _jsonArrayLength(routesJson, ".routes");

        string[] memory poolIds = new string[](poolCount);
        for (uint256 i; i < poolCount; ++i) {
            poolIds[i] = vm.parseJsonString(poolsJson, string.concat(".pools[", vm.toString(i), "].id"));
        }

        for (uint256 i; i < routeCount; ++i) {
            string[] memory routePoolIds =
                vm.parseJsonStringArray(routesJson, string.concat(".routes[", vm.toString(i), "].poolIds"));
            for (uint256 j; j < routePoolIds.length; ++j) {
                assertTrue(_contains(poolIds, routePoolIds[j]));
            }
        }
    }

    function test_PendingRouteListMatchesPendingMinimumPolicies() public view {
        string memory routesJson = vm.readFile(ROUTES_PATH);
        string[] memory pendingRoutes = abi.decode(vm.parseJson(routesJson, ".pendingLaunchBlockingRoutes"), (string[]));
        string[] memory coveredRoutes = _routeExecutionCoverageIds();
        uint256 routeCount = _jsonArrayLength(routesJson, ".routes");
        uint256 pendingPolicyCount;
        uint256 coveredPolicyCount;

        for (uint256 i; i < routeCount; ++i) {
            string memory routeKey = string.concat(".routes[", vm.toString(i), "]");
            string memory id = vm.parseJsonString(routesJson, string.concat(routeKey, ".id"));
            string memory minimumPolicy = vm.parseJsonString(routesJson, string.concat(routeKey, ".minimumPolicy"));
            bool isPending = _stringEq(minimumPolicy, "pending-frozen-fork-execution");
            assertEq(_contains(pendingRoutes, id), isPending);
            assertEq(_contains(coveredRoutes, id), !isPending);
            if (isPending) ++pendingPolicyCount;
            else ++coveredPolicyCount;
        }

        assertEq(FameRouterFixtureManifest.pendingLaunchBlockingRouteCount(), pendingPolicyCount);
        assertEq(FameRouterFixtureManifest.routeExecutionCoverageCount(), coveredPolicyCount);
    }

    function test_LaunchableRequiresNonzeroPinnedBaseBlock() public pure {
        assertGt(FameRouterFixtureManifest.pinnedBaseBlock(), 0);
        assertTrue(FameRouterFixtureManifest.isLaunchable());
    }

    function _jsonPinnedBaseBlock(string memory json) private pure returns (uint256) {
        bytes memory nullPinnedBlockNeedle = bytes('"pinnedBaseBlock": null');
        bytes memory raw = bytes(json);
        for (uint256 i; i + nullPinnedBlockNeedle.length <= raw.length; ++i) {
            bool matchesNeedle = true;
            for (uint256 j; j < nullPinnedBlockNeedle.length; ++j) {
                if (raw[i + j] != nullPinnedBlockNeedle[j]) {
                    matchesNeedle = false;
                    break;
                }
            }
            if (matchesNeedle) return 0;
        }

        return abi.decode(vm.parseJson(json, ".pinnedBaseBlock"), (uint256));
    }

    function _jsonArrayLength(string memory json, string memory key) private view returns (uint256 count) {
        while (vm.keyExistsJson(json, string.concat(key, "[", vm.toString(count), "]"))) {
            ++count;
        }
    }

    function _routePoolReferencesAreKnown(string[] memory poolIds, RouteFixtureForCoverage[] memory routes)
        private
        pure
        returns (bool)
    {
        for (uint256 i; i < routes.length; ++i) {
            for (uint256 j; j < routes[i].poolIds.length; ++j) {
                if (!_contains(poolIds, routes[i].poolIds[j])) return false;
            }
        }
        return true;
    }

    function _contains(string[] memory values, string memory needle) private pure returns (bool) {
        bytes32 needleHash = keccak256(bytes(needle));
        for (uint256 i; i < values.length; ++i) {
            if (keccak256(bytes(values[i])) == needleHash) return true;
        }
        return false;
    }

    function _routeExecutionCoverageIds() private pure returns (string[] memory ids) {
        uint256 count = FameRouterFixtureManifest.routeExecutionCoverageCount();
        ids = new string[](count);
        for (uint256 i; i < count; ++i) {
            ids[i] = FameRouterFixtureManifest.routeExecutionCoverageId(i);
        }
    }

    function _stringEq(string memory a, string memory b) private pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }
}
