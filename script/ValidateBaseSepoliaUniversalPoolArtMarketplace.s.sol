// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {UniversalPoolArtMarketplace} from "../src/UniversalPoolArtMarketplace.sol";
import {CreatorArtistMagic} from "../src/CreatorArtistMagic.sol";
import {Fame} from "../src/Fame.sol";
import {FameMirror} from "../src/FameMirror.sol";

contract ValidateBaseSepoliaUniversalPoolArtMarketplace is Script {
    uint256 internal constant BASE_SEPOLIA_CHAIN_ID = 84532;
    address internal constant BASE_SEPOLIA_FAME = 0x2cF0408Ee86b337216dD0073ab257F84497067cA;
    address internal constant BASE_SEPOLIA_MIRROR = 0x2907936013BDF568F98A98893AC1C746256A9cC5;
    uint256 internal constant EXPECTED_UNIT = 1_000_000 ether;
    uint256 internal constant EXPECTED_MAX_INVENTORY_BATCH_SIZE = 8;
    uint256 internal constant CREATOR_MAGIC_CREATOR_ROLE = 1 << 1;
    uint256 internal constant CREATOR_MAGIC_BANISHER_ROLE = 1 << 2;
    uint256 internal constant CREATOR_MAGIC_ART_POOL_MANAGER_ROLE = 1 << 3;
    uint256 internal constant FAME_SKIP_MANAGER_ROLE = 1 << 3;

    struct MarketplaceExpectations {
        address owner;
        address feeRecipient;
        uint256 communityFee;
        uint256 providerFee;
        uint256 activeProviderCap;
        uint256 minimumInventory;
        bool paused;
    }

    error ChainIdMismatch(uint256 expected, uint256 actual);
    error CanonicalAddressMismatch(string field, address expected, address actual);
    error CodeMissing(string field, address target);
    error AddressMismatch(string field, address expected, address actual);
    error ValueMismatch(string field, uint256 expected, uint256 actual);
    error FameIdentityMismatch();
    error PremiumOutOfRange(uint256 premium);
    error MarketplaceSkippingNFT();
    error MarketplaceInventoryTooLow(uint256 minimum, uint256 actual);
    error CreatorMagicBanisherRoleMissing();
    error CreatorMagicRoleTooBroad(uint256 role);
    error FameSkipManagerRoleTooBroad();

    function run() external view {
        if (block.chainid != BASE_SEPOLIA_CHAIN_ID) {
            revert ChainIdMismatch(BASE_SEPOLIA_CHAIN_ID, block.chainid);
        }

        Fame fame = Fame(payable(vm.envAddress("BASE_SEPOLIA_FAME_ADDRESS")));
        FameMirror mirror = FameMirror(payable(vm.envAddress("BASE_SEPOLIA_FAME_NFT_ADDRESS")));
        CreatorArtistMagic creatorMagic = CreatorArtistMagic(vm.envAddress("BASE_SEPOLIA_CREATOR_ARTIST_MAGIC_ADDRESS"));
        UniversalPoolArtMarketplace market =
            UniversalPoolArtMarketplace(vm.envAddress("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_ADDRESS"));
        MarketplaceExpectations memory expected = MarketplaceExpectations({
            owner: vm.envAddress("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_OWNER"),
            feeRecipient: vm.envAddress("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_FEE_RECIPIENT"),
            communityFee: vm.envUint("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_COMMUNITY_FEE"),
            providerFee: vm.envUint("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_PROVIDER_FEE"),
            activeProviderCap: vm.envUint("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_ACTIVE_PROVIDER_CAP"),
            minimumInventory: vm.envUint("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_MINIMUM_INVENTORY"),
            paused: vm.envOr("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_EXPECTED_PAUSED", true)
        });

        validateCanonicalAddresses(fame, mirror);
        validateMarketplace(fame, mirror, creatorMagic, market, expected);
    }

    function validateCanonicalAddresses(Fame fame, FameMirror mirror) public pure {
        if (address(fame) != BASE_SEPOLIA_FAME) {
            revert CanonicalAddressMismatch("fame", BASE_SEPOLIA_FAME, address(fame));
        }
        if (address(mirror) != BASE_SEPOLIA_MIRROR) {
            revert CanonicalAddressMismatch("mirror", BASE_SEPOLIA_MIRROR, address(mirror));
        }
    }

    function validateMarketplace(
        Fame fame,
        FameMirror mirror,
        CreatorArtistMagic creatorMagic,
        UniversalPoolArtMarketplace market,
        MarketplaceExpectations memory expected
    ) public view {
        _requireCode("fame", address(fame));
        _requireCode("mirror", address(mirror));
        _requireCode("creatorMagic", address(creatorMagic));
        _requireCode("marketplace", address(market));

        if (
            keccak256(bytes(fame.name())) != keccak256("Example")
                || keccak256(bytes(fame.symbol())) != keccak256("TEST") || fame.unit() != EXPECTED_UNIT
        ) {
            revert FameIdentityMismatch();
        }
        _checkAddress("fame.mirror", address(mirror), address(fame.fameMirror()));
        _checkAddress("fame.renderer", address(creatorMagic), address(fame.renderer()));
        _checkAddress("creatorMagic.fame", address(fame), address(creatorMagic.fame()));
        _checkAddress("marketplace.fame", address(fame), address(market.fame()));
        _checkAddress("marketplace.mirror", address(mirror), address(market.mirror()));
        _checkAddress("marketplace.creatorMagic", address(creatorMagic), address(market.creatorMagic()));
        _checkAddress("marketplace.owner", expected.owner, market.owner());
        _checkAddress("marketplace.feeRecipient", expected.feeRecipient, market.feeRecipient());

        uint256 maximumFee = fame.unit() / 10;
        if (expected.communityFee > maximumFee) {
            revert PremiumOutOfRange(expected.communityFee);
        }
        if (expected.providerFee > maximumFee) {
            revert PremiumOutOfRange(expected.providerFee);
        }
        _checkValue("marketplace.communityFee", expected.communityFee, market.communityFee());
        _checkValue("marketplace.providerFee", expected.providerFee, market.providerFee());
        _checkValue("marketplace.premium", expected.communityFee + expected.providerFee, market.premium());
        _checkValue("marketplace.activeProviderCap", expected.activeProviderCap, market.activeProviderCap());
        _checkValue(
            "marketplace.maxInventoryBatchSize", EXPECTED_MAX_INVENTORY_BATCH_SIZE, market.MAX_INVENTORY_BATCH_SIZE()
        );
        if (market.paused() != expected.paused) {
            revert ValueMismatch("marketplace.paused", expected.paused ? 1 : 0, market.paused() ? 1 : 0);
        }
        if (fame.getSkipNFT(address(market))) revert MarketplaceSkippingNFT();
        uint256 actualInventory = mirror.balanceOf(address(market));
        if (actualInventory < expected.minimumInventory) {
            revert MarketplaceInventoryTooLow(expected.minimumInventory, actualInventory);
        }

        if (!creatorMagic.hasAnyRole(address(market), CREATOR_MAGIC_BANISHER_ROLE)) {
            revert CreatorMagicBanisherRoleMissing();
        }
        if (creatorMagic.hasAnyRole(address(market), CREATOR_MAGIC_CREATOR_ROLE)) {
            revert CreatorMagicRoleTooBroad(CREATOR_MAGIC_CREATOR_ROLE);
        }
        if (creatorMagic.hasAnyRole(address(market), CREATOR_MAGIC_ART_POOL_MANAGER_ROLE)) {
            revert CreatorMagicRoleTooBroad(CREATOR_MAGIC_ART_POOL_MANAGER_ROLE);
        }
        if (fame.hasAnyRole(address(market), FAME_SKIP_MANAGER_ROLE)) {
            revert FameSkipManagerRoleTooBroad();
        }
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
}
