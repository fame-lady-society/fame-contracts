// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {UniversalPoolArtMarketplace} from "../src/UniversalPoolArtMarketplace.sol";
import {CreatorArtistMagic} from "../src/CreatorArtistMagic.sol";
import {Fame} from "../src/Fame.sol";
import {FameMirror} from "../src/FameMirror.sol";
import {
    ValidateBaseSepoliaUniversalPoolArtMarketplace
} from "../script/ValidateBaseSepoliaUniversalPoolArtMarketplace.s.sol";
import {ReentrantUniversalPoolMarketplaceRecipient} from "./mocks/ReentrantUniversalPoolMarketplaceRecipient.sol";

abstract contract UniversalPoolArtMarketplaceForkBaseSepoliaTestBase is Test {
    uint256 internal constant BASE_SEPOLIA_CHAIN_ID = 84532;
    uint256 internal constant CREATOR_MAGIC_BANISHER_ROLE = 1 << 2;
    uint256 internal constant CREATOR_MAGIC_CREATOR_ROLE = 1 << 1;
    uint256 internal constant CREATOR_MAGIC_ART_POOL_MANAGER_ROLE = 1 << 3;
    uint256 internal constant FAME_SKIP_MANAGER_ROLE = 1 << 3;
    uint256 internal constant SHELL_COUNT = 5;

    address internal buyer = address(0xB001);
    address internal feeRecipient;
    address internal recipient = address(0xCAFE);
    address internal forwardRecipient = address(0xF0A4);
    address internal burnHolder = address(0xB04E);
    address internal burnKeeper = address(0xB04F);

    Fame internal fame;
    FameMirror internal mirror;
    CreatorArtistMagic internal creatorMagic;
    address internal admin;

    error MissingReleaseGateInput(string name);
    error PoolCandidateUnavailable(string pool);
    error BuyerPremintCandidateUnavailable(uint256 sourceId);

    function _selectPinnedFork() internal returns (uint256 forkBlock, bytes32 forkHash) {
        string memory rpc = _requiredRpc();
        forkBlock = vm.envUint("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_PINNED_BLOCK");
        forkHash = vm.envBytes32("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_PINNED_BLOCK_HASH");
        vm.createSelectFork(rpc, forkBlock + 1);
        assertEq(block.chainid, BASE_SEPOLIA_CHAIN_ID, "wrong fork chain");
        assertEq(blockhash(forkBlock), forkHash, "pinned block hash drift");
        vm.rollFork(forkBlock);
        _loadCanonicalStack();
    }

    function _selectCurrentFork() internal returns (uint256 forkBlock, bytes32 forkHash) {
        vm.createSelectFork(_requiredRpc());
        assertEq(block.chainid, BASE_SEPOLIA_CHAIN_ID, "wrong fork chain");
        forkBlock = block.number - 1;
        forkHash = blockhash(forkBlock);
        assertNotEq(forkHash, bytes32(0), "current fork hash missing");
        vm.rollFork(forkBlock);
        _loadCanonicalStack();
    }

    function _requiredRpc() internal view returns (string memory rpc) {
        rpc = vm.envOr("BASE_SEPOLIA_RPC", string(""));
        if (bytes(rpc).length == 0) revert MissingReleaseGateInput("BASE_SEPOLIA_RPC");
    }

    function _loadCanonicalStack() internal {
        fame = Fame(payable(vm.envAddress("BASE_SEPOLIA_FAME_ADDRESS")));
        mirror = FameMirror(payable(vm.envAddress("BASE_SEPOLIA_FAME_NFT_ADDRESS")));
        creatorMagic = CreatorArtistMagic(vm.envAddress("BASE_SEPOLIA_CREATOR_ARTIST_MAGIC_ADDRESS"));
        admin = vm.envAddress("BASE_SEPOLIA_FAME_EXPECTED_ADMIN");
        feeRecipient = vm.envAddress("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_FEE_RECIPIENT");

        assertEq(address(fame.fameMirror()), address(mirror), "mirror drift");
        assertEq(address(fame.renderer()), address(creatorMagic), "renderer drift");
        assertEq(address(creatorMagic.fame()), address(fame), "CreatorMagic FAME drift");
        assertEq(fame.name(), "Example", "TEST name drift");
        assertEq(fame.symbol(), "TEST", "TEST symbol drift");
        assertEq(fame.unit(), 1_000_000 ether, "TEST unit drift");
    }

    function _deployEphemeralMarket() internal returns (UniversalPoolArtMarketplace market) {
        uint256 premium = vm.envUint("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_PREMIUM");

        vm.prank(feeRecipient);
        fame.setSkipNFT(true);

        vm.startPrank(admin, admin);
        market = new UniversalPoolArtMarketplace(
            payable(address(fame)), address(creatorMagic), premium, feeRecipient, admin
        );
        creatorMagic.grantRoles(address(market), CREATOR_MAGIC_BANISHER_ROLE);
        fame.transfer(address(market), SHELL_COUNT * fame.unit());
        vm.stopPrank();

        new ValidateBaseSepoliaUniversalPoolArtMarketplace()
            .validateMarketplace(fame, mirror, creatorMagic, market, admin, feeRecipient, premium, SHELL_COUNT, true);

        assertTrue(creatorMagic.hasAnyRole(address(market), CREATOR_MAGIC_BANISHER_ROLE));
        assertFalse(creatorMagic.hasAnyRole(address(market), CREATOR_MAGIC_CREATOR_ROLE));
        assertFalse(creatorMagic.hasAnyRole(address(market), CREATOR_MAGIC_ART_POOL_MANAGER_ROLE));
        assertFalse(fame.hasAnyRole(address(market), FAME_SKIP_MANAGER_ROLE));
        assertFalse(fame.getSkipNFT(address(market)));
    }

    function _fundBuyer(UniversalPoolArtMarketplace market, uint256 purchases) internal {
        uint256 total = fame.unit() + market.premium();
        vm.prank(buyer);
        fame.setSkipNFT(true);
        vm.prank(admin);
        fame.transfer(buyer, purchases * total);
        vm.prank(buyer);
        fame.approve(address(market), purchases * total);
    }

    function _createBurnCandidate() internal returns (uint256 sourceId) {
        uint256 unit = fame.unit();
        vm.prank(admin);
        fame.transfer(burnHolder, unit);
        sourceId = _ownedTokenAt(burnHolder, 0);
        vm.prank(admin);
        fame.transfer(burnKeeper, unit);
        vm.prank(burnHolder);
        fame.transfer(feeRecipient, unit);
        assertTrue(creatorMagic.isTokenInBurnedPool(sourceId), "burn source was not created");
    }

    function _exerciseAllPaths(UniversalPoolArtMarketplace market) internal {
        uint256 burnSource = _createBurnCandidate();
        _fundBuyer(market, 5);

        vm.prank(admin);
        market.unpause();

        uint256 inventoryFloor = market.inventory();
        _purchasePool(market, _ownedTokenAt(address(market), 0), burnSource, recipient);
        assertGe(market.inventory(), inventoryFloor, "Burn purchase reduced inventory");

        uint256 mintSource = _findMintPoolToken();
        _purchasePool(market, _ownedTokenAt(address(market), 0), mintSource, recipient);
        assertGe(market.inventory(), inventoryFloor, "Mint purchase reduced inventory");

        uint256 heldShell = _ownedTokenAt(address(market), 0);
        bytes32 heldArtwork = market.artworkHash(heldShell);
        uint256 maxPremium = market.premium();
        vm.prank(buyer);
        market.purchaseHeld(heldShell, heldArtwork, maxPremium, 0, recipient);
        assertEq(mirror.ownerAt(heldShell), recipient, "held recipient mismatch");
        assertEq(market.artworkHash(heldShell), heldArtwork, "held artwork mismatch");
        assertGe(market.inventory(), inventoryFloor, "held purchase reduced inventory");
    }

    function _exerciseAdversarialEdges(UniversalPoolArtMarketplace market) internal {
        uint256 inventoryFloor = market.inventory();
        uint256 shellId = _ownedTokenAt(address(market), 0);
        bytes32 shellArtwork = market.artworkHash(shellId);
        uint256 maxPremium = market.premium();

        vm.prank(feeRecipient);
        fame.setSkipNFT(false);
        vm.expectRevert(
            abi.encodeWithSelector(UniversalPoolArtMarketplace.FeeRecipientNotSkippingNFT.selector, feeRecipient)
        );
        vm.prank(buyer);
        market.purchaseHeld(shellId, shellArtwork, maxPremium, 0, recipient);
        vm.prank(feeRecipient);
        fame.setSkipNFT(true);

        uint256 artPoolSource = creatorMagic.artPoolStartIndex();
        bytes32 artPoolArtwork = market.artworkHash(artPoolSource);
        vm.expectRevert(
            abi.encodeWithSelector(UniversalPoolArtMarketplace.ArtPoolSourceExcluded.selector, artPoolSource)
        );
        vm.prank(buyer);
        market.purchasePool(shellId, artPoolSource, artPoolArtwork, maxPremium, 0, recipient);

        ReentrantUniversalPoolMarketplaceRecipient forwarding = new ReentrantUniversalPoolMarketplaceRecipient();
        forwarding.configure(
            market, ReentrantUniversalPoolMarketplaceRecipient.Action.Forward, forwardRecipient, shellArtwork
        );
        vm.prank(buyer);
        market.purchaseHeld(shellId, shellArtwork, maxPremium, 0, address(forwarding));
        assertEq(forwarding.observedArtworkHash(), shellArtwork, "callback observed wrong art");
        assertEq(mirror.ownerAt(shellId), forwardRecipient, "callback forwarding failed");

        uint256 reentryShell = _ownedTokenAt(address(market), 0);
        bytes32 reentryArtwork = market.artworkHash(reentryShell);
        ReentrantUniversalPoolMarketplaceRecipient reentrant = new ReentrantUniversalPoolMarketplaceRecipient();
        reentrant.configure(
            market, ReentrantUniversalPoolMarketplaceRecipient.Action.ReenterPurchase, recipient, reentryArtwork
        );
        vm.prank(buyer);
        market.purchaseHeld(reentryShell, reentryArtwork, maxPremium, 0, address(reentrant));
        assertFalse(reentrant.attemptedActionSucceeded(), "callback reentry succeeded");
        assertGt(reentrant.attemptedActionRevertData().length, 0, "callback reentry had no revert");
        assertGe(market.inventory(), inventoryFloor, "callback paths reduced inventory");
    }

    function _exerciseBuyerPremintHandling(UniversalPoolArtMarketplace market) internal {
        uint256 sourceId = _findMintPoolToken();
        address premintBuyer = address(0xA11CE);
        uint256 attempts;

        vm.prank(premintBuyer);
        fame.setSkipNFT(false);
        uint256 unit = fame.unit();
        while (mirror.ownerAt(sourceId) != premintBuyer && attempts < 888) {
            vm.prank(admin);
            fame.transfer(premintBuyer, unit);
            ++attempts;
        }
        if (mirror.ownerAt(sourceId) != premintBuyer) {
            revert BuyerPremintCandidateUnavailable(sourceId);
        }

        assertFalse(creatorMagic.isTokenInMintPool(sourceId), "owned art remained in Mint pool");
        assertFalse(creatorMagic.isTokenInBurnedPool(sourceId), "owned art entered Burn pool");

        uint256 shellId = _ownedTokenAt(address(market), 0);
        bytes32 expectedArtwork = market.artworkHash(sourceId);
        uint256 maxPremium = market.premium();
        vm.expectRevert(abi.encodeWithSelector(UniversalPoolArtMarketplace.IneligiblePoolSource.selector, sourceId));
        vm.prank(buyer);
        market.purchasePool(shellId, sourceId, expectedArtwork, maxPremium, 0, recipient);
    }

    function _purchasePool(
        UniversalPoolArtMarketplace market,
        uint256 shellId,
        uint256 sourceId,
        address purchaseRecipient
    ) internal {
        bytes32 expectedArtwork = market.artworkHash(sourceId);
        uint256 inventoryBefore = market.inventory();
        uint256 maxPremium = market.premium();
        vm.prank(buyer);
        (uint256 reportedBefore, uint256 reportedAfter) =
            market.purchasePool(shellId, sourceId, expectedArtwork, maxPremium, 0, purchaseRecipient);
        assertEq(reportedBefore, inventoryBefore, "reported inventory before mismatch");
        assertGe(reportedAfter, inventoryBefore, "reported inventory decreased");
        assertEq(mirror.ownerAt(shellId), purchaseRecipient, "pool recipient mismatch");
        assertEq(market.artworkHash(shellId), expectedArtwork, "pool artwork mismatch");
    }

    function _findMintPoolToken() internal view returns (uint256) {
        uint256 end = creatorMagic.getMintPoolEnd();
        for (uint256 tokenId = creatorMagic.getMintPoolStart(); tokenId < end; ++tokenId) {
            if (creatorMagic.isTokenInMintPool(tokenId)) return tokenId;
        }
        revert PoolCandidateUnavailable("Mint");
    }

    function _ownedTokenAt(address account, uint256 index) internal view returns (uint256) {
        uint256 seen;
        for (uint256 tokenId = 1; tokenId <= 888; ++tokenId) {
            if (mirror.ownerAt(tokenId) == account) {
                if (seen == index) return tokenId;
                ++seen;
            }
        }
        revert PoolCandidateUnavailable("owned shell");
    }

    function _logCampaign(string memory name, uint256 forkBlock, bytes32 forkHash) internal {
        emit log_named_string("campaign", name);
        emit log_named_uint("fork block", forkBlock);
        emit log_named_bytes32("fork hash", forkHash);
    }
}

contract UniversalPoolArtMarketplacePinnedForkBaseSepoliaTest is UniversalPoolArtMarketplaceForkBaseSepoliaTestBase {
    function testPinnedForkCampaign() public {
        (uint256 forkBlock, bytes32 forkHash) = _selectPinnedFork();
        _logCampaign("pinned", forkBlock, forkHash);

        UniversalPoolArtMarketplace market = _deployEphemeralMarket();
        _exerciseAllPaths(market);
        _exerciseAdversarialEdges(market);
        _exerciseBuyerPremintHandling(market);
    }
}

contract UniversalPoolArtMarketplaceCurrentHeadForkBaseSepoliaTest is
    UniversalPoolArtMarketplaceForkBaseSepoliaTestBase
{
    function testCurrentHeadForkCampaign() public {
        (uint256 forkBlock, bytes32 forkHash) = _selectCurrentFork();
        _logCampaign("current-head", forkBlock, forkHash);

        UniversalPoolArtMarketplace market = _deployEphemeralMarket();
        _exerciseAllPaths(market);
    }
}

contract UniversalPoolArtMarketplaceDeployedForkBaseSepoliaTest is UniversalPoolArtMarketplaceForkBaseSepoliaTestBase {
    function testStrictDeployedAddressFork() public {
        address marketAddress = vm.envOr("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_ADDRESS", address(0));
        if (marketAddress == address(0)) {
            if (vm.envOr("BASE_SEPOLIA_REQUIRE_UNIVERSAL_MARKETPLACE_DEPLOYED", false)) {
                revert MissingReleaseGateInput("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_ADDRESS");
            }
            vm.skip(true);
            return;
        }

        _selectCurrentFork();
        _validateDeployed(UniversalPoolArtMarketplace(marketAddress), true);
    }

    function testPostActivationFork() public {
        address marketAddress = vm.envOr("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_ADDRESS", address(0));
        if (marketAddress == address(0)) {
            if (vm.envOr("BASE_SEPOLIA_REQUIRE_UNIVERSAL_MARKETPLACE_ACTIVATED", false)) {
                revert MissingReleaseGateInput("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_ADDRESS");
            }
            vm.skip(true);
            return;
        }

        _selectCurrentFork();
        _validateDeployed(UniversalPoolArtMarketplace(marketAddress), false);
    }

    function _validateDeployed(UniversalPoolArtMarketplace market, bool expectedPaused) internal {
        new ValidateBaseSepoliaUniversalPoolArtMarketplace()
            .validateMarketplace(
                fame,
                mirror,
                creatorMagic,
                market,
                vm.envAddress("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_OWNER"),
                vm.envAddress("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_FEE_RECIPIENT"),
                vm.envUint("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_PREMIUM"),
                vm.envUint("BASE_SEPOLIA_UNIVERSAL_MARKETPLACE_MINIMUM_INVENTORY"),
                expectedPaused
            );
    }
}
