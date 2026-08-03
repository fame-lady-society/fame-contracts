// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {FameMarketplaceCheckout} from "../src/FameMarketplaceCheckout.sol";
import {FameRouter} from "../src/FameRouter.sol";
import {UniversalPoolArtMarketplace} from "../src/UniversalPoolArtMarketplace.sol";
import {CreatorArtistMagic} from "../src/CreatorArtistMagic.sol";
import {Fame} from "../src/Fame.sol";
import {FameMirror} from "../src/FameMirror.sol";
import {FameRouterTypes} from "../src/router/FameRouterTypes.sol";
import {FameRouterFixtureManifest} from "../test/router/fixtures/FameRouterFixtureManifest.sol";
import {ValidateFameRouterBase} from "./ValidateFameRouterBase.s.sol";

contract ValidateBaseUniversalPoolArtMarketplace is Script {
    uint256 internal constant BASE_CHAIN_ID = 8453;
    address internal constant BASE_FAME = 0xf307e242BfE1EC1fF01a4Cef2fdaa81b10A52418;
    address internal constant BASE_MIRROR = 0xBB5ED04dD7B207592429eb8d599d103CCad646c4;
    address internal constant BASE_CREATOR_MAGIC = 0xC8268c2aa571F3C88044C2959F73DdB8eB9e139F;
    address internal constant BASE_CHILD_RENDERER = 0x8091D00A25ebE87A2A1Ef19e1d33689FCAdC3fA5;
    uint256 internal constant EXPECTED_UNIT = 1_000_000 ether;
    uint256 internal constant EXPECTED_MAX_INVENTORY_BATCH_SIZE = 8;
    uint256 internal constant CREATOR_MAGIC_BANISHER_ROLE = 1 << 2;
    uint256 internal constant FAME_SKIP_MANAGER_ROLE = 1 << 3;

    struct MarketplaceExpectations {
        address owner;
        address creatorMagicOwner;
        address feeRecipient;
        uint256 communityFee;
        uint256 providerFee;
        uint256 activeProviderCap;
        uint256 minimumInventory;
        bool paused;
    }

    struct CheckoutExpectations {
        address router;
        address usdc;
        address weth;
        address routerFeeRecipient;
        uint256 routerFeePpm;
    }

    error ChainIdMismatch(uint256 expected, uint256 actual);
    error AddressMismatch(string field, address expected, address actual);
    error ValueMismatch(string field, uint256 expected, uint256 actual);
    error CodeMissing(string field, address target);
    error FameIdentityMismatch();
    error FeeRecipientNotSkippingNFT(address recipient);
    error CheckoutNotSkippingNFT(address checkout);
    error RouterNotSkippingNFT(address router);
    error CheckoutIsFeeRecipient(address checkout);
    error RouterFeeRecipientIsCheckout(address checkout);
    error RouterVenueFamilyDisabled(FameRouterTypes.VenueFamily family);
    error RouterVenueTargetDisabled(FameRouterTypes.VenueFamily family, address target);
    error MarketplaceSkippingNFT();
    error CreatorMagicBanisherRoleMissing();
    error CreatorMagicRoleTooBroad(uint256 role);
    error FameSkipManagerRoleTooBroad();

    function run() external {
        _requireBase();

        Fame fame = Fame(payable(vm.envAddress("BASE_FAME_ADDRESS")));
        FameMirror mirror = FameMirror(payable(vm.envAddress("BASE_FAME_NFT_ADDRESS")));
        CreatorArtistMagic creatorMagic = CreatorArtistMagic(vm.envAddress("BASE_CREATOR_ARTIST_MAGIC_ADDRESS"));
        UniversalPoolArtMarketplace market =
            UniversalPoolArtMarketplace(vm.envAddress("BASE_UNIVERSAL_MARKETPLACE_ADDRESS"));
        FameMarketplaceCheckout checkout =
            FameMarketplaceCheckout(payable(vm.envAddress("BASE_FAME_MARKETPLACE_CHECKOUT_ADDRESS")));

        _checkAddress("fame", BASE_FAME, address(fame));
        _checkAddress("mirror", BASE_MIRROR, address(mirror));
        _checkAddress("creatorMagic", BASE_CREATOR_MAGIC, address(creatorMagic));
        validateBaseCheckoutDependencies(
            checkout,
            vm.envAddress("BASE_FAME_ROUTER_ADDRESS"),
            vm.envAddress("BASE_USDC_ADDRESS"),
            vm.envAddress("BASE_WETH_ADDRESS")
        );

        new ValidateFameRouterBase().run();

        validateMarketplaceStack(
            fame,
            mirror,
            creatorMagic,
            market,
            checkout,
            BASE_CHILD_RENDERER,
            configuredMarketplaceExpectations(
                vm.envAddress("BASE_UNIVERSAL_MARKETPLACE_OWNER"),
                vm.envBool("BASE_UNIVERSAL_MARKETPLACE_EXPECTED_PAUSED")
            ),
            configuredCheckoutExpectations()
        );
    }

    function configuredMarketplaceExpectations(address owner, bool paused)
        public
        view
        returns (MarketplaceExpectations memory)
    {
        return MarketplaceExpectations({
            owner: owner,
            creatorMagicOwner: vm.envAddress("BASE_UNIVERSAL_MARKETPLACE_DEPLOYER"),
            feeRecipient: vm.envAddress("BASE_UNIVERSAL_MARKETPLACE_FEE_RECIPIENT"),
            communityFee: vm.envUint("BASE_UNIVERSAL_MARKETPLACE_COMMUNITY_FEE"),
            providerFee: vm.envUint("BASE_UNIVERSAL_MARKETPLACE_PROVIDER_FEE"),
            activeProviderCap: vm.envUint("BASE_UNIVERSAL_MARKETPLACE_ACTIVE_PROVIDER_CAP"),
            minimumInventory: vm.envUint("BASE_UNIVERSAL_MARKETPLACE_INVENTORY"),
            paused: paused
        });
    }

    function configuredCheckoutExpectations() public view returns (CheckoutExpectations memory) {
        return CheckoutExpectations({
            router: vm.envAddress("BASE_FAME_ROUTER_ADDRESS"),
            usdc: vm.envAddress("BASE_USDC_ADDRESS"),
            weth: vm.envAddress("BASE_WETH_ADDRESS"),
            routerFeeRecipient: vm.envAddress("BASE_FAME_ROUTER_FEE_RECIPIENT"),
            routerFeePpm: vm.envUint("BASE_FAME_ROUTER_FEE_PPM")
        });
    }

    function validateBaseCheckoutDependencies(
        FameMarketplaceCheckout checkout,
        address expectedRouter,
        address expectedUsdc,
        address expectedWeth
    ) public view {
        _requireBase();
        _checkAddress("router", expectedRouter, checkout.router());
        _checkAddress("usdc", expectedUsdc, checkout.usdc());
        _checkAddress("weth", expectedWeth, checkout.weth());
    }

    function validateMarketplaceStack(
        Fame fame,
        FameMirror mirror,
        CreatorArtistMagic creatorMagic,
        UniversalPoolArtMarketplace market,
        FameMarketplaceCheckout checkout,
        address expectedChildRenderer,
        MarketplaceExpectations memory marketExpected,
        CheckoutExpectations memory checkoutExpected
    ) public view {
        validateMarketplace(fame, mirror, creatorMagic, market, expectedChildRenderer, marketExpected);

        _requireCode("checkout", address(checkout));
        _requireCode("router", checkoutExpected.router);
        _requireCode("usdc", checkoutExpected.usdc);
        _requireCode("weth", checkoutExpected.weth);

        _checkAddress("marketplace.authorizedCheckout", address(checkout), market.authorizedCheckout());
        _checkAddress("checkout.router", checkoutExpected.router, checkout.router());
        _checkAddress("checkout.market", address(market), address(checkout.market()));
        _checkAddress("checkout.fame", address(fame), address(checkout.fame()));
        _checkAddress("checkout.usdc", checkoutExpected.usdc, checkout.usdc());
        _checkAddress("checkout.weth", checkoutExpected.weth, checkout.weth());

        if (marketExpected.feeRecipient == address(checkout)) revert CheckoutIsFeeRecipient(address(checkout));
        if (!fame.getSkipNFT(address(checkout))) revert CheckoutNotSkippingNFT(address(checkout));
        _checkValue("checkout.ownedSocietyTokenIds", 0, checkout.ownedSocietyTokenIds(address(checkout), 1, 889).length);
        if (!fame.getSkipNFT(checkoutExpected.router)) revert RouterNotSkippingNFT(checkoutExpected.router);

        FameRouter router = FameRouter(payable(checkoutExpected.router));
        if (router.feeRecipient() == address(checkout)) {
            revert RouterFeeRecipientIsCheckout(address(checkout));
        }
        _checkAddress("router.feeRecipient", checkoutExpected.routerFeeRecipient, router.feeRecipient());
        _checkValue("router.feePpm", checkoutExpected.routerFeePpm, router.feePpm());
        for (uint256 i; i < FameRouterFixtureManifest.requiredVenueTargetCount(); ++i) {
            FameRouterTypes.VenueFamily family = FameRouterFixtureManifest.requiredVenueFamily(i);
            address target = FameRouterFixtureManifest.requiredVenueTarget(i);
            if (!router.venueFamilyEnabled(family)) revert RouterVenueFamilyDisabled(family);
            if (!router.venueTargetEnabled(family, target)) revert RouterVenueTargetDisabled(family, target);
        }
    }

    function validateMarketplace(
        Fame fame,
        FameMirror mirror,
        CreatorArtistMagic creatorMagic,
        UniversalPoolArtMarketplace market,
        address expectedChildRenderer,
        MarketplaceExpectations memory expected
    ) public view {
        _requireBase();
        _requireCode("fame", address(fame));
        _requireCode("mirror", address(mirror));
        _requireCode("creatorMagic", address(creatorMagic));
        _requireCode("childRenderer", expectedChildRenderer);
        _requireCode("marketplace", address(market));

        if (
            keccak256(bytes(fame.name())) != keccak256("Society")
                || keccak256(bytes(fame.symbol())) != keccak256("FAME") || fame.unit() != EXPECTED_UNIT
        ) {
            revert FameIdentityMismatch();
        }
        _checkAddress("fame.mirror", address(mirror), address(fame.fameMirror()));
        _checkAddress("fame.renderer", address(creatorMagic), address(fame.renderer()));
        _checkAddress("creatorMagic.fame", address(fame), address(creatorMagic.fame()));
        _checkAddress("creatorMagic.childRenderer", expectedChildRenderer, address(creatorMagic.childRenderer()));
        _checkAddress("creatorMagic.owner", expected.creatorMagicOwner, creatorMagic.owner());
        _checkAddress("marketplace.fame", address(fame), address(market.fame()));
        _checkAddress("marketplace.mirror", address(mirror), address(market.mirror()));
        _checkAddress("marketplace.creatorMagic", address(creatorMagic), address(market.creatorMagic()));
        _checkAddress("marketplace.owner", expected.owner, market.owner());
        _checkAddress("marketplace.feeRecipient", expected.feeRecipient, market.feeRecipient());

        _checkValue("marketplace.communityFee", expected.communityFee, market.communityFee());
        _checkValue("marketplace.providerFee", expected.providerFee, market.providerFee());
        _checkValue("marketplace.premium", expected.communityFee + expected.providerFee, market.premium());
        _checkValue("marketplace.activeProviderCap", expected.activeProviderCap, market.activeProviderCap());
        _checkValue(
            "marketplace.maxInventoryBatchSize", EXPECTED_MAX_INVENTORY_BATCH_SIZE, market.MAX_INVENTORY_BATCH_SIZE()
        );
        _validateProviderState(market);
        _checkAtLeast("marketplace.inventory", expected.minimumInventory, market.inventory());
        _checkValue("marketplace.paused", expected.paused ? 1 : 0, market.paused() ? 1 : 0);

        if (!fame.getSkipNFT(expected.feeRecipient)) {
            revert FeeRecipientNotSkippingNFT(expected.feeRecipient);
        }
        if (fame.getSkipNFT(address(market))) revert MarketplaceSkippingNFT();
        uint256 creatorMagicRoles = creatorMagic.rolesOf(address(market));
        if (creatorMagicRoles & CREATOR_MAGIC_BANISHER_ROLE == 0) {
            revert CreatorMagicBanisherRoleMissing();
        }
        if (creatorMagicRoles != CREATOR_MAGIC_BANISHER_ROLE) {
            revert CreatorMagicRoleTooBroad(creatorMagicRoles & ~CREATOR_MAGIC_BANISHER_ROLE);
        }
        if (fame.hasAnyRole(address(market), FAME_SKIP_MANAGER_ROLE)) revert FameSkipManagerRoleTooBroad();
    }

    function _validateProviderState(UniversalPoolArtMarketplace market) internal view {
        uint256 providerCount = market.activeProviderCount();
        uint256 providerCap = market.activeProviderCap();
        if (providerCount > providerCap) {
            revert ValueMismatch("marketplace.activeProviderCount", providerCap, providerCount);
        }

        uint256 summedUnits;
        for (uint256 i; i < providerCount; ++i) {
            address provider = market.activeProviderAt(i);
            if (provider == address(0)) {
                revert AddressMismatch("marketplace.activeProvider", address(1), address(0));
            }
            (uint256 units, uint256 indexPlusOne) = market.providerPosition(provider);
            if (units == 0) revert ValueMismatch("marketplace.providerUnits", 1, 0);
            _checkValue("marketplace.providerIndex", i + 1, indexPlusOne);
            summedUnits += units;
        }
        _checkValue("marketplace.totalProviderUnits", summedUnits, market.totalProviderUnits());
    }

    function _requireBase() internal view {
        if (block.chainid != BASE_CHAIN_ID) revert ChainIdMismatch(BASE_CHAIN_ID, block.chainid);
    }

    function _requireCode(string memory field, address target) internal view {
        if (target.code.length == 0) revert CodeMissing(field, target);
    }

    function _checkAddress(string memory field, address expected, address actual) internal pure {
        if (actual != expected) revert AddressMismatch(field, expected, actual);
    }

    function _checkValue(string memory field, uint256 expected, uint256 actual) internal pure {
        if (actual != expected) revert ValueMismatch(field, expected, actual);
    }

    function _checkAtLeast(string memory field, uint256 minimum, uint256 actual) internal pure {
        if (actual < minimum) revert ValueMismatch(field, minimum, actual);
    }
}
