// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {UniversalPoolArtMarketplace} from "../src/UniversalPoolArtMarketplace.sol";
import {CreatorArtistMagic} from "../src/CreatorArtistMagic.sol";
import {Fame} from "../src/Fame.sol";
import {FameMirror} from "../src/FameMirror.sol";

contract ValidateBaseUniversalPoolArtMarketplace is Script {
    uint256 internal constant BASE_CHAIN_ID = 8453;
    address internal constant BASE_FAME = 0xf307e242BfE1EC1fF01a4Cef2fdaa81b10A52418;
    address internal constant BASE_MIRROR = 0xBB5ED04dD7B207592429eb8d599d103CCad646c4;
    address internal constant BASE_CREATOR_MAGIC = 0xC8268c2aa571F3C88044C2959F73DdB8eB9e139F;
    address internal constant BASE_CHILD_RENDERER = 0x8091D00A25ebE87A2A1Ef19e1d33689FCAdC3fA5;
    uint256 internal constant EXPECTED_UNIT = 1_000_000 ether;
    uint256 internal constant CREATOR_MAGIC_CREATOR_ROLE = 1 << 1;
    uint256 internal constant CREATOR_MAGIC_BANISHER_ROLE = 1 << 2;
    uint256 internal constant CREATOR_MAGIC_ART_POOL_MANAGER_ROLE = 1 << 3;
    uint256 internal constant FAME_SKIP_MANAGER_ROLE = 1 << 3;

    struct MarketplaceExpectations {
        address owner;
        address feeRecipient;
        uint256 premium;
        uint256 inventory;
        bool paused;
    }

    error ChainIdMismatch(uint256 expected, uint256 actual);
    error AddressMismatch(string field, address expected, address actual);
    error ValueMismatch(string field, uint256 expected, uint256 actual);
    error CodeMissing(string field, address target);
    error FameIdentityMismatch();
    error FeeRecipientNotSkippingNFT(address recipient);
    error MarketplaceSkippingNFT();
    error CreatorMagicBanisherRoleMissing();
    error CreatorMagicRoleTooBroad(uint256 role);
    error FameSkipManagerRoleTooBroad();

    function run() external view {
        _requireBase();

        Fame fame = Fame(payable(vm.envAddress("BASE_FAME_ADDRESS")));
        FameMirror mirror = FameMirror(payable(vm.envAddress("BASE_FAME_NFT_ADDRESS")));
        CreatorArtistMagic creatorMagic = CreatorArtistMagic(vm.envAddress("BASE_CREATOR_ARTIST_MAGIC_ADDRESS"));
        UniversalPoolArtMarketplace market =
            UniversalPoolArtMarketplace(vm.envAddress("BASE_UNIVERSAL_MARKETPLACE_ADDRESS"));

        _checkAddress("fame", BASE_FAME, address(fame));
        _checkAddress("mirror", BASE_MIRROR, address(mirror));
        _checkAddress("creatorMagic", BASE_CREATOR_MAGIC, address(creatorMagic));

        validateMarketplace(
            fame,
            mirror,
            creatorMagic,
            market,
            BASE_CHILD_RENDERER,
            MarketplaceExpectations({
                owner: vm.envAddress("BASE_UNIVERSAL_MARKETPLACE_OWNER"),
                feeRecipient: vm.envAddress("BASE_UNIVERSAL_MARKETPLACE_FEE_RECIPIENT"),
                premium: vm.envUint("BASE_UNIVERSAL_MARKETPLACE_PREMIUM"),
                inventory: vm.envUint("BASE_UNIVERSAL_MARKETPLACE_INVENTORY"),
                paused: vm.envBool("BASE_UNIVERSAL_MARKETPLACE_EXPECTED_PAUSED")
            })
        );
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
        _checkAddress("creatorMagic.owner", expected.owner, creatorMagic.owner());
        _checkAddress("marketplace.fame", address(fame), address(market.fame()));
        _checkAddress("marketplace.mirror", address(mirror), address(market.mirror()));
        _checkAddress("marketplace.creatorMagic", address(creatorMagic), address(market.creatorMagic()));
        _checkAddress("marketplace.owner", expected.owner, market.owner());
        _checkAddress("marketplace.feeRecipient", expected.feeRecipient, market.feeRecipient());

        _checkValue("marketplace.premium", expected.premium, market.premium());
        _checkValue("marketplace.inventory", expected.inventory, market.inventory());
        _checkValue("marketplace.paused", expected.paused ? 1 : 0, market.paused() ? 1 : 0);

        if (!fame.getSkipNFT(expected.feeRecipient)) {
            revert FeeRecipientNotSkippingNFT(expected.feeRecipient);
        }
        if (fame.getSkipNFT(address(market))) revert MarketplaceSkippingNFT();
        if (!creatorMagic.hasAnyRole(address(market), CREATOR_MAGIC_BANISHER_ROLE)) {
            revert CreatorMagicBanisherRoleMissing();
        }
        if (creatorMagic.hasAnyRole(address(market), CREATOR_MAGIC_CREATOR_ROLE)) {
            revert CreatorMagicRoleTooBroad(CREATOR_MAGIC_CREATOR_ROLE);
        }
        if (creatorMagic.hasAnyRole(address(market), CREATOR_MAGIC_ART_POOL_MANAGER_ROLE)) {
            revert CreatorMagicRoleTooBroad(CREATOR_MAGIC_ART_POOL_MANAGER_ROLE);
        }
        if (fame.hasAnyRole(address(market), FAME_SKIP_MANAGER_ROLE)) revert FameSkipManagerRoleTooBroad();
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
}
