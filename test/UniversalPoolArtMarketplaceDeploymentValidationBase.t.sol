// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {UniversalPoolArtMarketplace} from "../src/UniversalPoolArtMarketplace.sol";
import {FameMarketplaceCheckout} from "../src/FameMarketplaceCheckout.sol";
import {FameRouter} from "../src/FameRouter.sol";
import {FameRouterTypes} from "../src/router/FameRouterTypes.sol";
import {ActivateBaseUniversalPoolArtMarketplace} from "../script/ActivateBaseUniversalPoolArtMarketplace.s.sol";
import {DeployBaseUniversalPoolArtMarketplace} from "../script/DeployBaseUniversalPoolArtMarketplace.s.sol";
import {
    TransferBaseUniversalPoolArtMarketplaceOwnership
} from "../script/TransferBaseUniversalPoolArtMarketplaceOwnership.s.sol";
import {ValidateBaseUniversalPoolArtMarketplace} from "../script/ValidateBaseUniversalPoolArtMarketplace.s.sol";
import {UniversalPoolArtMarketplaceTestBase} from "./helpers/UniversalPoolArtMarketplaceTestBase.sol";
import {MockERC20, MockWETH} from "./router/mocks/MockERC20.sol";
import {FameRouterFixtureManifest} from "./router/fixtures/FameRouterFixtureManifest.sol";

contract UniversalPoolArtMarketplaceDeploymentValidationBaseTest is UniversalPoolArtMarketplaceTestBase {
    uint256 internal constant BASE_CHAIN_ID = 8453;
    uint256 internal constant PREMIUM = 30_000 ether;
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
    }

    function _fameName() internal pure override returns (string memory) {
        return "Society";
    }

    function testPausedHandoffAndSafeActivationValidationAcceptZeroInventory() public {
        (UniversalPoolArtMarketplace deployed, FameMarketplaceCheckout checkout) =
            deployer.deployMarketplaceStack(fame, creatorMagic, _deploymentConfig());

        assertTrue(deployed.paused());
        assertEq(deployed.owner(), DEPLOYER);
        assertEq(deployed.feeRecipient(), SAFE);
        assertEq(deployed.authorizedCheckout(), address(checkout));
        assertEq(address(checkout.market()), address(deployed));
        assertTrue(fame.getSkipNFT(address(checkout)));

        _grantBanisherRole(deployed);
        _assertEmptyInventoryAndProviderState(deployed);
        _validateStack(deployed, checkout, DEPLOYER, true);

        TransferBaseUniversalPoolArtMarketplaceOwnership handoff =
            new TransferBaseUniversalPoolArtMarketplaceOwnership();
        vm.etch(SAFE, hex"00");
        handoff.validateHandoff(deployed, DEPLOYER, SAFE);
        vm.prank(DEPLOYER);
        deployed.transferOwnership(SAFE);
        assertEq(deployed.owner(), SAFE);
        _assertEmptyInventoryAndProviderState(deployed);
        _validateStack(deployed, checkout, SAFE, true);

        activator.activateMarketplace(deployed, checkout, SAFE);
        _assertEmptyInventoryAndProviderState(deployed);
        _validateStack(deployed, checkout, SAFE, false);

        address provider = address(0xBEEF);
        _depositUnits(deployed, provider, 1);

        assertEq(deployed.inventory(), 1);
        assertEq(deployed.totalProviderUnits(), 1);
        assertEq(deployed.activeProviderCount(), 1);
        assertEq(deployed.owner(), SAFE);
        assertFalse(deployed.paused());
    }

    function testValidationAndActivationAllowProviderDepositsWhilePaused() public {
        (UniversalPoolArtMarketplace deployed, FameMarketplaceCheckout checkout) =
            deployer.deployMarketplaceStack(fame, creatorMagic, _deploymentConfig());
        _grantBanisherRole(deployed);

        address provider = address(0xBEEF);
        fame.transfer(provider, fame.unit());
        uint256 tokenId = _ownedTokenAt(provider, 0);
        vm.startPrank(provider);
        mirror.approve(address(deployed), tokenId);
        deployed.depositInventory(tokenId);
        vm.stopPrank();

        _validateStack(deployed, checkout, DEPLOYER, true);
        activator.activateMarketplace(deployed, checkout, DEPLOYER);
        _validateStack(deployed, checkout, DEPLOYER, false);

        assertFalse(deployed.paused());
        assertEq(deployed.inventory(), 1);
        assertEq(deployed.totalProviderUnits(), 1);
        assertEq(deployed.activeProviderCount(), 1);
    }

    function testValidationAllowsDonationOnlyInventory() public {
        (UniversalPoolArtMarketplace deployed, FameMarketplaceCheckout checkout) =
            deployer.deployMarketplaceStack(fame, creatorMagic, _deploymentConfig());
        _grantBanisherRole(deployed);

        _seedShells(deployed, 1);

        assertEq(deployed.inventory(), 1);
        assertEq(deployed.totalProviderUnits(), 0);
        assertEq(deployed.activeProviderCount(), 0);
        _validateStack(deployed, checkout, DEPLOYER, true);
    }

    function testValidationAllowsFractionalRawFame() public {
        (UniversalPoolArtMarketplace deployed, FameMarketplaceCheckout checkout) =
            deployer.deployMarketplaceStack(fame, creatorMagic, _deploymentConfig());
        _grantBanisherRole(deployed);

        fame.transfer(address(deployed), fame.unit() / 2);

        assertEq(deployed.inventory(), 0);
        assertEq(fame.balanceOf(address(deployed)), fame.unit() / 2);
        _validateStack(deployed, checkout, DEPLOYER, true);
    }

    function testValidationRejectsInconsistentProviderIndex() public {
        (UniversalPoolArtMarketplace deployed, FameMarketplaceCheckout checkout) =
            deployer.deployMarketplaceStack(fame, creatorMagic, _deploymentConfig());
        _grantBanisherRole(deployed);
        address provider = address(0xBEEF);
        _depositUnits(deployed, provider, 1);
        _setProviderPosition(deployed, provider, 1, 2);

        vm.expectRevert(
            abi.encodeWithSelector(
                ValidateBaseUniversalPoolArtMarketplace.ValueMismatch.selector, "marketplace.providerIndex", 1, 2
            )
        );
        _validateStack(deployed, checkout, DEPLOYER, true);
    }

    function testValidationRejectsZeroActiveProvider() public {
        (UniversalPoolArtMarketplace deployed, FameMarketplaceCheckout checkout) =
            deployer.deployMarketplaceStack(fame, creatorMagic, _deploymentConfig());
        _grantBanisherRole(deployed);
        _depositUnits(deployed, address(0xBEEF), 1);
        _setActiveProviderAt(deployed, 0, address(0));

        vm.expectRevert(
            abi.encodeWithSelector(
                ValidateBaseUniversalPoolArtMarketplace.AddressMismatch.selector,
                "marketplace.activeProvider",
                address(1),
                address(0)
            )
        );
        _validateStack(deployed, checkout, DEPLOYER, true);
    }

    function testValidationRejectsDuplicateActiveProvider() public {
        (UniversalPoolArtMarketplace deployed, FameMarketplaceCheckout checkout) =
            deployer.deployMarketplaceStack(fame, creatorMagic, _deploymentConfig());
        _grantBanisherRole(deployed);
        address firstProvider = address(0xBEEF);
        _depositUnits(deployed, firstProvider, 1);
        _depositUnits(deployed, address(0xCAFE), 1);
        _setActiveProviderAt(deployed, 1, firstProvider);

        vm.expectRevert(
            abi.encodeWithSelector(ValidateBaseUniversalPoolArtMarketplace.DuplicateProvider.selector, firstProvider)
        );
        _validateStack(deployed, checkout, DEPLOYER, true);
    }

    function testValidationRejectsProviderUnitSumMismatch() public {
        (UniversalPoolArtMarketplace deployed, FameMarketplaceCheckout checkout) =
            deployer.deployMarketplaceStack(fame, creatorMagic, _deploymentConfig());
        _grantBanisherRole(deployed);
        _depositUnits(deployed, address(0xBEEF), 1);
        vm.store(address(deployed), bytes32(uint256(3)), bytes32(uint256(2)));

        vm.expectRevert(
            abi.encodeWithSelector(
                ValidateBaseUniversalPoolArtMarketplace.ValueMismatch.selector, "marketplace.totalProviderUnits", 1, 2
            )
        );
        _validateStack(deployed, checkout, DEPLOYER, true);
    }

    function testValidationRejectsProviderUnitsWithoutInventoryBacking() public {
        (UniversalPoolArtMarketplace deployed, FameMarketplaceCheckout checkout) =
            deployer.deployMarketplaceStack(fame, creatorMagic, _deploymentConfig());
        _grantBanisherRole(deployed);
        address provider = address(0xBEEF);
        _depositUnits(deployed, provider, 1);
        _setProviderPosition(deployed, provider, 2, 1);
        vm.store(address(deployed), bytes32(uint256(3)), bytes32(uint256(2)));

        vm.expectRevert(
            abi.encodeWithSelector(
                ValidateBaseUniversalPoolArtMarketplace.ValueMismatch.selector, "marketplace.inventoryBacking", 2, 1
            )
        );
        _validateStack(deployed, checkout, DEPLOYER, true);
    }

    function testValidationRejectsProviderUnitsWithoutFameBacking() public {
        (UniversalPoolArtMarketplace deployed, FameMarketplaceCheckout checkout) =
            deployer.deployMarketplaceStack(fame, creatorMagic, _deploymentConfig());
        _grantBanisherRole(deployed);
        _depositUnits(deployed, address(0xBEEF), 1);
        _setFameBalance(address(deployed), fame.unit() - 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                ValidateBaseUniversalPoolArtMarketplace.ValueMismatch.selector,
                "marketplace.fameBacking",
                fame.unit(),
                fame.unit() - 1
            )
        );
        _validateStack(deployed, checkout, DEPLOYER, true);
    }

    function testValidationRejectsCheckoutSocietyCustody() public {
        (UniversalPoolArtMarketplace deployed, FameMarketplaceCheckout checkout) =
            deployer.deployMarketplaceStack(fame, creatorMagic, _deploymentConfig());
        _grantBanisherRole(deployed);
        address donor = address(0xBEEF);
        fame.transfer(donor, fame.unit());
        uint256 tokenId = _ownedTokenAt(donor, 0);
        vm.prank(donor);
        mirror.transferFrom(donor, address(checkout), tokenId);

        vm.expectRevert(
            abi.encodeWithSelector(
                ValidateBaseUniversalPoolArtMarketplace.ValueMismatch.selector, "checkout.ownedSocietyTokenIds", 0, 1
            )
        );
        _validateStack(deployed, checkout, DEPLOYER, true);
    }

    function testValidationRejectsCheckoutNativeBalance() public {
        (UniversalPoolArtMarketplace deployed, FameMarketplaceCheckout checkout) =
            deployer.deployMarketplaceStack(fame, creatorMagic, _deploymentConfig());
        _grantBanisherRole(deployed);
        vm.deal(address(checkout), 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                ValidateBaseUniversalPoolArtMarketplace.ValueMismatch.selector, "checkout.nativeBalance", 0, 1
            )
        );
        _validateStack(deployed, checkout, DEPLOYER, true);
    }

    function testValidationRejectsCheckoutFameBalance() public {
        (UniversalPoolArtMarketplace deployed, FameMarketplaceCheckout checkout) =
            deployer.deployMarketplaceStack(fame, creatorMagic, _deploymentConfig());
        _grantBanisherRole(deployed);
        fame.transfer(address(checkout), 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                ValidateBaseUniversalPoolArtMarketplace.ValueMismatch.selector, "checkout.fameBalance", 0, 1
            )
        );
        _validateStack(deployed, checkout, DEPLOYER, true);
    }

    function testValidationRejectsCheckoutUsdcBalance() public {
        (UniversalPoolArtMarketplace deployed, FameMarketplaceCheckout checkout) =
            deployer.deployMarketplaceStack(fame, creatorMagic, _deploymentConfig());
        _grantBanisherRole(deployed);
        usdc.mint(address(checkout), 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                ValidateBaseUniversalPoolArtMarketplace.ValueMismatch.selector, "checkout.usdcBalance", 0, 1
            )
        );
        _validateStack(deployed, checkout, DEPLOYER, true);
    }

    function testValidationRejectsCheckoutWethBalance() public {
        (UniversalPoolArtMarketplace deployed, FameMarketplaceCheckout checkout) =
            deployer.deployMarketplaceStack(fame, creatorMagic, _deploymentConfig());
        _grantBanisherRole(deployed);
        weth.mint(address(checkout), 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                ValidateBaseUniversalPoolArtMarketplace.ValueMismatch.selector, "checkout.wethBalance", 0, 1
            )
        );
        _validateStack(deployed, checkout, DEPLOYER, true);
    }

    function testValidationRejectsCheckoutMarketplaceAllowance() public {
        (UniversalPoolArtMarketplace deployed, FameMarketplaceCheckout checkout) =
            deployer.deployMarketplaceStack(fame, creatorMagic, _deploymentConfig());
        _grantBanisherRole(deployed);
        vm.prank(address(checkout));
        fame.approve(address(deployed), 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                ValidateBaseUniversalPoolArtMarketplace.ValueMismatch.selector,
                "checkout.marketplaceFameAllowance",
                0,
                1
            )
        );
        _validateStack(deployed, checkout, DEPLOYER, true);
    }

    function testValidationRejectsCheckoutRouterFameAllowance() public {
        (UniversalPoolArtMarketplace deployed, FameMarketplaceCheckout checkout) =
            deployer.deployMarketplaceStack(fame, creatorMagic, _deploymentConfig());
        _grantBanisherRole(deployed);
        vm.prank(address(checkout));
        fame.approve(address(router), 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                ValidateBaseUniversalPoolArtMarketplace.ValueMismatch.selector, "checkout.routerFameAllowance", 0, 1
            )
        );
        _validateStack(deployed, checkout, DEPLOYER, true);
    }

    function testValidationRejectsCheckoutRouterUsdcAllowance() public {
        (UniversalPoolArtMarketplace deployed, FameMarketplaceCheckout checkout) =
            deployer.deployMarketplaceStack(fame, creatorMagic, _deploymentConfig());
        _grantBanisherRole(deployed);
        vm.prank(address(checkout));
        usdc.approve(address(router), 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                ValidateBaseUniversalPoolArtMarketplace.ValueMismatch.selector, "checkout.routerUsdcAllowance", 0, 1
            )
        );
        _validateStack(deployed, checkout, DEPLOYER, true);
    }

    function testValidationRejectsCheckoutRouterWethAllowance() public {
        (UniversalPoolArtMarketplace deployed, FameMarketplaceCheckout checkout) =
            deployer.deployMarketplaceStack(fame, creatorMagic, _deploymentConfig());
        _grantBanisherRole(deployed);
        vm.prank(address(checkout));
        weth.approve(address(router), 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                ValidateBaseUniversalPoolArtMarketplace.ValueMismatch.selector, "checkout.routerWethAllowance", 0, 1
            )
        );
        _validateStack(deployed, checkout, DEPLOYER, true);
    }

    function testHandoffAcceptsExactSocietySafeWithCode() public {
        (UniversalPoolArtMarketplace deployed,) =
            deployer.deployMarketplaceStack(fame, creatorMagic, _deploymentConfig());
        vm.etch(SAFE, hex"00");

        new TransferBaseUniversalPoolArtMarketplaceOwnership().validateHandoff(deployed, DEPLOYER, SAFE);
    }

    function testHandoffRejectsArbitraryEoa() public {
        (UniversalPoolArtMarketplace deployed,) =
            deployer.deployMarketplaceStack(fame, creatorMagic, _deploymentConfig());
        address arbitraryEoa = address(0xBEEF);
        TransferBaseUniversalPoolArtMarketplaceOwnership handoff =
            new TransferBaseUniversalPoolArtMarketplaceOwnership();

        vm.expectRevert(
            abi.encodeWithSelector(
                TransferBaseUniversalPoolArtMarketplaceOwnership.FutureOwnerMismatch.selector, SAFE, arbitraryEoa
            )
        );
        handoff.validateHandoff(deployed, DEPLOYER, arbitraryEoa);
    }

    function testHandoffRejectsZeroFutureOwner() public {
        (UniversalPoolArtMarketplace deployed,) =
            deployer.deployMarketplaceStack(fame, creatorMagic, _deploymentConfig());
        TransferBaseUniversalPoolArtMarketplaceOwnership handoff =
            new TransferBaseUniversalPoolArtMarketplaceOwnership();

        vm.expectRevert(
            abi.encodeWithSelector(
                TransferBaseUniversalPoolArtMarketplaceOwnership.FutureOwnerMismatch.selector, SAFE, address(0)
            )
        );
        handoff.validateHandoff(deployed, DEPLOYER, address(0));
    }

    function testHandoffRejectsArbitraryContract() public {
        (UniversalPoolArtMarketplace deployed,) =
            deployer.deployMarketplaceStack(fame, creatorMagic, _deploymentConfig());
        address arbitraryContract = address(router);
        TransferBaseUniversalPoolArtMarketplaceOwnership handoff =
            new TransferBaseUniversalPoolArtMarketplaceOwnership();

        vm.expectRevert(
            abi.encodeWithSelector(
                TransferBaseUniversalPoolArtMarketplaceOwnership.FutureOwnerMismatch.selector, SAFE, arbitraryContract
            )
        );
        handoff.validateHandoff(deployed, DEPLOYER, arbitraryContract);
    }

    function testHandoffRejectsCodeLessSocietySafe() public {
        (UniversalPoolArtMarketplace deployed,) =
            deployer.deployMarketplaceStack(fame, creatorMagic, _deploymentConfig());
        TransferBaseUniversalPoolArtMarketplaceOwnership handoff =
            new TransferBaseUniversalPoolArtMarketplaceOwnership();

        vm.expectRevert(
            abi.encodeWithSelector(TransferBaseUniversalPoolArtMarketplaceOwnership.CodeMissing.selector, SAFE)
        );
        handoff.validateHandoff(deployed, DEPLOYER, SAFE);
    }

    function testHandoffRejectsSocietySafeAsCurrentOwner() public {
        (UniversalPoolArtMarketplace deployed,) =
            deployer.deployMarketplaceStack(fame, creatorMagic, _deploymentConfig());
        vm.etch(SAFE, hex"00");
        vm.prank(DEPLOYER);
        deployed.transferOwnership(SAFE);
        TransferBaseUniversalPoolArtMarketplaceOwnership handoff =
            new TransferBaseUniversalPoolArtMarketplaceOwnership();

        vm.expectRevert(
            abi.encodeWithSelector(
                TransferBaseUniversalPoolArtMarketplaceOwnership.FutureOwnerIsCurrentOwner.selector, SAFE
            )
        );
        handoff.validateHandoff(deployed, SAFE, SAFE);
    }

    function testValidationRejectsRendererAuthorityInAdditionToBanisher() public {
        (UniversalPoolArtMarketplace deployed, FameMarketplaceCheckout checkout) =
            deployer.deployMarketplaceStack(fame, creatorMagic, _deploymentConfig());

        vm.startPrank(DEPLOYER);
        creatorMagic.grantRoles(address(deployed), CREATOR_MAGIC_BANISHER_ROLE | CREATOR_MAGIC_RENDERER_ROLE);
        vm.stopPrank();

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

    function testValidationRejectsRouterSkipNftDisabled() public {
        (UniversalPoolArtMarketplace deployed, FameMarketplaceCheckout checkout) =
            deployer.deployMarketplaceStack(fame, creatorMagic, _deploymentConfig());
        _grantBanisherRole(deployed);
        vm.prank(address(router));
        fame.setSkipNFT(false);

        vm.expectRevert(
            abi.encodeWithSelector(
                ValidateBaseUniversalPoolArtMarketplace.RouterNotSkippingNFT.selector, address(router)
            )
        );
        _validateStack(deployed, checkout, DEPLOYER, true);
    }

    function testValidationRejectsCheckoutAsRouterFeeRecipient() public {
        (UniversalPoolArtMarketplace deployed, FameMarketplaceCheckout checkout) =
            deployer.deployMarketplaceStack(fame, creatorMagic, _deploymentConfig());
        _grantBanisherRole(deployed);
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
        _grantBanisherRole(deployed);

        vm.expectRevert(
            abi.encodeWithSelector(
                ValidateBaseUniversalPoolArtMarketplace.AddressMismatch.selector,
                "checkout.usdc",
                address(usdc),
                address(wrongUsdc)
            )
        );
        _validateStack(deployed, wrongCheckout, DEPLOYER, true);
    }

    function _grantBanisherRole(UniversalPoolArtMarketplace deployed) private {
        vm.prank(DEPLOYER);
        creatorMagic.grantRoles(address(deployed), CREATOR_MAGIC_BANISHER_ROLE);
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

    function _validateStack(
        UniversalPoolArtMarketplace deployed,
        FameMarketplaceCheckout checkout,
        address expectedOwner,
        bool expectedPaused
    ) private view {
        validator.validateMarketplaceStack(
            fame,
            mirror,
            creatorMagic,
            deployed,
            checkout,
            address(childRenderer),
            ValidateBaseUniversalPoolArtMarketplace.MarketplaceExpectations({
                owner: expectedOwner,
                creatorMagicOwner: DEPLOYER,
                feeRecipient: SAFE,
                communityFee: PREMIUM,
                providerFee: 0,
                activeProviderCap: TEST_ACTIVE_PROVIDER_CAP,
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

    function _assertEmptyInventoryAndProviderState(UniversalPoolArtMarketplace deployed) private view {
        assertEq(deployed.inventory(), 0);
        assertEq(deployed.activeProviderCount(), 0);
        assertEq(deployed.totalProviderUnits(), 0);
    }

    function _setProviderPosition(
        UniversalPoolArtMarketplace deployed,
        address provider,
        uint32 unitCount,
        uint32 indexPlusOne
    ) private {
        bytes32 positionSlot = keccak256(abi.encode(provider, uint256(5)));
        vm.store(address(deployed), positionSlot, bytes32(uint256(unitCount) | (uint256(indexPlusOne) << 32)));
    }

    function _setActiveProviderAt(UniversalPoolArtMarketplace deployed, uint256 index, address provider) private {
        bytes32 providersStart = keccak256(abi.encode(uint256(8)));
        vm.store(address(deployed), bytes32(uint256(providersStart) + index), bytes32(uint256(uint160(provider))));
    }

    function _setFameBalance(address account, uint256 balance) private {
        uint256 dn404StorageSlot = 0xa20d6e21d0e5255308;
        bytes32 addressDataSlot = keccak256(abi.encode(account, dn404StorageSlot + 11));
        uint256 packedAddressData = uint256(vm.load(address(fame), addressDataSlot));
        uint256 lowerFieldsMask = type(uint160).max;
        vm.store(address(fame), addressDataSlot, bytes32((packedAddressData & lowerFieldsMask) | (balance << 160)));
    }
}
