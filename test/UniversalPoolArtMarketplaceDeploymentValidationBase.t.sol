// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {UniversalPoolArtMarketplace} from "../src/UniversalPoolArtMarketplace.sol";
import {FameMarketplaceCheckout} from "../src/FameMarketplaceCheckout.sol";
import {FameRouter} from "../src/FameRouter.sol";
import {FameRouterTypes} from "../src/router/FameRouterTypes.sol";
import {ActivateBaseUniversalPoolArtMarketplace} from "../script/ActivateBaseUniversalPoolArtMarketplace.s.sol";
import {DeployBaseUniversalPoolArtMarketplace} from "../script/DeployBaseUniversalPoolArtMarketplace.s.sol";
import {ValidateBaseUniversalPoolArtMarketplace} from "../script/ValidateBaseUniversalPoolArtMarketplace.s.sol";
import {UniversalPoolArtMarketplaceTestBase} from "./helpers/UniversalPoolArtMarketplaceTestBase.sol";
import {MockERC20, MockWETH} from "./router/mocks/MockERC20.sol";
import {FameRouterFixtureManifest} from "./router/fixtures/FameRouterFixtureManifest.sol";

contract UniversalPoolArtMarketplaceDeploymentValidationBaseTest is UniversalPoolArtMarketplaceTestBase {
    uint256 internal constant BASE_CHAIN_ID = 8453;
    uint256 internal constant PREMIUM = 30_000 ether;
    uint256 internal constant REQUIRED_INVENTORY = 1;
    uint256 internal constant CREATOR_MAGIC_RENDERER_ROLE = 1;
    address internal constant DEPLOYER = 0xD52E2A6bBcEba9673440e4D7843Db6713E9B6FD9;
    address internal constant SAFE = 0xC952C53D8B63919e372caa2E6FEe605ee24E4D3D;

    DeployBaseUniversalPoolArtMarketplace internal deployer;
    ValidateBaseUniversalPoolArtMarketplace internal validator;
    ActivateBaseUniversalPoolArtMarketplace internal activator;
    FameRouter internal router;
    MockERC20 internal usdc;
    MockWETH internal weth;

    function setUp() public override {
        super.setUp();
        vm.chainId(BASE_CHAIN_ID);

        deployer = new DeployBaseUniversalPoolArtMarketplace();
        validator = new ValidateBaseUniversalPoolArtMarketplace();
        activator = new ActivateBaseUniversalPoolArtMarketplace();
        router = new FameRouter(SAFE);
        usdc = new MockERC20("USD Coin", "USDC", 6);
        weth = new MockWETH();

        for (uint256 i; i < FameRouterFixtureManifest.requiredVenueTargetCount(); ++i) {
            FameRouterTypes.VenueFamily family = FameRouterFixtureManifest.requiredVenueFamily(i);
            router.setVenueFamilyEnabled(family, true);
            router.setVenueTargetEnabled(family, FameRouterFixtureManifest.requiredVenueTarget(i), true);
        }

        vm.prank(SAFE);
        fame.setSkipNFT(true);
        vm.prank(address(router));
        fame.setSkipNFT(true);
        creatorMagic.transferOwnership(DEPLOYER);
        fame.transfer(SAFE, fame.unit());
    }

    function _fameName() internal pure override returns (string memory) {
        return "Society";
    }

    function testOneShellLifecycleDeploysPausedSeedsAndActivatesFromDeployer() public {
        uint256 unit = fame.unit();
        uint256 safeBalanceBefore = fame.balanceOf(SAFE);

        (UniversalPoolArtMarketplace deployed, FameMarketplaceCheckout checkout) =
            deployer.deployMarketplaceStack(fame, creatorMagic, _deploymentConfig());

        assertTrue(deployed.paused());
        assertEq(deployed.owner(), DEPLOYER);
        assertEq(deployed.feeRecipient(), SAFE);
        assertEq(deployed.authorizedCheckout(), address(checkout));
        assertEq(address(checkout.market()), address(deployed));
        assertTrue(fame.getSkipNFT(address(checkout)));

        vm.prank(SAFE);
        fame.transfer(DEPLOYER, unit);
        assertEq(safeBalanceBefore - fame.balanceOf(SAFE), unit);
        assertEq(fame.balanceOf(DEPLOYER), unit);

        vm.startPrank(DEPLOYER);
        creatorMagic.grantRoles(address(deployed), CREATOR_MAGIC_BANISHER_ROLE);
        fame.transfer(address(deployed), unit);
        vm.stopPrank();

        validator.validateMarketplaceStack(
            fame,
            mirror,
            creatorMagic,
            deployed,
            checkout,
            address(childRenderer),
            ValidateBaseUniversalPoolArtMarketplace.MarketplaceExpectations({
                owner: DEPLOYER,
                creatorMagicOwner: DEPLOYER,
                feeRecipient: SAFE,
                communityFee: PREMIUM,
                providerFee: 0,
                activeProviderCap: TEST_ACTIVE_PROVIDER_CAP,
                minimumInventory: REQUIRED_INVENTORY,
                paused: true
            }),
            ValidateBaseUniversalPoolArtMarketplace.CheckoutExpectations({
                router: address(router),
                usdc: address(usdc),
                weth: address(weth),
                routerFeeRecipient: SAFE,
                routerFeePpm: FameRouterTypes.DEFAULT_FEE_PPM
            })
        );

        activator.activateMarketplace(deployed, checkout, DEPLOYER);

        validator.validateMarketplaceStack(
            fame,
            mirror,
            creatorMagic,
            deployed,
            checkout,
            address(childRenderer),
            ValidateBaseUniversalPoolArtMarketplace.MarketplaceExpectations({
                owner: DEPLOYER,
                creatorMagicOwner: DEPLOYER,
                feeRecipient: SAFE,
                communityFee: PREMIUM,
                providerFee: 0,
                activeProviderCap: TEST_ACTIVE_PROVIDER_CAP,
                minimumInventory: REQUIRED_INVENTORY,
                paused: false
            }),
            ValidateBaseUniversalPoolArtMarketplace.CheckoutExpectations({
                router: address(router),
                usdc: address(usdc),
                weth: address(weth),
                routerFeeRecipient: SAFE,
                routerFeePpm: FameRouterTypes.DEFAULT_FEE_PPM
            })
        );
    }

    function testValidationAndActivationAllowProviderDepositsWhilePaused() public {
        (UniversalPoolArtMarketplace deployed, FameMarketplaceCheckout checkout) =
            deployer.deployMarketplaceStack(fame, creatorMagic, _deploymentConfig());
        _grantRoleAndSeed(deployed);

        address provider = address(0xBEEF);
        fame.transfer(provider, fame.unit());
        uint256 tokenId = _ownedTokenAt(provider, 0);
        vm.startPrank(provider);
        mirror.approve(address(deployed), tokenId);
        deployed.depositInventory(tokenId);
        vm.stopPrank();

        _validatePausedStack(deployed, checkout);
        activator.activateMarketplace(deployed, checkout, DEPLOYER);
        _validateStack(deployed, checkout, false);

        assertFalse(deployed.paused());
        assertEq(deployed.inventory(), REQUIRED_INVENTORY + 1);
        assertEq(deployed.totalProviderUnits(), 1);
        assertEq(deployed.activeProviderCount(), 1);
    }

    function testValidationRejectsRendererAuthorityInAdditionToBanisher() public {
        (UniversalPoolArtMarketplace deployed, FameMarketplaceCheckout checkout) =
            deployer.deployMarketplaceStack(fame, creatorMagic, _deploymentConfig());

        vm.startPrank(DEPLOYER);
        creatorMagic.grantRoles(address(deployed), CREATOR_MAGIC_BANISHER_ROLE | CREATOR_MAGIC_RENDERER_ROLE);
        vm.stopPrank();

        vm.prank(SAFE);
        fame.transfer(address(deployed), fame.unit());

        vm.expectRevert(
            abi.encodeWithSelector(
                ValidateBaseUniversalPoolArtMarketplace.CreatorMagicRoleTooBroad.selector, CREATOR_MAGIC_RENDERER_ROLE
            )
        );
        validator.validateMarketplaceStack(
            fame,
            mirror,
            creatorMagic,
            deployed,
            checkout,
            address(childRenderer),
            ValidateBaseUniversalPoolArtMarketplace.MarketplaceExpectations({
                owner: DEPLOYER,
                creatorMagicOwner: DEPLOYER,
                feeRecipient: SAFE,
                communityFee: PREMIUM,
                providerFee: 0,
                activeProviderCap: TEST_ACTIVE_PROVIDER_CAP,
                minimumInventory: REQUIRED_INVENTORY,
                paused: true
            }),
            ValidateBaseUniversalPoolArtMarketplace.CheckoutExpectations({
                router: address(router),
                usdc: address(usdc),
                weth: address(weth),
                routerFeeRecipient: SAFE,
                routerFeePpm: FameRouterTypes.DEFAULT_FEE_PPM
            })
        );
    }

    function testValidationRejectsMarketplacePointingAtAnotherCheckout() public {
        (UniversalPoolArtMarketplace deployed, FameMarketplaceCheckout checkout) =
            deployer.deployMarketplaceStack(fame, creatorMagic, _deploymentConfig());

        vm.startPrank(DEPLOYER);
        creatorMagic.grantRoles(address(deployed), CREATOR_MAGIC_BANISHER_ROLE);
        deployed.setAuthorizedCheckout(address(router));
        vm.stopPrank();

        vm.prank(SAFE);
        fame.transfer(address(deployed), fame.unit());

        vm.expectRevert(
            abi.encodeWithSelector(
                ValidateBaseUniversalPoolArtMarketplace.AddressMismatch.selector,
                "marketplace.authorizedCheckout",
                address(checkout),
                address(router)
            )
        );
        validator.validateMarketplaceStack(
            fame,
            mirror,
            creatorMagic,
            deployed,
            checkout,
            address(childRenderer),
            ValidateBaseUniversalPoolArtMarketplace.MarketplaceExpectations({
                owner: DEPLOYER,
                creatorMagicOwner: DEPLOYER,
                feeRecipient: SAFE,
                communityFee: PREMIUM,
                providerFee: 0,
                activeProviderCap: TEST_ACTIVE_PROVIDER_CAP,
                minimumInventory: REQUIRED_INVENTORY,
                paused: true
            }),
            ValidateBaseUniversalPoolArtMarketplace.CheckoutExpectations({
                router: address(router),
                usdc: address(usdc),
                weth: address(weth),
                routerFeeRecipient: SAFE,
                routerFeePpm: FameRouterTypes.DEFAULT_FEE_PPM
            })
        );
    }

    function testValidationRejectsMissingOneUnitSeed() public {
        (UniversalPoolArtMarketplace deployed, FameMarketplaceCheckout checkout) =
            deployer.deployMarketplaceStack(fame, creatorMagic, _deploymentConfig());
        vm.prank(DEPLOYER);
        creatorMagic.grantRoles(address(deployed), CREATOR_MAGIC_BANISHER_ROLE);

        vm.expectRevert(
            abi.encodeWithSelector(
                ValidateBaseUniversalPoolArtMarketplace.ValueMismatch.selector, "marketplace.inventory", 1, 0
            )
        );
        _validatePausedStack(deployed, checkout);
    }

    function testValidationRejectsRouterSkipNftDisabled() public {
        (UniversalPoolArtMarketplace deployed, FameMarketplaceCheckout checkout) =
            deployer.deployMarketplaceStack(fame, creatorMagic, _deploymentConfig());
        _grantRoleAndSeed(deployed);
        vm.prank(address(router));
        fame.setSkipNFT(false);

        vm.expectRevert(
            abi.encodeWithSelector(
                ValidateBaseUniversalPoolArtMarketplace.RouterNotSkippingNFT.selector, address(router)
            )
        );
        _validatePausedStack(deployed, checkout);
    }

    function testValidationRejectsCheckoutAsRouterFeeRecipient() public {
        (UniversalPoolArtMarketplace deployed, FameMarketplaceCheckout checkout) =
            deployer.deployMarketplaceStack(fame, creatorMagic, _deploymentConfig());
        _grantRoleAndSeed(deployed);
        router.setFeeRecipient(address(checkout));

        vm.expectRevert(
            abi.encodeWithSelector(
                ValidateBaseUniversalPoolArtMarketplace.RouterFeeRecipientIsCheckout.selector, address(checkout)
            )
        );
        validator.validateMarketplaceStack(
            fame,
            mirror,
            creatorMagic,
            deployed,
            checkout,
            address(childRenderer),
            ValidateBaseUniversalPoolArtMarketplace.MarketplaceExpectations({
                owner: DEPLOYER,
                creatorMagicOwner: DEPLOYER,
                feeRecipient: SAFE,
                communityFee: PREMIUM,
                providerFee: 0,
                activeProviderCap: TEST_ACTIVE_PROVIDER_CAP,
                minimumInventory: REQUIRED_INVENTORY,
                paused: true
            }),
            ValidateBaseUniversalPoolArtMarketplace.CheckoutExpectations({
                router: address(router),
                usdc: address(usdc),
                weth: address(weth),
                routerFeeRecipient: address(checkout),
                routerFeePpm: FameRouterTypes.DEFAULT_FEE_PPM
            })
        );
    }

    function testActivationRejectsMarketplacePointingAtAnotherCheckout() public {
        (UniversalPoolArtMarketplace deployed, FameMarketplaceCheckout checkout) =
            deployer.deployMarketplaceStack(fame, creatorMagic, _deploymentConfig());
        vm.prank(DEPLOYER);
        deployed.setAuthorizedCheckout(address(router));

        vm.expectRevert(
            abi.encodeWithSelector(
                ActivateBaseUniversalPoolArtMarketplace.UnexpectedCheckout.selector, address(checkout), address(router)
            )
        );
        activator.activateMarketplace(deployed, checkout, DEPLOYER);
    }

    function testValidationRejectsCheckoutWithWrongUsdc() public {
        (UniversalPoolArtMarketplace deployed,) =
            deployer.deployMarketplaceStack(fame, creatorMagic, _deploymentConfig());
        MockERC20 wrongUsdc = new MockERC20("Wrong USD", "WUSD", 6);
        FameMarketplaceCheckout wrongCheckout = new FameMarketplaceCheckout(
            address(router), address(deployed), payable(address(fame)), address(wrongUsdc), address(weth)
        );
        vm.prank(DEPLOYER);
        deployed.setAuthorizedCheckout(address(wrongCheckout));
        _grantRoleAndSeed(deployed);

        vm.expectRevert(
            abi.encodeWithSelector(
                ValidateBaseUniversalPoolArtMarketplace.AddressMismatch.selector,
                "checkout.usdc",
                address(usdc),
                address(wrongUsdc)
            )
        );
        _validatePausedStack(deployed, wrongCheckout);
    }

    function _grantRoleAndSeed(UniversalPoolArtMarketplace deployed) private {
        vm.startPrank(DEPLOYER);
        creatorMagic.grantRoles(address(deployed), CREATOR_MAGIC_BANISHER_ROLE);
        vm.stopPrank();
        vm.prank(SAFE);
        fame.transfer(address(deployed), fame.unit());
    }

    function _deploymentConfig()
        private
        view
        returns (DeployBaseUniversalPoolArtMarketplace.DeploymentConfig memory config)
    {
        config = DeployBaseUniversalPoolArtMarketplace.DeploymentConfig({
            router: address(router),
            usdc: address(usdc),
            weth: address(weth),
            communityFee: PREMIUM,
            providerFee: 0,
            feeRecipient: SAFE,
            owner: DEPLOYER,
            activeProviderCap: TEST_ACTIVE_PROVIDER_CAP,
            sender: DEPLOYER
        });
    }

    function _validatePausedStack(UniversalPoolArtMarketplace deployed, FameMarketplaceCheckout checkout) private view {
        _validateStack(deployed, checkout, true);
    }

    function _validateStack(UniversalPoolArtMarketplace deployed, FameMarketplaceCheckout checkout, bool expectedPaused)
        private
        view
    {
        validator.validateMarketplaceStack(
            fame,
            mirror,
            creatorMagic,
            deployed,
            checkout,
            address(childRenderer),
            ValidateBaseUniversalPoolArtMarketplace.MarketplaceExpectations({
                owner: DEPLOYER,
                creatorMagicOwner: DEPLOYER,
                feeRecipient: SAFE,
                communityFee: PREMIUM,
                providerFee: 0,
                activeProviderCap: TEST_ACTIVE_PROVIDER_CAP,
                minimumInventory: REQUIRED_INVENTORY,
                paused: expectedPaused
            }),
            ValidateBaseUniversalPoolArtMarketplace.CheckoutExpectations({
                router: address(router),
                usdc: address(usdc),
                weth: address(weth),
                routerFeeRecipient: SAFE,
                routerFeePpm: FameRouterTypes.DEFAULT_FEE_PPM
            })
        );
    }
}
