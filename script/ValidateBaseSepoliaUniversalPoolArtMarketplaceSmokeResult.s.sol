// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {UniversalPoolArtMarketplace} from "../src/UniversalPoolArtMarketplace.sol";
import {CreatorArtistMagic} from "../src/CreatorArtistMagic.sol";
import {Fame} from "../src/Fame.sol";
import {SmokeBaseSepoliaUniversalPoolArtMarketplace} from "./SmokeBaseSepoliaUniversalPoolArtMarketplace.s.sol";

contract ValidateBaseSepoliaUniversalPoolArtMarketplaceSmokeResult is Script {
    uint256 internal constant BASE_SEPOLIA_CHAIN_ID = 84532;

    error ChainIdMismatch(uint256 expected, uint256 actual);
    error MarketplaceNotActive();
    error ResultAddressMismatch(string field, address expected, address actual);
    error ResultValueMismatch(string field, uint256 expected, uint256 actual);
    error ResultArtworkMismatch(uint256 tokenId, bytes32 expected, bytes32 actual);

    function run() external view {
        if (block.chainid != BASE_SEPOLIA_CHAIN_ID) {
            revert ChainIdMismatch(BASE_SEPOLIA_CHAIN_ID, block.chainid);
        }

        Fame fame = Fame(payable(vm.envAddress("BASE_SEPOLIA_FAME_ADDRESS")));
        CreatorArtistMagic creatorMagic = CreatorArtistMagic(vm.envAddress("BASE_SEPOLIA_CREATOR_ARTIST_MAGIC_ADDRESS"));
        UniversalPoolArtMarketplace market =
            UniversalPoolArtMarketplace(vm.envAddress("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_ADDRESS"));
        SmokeBaseSepoliaUniversalPoolArtMarketplace.SmokePlan memory plan = _loadPlan();
        bytes32 expectedCommitment = vm.envBytes32("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_SMOKE_PLAN_HASH");
        bytes32 actualCommitment = keccak256(abi.encode(plan));
        if (actualCommitment != expectedCommitment) {
            revert ResultValueMismatch("planHash", uint256(expectedCommitment), uint256(actualCommitment));
        }

        validateResult(plan, fame, creatorMagic, market);
    }

    function validateResult(
        SmokeBaseSepoliaUniversalPoolArtMarketplace.SmokePlan memory plan,
        Fame fame,
        CreatorArtistMagic creatorMagic,
        UniversalPoolArtMarketplace market
    ) public view {
        if (market.paused()) revert MarketplaceNotActive();
        _checkAddress("market.fame", address(fame), address(market.fame()));
        _checkAddress("market.creatorMagic", address(creatorMagic), address(market.creatorMagic()));
        _checkAddress("direct.owner", plan.directRecipient, market.mirror().ownerAt(plan.directShell));
        _checkAddress("mint.owner", plan.mintRecipient, market.mirror().ownerAt(plan.mintShell));
        _checkAddress("burn.owner", plan.burnRecipient, market.mirror().ownerAt(plan.burnShell));
        _checkArtwork(market, plan.directShell, plan.directArtwork);
        _checkArtwork(market, plan.mintShell, plan.mintArtwork);
        _checkArtwork(market, plan.mintSource, plan.mintDisplacedArtwork);
        _checkArtwork(market, plan.burnShell, plan.burnArtwork);
        _checkArtwork(market, plan.burnSource, plan.burnDisplacedArtwork);

        uint256 inventoryAfter = market.inventory();
        if (inventoryAfter < plan.inventoryBefore) {
            revert ResultValueMismatch("inventory.minimum", plan.inventoryBefore, inventoryAfter);
        }
        uint256 expectedFeeBalance = plan.feeBalanceBefore;
        if (plan.buyer != market.feeRecipient()) {
            expectedFeeBalance += 3 * plan.premium;
        } else {
            expectedFeeBalance -= 3 * plan.unit;
        }
        if (plan.directRecipient == market.feeRecipient()) expectedFeeBalance += plan.unit;
        if (plan.mintRecipient == market.feeRecipient()) expectedFeeBalance += plan.unit;
        if (plan.burnRecipient == market.feeRecipient()) expectedFeeBalance += plan.unit;
        _checkValue("feeBalance", expectedFeeBalance, fame.balanceOf(market.feeRecipient()));
        _checkValue("allowance", 0, fame.allowance(plan.buyer, address(market)));
        uint256 buyerMirrorBalance = market.mirror().balanceOf(plan.buyer);
        if (buyerMirrorBalance < plan.minimumBuyerMirrorBalanceAfter) {
            revert ResultValueMismatch("buyerMirror.minimum", plan.minimumBuyerMirrorBalanceAfter, buyerMirrorBalance);
        }
        _checkValue("premium", plan.premium, market.premium());
    }

    function _loadPlan() internal view returns (SmokeBaseSepoliaUniversalPoolArtMarketplace.SmokePlan memory plan) {
        plan.buyer = vm.envAddress("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_SMOKE_BUYER");
        plan.directRecipient = vm.envAddress("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_SMOKE_DIRECT_RECIPIENT");
        plan.mintRecipient = vm.envAddress("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_SMOKE_MINT_RECIPIENT");
        plan.burnRecipient = vm.envAddress("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_SMOKE_BURN_RECIPIENT");
        plan.directShell = vm.envUint("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_SMOKE_DIRECT_SHELL");
        plan.mintShell = vm.envUint("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_SMOKE_MINT_SHELL");
        plan.mintSource = vm.envUint("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_SMOKE_MINT_SOURCE");
        plan.burnShell = vm.envUint("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_SMOKE_BURN_SHELL");
        plan.burnSource = vm.envUint("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_SMOKE_BURN_SOURCE");
        plan.directArtwork = vm.envBytes32("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_SMOKE_DIRECT_ARTWORK");
        plan.mintArtwork = vm.envBytes32("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_SMOKE_MINT_ARTWORK");
        plan.mintDisplacedArtwork = vm.envBytes32("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_SMOKE_MINT_DISPLACED_ARTWORK");
        plan.burnArtwork = vm.envBytes32("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_SMOKE_BURN_ARTWORK");
        plan.burnDisplacedArtwork = vm.envBytes32("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_SMOKE_BURN_DISPLACED_ARTWORK");
        plan.premium = vm.envUint("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_SMOKE_PREMIUM");
        plan.unit = vm.envUint("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_SMOKE_UNIT");
        plan.totalSpend = vm.envUint("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_SMOKE_TOTAL_SPEND");
        plan.inventoryBefore = vm.envUint("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_SMOKE_INVENTORY_BEFORE");
        plan.feeBalanceBefore = vm.envUint("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_SMOKE_FEE_BALANCE_BEFORE");
        plan.buyerMirrorBalanceBefore =
            vm.envUint("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_SMOKE_BUYER_MIRROR_BALANCE_BEFORE");
        plan.minimumBuyerMirrorBalanceAfter =
            vm.envUint("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_SMOKE_MINIMUM_BUYER_MIRROR_BALANCE_AFTER");
        plan.expectedNonce = vm.envUint("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_SMOKE_BUYER_NONCE");
    }

    function _checkAddress(string memory field, address expected, address actual) internal pure {
        if (actual != expected) {
            revert ResultAddressMismatch(field, expected, actual);
        }
    }

    function _checkValue(string memory field, uint256 expected, uint256 actual) internal pure {
        if (actual != expected) {
            revert ResultValueMismatch(field, expected, actual);
        }
    }

    function _checkArtwork(UniversalPoolArtMarketplace market, uint256 tokenId, bytes32 expected) internal view {
        bytes32 actual = market.artworkHash(tokenId);
        if (actual != expected) {
            revert ResultArtworkMismatch(tokenId, expected, actual);
        }
    }
}
