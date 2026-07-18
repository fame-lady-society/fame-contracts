// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {UniversalPoolArtMarketplace} from "../src/UniversalPoolArtMarketplace.sol";
import {CreatorArtistMagic} from "../src/CreatorArtistMagic.sol";
import {Fame} from "../src/Fame.sol";
import {FameMirror} from "../src/FameMirror.sol";
import {ValidateBaseSepoliaUniversalPoolArtMarketplace} from "./ValidateBaseSepoliaUniversalPoolArtMarketplace.s.sol";

contract SmokeBaseSepoliaUniversalPoolArtMarketplace is Script {
    uint256 internal constant BASE_SEPOLIA_CHAIN_ID = 84532;

    struct SmokePlan {
        address buyer;
        address directRecipient;
        address mintRecipient;
        address burnRecipient;
        uint256 directShell;
        uint256 mintShell;
        uint256 mintSource;
        uint256 burnShell;
        uint256 burnSource;
        bytes32 directArtwork;
        bytes32 mintArtwork;
        bytes32 mintDisplacedArtwork;
        bytes32 burnArtwork;
        bytes32 burnDisplacedArtwork;
        uint256 premium;
        uint256 unit;
        uint256 totalSpend;
        uint256 inventoryBefore;
        uint256 feeBalanceBefore;
        uint256 buyerMirrorBalanceBefore;
        uint256 minimumBuyerMirrorBalanceAfter;
        uint256 expectedNonce;
    }

    error ChainIdMismatch(uint256 expected, uint256 actual);
    error SmokeNotConfirmed();
    error UnexpectedSigner(address expected, address actual);
    error BuyerNonceMismatch(uint256 expected, uint256 actual);
    error SmokePlanCommitmentMismatch(bytes32 expected, bytes32 actual);
    error MarketplaceNotActive();
    error InvalidSmokeRecipient(address recipient);
    error InvalidSmokeTokenIds();
    error SmokeValueMismatch(string field, uint256 expected, uint256 actual);
    error SmokeAddressMismatch(string field, address expected, address actual);
    error SmokeArtworkMismatch(uint256 tokenId, bytes32 expected, bytes32 actual);
    error SmokeSourceIneligible(uint256 tokenId);
    error InsufficientSmokeBalance(uint256 required, uint256 available);

    function run() external {
        if (block.chainid != BASE_SEPOLIA_CHAIN_ID) {
            revert ChainIdMismatch(BASE_SEPOLIA_CHAIN_ID, block.chainid);
        }
        if (!vm.envOr("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_SMOKE_CONFIRMED", false)) {
            revert SmokeNotConfirmed();
        }

        Fame fame = Fame(payable(vm.envAddress("BASE_SEPOLIA_FAME_ADDRESS")));
        FameMirror mirror = FameMirror(payable(vm.envAddress("BASE_SEPOLIA_FAME_NFT_ADDRESS")));
        CreatorArtistMagic creatorMagic = CreatorArtistMagic(vm.envAddress("BASE_SEPOLIA_CREATOR_ARTIST_MAGIC_ADDRESS"));
        UniversalPoolArtMarketplace market =
            UniversalPoolArtMarketplace(vm.envAddress("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_ADDRESS"));
        new ValidateBaseSepoliaUniversalPoolArtMarketplace().validateCanonicalAddresses(fame, mirror);

        uint256 privateKey = vm.envUint("UNIVERSAL_MARKETPLACE_SMOKE_BUYER_PRIVATE_KEY");
        address signer = vm.addr(privateKey);
        SmokePlan memory plan = _loadPlan();
        bytes32 expectedCommitment = vm.envBytes32("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_SMOKE_PLAN_HASH");
        uint256 actualNonce = vm.getNonce(signer);
        validateAuthorization(plan, signer, actualNonce, expectedCommitment);

        preflight(plan, fame, creatorMagic, market);
        vm.startBroadcast(privateKey);
        _executePrepared(plan, fame, market);
        vm.stopBroadcast();
    }

    function execute(
        SmokePlan memory plan,
        Fame fame,
        CreatorArtistMagic creatorMagic,
        UniversalPoolArtMarketplace market
    ) public {
        if (plan.buyer != address(this)) {
            revert UnexpectedSigner(plan.buyer, address(this));
        }
        preflight(plan, fame, creatorMagic, market);
        _executePrepared(plan, fame, market);
    }

    function preflight(
        SmokePlan memory plan,
        Fame fame,
        CreatorArtistMagic creatorMagic,
        UniversalPoolArtMarketplace market
    ) public view {
        if (market.paused()) revert MarketplaceNotActive();
        _checkAddress("market.fame", address(fame), address(market.fame()));
        _checkAddress("market.creatorMagic", address(creatorMagic), address(market.creatorMagic()));
        _checkAddress("market.mirror", address(fame.fameMirror()), address(market.mirror()));

        _requireRecipient(plan.directRecipient, market);
        _requireRecipient(plan.mintRecipient, market);
        _requireRecipient(plan.burnRecipient, market);
        if (
            plan.directShell == plan.mintShell || plan.directShell == plan.burnShell || plan.mintShell == plan.burnShell
                || plan.mintSource == plan.burnSource || plan.mintSource == plan.mintShell
                || plan.burnSource == plan.burnShell
        ) {
            revert InvalidSmokeTokenIds();
        }

        _checkValue("unit", plan.unit, fame.unit());
        _checkValue("premium", plan.premium, market.premium());
        uint256 expectedSpend = 3 * plan.unit;
        if (plan.buyer != market.feeRecipient()) expectedSpend += 3 * plan.premium;
        _checkValue("totalSpend", plan.totalSpend, expectedSpend);
        _checkValue("inventoryBefore", plan.inventoryBefore, market.inventory());
        _checkValue("feeBalanceBefore", plan.feeBalanceBefore, fame.balanceOf(market.feeRecipient()));
        _checkValue("buyerMirrorBalanceBefore", plan.buyerMirrorBalanceBefore, fame.fameMirror().balanceOf(plan.buyer));
        uint256 buyerBalance = fame.balanceOf(plan.buyer);
        if (buyerBalance < plan.totalSpend) {
            revert InsufficientSmokeBalance(plan.totalSpend, buyerBalance);
        }

        _requireShellAndArtwork(market, plan.directShell, plan.directArtwork);
        _requireShellAndArtwork(market, plan.mintShell, bytes32(0));
        _requireShellAndArtwork(market, plan.burnShell, bytes32(0));
        _requireArtwork(market, plan.mintSource, plan.mintArtwork);
        _requireArtwork(market, plan.mintShell, plan.mintDisplacedArtwork);
        _requireArtwork(market, plan.burnSource, plan.burnArtwork);
        _requireArtwork(market, plan.burnShell, plan.burnDisplacedArtwork);

        if (!creatorMagic.isTokenInMintPool(plan.mintSource)) {
            revert SmokeSourceIneligible(plan.mintSource);
        }
        if (!creatorMagic.isTokenInBurnedPool(plan.burnSource)) {
            revert SmokeSourceIneligible(plan.burnSource);
        }
    }

    function hashPlan(SmokePlan memory plan) public pure returns (bytes32) {
        return keccak256(abi.encode(plan));
    }

    function validateAuthorization(
        SmokePlan memory plan,
        address signer,
        uint256 actualNonce,
        bytes32 expectedCommitment
    ) public pure {
        if (signer != plan.buyer) {
            revert UnexpectedSigner(plan.buyer, signer);
        }
        if (actualNonce != plan.expectedNonce) {
            revert BuyerNonceMismatch(plan.expectedNonce, actualNonce);
        }
        bytes32 actualCommitment = hashPlan(plan);
        if (actualCommitment != expectedCommitment) {
            revert SmokePlanCommitmentMismatch(expectedCommitment, actualCommitment);
        }
    }

    function _executePrepared(SmokePlan memory plan, Fame fame, UniversalPoolArtMarketplace market) internal {
        fame.approve(address(market), plan.totalSpend);
        market.purchasePool(
            plan.burnShell,
            plan.burnSource,
            plan.burnArtwork,
            plan.premium,
            plan.minimumBuyerMirrorBalanceAfter,
            plan.burnRecipient
        );
        market.purchasePool(
            plan.mintShell,
            plan.mintSource,
            plan.mintArtwork,
            plan.premium,
            plan.minimumBuyerMirrorBalanceAfter,
            plan.mintRecipient
        );
        market.purchaseHeld(
            plan.directShell,
            plan.directArtwork,
            plan.premium,
            plan.minimumBuyerMirrorBalanceAfter,
            plan.directRecipient
        );
    }

    function _loadPlan() internal view returns (SmokePlan memory plan) {
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

    function _requireRecipient(address recipient, UniversalPoolArtMarketplace market) internal view {
        if (recipient == address(0) || recipient == address(market) || recipient.code.length != 0) {
            revert InvalidSmokeRecipient(recipient);
        }
    }

    function _requireShellAndArtwork(UniversalPoolArtMarketplace market, uint256 tokenId, bytes32 expectedArtwork)
        internal
        view
    {
        address owner = market.mirror().ownerAt(tokenId);
        if (owner != address(market)) {
            revert SmokeAddressMismatch("shell.owner", address(market), owner);
        }
        if (expectedArtwork != bytes32(0)) {
            _requireArtwork(market, tokenId, expectedArtwork);
        }
    }

    function _requireArtwork(UniversalPoolArtMarketplace market, uint256 tokenId, bytes32 expectedArtwork)
        internal
        view
    {
        bytes32 actualArtwork = market.artworkHash(tokenId);
        if (actualArtwork != expectedArtwork) {
            revert SmokeArtworkMismatch(tokenId, expectedArtwork, actualArtwork);
        }
    }

    function _checkAddress(string memory field, address expected, address actual) internal pure {
        if (actual != expected) {
            revert SmokeAddressMismatch(field, expected, actual);
        }
    }

    function _checkValue(string memory field, uint256 expected, uint256 actual) internal pure {
        if (actual != expected) {
            revert SmokeValueMismatch(field, expected, actual);
        }
    }
}
