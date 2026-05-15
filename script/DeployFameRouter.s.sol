// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {FameRouter} from "../src/FameRouter.sol";
import {FameRouterTypes} from "../src/router/FameRouterTypes.sol";
import {FameRouterFixtureManifest} from "../test/router/fixtures/FameRouterFixtureManifest.sol";

contract DeployFameRouter is Script {
    error RouterChainIdMismatch(uint256 expected, uint256 actual);
    error FeePpmMismatch(uint256 expected, uint256 actual);
    error FixtureSnapshotStillPending();
    error ZeroRouterOwner();

    function run() external returns (FameRouter router) {
        uint256 expectedChainId = vm.envUint("BASE_CHAIN_ID");
        if (block.chainid != expectedChainId) revert RouterChainIdMismatch(expectedChainId, block.chainid);

        uint256 deployerPrivateKey = vm.envUint("BASE_DEPLOYER_PRIVATE_KEY");
        address feeRecipient = vm.envAddress("BASE_FAME_ROUTER_FEE_RECIPIENT");
        address owner = vm.envOr("BASE_FAME_ROUTER_OWNER", vm.addr(deployerPrivateKey));
        uint256 expectedFeePpm = vm.envOr("BASE_FAME_ROUTER_FEE_PPM", uint256(FameRouterTypes.DEFAULT_FEE_PPM));

        vm.startBroadcast(deployerPrivateKey);
        router = deployConfiguredRouter(feeRecipient, owner, expectedFeePpm);
        vm.stopBroadcast();
    }

    function deployConfiguredRouter(address feeRecipient, address owner, uint256 expectedFeePpm)
        public
        returns (FameRouter router)
    {
        if (!FameRouterFixtureManifest.isLaunchable()) revert FixtureSnapshotStillPending();
        if (owner == address(0)) revert ZeroRouterOwner();
        if (expectedFeePpm != FameRouterTypes.DEFAULT_FEE_PPM) {
            revert FeePpmMismatch(expectedFeePpm, FameRouterTypes.DEFAULT_FEE_PPM);
        }

        router = new FameRouter(feeRecipient);
        _configureVenueTargets(router);
        if (router.owner() != owner) router.transferOwnership(owner);
    }

    function _configureVenueTargets(FameRouter router) private {
        for (uint256 i; i < FameRouterFixtureManifest.requiredVenueTargetCount(); ++i) {
            FameRouterTypes.VenueFamily family = FameRouterFixtureManifest.requiredVenueFamily(i);
            address target = FameRouterFixtureManifest.requiredVenueTarget(i);
            router.setVenueFamilyEnabled(family, true);
            router.setVenueTargetEnabled(family, target, true);
        }
    }
}
