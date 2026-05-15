// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {FameRouter} from "../src/FameRouter.sol";
import {FameRouterTypes} from "../src/router/FameRouterTypes.sol";
import {FameRouterFixtureManifest} from "../test/router/fixtures/FameRouterFixtureManifest.sol";

interface IFameSkipNft {
    function getSkipNFT(address owner) external view returns (bool);
}

interface IBaseRouterPoolMetadata {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function factory() external view returns (address);
    function stable() external view returns (bool);
    function tickSpacing() external view returns (int24);
    function fee() external view returns (uint24);
}

interface IV4StateView {
    function getSlot0(bytes32 poolId)
        external
        view
        returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee);
}

interface IAerodromeV2FactoryMetadata {
    function getPool(address tokenA, address tokenB, bool stable) external view returns (address);
    function getFee(address pool, bool stable) external view returns (uint256);
    function isPool(address pool) external view returns (bool);
}

contract ValidateFameRouterBase is Script {
    error RouterNotConfigured();
    error RouterChainIdMismatch(uint256 expected, uint256 actual);
    error RouterFeeRecipientMismatch(address expected, address actual);
    error RouterFeePpmMismatch(uint256 expected, uint256 actual);
    error RouterOwnerMismatch(address expected, address actual);
    error RouterVenueFamilyDisabled(FameRouterTypes.VenueFamily family);
    error RouterVenueTargetDisabled(FameRouterTypes.VenueFamily family, address target);
    error RouterSkipNftDisabled();
    error FixtureSnapshotStillPending();
    error FixtureSchemaMismatch(uint256 expected, uint256 actual);
    error FixtureSnapshotHashMismatch(bytes32 expected, bytes32 actual);
    error FixtureCodeMissing(address target);
    error FixturePoolTokenMismatch(string id);
    error FixturePoolFactoryMismatch(string id);
    error FixturePoolIdentityMismatch(string id);
    error FixturePoolStableMismatch(string id);
    error FixturePoolTickSpacingMismatch(string id);
    error FixturePoolFeeMismatch(string id);
    error FixtureV4PoolIdMismatch(string id);
    error FixtureV4PoolUninitialized(string id);

    function run() external view {
        address routerAddress = vm.envAddress("BASE_FAME_ROUTER_ADDRESS");
        address fameAddress = vm.envAddress("BASE_FAME_ADDRESS");
        if (routerAddress == address(0) || fameAddress == address(0)) revert RouterNotConfigured();

        FameRouter router = FameRouter(payable(routerAddress));
        validateRouterConfiguration(router);
        validateRequiredVenueTargets(router);
        validateFixtureParity();
        validateSkipNft(fameAddress, routerAddress);
        validateLaunchableManifest();
        if (block.chainid == 8453) validateLivePoolMetadata();
    }

    function validateRouterConfiguration(FameRouter router) public view {
        uint256 expectedChainId = vm.envUint("BASE_CHAIN_ID");
        address expectedFeeRecipient = vm.envAddress("BASE_FAME_ROUTER_FEE_RECIPIENT");
        uint256 expectedFeePpm = vm.envUint("BASE_FAME_ROUTER_FEE_PPM");
        address expectedOwner = vm.envOr("BASE_FAME_ROUTER_OWNER", address(0));

        if (block.chainid != expectedChainId) revert RouterChainIdMismatch(expectedChainId, block.chainid);
        if (router.feeRecipient() != expectedFeeRecipient) {
            revert RouterFeeRecipientMismatch(expectedFeeRecipient, router.feeRecipient());
        }
        if (router.feePpm() != expectedFeePpm) revert RouterFeePpmMismatch(expectedFeePpm, router.feePpm());
        if (expectedOwner != address(0) && router.owner() != expectedOwner) {
            revert RouterOwnerMismatch(expectedOwner, router.owner());
        }
    }

    function validateRequiredVenueTargets(FameRouter router) public view {
        for (uint256 i; i < FameRouterFixtureManifest.requiredVenueTargetCount(); ++i) {
            validateVenueTarget(
                router,
                FameRouterFixtureManifest.requiredVenueFamily(i),
                FameRouterFixtureManifest.requiredVenueTarget(i)
            );
        }
    }

    function validateVenueTarget(FameRouter router, FameRouterTypes.VenueFamily family, address target) public view {
        if (!router.venueFamilyEnabled(family)) revert RouterVenueFamilyDisabled(family);
        if (!router.venueTargetEnabled(family, target)) revert RouterVenueTargetDisabled(family, target);
    }

    function validateFixtureParity() public view {
        validateFixtureParityExpected(
            vm.envUint("BASE_FAME_ROUTER_SCHEMA_VERSION"), vm.envBytes32("BASE_FAME_ROUTER_FIXTURE_SNAPSHOT_HASH")
        );
    }

    function validateFixtureParityExpected(uint256 expectedSchemaVersion, bytes32 expectedSnapshotHash) public pure {
        if (expectedSchemaVersion != FameRouterTypes.SCHEMA_VERSION) {
            revert FixtureSchemaMismatch(expectedSchemaVersion, FameRouterTypes.SCHEMA_VERSION);
        }
        if (expectedSnapshotHash != FameRouterFixtureManifest.snapshotHash()) {
            revert FixtureSnapshotHashMismatch(expectedSnapshotHash, FameRouterFixtureManifest.snapshotHash());
        }
    }

    function validateSkipNft(address fameAddress, address routerAddress) public view {
        if (!IFameSkipNft(fameAddress).getSkipNFT(routerAddress)) revert RouterSkipNftDisabled();
    }

    function validateLaunchableManifest() public pure {
        if (!FameRouterFixtureManifest.isLaunchable()) revert FixtureSnapshotStillPending();
    }

    function validateLivePoolMetadata() public view {
        string memory poolsJson = vm.readFile("test/router/fixtures/base-v1-pools.json");
        uint256 poolCount = _jsonArrayLength(poolsJson, ".pools");

        for (uint256 i; i < poolCount; ++i) {
            string memory key = string.concat(".pools[", vm.toString(i), "]");
            string memory venue = vm.parseJsonString(poolsJson, string.concat(key, ".venue"));

            if (_hasKey(poolsJson, key, "router")) {
                _assertCode(vm.parseJsonAddress(poolsJson, string.concat(key, ".router")));
            }
            if (_hasKey(poolsJson, key, "factory")) {
                _assertCode(vm.parseJsonAddress(poolsJson, string.concat(key, ".factory")));
            }

            if (_stringEq(venue, "uniswap-v4")) {
                _validateV4PoolMetadata(poolsJson, key);
            } else {
                _validateErc20PoolMetadata(poolsJson, key, venue);
            }
        }
    }

    function _validateErc20PoolMetadata(string memory poolsJson, string memory key, string memory venue) private view {
        string memory id = vm.parseJsonString(poolsJson, string.concat(key, ".id"));
        address pool = vm.parseJsonAddress(poolsJson, string.concat(key, ".pool"));
        address token0 = vm.parseJsonAddress(poolsJson, string.concat(key, ".token0"));
        address token1 = vm.parseJsonAddress(poolsJson, string.concat(key, ".token1"));
        IBaseRouterPoolMetadata metadata = IBaseRouterPoolMetadata(pool);

        _assertCode(pool);
        _assertCode(token0);
        _assertCode(token1);
        if (metadata.token0() != token0 || metadata.token1() != token1) revert FixturePoolTokenMismatch(id);

        if (_hasKey(poolsJson, key, "factory")) {
            if (metadata.factory() != vm.parseJsonAddress(poolsJson, string.concat(key, ".factory"))) {
                revert FixturePoolFactoryMismatch(id);
            }
        }
        if (_stringEq(venue, "solidly") || _stringEq(venue, "aerodrome-v2")) {
            if (metadata.stable() != vm.parseJsonBool(poolsJson, string.concat(key, ".stable"))) {
                revert FixturePoolStableMismatch(id);
            }
        }
        if (_stringEq(venue, "aerodrome-v2")) {
            address factory = vm.parseJsonAddress(poolsJson, string.concat(key, ".factory"));
            bool stable = vm.parseJsonBool(poolsJson, string.concat(key, ".stable"));
            IAerodromeV2FactoryMetadata aerodromeFactory = IAerodromeV2FactoryMetadata(factory);
            if (aerodromeFactory.getPool(token0, token1, stable) != pool || !aerodromeFactory.isPool(pool)) {
                revert FixturePoolIdentityMismatch(id);
            }
            if (aerodromeFactory.getFee(pool, stable) != vm.parseJsonUint(poolsJson, string.concat(key, ".feeBps"))) {
                revert FixturePoolFeeMismatch(id);
            }
        }
        if (
            _stringEq(venue, "aerodrome-slipstream") || _stringEq(venue, "aerodrome-slipstream2")
                || _stringEq(venue, "uniswap-v3")
        ) {
            if (metadata.tickSpacing() != vm.parseJsonInt(poolsJson, string.concat(key, ".tickSpacing"))) {
                revert FixturePoolTickSpacingMismatch(id);
            }
        }
        if (_stringEq(venue, "uniswap-v3")) {
            if (metadata.fee() != uint24(vm.parseJsonUint(poolsJson, string.concat(key, ".fee")))) {
                revert FixturePoolFeeMismatch(id);
            }
        }
    }

    function _validateV4PoolMetadata(string memory poolsJson, string memory key) private view {
        string memory id = vm.parseJsonString(poolsJson, string.concat(key, ".id"));
        address poolManager = vm.parseJsonAddress(poolsJson, string.concat(key, ".poolManager"));
        address stateView = vm.parseJsonAddress(poolsJson, string.concat(key, ".stateView"));
        address currency0 = vm.parseJsonAddress(poolsJson, string.concat(key, ".currency0"));
        address currency1 = vm.parseJsonAddress(poolsJson, string.concat(key, ".currency1"));
        address hooks = vm.parseJsonAddress(poolsJson, string.concat(key, ".hooks"));
        uint24 fee = uint24(vm.parseJsonUint(poolsJson, string.concat(key, ".fee")));
        int24 tickSpacing = int24(vm.parseJsonInt(poolsJson, string.concat(key, ".tickSpacing")));
        bytes32 poolId = vm.parseJsonBytes32(poolsJson, string.concat(key, ".poolId"));
        bytes32 derivedPoolId = keccak256(abi.encode(currency0, currency1, fee, tickSpacing, hooks));

        if (poolId != derivedPoolId) revert FixtureV4PoolIdMismatch(id);
        _assertCode(poolManager);
        _assertCode(stateView);
        if (currency0 != address(0)) _assertCode(currency0);
        if (currency1 != address(0)) _assertCode(currency1);
        if (hooks != address(0)) _assertCode(hooks);

        (uint160 sqrtPriceX96,,,) = IV4StateView(stateView).getSlot0(poolId);
        if (sqrtPriceX96 == 0) revert FixtureV4PoolUninitialized(id);
    }

    function _assertCode(address target) private view {
        if (target.code.length == 0) revert FixtureCodeMissing(target);
    }

    function _jsonArrayLength(string memory json, string memory key) private view returns (uint256 count) {
        while (vm.keyExistsJson(json, string.concat(key, "[", vm.toString(count), "]"))) {
            ++count;
        }
    }

    function _hasKey(string memory json, string memory objectKey, string memory field) private view returns (bool) {
        return vm.keyExistsJson(json, string.concat(objectKey, ".", field));
    }

    function _stringEq(string memory a, string memory b) private pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }
}
