// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {UniversalPoolArtMarketplace} from "../src/UniversalPoolArtMarketplace.sol";
import {
    ValidateBaseSepoliaUniversalPoolArtMarketplace
} from "../script/ValidateBaseSepoliaUniversalPoolArtMarketplace.s.sol";
import {
    DeployBaseSepoliaUniversalPoolArtMarketplace
} from "../script/DeployBaseSepoliaUniversalPoolArtMarketplace.s.sol";
import {UniversalPoolArtMarketplaceTestBase} from "./helpers/UniversalPoolArtMarketplaceTestBase.sol";

contract UniversalPoolArtMarketplaceDeploymentValidationTest is UniversalPoolArtMarketplaceTestBase {
    uint256 internal constant MINIMUM_INVENTORY = 0;
    uint256 internal constant FAME_SKIP_MANAGER_ROLE = 1 << 3;
    uint256 internal constant CREATOR_MAGIC_CREATOR_ROLE = 1 << 1;
    uint256 internal constant CREATOR_MAGIC_ART_POOL_MANAGER_ROLE = 1 << 3;

    ValidateBaseSepoliaUniversalPoolArtMarketplace internal validator;
    DeployBaseSepoliaUniversalPoolArtMarketplace internal deployer;

    function setUp() public override {
        super.setUp();
        validator = new ValidateBaseSepoliaUniversalPoolArtMarketplace();
        deployer = new DeployBaseSepoliaUniversalPoolArtMarketplace();
        creatorMagic.grantRoles(address(market), CREATOR_MAGIC_BANISHER_ROLE);
    }

    function _fameName() internal pure override returns (string memory) {
        return "Example";
    }

    function _fameSymbol() internal pure override returns (string memory) {
        return "TEST";
    }

    function testValidationPassesForPausedConfiguredMarketplace() public view {
        _validate(true);
    }

    function testValidationPassesAfterExplicitActivation() public {
        market.unpause();
        _validate(false);
    }

    function testValidationRejectsWrongChainBeforeReadingEnvironment() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ValidateBaseSepoliaUniversalPoolArtMarketplace.ChainIdMismatch.selector, uint256(84532), block.chainid
            )
        );
        validator.run();
    }

    function testValidationRejectsWrongOwnerFeePremiumAndPause() public {
        uint256 configuredPremium = market.premium();

        vm.expectRevert(
            abi.encodeWithSelector(
                ValidateBaseSepoliaUniversalPoolArtMarketplace.AddressMismatch.selector,
                "marketplace.owner",
                address(0xBEEF),
                owner
            )
        );
        _validateMarket(market, address(0xBEEF), feeRecipient, configuredPremium, MINIMUM_INVENTORY, true);

        vm.expectRevert(
            abi.encodeWithSelector(
                ValidateBaseSepoliaUniversalPoolArtMarketplace.AddressMismatch.selector,
                "marketplace.feeRecipient",
                address(0xBEEF),
                feeRecipient
            )
        );
        _validateMarket(market, owner, address(0xBEEF), configuredPremium, MINIMUM_INVENTORY, true);

        vm.expectRevert(
            abi.encodeWithSelector(
                ValidateBaseSepoliaUniversalPoolArtMarketplace.ValueMismatch.selector,
                "marketplace.communityFee",
                configuredPremium - 1,
                configuredPremium
            )
        );
        _validateMarket(market, owner, feeRecipient, configuredPremium - 1, MINIMUM_INVENTORY, true);

        vm.expectRevert(
            abi.encodeWithSelector(
                ValidateBaseSepoliaUniversalPoolArtMarketplace.ValueMismatch.selector,
                "marketplace.paused",
                uint256(0),
                uint256(1)
            )
        );
        _validateMarket(market, owner, feeRecipient, configuredPremium, MINIMUM_INVENTORY, false);
    }

    function testValidationRejectsOutOfRangeFeeExpectation() public {
        uint256 oversized = fame.unit() / 10 + 1;
        vm.expectRevert(
            abi.encodeWithSelector(ValidateBaseSepoliaUniversalPoolArtMarketplace.PremiumOutOfRange.selector, oversized)
        );
        _validateMarket(market, owner, feeRecipient, oversized, MINIMUM_INVENTORY, true);
    }

    function testValidationRejectsFeeAndMarketplaceSkipDrift() public {
        uint256 configuredPremium = market.premium();

        vm.prank(feeRecipient);
        fame.setSkipNFT(false);
        vm.expectRevert(
            abi.encodeWithSelector(
                ValidateBaseSepoliaUniversalPoolArtMarketplace.FeeRecipientNotSkippingNFT.selector, feeRecipient
            )
        );
        _validateMarket(market, owner, feeRecipient, configuredPremium, MINIMUM_INVENTORY, true);

        vm.prank(feeRecipient);
        fame.setSkipNFT(true);
        fame.grantRoles(address(this), FAME_SKIP_MANAGER_ROLE);
        fame.setSkipNftForAccount(address(market), true);
        vm.expectRevert(ValidateBaseSepoliaUniversalPoolArtMarketplace.MarketplaceSkippingNFT.selector);
        _validateMarket(market, owner, feeRecipient, configuredPremium, MINIMUM_INVENTORY, true);
    }

    function testValidationRejectsInventoryBelowExplicitNonzeroExpectation() public {
        uint256 configuredPremium = market.premium();
        vm.expectRevert(
            abi.encodeWithSelector(
                ValidateBaseSepoliaUniversalPoolArtMarketplace.MarketplaceInventoryTooLow.selector,
                uint256(1),
                uint256(0)
            )
        );
        _validateMarket(market, owner, feeRecipient, configuredPremium, 1, true);
    }

    function testValidationRejectsMissingOrBroadCreatorMagicRoles() public {
        uint256 configuredPremium = market.premium();

        creatorMagic.revokeRoles(address(market), CREATOR_MAGIC_BANISHER_ROLE);
        vm.expectRevert(ValidateBaseSepoliaUniversalPoolArtMarketplace.CreatorMagicBanisherRoleMissing.selector);
        _validateMarket(market, owner, feeRecipient, configuredPremium, MINIMUM_INVENTORY, true);

        creatorMagic.grantRoles(address(market), CREATOR_MAGIC_BANISHER_ROLE | CREATOR_MAGIC_CREATOR_ROLE);
        vm.expectRevert(
            abi.encodeWithSelector(
                ValidateBaseSepoliaUniversalPoolArtMarketplace.CreatorMagicRoleTooBroad.selector,
                CREATOR_MAGIC_CREATOR_ROLE
            )
        );
        _validateMarket(market, owner, feeRecipient, configuredPremium, MINIMUM_INVENTORY, true);

        creatorMagic.revokeRoles(address(market), CREATOR_MAGIC_CREATOR_ROLE);
        creatorMagic.grantRoles(address(market), CREATOR_MAGIC_ART_POOL_MANAGER_ROLE);
        vm.expectRevert(
            abi.encodeWithSelector(
                ValidateBaseSepoliaUniversalPoolArtMarketplace.CreatorMagicRoleTooBroad.selector,
                CREATOR_MAGIC_ART_POOL_MANAGER_ROLE
            )
        );
        _validateMarket(market, owner, feeRecipient, configuredPremium, MINIMUM_INVENTORY, true);
    }

    function testValidationRejectsMarketplaceSkipManagerAuthority() public {
        uint256 configuredPremium = market.premium();

        fame.grantRoles(address(market), FAME_SKIP_MANAGER_ROLE);
        vm.expectRevert(ValidateBaseSepoliaUniversalPoolArtMarketplace.FameSkipManagerRoleTooBroad.selector);
        _validateMarket(market, owner, feeRecipient, configuredPremium, MINIMUM_INVENTORY, true);
    }

    function testValidationRejectsRendererAndDependencyDrift() public {
        uint256 configuredPremium = market.premium();

        fame.setRenderer(address(childRenderer));
        vm.expectRevert(
            abi.encodeWithSelector(
                ValidateBaseSepoliaUniversalPoolArtMarketplace.AddressMismatch.selector,
                "fame.renderer",
                address(creatorMagic),
                address(childRenderer)
            )
        );
        _validateMarket(market, owner, feeRecipient, configuredPremium, MINIMUM_INVENTORY, true);

        fame.setRenderer(address(creatorMagic));
        UniversalPoolArtMarketplace otherMarket = _deployMarket(market.premium(), feeRecipient, owner);
        creatorMagic.grantRoles(address(otherMarket), CREATOR_MAGIC_BANISHER_ROLE);
        _validateMarket(otherMarket, owner, feeRecipient, otherMarket.premium(), MINIMUM_INVENTORY, true);
    }

    function testDeploymentPrefixClassifiesEverySafeContinuation() public {
        uint256 configuredPremium = market.premium();
        (DeployBaseSepoliaUniversalPoolArtMarketplace.DeploymentPrefix prefix, uint256 inventory) =
            _deploymentPrefix(market, configuredPremium, MINIMUM_INVENTORY);
        assertEq(uint256(prefix), uint256(DeployBaseSepoliaUniversalPoolArtMarketplace.DeploymentPrefix.ReadyPaused));
        assertEq(inventory, 0);

        UniversalPoolArtMarketplace partialMarket = _deployMarket(configuredPremium, feeRecipient, owner);
        (prefix, inventory) = _deploymentPrefix(partialMarket, configuredPremium, MINIMUM_INVENTORY);
        assertEq(uint256(prefix), uint256(DeployBaseSepoliaUniversalPoolArtMarketplace.DeploymentPrefix.Deployed));
        assertEq(inventory, 0);

        creatorMagic.grantRoles(address(partialMarket), CREATOR_MAGIC_BANISHER_ROLE);
        (prefix, inventory) = _deploymentPrefix(partialMarket, configuredPremium, MINIMUM_INVENTORY);
        assertEq(uint256(prefix), uint256(DeployBaseSepoliaUniversalPoolArtMarketplace.DeploymentPrefix.ReadyPaused));
        assertEq(inventory, 0);

        fame.transfer(address(partialMarket), fame.unit());
        (prefix, inventory) = _deploymentPrefix(partialMarket, configuredPremium, MINIMUM_INVENTORY);
        assertEq(uint256(prefix), uint256(DeployBaseSepoliaUniversalPoolArtMarketplace.DeploymentPrefix.ReadyPaused));
        assertEq(inventory, 1);
    }

    function testDeploymentPrefixRejectsNonzeroRequiredLaunchInventory() public {
        uint256 configuredPremium = market.premium();
        vm.expectRevert(
            abi.encodeWithSelector(
                DeployBaseSepoliaUniversalPoolArtMarketplace.InvalidMinimumInventory.selector, uint256(0), uint256(1)
            )
        );
        _deploymentPrefix(market, configuredPremium, 1);
    }

    function testDeploymentPrefixRejectsProviderFeeAndCapDrift() public {
        uint256 configuredCommunityFee = market.communityFee();
        UniversalPoolArtMarketplace providerFeeDrift =
            _deployMarketWithFees(configuredCommunityFee, 1, feeRecipient, owner, TEST_ACTIVE_PROVIDER_CAP);
        vm.expectRevert(
            abi.encodeWithSelector(
                DeployBaseSepoliaUniversalPoolArtMarketplace.ExistingDeploymentMismatch.selector, "providerFee"
            )
        );
        deployer.deploymentPrefix(
            providerFeeDrift,
            fame,
            creatorMagic,
            owner,
            feeRecipient,
            configuredCommunityFee,
            0,
            TEST_ACTIVE_PROVIDER_CAP,
            MINIMUM_INVENTORY
        );

        UniversalPoolArtMarketplace capDrift = _deployMarketWithFees(configuredCommunityFee, 0, feeRecipient, owner, 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                DeployBaseSepoliaUniversalPoolArtMarketplace.ExistingDeploymentMismatch.selector, "activeProviderCap"
            )
        );
        deployer.deploymentPrefix(
            capDrift,
            fame,
            creatorMagic,
            owner,
            feeRecipient,
            configuredCommunityFee,
            0,
            TEST_ACTIVE_PROVIDER_CAP,
            MINIMUM_INVENTORY
        );
    }

    function testDeploymentPrefixRejectsMissingOrMismatchedBatchApi() public {
        bytes memory batchSizeCall = abi.encodeWithSignature("MAX_INVENTORY_BATCH_SIZE()");
        uint256 configuredProviderFee = market.providerFee();

        vm.mockCall(address(market), batchSizeCall, abi.encode(uint256(7)));
        vm.expectRevert(
            abi.encodeWithSelector(
                DeployBaseSepoliaUniversalPoolArtMarketplace.ExistingDeploymentMismatch.selector,
                "maxInventoryBatchSize"
            )
        );
        _deploymentPrefix(market, configuredProviderFee, MINIMUM_INVENTORY);

        vm.clearMockedCalls();
        vm.mockCallRevert(address(market), batchSizeCall, bytes("missing getter"));
        vm.expectRevert(
            abi.encodeWithSelector(
                DeployBaseSepoliaUniversalPoolArtMarketplace.ExistingDeploymentMismatch.selector,
                "maxInventoryBatchSize"
            )
        );
        _deploymentPrefix(market, configuredProviderFee, MINIMUM_INVENTORY);
    }

    function testDeploymentPrefixRejectsActivationAndBroadAuthority() public {
        uint256 configuredPremium = market.premium();
        market.unpause();
        vm.expectRevert(
            abi.encodeWithSelector(
                DeployBaseSepoliaUniversalPoolArtMarketplace.ExistingDeploymentActivated.selector, address(market)
            )
        );
        _deploymentPrefix(market, configuredPremium, MINIMUM_INVENTORY);

        market.pause();
        creatorMagic.grantRoles(address(market), CREATOR_MAGIC_CREATOR_ROLE);
        vm.expectRevert(
            abi.encodeWithSelector(
                DeployBaseSepoliaUniversalPoolArtMarketplace.ExistingDeploymentAuthorityTooBroad.selector,
                CREATOR_MAGIC_CREATOR_ROLE
            )
        );
        _deploymentPrefix(market, configuredPremium, MINIMUM_INVENTORY);
    }

    function _validate(bool expectedPaused) internal view {
        _validateMarket(market, owner, feeRecipient, market.premium(), MINIMUM_INVENTORY, expectedPaused);
    }

    function _deploymentPrefix(
        UniversalPoolArtMarketplace target,
        uint256 expectedCommunityFee,
        uint256 minimumInventory
    ) internal view returns (DeployBaseSepoliaUniversalPoolArtMarketplace.DeploymentPrefix prefix, uint256 inventory) {
        return deployer.deploymentPrefix(
            target,
            fame,
            creatorMagic,
            owner,
            feeRecipient,
            expectedCommunityFee,
            0,
            TEST_ACTIVE_PROVIDER_CAP,
            minimumInventory
        );
    }

    function _validateMarket(
        UniversalPoolArtMarketplace target,
        address expectedOwner,
        address expectedFeeRecipient,
        uint256 expectedPremium,
        uint256 minimumInventory,
        bool expectedPaused
    ) internal view {
        validator.validateMarketplace(
            fame,
            mirror,
            creatorMagic,
            target,
            ValidateBaseSepoliaUniversalPoolArtMarketplace.MarketplaceExpectations({
                owner: expectedOwner,
                feeRecipient: expectedFeeRecipient,
                communityFee: expectedPremium,
                providerFee: 0,
                activeProviderCap: TEST_ACTIVE_PROVIDER_CAP,
                minimumInventory: minimumInventory,
                paused: expectedPaused
            })
        );
    }
}
