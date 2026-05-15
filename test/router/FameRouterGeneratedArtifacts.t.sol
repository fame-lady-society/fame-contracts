// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {FameRouterTypes} from "../../src/router/FameRouterTypes.sol";
import {UniversalRouterAdapter} from "../../src/router/adapters/UniversalRouterAdapter.sol";
import {FameRouterSolverFixtureManifest} from "./fixtures/FameRouterSolverFixtureManifest.sol";

contract FameRouterGeneratedArtifactsTest is Test {
    string private constant SOLVER_ROUTES_PATH = "test/router/fixtures/base-v1-solver-routes.json";
    string private constant GAP_MATRIX_PATH = "test/router/fixtures/base-v1-route-gap-matrix.json";
    string private constant PARITY_VECTORS_PATH = "test/router/fixtures/base-v1-route-parity-vectors.json";
    string private constant CREATOR_COIN_CATALOG_PATH = "test/router/fixtures/base-v1-creator-coin-catalog.json";

    function test_SolverManifestHashesMatchGeneratedFiles() public view {
        assertEq(
            FameRouterSolverFixtureManifest.solverRoutesJsonHash(), keccak256(bytes(vm.readFile(SOLVER_ROUTES_PATH)))
        );
        assertEq(FameRouterSolverFixtureManifest.gapMatrixJsonHash(), keccak256(bytes(vm.readFile(GAP_MATRIX_PATH))));
        assertEq(
            FameRouterSolverFixtureManifest.parityVectorsJsonHash(), keccak256(bytes(vm.readFile(PARITY_VECTORS_PATH)))
        );
        assertEq(
            FameRouterSolverFixtureManifest.creatorCoinCatalogJsonHash(),
            keccak256(bytes(vm.readFile(CREATOR_COIN_CATALOG_PATH)))
        );
    }

    function test_CreatorCoinCatalogRecordsHookAddressPolicy() public view {
        string memory json = vm.readFile(CREATOR_COIN_CATALOG_PATH);
        assertEq(_jsonArrayLength(json, ".entries"), FameRouterSolverFixtureManifest.creatorCoinCatalogEntryCount());
        assertEq(FameRouterSolverFixtureManifest.creatorCoinCatalogEntryCount(), 1);
        assertEq(vm.parseJsonString(json, ".entries[0].id"), "creator-basedflick-zora");
        assertEq(vm.parseJsonString(json, ".entries[0].poolConfigId"), "uniswap-v4-basedflick-zora");
        assertEq(
            vm.parseJsonBytes32(json, ".entries[0].v4PoolId"),
            0x0fe6333346fcd0ffa4be3fda91f271bda52c6755f604b06483b709666d363628
        );
        assertEq(vm.parseJsonString(json, ".entries[0].swapHookDataPolicy"), "empty");
        assertEq(vm.parseJsonBytes(json, ".entries[0].hookData"), bytes(""));
        assertTrue(vm.parseJsonBool(json, ".entries[0].proves.hookAddressSwap"));
        assertFalse(vm.parseJsonBool(json, ".entries[0].proves.nonEmptySwapHookData"));
    }

    function test_GeneratedRouteArtifactsMatchSolidityAbiEncoding() public view {
        string memory json = vm.readFile(SOLVER_ROUTES_PATH);
        assertEq(_jsonArrayLength(json, ".routes"), FameRouterSolverFixtureManifest.routeArtifactCount());
        for (uint256 i; i < FameRouterSolverFixtureManifest.routeArtifactCount(); ++i) {
            string memory key = string.concat(".routes[", vm.toString(i), "]");
            assertEq(vm.parseJsonString(json, string.concat(key, ".id")), FameRouterSolverFixtureManifest.routeArtifactId(i));
            FameRouterTypes.Route memory route = _loadRoute(json, string.concat(key, ".route"));
            bytes memory abiEncodedRoute = vm.parseJsonBytes(json, string.concat(key, ".abiEncodedRoute"));
            bytes32 routeHash = vm.parseJsonBytes32(json, string.concat(key, ".routeHash"));

            assertEq(keccak256(abiEncodedRoute), routeHash);
            assertEq(keccak256(abi.encode(route)), routeHash);
            assertEq(keccak256(abi.encode(route)), keccak256(abiEncodedRoute));
        }
    }

    function test_ParityVectorArtifactsMatchSolidityAbiEncoding() public view {
        string memory json = vm.readFile(PARITY_VECTORS_PATH);
        assertEq(_jsonArrayLength(json, ".vectors"), FameRouterSolverFixtureManifest.routeArtifactCount());
        for (uint256 i; i < FameRouterSolverFixtureManifest.routeArtifactCount(); ++i) {
            string memory key = string.concat(".vectors[", vm.toString(i), "]");
            assertEq(vm.parseJsonString(json, string.concat(key, ".id")), FameRouterSolverFixtureManifest.routeArtifactId(i));
            FameRouterTypes.Route memory route = _loadRoute(json, string.concat(key, ".route"));
            bytes memory abiEncodedRoute = vm.parseJsonBytes(json, string.concat(key, ".abiEncodedRoute"));
            bytes32 routeHash = vm.parseJsonBytes32(json, string.concat(key, ".routeHash"));

            assertEq(keccak256(abiEncodedRoute), routeHash);
            assertEq(keccak256(abi.encode(route)), routeHash);
        }
    }

    function test_GapMatrixReferencesGeneratedArtifactsAndHookDataKeys() public view {
        string memory gapJson = vm.readFile(GAP_MATRIX_PATH);
        string memory routesJson = vm.readFile(SOLVER_ROUTES_PATH);
        uint256 generatedRows;

        for (uint256 i; i < _jsonArrayLength(gapJson, ".rows"); ++i) {
            string memory rowKey = string.concat(".rows[", vm.toString(i), "]");
            if (!vm.parseJsonBool(gapJson, string.concat(rowKey, ".tsGenerated"))) continue;
            string memory artifactId = vm.parseJsonString(gapJson, string.concat(rowKey, ".routeArtifactId"));
            assertTrue(_manifestHasRouteId(artifactId));
            ++generatedRows;
        }
        assertGe(generatedRows, FameRouterSolverFixtureManifest.routeArtifactCount());

        uint256 hookDataKeyCount;
        for (uint256 i; i < FameRouterSolverFixtureManifest.routeArtifactCount(); ++i) {
            FameRouterTypes.Route memory route =
                _loadRoute(routesJson, string.concat(".routes[", vm.toString(i), "].route"));
            for (uint256 j; j < route.legs.length; ++j) {
                if (route.legs[j].venue != FameRouterTypes.VenueFamily.UniswapV4) continue;
                UniversalRouterAdapter.V4SwapPayload memory payload =
                    abi.decode(route.legs[j].data, (UniversalRouterAdapter.V4SwapPayload));
                if (payload.hookData.length != 0) {
                    ++hookDataKeyCount;
                }
            }
        }
        assertEq(hookDataKeyCount, FameRouterSolverFixtureManifest.requiredV4HookDataKeyCount());
    }

    function _manifestHasRouteId(string memory routeId) private pure returns (bool) {
        for (uint256 i; i < FameRouterSolverFixtureManifest.routeArtifactCount(); ++i) {
            if (_stringEq(FameRouterSolverFixtureManifest.routeArtifactId(i), routeId)) return true;
        }
        return false;
    }

    function _loadRoute(string memory json, string memory key)
        internal
        view
        returns (FameRouterTypes.Route memory route)
    {
        route.version = uint16(vm.parseJsonUint(json, string.concat(key, ".version")));
        route.tokenIn = vm.parseJsonAddress(json, string.concat(key, ".tokenIn"));
        route.tokenOut = vm.parseJsonAddress(json, string.concat(key, ".tokenOut"));
        route.amountIn = vm.parseUint(vm.parseJsonString(json, string.concat(key, ".amountIn")));
        route.minAmountOutAfterFee = vm.parseUint(vm.parseJsonString(json, string.concat(key, ".minAmountOutAfterFee")));
        route.recipient = vm.parseJsonAddress(json, string.concat(key, ".recipient"));
        route.deadline = vm.parseUint(vm.parseJsonString(json, string.concat(key, ".deadline")));

        uint256 legCount = _jsonArrayLength(json, string.concat(key, ".legs"));
        route.legs = new FameRouterTypes.Leg[](legCount);
        for (uint256 i; i < legCount; ++i) {
            string memory legKey = string.concat(key, ".legs[", vm.toString(i), "]");
            route.legs[i] = FameRouterTypes.Leg({
                tokenIn: vm.parseJsonAddress(json, string.concat(legKey, ".tokenIn")),
                tokenOut: vm.parseJsonAddress(json, string.concat(legKey, ".tokenOut")),
                venue: FameRouterTypes.VenueFamily(
                    uint8(vm.parseJsonUint(json, string.concat(legKey, ".venueOrdinal")))
                ),
                amountMode: FameRouterTypes.AmountMode(
                    uint8(vm.parseJsonUint(json, string.concat(legKey, ".amountModeOrdinal")))
                ),
                amount: vm.parseUint(vm.parseJsonString(json, string.concat(legKey, ".amount"))),
                minAmountOut: vm.parseUint(vm.parseJsonString(json, string.concat(legKey, ".minAmountOut"))),
                target: vm.parseJsonAddress(json, string.concat(legKey, ".target")),
                data: vm.parseJsonBytes(json, string.concat(legKey, ".data"))
            });
        }
    }

    function _jsonArrayLength(string memory json, string memory key) private view returns (uint256 count) {
        while (vm.keyExistsJson(json, string.concat(key, "[", vm.toString(count), "]"))) {
            ++count;
        }
    }

    function _stringEq(string memory a, string memory b) private pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }
}
