// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DeployFameRouter} from "../../script/DeployFameRouter.s.sol";
import {ValidateFameRouterBase} from "../../script/ValidateFameRouterBase.s.sol";
import {FameRouter} from "../../src/FameRouter.sol";
import {FameRouterTypes} from "../../src/router/FameRouterTypes.sol";
import {FameRouterFixtureManifest} from "./fixtures/FameRouterFixtureManifest.sol";

contract FameRouterDeploymentValidationTest is Test {
    address private feeRecipient = address(0x1004);
    address private owner = address(0x1001);
    ValidateFameRouterBase private validator;

    function setUp() public {
        validator = new ValidateFameRouterBase();
        _setBaseRouterEnv();
    }

    function test_DeployConfiguredRouterRequiresLaunchableManifest() public {
        DeployFameRouter deployer = new DeployFameRouter();

        FameRouter router = deployer.deployConfiguredRouter(feeRecipient, owner, FameRouterTypes.DEFAULT_FEE_PPM);

        assertEq(router.owner(), owner);
        assertEq(router.feeRecipient(), feeRecipient);
        assertEq(router.feePpm(), FameRouterTypes.DEFAULT_FEE_PPM);
        _assertManifestVenueTargetsEnabled(router);
        assertTrue(FameRouterFixtureManifest.isLaunchable());
    }

    function test_DeployRunFailsOnWrongChainBeforeBroadcast() public {
        uint256 expectedChainId = block.chainid;
        uint256 wrongChainId = expectedChainId + 1;
        vm.chainId(wrongChainId);
        DeployFameRouter deployer = new DeployFameRouter();

        vm.expectRevert(
            abi.encodeWithSelector(DeployFameRouter.RouterChainIdMismatch.selector, expectedChainId, wrongChainId)
        );
        deployer.run();
    }

    function test_RouterConstructorInitializesConfigForValidation() public {
        FameRouter router = new FameRouter(feeRecipient);
        router.transferOwnership(owner);

        assertEq(router.feeRecipient(), feeRecipient);
        assertEq(router.feePpm(), FameRouterTypes.DEFAULT_FEE_PPM);
        assertEq(router.owner(), owner);
    }

    function test_LaunchabilityRequiresManifestVenueTargets() public pure {
        assertTrue(FameRouterFixtureManifest.isLaunchable());
        assertEq(FameRouterFixtureManifest.requiredVenueTargetCount(), 8);
    }

    function test_ValidationRunPassesWhenManifestIsLaunchable() public {
        FameRouter router = new FameRouter(feeRecipient);
        MockFameSkipNft fame = new MockFameSkipNft(true);
        _enableManifestVenueTargets(router);
        router.transferOwnership(owner);

        vm.setEnv("BASE_FAME_ROUTER_ADDRESS", vm.toString(address(router)));
        vm.setEnv("BASE_FAME_ADDRESS", vm.toString(address(fame)));

        validator.run();
    }

    function test_ValidationRunFailsWhenSkipNftDisabled() public {
        FameRouter router = new FameRouter(feeRecipient);
        MockFameSkipNft fame = new MockFameSkipNft(false);
        _enableManifestVenueTargets(router);
        router.transferOwnership(owner);

        vm.setEnv("BASE_FAME_ROUTER_ADDRESS", vm.toString(address(router)));
        vm.setEnv("BASE_FAME_ADDRESS", vm.toString(address(fame)));

        vm.expectRevert(ValidateFameRouterBase.RouterSkipNftDisabled.selector);
        validator.run();
    }

    function test_ValidationPassesConfiguredRouterChecks() public {
        _setBaseRouterEnv();
        FameRouter router = new FameRouter(feeRecipient);
        router.transferOwnership(owner);
        vm.startPrank(owner);
        _enableManifestVenueTargets(router);
        vm.stopPrank();

        validator.validateRouterConfiguration(router);
        validator.validateFixtureParity();
        validator.validateRequiredVenueTargets(router);
    }

    function test_ValidationFailsWhenFixtureVenueFamilyDisabled() public {
        FameRouter router = new FameRouter(feeRecipient);

        vm.expectRevert(
            abi.encodeWithSelector(
                ValidateFameRouterBase.RouterVenueFamilyDisabled.selector, FameRouterTypes.VenueFamily.UniswapV2
            )
        );
        validator.validateVenueTarget(router, FameRouterTypes.VenueFamily.UniswapV2, address(0xBEEF));
    }

    function test_ValidationFailsWhenFixtureVenueTargetDisabled() public {
        FameRouter router = new FameRouter(feeRecipient);
        router.setVenueFamilyEnabled(FameRouterTypes.VenueFamily.UniswapV2, true);

        vm.expectRevert(
            abi.encodeWithSelector(
                ValidateFameRouterBase.RouterVenueTargetDisabled.selector,
                FameRouterTypes.VenueFamily.UniswapV2,
                address(0xBEEF)
            )
        );
        validator.validateVenueTarget(router, FameRouterTypes.VenueFamily.UniswapV2, address(0xBEEF));
    }

    function test_ValidationFailsWhenSkipNftDisabled() public {
        MockFameSkipNft fame = new MockFameSkipNft(false);

        vm.expectRevert(ValidateFameRouterBase.RouterSkipNftDisabled.selector);
        validator.validateSkipNft(address(fame), address(0xCAFE));
    }

    function test_ValidationFailsWhenFixtureSnapshotHashMismatches() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ValidateFameRouterBase.FixtureSnapshotHashMismatch.selector,
                bytes32(uint256(1)),
                FameRouterFixtureManifest.snapshotHash()
            )
        );
        validator.validateFixtureParityExpected(uint256(FameRouterTypes.SCHEMA_VERSION), bytes32(uint256(1)));
    }

    function test_ValidationPassesWhenManifestLaunchable() public view {
        validator.validateLaunchableManifest();
    }

    function _setBaseRouterEnv() private {
        vm.setEnv("BASE_CHAIN_ID", vm.toString(block.chainid));
        vm.setEnv("BASE_FAME_ROUTER_FEE_RECIPIENT", vm.toString(feeRecipient));
        vm.setEnv("BASE_FAME_ROUTER_FEE_PPM", vm.toString(uint256(FameRouterTypes.DEFAULT_FEE_PPM)));
        vm.setEnv("BASE_FAME_ROUTER_OWNER", vm.toString(owner));
        vm.setEnv("BASE_FAME_ROUTER_SCHEMA_VERSION", vm.toString(uint256(FameRouterTypes.SCHEMA_VERSION)));
        vm.setEnv("BASE_FAME_ROUTER_FIXTURE_SNAPSHOT_HASH", vm.toString(FameRouterFixtureManifest.snapshotHash()));
    }

    function _enableManifestVenueTargets(FameRouter router) private {
        for (uint256 i; i < FameRouterFixtureManifest.requiredVenueTargetCount(); ++i) {
            FameRouterTypes.VenueFamily family = FameRouterFixtureManifest.requiredVenueFamily(i);
            router.setVenueFamilyEnabled(family, true);
            router.setVenueTargetEnabled(family, FameRouterFixtureManifest.requiredVenueTarget(i), true);
        }
    }

    function _assertManifestVenueTargetsEnabled(FameRouter router) private view {
        for (uint256 i; i < FameRouterFixtureManifest.requiredVenueTargetCount(); ++i) {
            FameRouterTypes.VenueFamily family = FameRouterFixtureManifest.requiredVenueFamily(i);
            address target = FameRouterFixtureManifest.requiredVenueTarget(i);
            assertTrue(router.venueFamilyEnabled(family));
            assertTrue(router.venueTargetEnabled(family, target));
        }
    }
}

contract MockFameSkipNft {
    bool private immutable skipNft;

    constructor(bool skipNft_) {
        skipNft = skipNft_;
    }

    function getSkipNFT(address) external view returns (bool) {
        return skipNft;
    }
}
