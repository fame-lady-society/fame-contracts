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
    uint256 internal constant INITIAL_INVENTORY = 3;
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
        _seedShells(market, INITIAL_INVENTORY);
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
        _validateMarket(market, address(0xBEEF), feeRecipient, configuredPremium, INITIAL_INVENTORY, true);

        vm.expectRevert(
            abi.encodeWithSelector(
                ValidateBaseSepoliaUniversalPoolArtMarketplace.AddressMismatch.selector,
                "marketplace.feeRecipient",
                address(0xBEEF),
                feeRecipient
            )
        );
        _validateMarket(market, owner, address(0xBEEF), configuredPremium, INITIAL_INVENTORY, true);

        vm.expectRevert(
            abi.encodeWithSelector(
                ValidateBaseSepoliaUniversalPoolArtMarketplace.ValueMismatch.selector,
                "marketplace.premium",
                configuredPremium + 1,
                configuredPremium
            )
        );
        _validateMarket(market, owner, feeRecipient, configuredPremium + 1, INITIAL_INVENTORY, true);

        vm.expectRevert(
            abi.encodeWithSelector(
                ValidateBaseSepoliaUniversalPoolArtMarketplace.ValueMismatch.selector,
                "marketplace.paused",
                uint256(0),
                uint256(1)
            )
        );
        _validateMarket(market, owner, feeRecipient, configuredPremium, INITIAL_INVENTORY, false);
    }

    function testValidationRejectsInvalidPremiumExpectation() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ValidateBaseSepoliaUniversalPoolArtMarketplace.PremiumOutOfRange.selector, uint256(0)
            )
        );
        _validateMarket(market, owner, feeRecipient, 0, INITIAL_INVENTORY, true);

        uint256 oversized = uint256(type(uint96).max) + 1;
        vm.expectRevert(
            abi.encodeWithSelector(ValidateBaseSepoliaUniversalPoolArtMarketplace.PremiumOutOfRange.selector, oversized)
        );
        _validateMarket(market, owner, feeRecipient, oversized, INITIAL_INVENTORY, true);
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
        _validateMarket(market, owner, feeRecipient, configuredPremium, INITIAL_INVENTORY, true);

        vm.prank(feeRecipient);
        fame.setSkipNFT(true);
        fame.grantRoles(address(this), FAME_SKIP_MANAGER_ROLE);
        fame.setSkipNftForAccount(address(market), true);
        vm.expectRevert(ValidateBaseSepoliaUniversalPoolArtMarketplace.MarketplaceSkippingNFT.selector);
        _validateMarket(market, owner, feeRecipient, configuredPremium, INITIAL_INVENTORY, true);
    }

    function testValidationRejectsInsufficientInventory() public {
        uint256 configuredPremium = market.premium();
        UniversalPoolArtMarketplace underseededMarket = _deployMarket(configuredPremium, feeRecipient, owner);
        creatorMagic.grantRoles(address(underseededMarket), CREATOR_MAGIC_BANISHER_ROLE);
        _seedShells(underseededMarket, INITIAL_INVENTORY - 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                ValidateBaseSepoliaUniversalPoolArtMarketplace.MarketplaceInventoryTooLow.selector,
                INITIAL_INVENTORY,
                INITIAL_INVENTORY - 1
            )
        );
        _validateMarket(underseededMarket, owner, feeRecipient, configuredPremium, INITIAL_INVENTORY, true);
    }

    function testValidationRejectsConfiguredMinimumBelowReleaseInventory() public {
        uint256 configuredPremium = market.premium();
        vm.expectRevert(
            abi.encodeWithSelector(
                ValidateBaseSepoliaUniversalPoolArtMarketplace.InvalidMinimumInventory.selector,
                INITIAL_INVENTORY,
                INITIAL_INVENTORY - 1
            )
        );
        _validateMarket(market, owner, feeRecipient, configuredPremium, INITIAL_INVENTORY - 1, true);
    }

    function testValidationRejectsMissingOrBroadCreatorMagicRoles() public {
        uint256 configuredPremium = market.premium();

        creatorMagic.revokeRoles(address(market), CREATOR_MAGIC_BANISHER_ROLE);
        vm.expectRevert(ValidateBaseSepoliaUniversalPoolArtMarketplace.CreatorMagicBanisherRoleMissing.selector);
        _validateMarket(market, owner, feeRecipient, configuredPremium, INITIAL_INVENTORY, true);

        creatorMagic.grantRoles(address(market), CREATOR_MAGIC_BANISHER_ROLE | CREATOR_MAGIC_CREATOR_ROLE);
        vm.expectRevert(
            abi.encodeWithSelector(
                ValidateBaseSepoliaUniversalPoolArtMarketplace.CreatorMagicRoleTooBroad.selector,
                CREATOR_MAGIC_CREATOR_ROLE
            )
        );
        _validateMarket(market, owner, feeRecipient, configuredPremium, INITIAL_INVENTORY, true);

        creatorMagic.revokeRoles(address(market), CREATOR_MAGIC_CREATOR_ROLE);
        creatorMagic.grantRoles(address(market), CREATOR_MAGIC_ART_POOL_MANAGER_ROLE);
        vm.expectRevert(
            abi.encodeWithSelector(
                ValidateBaseSepoliaUniversalPoolArtMarketplace.CreatorMagicRoleTooBroad.selector,
                CREATOR_MAGIC_ART_POOL_MANAGER_ROLE
            )
        );
        _validateMarket(market, owner, feeRecipient, configuredPremium, INITIAL_INVENTORY, true);
    }

    function testValidationRejectsMarketplaceSkipManagerAuthority() public {
        uint256 configuredPremium = market.premium();

        fame.grantRoles(address(market), FAME_SKIP_MANAGER_ROLE);
        vm.expectRevert(ValidateBaseSepoliaUniversalPoolArtMarketplace.FameSkipManagerRoleTooBroad.selector);
        _validateMarket(market, owner, feeRecipient, configuredPremium, INITIAL_INVENTORY, true);
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
        _validateMarket(market, owner, feeRecipient, configuredPremium, INITIAL_INVENTORY, true);

        fame.setRenderer(address(creatorMagic));
        UniversalPoolArtMarketplace otherMarket = _deployMarket(market.premium(), feeRecipient, owner);
        creatorMagic.grantRoles(address(otherMarket), CREATOR_MAGIC_BANISHER_ROLE);
        _seedShells(otherMarket, INITIAL_INVENTORY);
        _validateMarket(otherMarket, owner, feeRecipient, otherMarket.premium(), INITIAL_INVENTORY, true);
    }

    function testDeploymentPrefixClassifiesEverySafeContinuation() public {
        uint256 configuredPremium = market.premium();
        (DeployBaseSepoliaUniversalPoolArtMarketplace.DeploymentPrefix prefix, uint256 inventory) = deployer.deploymentPrefix(
            market, fame, creatorMagic, owner, feeRecipient, configuredPremium, INITIAL_INVENTORY
        );
        assertEq(uint256(prefix), uint256(DeployBaseSepoliaUniversalPoolArtMarketplace.DeploymentPrefix.ReadyPaused));
        assertEq(inventory, INITIAL_INVENTORY);

        UniversalPoolArtMarketplace partialMarket = _deployMarket(configuredPremium, feeRecipient, owner);
        (prefix, inventory) = deployer.deploymentPrefix(
            partialMarket, fame, creatorMagic, owner, feeRecipient, configuredPremium, INITIAL_INVENTORY
        );
        assertEq(uint256(prefix), uint256(DeployBaseSepoliaUniversalPoolArtMarketplace.DeploymentPrefix.Deployed));
        assertEq(inventory, 0);

        creatorMagic.grantRoles(address(partialMarket), CREATOR_MAGIC_BANISHER_ROLE);
        (prefix, inventory) = deployer.deploymentPrefix(
            partialMarket, fame, creatorMagic, owner, feeRecipient, configuredPremium, INITIAL_INVENTORY
        );
        assertEq(
            uint256(prefix), uint256(DeployBaseSepoliaUniversalPoolArtMarketplace.DeploymentPrefix.BanisherGranted)
        );

        fame.transfer(address(partialMarket), fame.unit());
        (prefix, inventory) = deployer.deploymentPrefix(
            partialMarket, fame, creatorMagic, owner, feeRecipient, configuredPremium, INITIAL_INVENTORY
        );
        assertEq(
            uint256(prefix), uint256(DeployBaseSepoliaUniversalPoolArtMarketplace.DeploymentPrefix.PartiallySeeded)
        );
        assertEq(inventory, 1);

        fame.transfer(address(partialMarket), fame.unit());
        (prefix, inventory) = deployer.deploymentPrefix(
            partialMarket, fame, creatorMagic, owner, feeRecipient, configuredPremium, INITIAL_INVENTORY
        );
        assertEq(
            uint256(prefix), uint256(DeployBaseSepoliaUniversalPoolArtMarketplace.DeploymentPrefix.PartiallySeeded)
        );
        assertEq(inventory, INITIAL_INVENTORY - 1);

        fame.transfer(address(partialMarket), fame.unit());
        (prefix, inventory) = deployer.deploymentPrefix(
            partialMarket, fame, creatorMagic, owner, feeRecipient, configuredPremium, INITIAL_INVENTORY
        );
        assertEq(uint256(prefix), uint256(DeployBaseSepoliaUniversalPoolArtMarketplace.DeploymentPrefix.ReadyPaused));
        assertEq(inventory, INITIAL_INVENTORY);
    }

    function testDeploymentPrefixRejectsInventoryOtherThanThreeShells() public {
        uint256 configuredPremium = market.premium();
        vm.expectRevert(
            abi.encodeWithSelector(
                DeployBaseSepoliaUniversalPoolArtMarketplace.InvalidMinimumInventory.selector,
                INITIAL_INVENTORY,
                INITIAL_INVENTORY - 1
            )
        );
        deployer.deploymentPrefix(
            market, fame, creatorMagic, owner, feeRecipient, configuredPremium, INITIAL_INVENTORY - 1
        );
    }

    function testDeploymentPrefixRejectsActivationAndBroadAuthority() public {
        uint256 configuredPremium = market.premium();
        market.unpause();
        vm.expectRevert(
            abi.encodeWithSelector(
                DeployBaseSepoliaUniversalPoolArtMarketplace.ExistingDeploymentActivated.selector, address(market)
            )
        );
        deployer.deploymentPrefix(market, fame, creatorMagic, owner, feeRecipient, configuredPremium, INITIAL_INVENTORY);

        market.pause();
        creatorMagic.grantRoles(address(market), CREATOR_MAGIC_CREATOR_ROLE);
        vm.expectRevert(
            abi.encodeWithSelector(
                DeployBaseSepoliaUniversalPoolArtMarketplace.ExistingDeploymentAuthorityTooBroad.selector,
                CREATOR_MAGIC_CREATOR_ROLE
            )
        );
        deployer.deploymentPrefix(market, fame, creatorMagic, owner, feeRecipient, configuredPremium, INITIAL_INVENTORY);
    }

    function _validate(bool expectedPaused) internal view {
        _validateMarket(market, owner, feeRecipient, market.premium(), INITIAL_INVENTORY, expectedPaused);
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
                premium: expectedPremium,
                minimumInventory: minimumInventory,
                paused: expectedPaused
            })
        );
    }
}
