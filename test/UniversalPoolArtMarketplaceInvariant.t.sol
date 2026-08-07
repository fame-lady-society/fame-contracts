// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test} from "forge-std/Test.sol";
import {IERC721Receiver} from "@openzeppelin5/contracts/token/ERC721/IERC721Receiver.sol";
import {UniversalPoolArtMarketplace} from "../src/UniversalPoolArtMarketplace.sol";
import {CreatorArtistMagic} from "../src/CreatorArtistMagic.sol";
import {Fame} from "../src/Fame.sol";
import {FameMirror} from "../src/FameMirror.sol";
import {UniversalPoolArtMarketplaceTestBase} from "./helpers/UniversalPoolArtMarketplaceTestBase.sol";
import {ReentrantUniversalPoolMarketplaceRecipient} from "./mocks/ReentrantUniversalPoolMarketplaceRecipient.sol";

contract UniversalPoolArtMarketplaceHandler is Test, IERC721Receiver {
    struct FailureCase {
        address buyer;
        uint256 shellId;
        bytes32 artwork;
        uint256 premium;
        uint256 payerFame;
        uint256 feeFame;
        uint256 marketFame;
        uint256 inventory;
        address shellOwner;
    }

    struct PurchaseCase {
        address buyer;
        address destination;
        uint256 shellId;
        uint256 sourceId;
        uint256 premium;
        uint256 minimum;
        bytes32 artwork;
        bytes32 displacedArtwork;
    }

    Fame public immutable fame;
    FameMirror public immutable mirror;
    CreatorArtistMagic public immutable creatorMagic;
    UniversalPoolArtMarketplace public immutable market;
    ReentrantUniversalPoolMarketplaceRecipient public immutable forwardingRecipient;
    uint256 public immutable initialInventory;
    uint256 public immutable initialMarketFame;
    uint256 public immutable campaignInventoryFloor;
    uint256 public immutable campaignFameFloor;

    address[3] internal _buyers;
    address[2] internal _feeRecipients;
    address[4] internal _providers;

    uint256 public fundingSuccesses;
    uint256 public directSuccesses;
    uint256 public mintSuccesses;
    uint256 public burnSuccesses;
    uint256 public forwardingSuccesses;
    uint256 public adminSuccesses;
    uint256 public expectedFailures;
    uint256 public poolPlacementChecks;
    uint256 public callbackChecks;
    uint256 public buyerMinimumChecks;
    uint256 public handoffChecks;
    uint256 public providerDeposits;
    uint256 public providerBatchDeposits;
    uint256 public withdrawals;
    uint256 public minimumObservedInventory;

    constructor(
        Fame fame_,
        FameMirror mirror_,
        CreatorArtistMagic creatorMagic_,
        UniversalPoolArtMarketplace market_,
        address[3] memory buyers_,
        address[2] memory feeRecipients_
    ) {
        fame = fame_;
        mirror = mirror_;
        creatorMagic = creatorMagic_;
        market = market_;
        _buyers = buyers_;
        _feeRecipients = feeRecipients_;
        _providers = [address(0xC001), address(0xC002), address(0xC003), address(0xC004)];
        forwardingRecipient = new ReentrantUniversalPoolMarketplaceRecipient();
        initialInventory = mirror_.balanceOf(address(market_));
        initialMarketFame = fame_.balanceOf(address(market_));
        campaignInventoryFloor = initialInventory - market_.totalProviderUnits();
        campaignFameFloor = initialMarketFame - market_.totalProviderUnits() * fame_.unit();
        minimumObservedInventory = initialInventory;

        for (uint256 i; i < buyers_.length; ++i) {
            vm.prank(buyers_[i]);
            fame_.setSkipNFT(true);
            vm.prank(buyers_[i]);
            fame_.approve(address(market_), type(uint256).max);
        }
    }

    function fundBuyer(uint256 buyerSeed, uint96 amountSeed) external {
        address selectedBuyer = _buyer(buyerSeed);
        uint256 amount = 1 + (uint256(amountSeed) % (fame.unit() * 4));
        if (fame.balanceOf(address(this)) < amount) return;
        fame.transfer(selectedBuyer, amount);
        ++fundingSuccesses;
    }

    function purchaseHeld(uint256 buyerSeed, uint256 shellSeed, bool selfRecipient, bool useMinimum) external {
        PurchaseCase memory purchase;
        purchase.buyer = _buyer(buyerSeed);
        purchase.destination = selfRecipient ? purchase.buyer : _nextBuyer(buyerSeed);
        purchase.shellId = _marketShell(shellSeed);
        purchase.artwork = market.artworkHash(purchase.shellId);
        purchase.premium = market.premium();
        _preparePurchase(purchase.buyer, purchase.premium);
        purchase.minimum = useMinimum && selfRecipient ? 1 : 0;

        uint256 inventoryBefore = market.inventory();
        uint256 marketFameBefore = fame.balanceOf(address(market));
        uint256 payoutRecipientsBefore = _payoutRecipientBalances();
        vm.prank(purchase.buyer);
        (, uint256 inventoryAfter) = market.purchaseHeld(
            purchase.shellId, purchase.artwork, purchase.premium, purchase.minimum, purchase.destination
        );
        _checkSuccessfulPurchase(purchase, inventoryBefore, inventoryAfter, marketFameBefore, payoutRecipientsBefore);
        ++directSuccesses;
    }

    function purchaseMint(uint256 buyerSeed, uint256 shellSeed, uint256 sourceSeed, bool selfRecipient) external {
        PurchaseCase memory purchase;
        purchase.buyer = _buyer(buyerSeed);
        purchase.destination = selfRecipient ? purchase.buyer : _nextBuyer(buyerSeed);
        purchase.shellId = _marketShell(shellSeed);
        purchase.sourceId = _mintSource(sourceSeed);
        purchase.artwork = market.artworkHash(purchase.sourceId);
        purchase.displacedArtwork = market.artworkHash(purchase.shellId);
        purchase.premium = market.premium();
        _preparePurchase(purchase.buyer, purchase.premium);

        uint256 inventoryBefore = market.inventory();
        uint256 marketFameBefore = fame.balanceOf(address(market));
        uint256 payoutRecipientsBefore = _payoutRecipientBalances();
        vm.prank(purchase.buyer);
        (, uint256 inventoryAfter) = market.purchasePool(
            purchase.shellId, purchase.sourceId, purchase.artwork, purchase.premium, 0, purchase.destination
        );

        assertEq(market.artworkHash(purchase.sourceId), purchase.displacedArtwork);
        ++poolPlacementChecks;
        _checkSuccessfulPurchase(purchase, inventoryBefore, inventoryAfter, marketFameBefore, payoutRecipientsBefore);
        ++mintSuccesses;
    }

    function purchaseBurn(uint256 buyerSeed, uint256 shellSeed, bool selfRecipient) external {
        PurchaseCase memory purchase;
        purchase.buyer = _buyer(buyerSeed);
        purchase.destination = selfRecipient ? purchase.buyer : _nextBuyer(buyerSeed);
        purchase.shellId = _marketShell(shellSeed);
        purchase.sourceId = _burnSource();
        purchase.artwork = market.artworkHash(purchase.sourceId);
        purchase.displacedArtwork = market.artworkHash(purchase.shellId);
        purchase.premium = market.premium();
        _preparePurchase(purchase.buyer, purchase.premium);

        uint256 inventoryBefore = market.inventory();
        uint256 marketFameBefore = fame.balanceOf(address(market));
        uint256 payoutRecipientsBefore = _payoutRecipientBalances();
        vm.prank(purchase.buyer);
        (, uint256 inventoryAfter) = market.purchasePool(
            purchase.shellId, purchase.sourceId, purchase.artwork, purchase.premium, 0, purchase.destination
        );

        assertEq(market.artworkHash(purchase.sourceId), purchase.displacedArtwork);
        ++poolPlacementChecks;
        _checkSuccessfulPurchase(purchase, inventoryBefore, inventoryAfter, marketFameBefore, payoutRecipientsBefore);
        ++burnSuccesses;
    }

    function purchaseAndForward(uint256 buyerSeed, uint256 shellSeed) external {
        PurchaseCase memory purchase;
        purchase.buyer = _buyer(buyerSeed);
        purchase.destination = _nextBuyer(buyerSeed);
        purchase.shellId = _marketShell(shellSeed);
        purchase.artwork = market.artworkHash(purchase.shellId);
        purchase.premium = market.premium();
        _preparePurchase(purchase.buyer, purchase.premium);
        forwardingRecipient.configure(
            market, ReentrantUniversalPoolMarketplaceRecipient.Action.Forward, purchase.destination, purchase.artwork
        );

        uint256 inventoryBefore = market.inventory();
        uint256 marketFameBefore = fame.balanceOf(address(market));
        uint256 payoutRecipientsBefore = _payoutRecipientBalances();
        vm.prank(purchase.buyer);
        (, uint256 inventoryAfter) =
            market.purchaseHeld(purchase.shellId, purchase.artwork, purchase.premium, 0, address(forwardingRecipient));

        assertEq(forwardingRecipient.observedTokenId(), purchase.shellId);
        assertEq(forwardingRecipient.observedArtworkHash(), purchase.artwork);
        ++callbackChecks;
        _checkSuccessfulPurchase(purchase, inventoryBefore, inventoryAfter, marketFameBefore, payoutRecipientsBefore);
        ++forwardingSuccesses;
    }

    function configureMarket(uint96 premiumSeed, uint256 feeSeed, bool shouldPause) external {
        uint256 nextPremium = uint256(premiumSeed) % (fame.unit() / 10 + 1);
        market.setCommunityFee(nextPremium);
        market.setProviderFee(uint256(keccak256(abi.encode(premiumSeed))) % (fame.unit() / 10 + 1));
        address nextFeeRecipient = _feeRecipients[feeSeed % _feeRecipients.length];
        if (market.feeRecipient() != nextFeeRecipient) market.setFeeRecipient(nextFeeRecipient);
        if (shouldPause && !market.paused()) {
            market.pause();
        } else if (!shouldPause && market.paused()) {
            market.unpause();
        }
        ++adminSuccesses;
    }

    function depositProvider(uint256 providerSeed) external {
        address provider = _provider(providerSeed);
        uint256 tokenId = _firstOwnedToken(provider);
        if (tokenId == 0) {
            uint256 unit = fame.unit();
            if (fame.balanceOf(address(this)) < unit) return;
            fame.transfer(provider, unit);
            tokenId = _firstOwnedToken(provider);
            if (tokenId == 0) return;
        }

        vm.startPrank(provider);
        mirror.approve(address(market), tokenId);
        market.depositInventory(tokenId);
        vm.stopPrank();
        ++providerDeposits;
    }

    function depositProviderBatch(uint256 providerSeed, uint8 batchSeed) external {
        address provider = _provider(providerSeed);
        uint256 count = 1 + (uint256(batchSeed) % market.MAX_INVENTORY_BATCH_SIZE());
        uint256 owned = mirror.balanceOf(provider);
        if (owned < count) {
            uint256 funding = (count - owned) * fame.unit();
            if (fame.balanceOf(address(this)) < funding) return;
            fame.transfer(provider, funding);
        }

        uint256[] memory tokenIds = new uint256[](count);
        uint256 found;
        for (uint256 tokenId = 1; tokenId <= 888 && found < count; ++tokenId) {
            if (mirror.ownerAt(tokenId) == provider) tokenIds[found++] = tokenId;
        }
        if (found != count) return;

        vm.startPrank(provider);
        mirror.setApprovalForAll(address(market), true);
        market.depositInventoryBatch(tokenIds);
        vm.stopPrank();
        providerDeposits += count;
        ++providerBatchDeposits;
    }

    function withdrawProvider(uint256 providerSeed, uint256 tokenSeed) external {
        address provider = _provider(providerSeed);
        (uint256 units,) = market.providerPosition(provider);
        if (units == 0) return;

        uint256 grossPremiumAmount = market.withdrawalPremium(provider);
        uint256 balance = fame.balanceOf(provider);
        if (balance < grossPremiumAmount) {
            uint256 shortfall = grossPremiumAmount - balance;
            if (fame.balanceOf(address(this)) < shortfall) return;
            fame.transfer(provider, shortfall);
        }
        uint256 tokenId = _marketShell(tokenSeed);
        vm.startPrank(provider);
        fame.approve(address(market), grossPremiumAmount);
        market.withdrawInventory(tokenId, grossPremiumAmount);
        vm.stopPrank();
        _observeInventory();
        ++withdrawals;
    }

    function attemptInvalidPurchase(uint256 buyerSeed, uint256 shellSeed, uint8 failureSeed) external {
        FailureCase memory failure;
        failure.buyer = _buyer(buyerSeed);
        failure.shellId = _marketShell(shellSeed);
        failure.artwork = market.artworkHash(failure.shellId);
        failure.premium = market.premium();
        _preparePurchase(failure.buyer, failure.premium);
        failure.payerFame = fame.balanceOf(failure.buyer);
        failure.feeFame = fame.balanceOf(market.feeRecipient());
        failure.marketFame = fame.balanceOf(address(market));
        failure.inventory = market.inventory();
        failure.shellOwner = mirror.ownerAt(failure.shellId);
        bool reverted;

        uint256 failureKind = failureSeed % 4;
        if (failureKind == 0) {
            vm.prank(failure.buyer);
            try market.purchaseHeld(
                failure.shellId, failure.artwork ^ bytes32(uint256(1)), failure.premium, 0, failure.buyer
            ) {}
            catch {
                reverted = true;
            }
        } else if (failureKind == 1) {
            vm.prank(failure.buyer);
            try market.purchaseHeld(
                failure.shellId,
                failure.premium == 0 ? failure.artwork ^ bytes32(uint256(1)) : failure.artwork,
                failure.premium == 0 ? 0 : failure.premium - 1,
                0,
                failure.buyer
            ) {}
            catch {
                reverted = true;
            }
        } else if (failureKind == 2) {
            uint256 artPoolSource = creatorMagic.artPoolStartIndex();
            bytes32 artPoolArtwork = market.artworkHash(artPoolSource);
            vm.prank(failure.buyer);
            try market.purchasePool(
                failure.shellId, artPoolSource, artPoolArtwork, failure.premium, 0, failure.buyer
            ) {}
            catch {
                reverted = true;
            }
        } else {
            vm.prank(failure.buyer);
            try market.purchaseHeld(
                failure.shellId, failure.artwork, failure.premium, type(uint256).max, _nextBuyer(buyerSeed)
            ) {}
            catch {
                reverted = true;
            }
        }

        assertTrue(reverted);
        assertEq(fame.balanceOf(failure.buyer), failure.payerFame);
        assertEq(fame.balanceOf(market.feeRecipient()), failure.feeFame);
        assertEq(fame.balanceOf(address(market)), failure.marketFame);
        assertEq(market.inventory(), failure.inventory);
        assertEq(mirror.ownerAt(failure.shellId), failure.shellOwner);
        assertEq(market.artworkHash(failure.shellId), failure.artwork);
        ++expectedFailures;
    }

    function buyerAt(uint256 index) external view returns (address) {
        return _buyers[index % _buyers.length];
    }

    function feeRecipientAt(uint256 index) external view returns (address) {
        return _feeRecipients[index % _feeRecipients.length];
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function _preparePurchase(address selectedBuyer, uint256 currentPremium) internal {
        if (market.paused()) market.unpause();
        uint256 requiredBalance = fame.unit() + currentPremium;
        uint256 currentBalance = fame.balanceOf(selectedBuyer);
        if (currentBalance < requiredBalance) {
            fame.transfer(selectedBuyer, requiredBalance - currentBalance);
        }
    }

    function _checkSuccessfulPurchase(
        PurchaseCase memory purchase,
        uint256 inventoryBefore,
        uint256 inventoryAfter,
        uint256 marketFameBefore,
        uint256 payoutRecipientsBefore
    ) internal {
        assertEq(_payoutRecipientBalances(), payoutRecipientsBefore + purchase.premium);
        assertEq(fame.balanceOf(address(market)), marketFameBefore);
        assertEq(inventoryAfter, market.inventory());
        assertGe(inventoryAfter, inventoryBefore);
        assertEq(mirror.ownerAt(purchase.shellId), purchase.destination);
        assertEq(market.artworkHash(purchase.shellId), purchase.artwork);
        assertGe(mirror.balanceOf(purchase.buyer), purchase.minimum);

        if (purchase.minimum != 0) ++buyerMinimumChecks;
        ++handoffChecks;
        if (inventoryAfter < minimumObservedInventory) minimumObservedInventory = inventoryAfter;
    }

    function _payoutRecipientBalances() internal view returns (uint256 total) {
        total = fame.balanceOf(market.feeRecipient());
        uint256 providerCount = market.activeProviderCount();
        for (uint256 i; i < providerCount; ++i) {
            address provider = market.activeProviderAt(i);
            if (provider != market.feeRecipient()) total += fame.balanceOf(provider);
        }
    }

    function _observeInventory() internal {
        uint256 currentInventory = market.inventory();
        if (currentInventory < minimumObservedInventory) minimumObservedInventory = currentInventory;
    }

    function _provider(uint256 seed) internal view returns (address) {
        return _providers[seed % _providers.length];
    }

    function _firstOwnedToken(address account) internal view returns (uint256) {
        for (uint256 tokenId = 1; tokenId <= 888; ++tokenId) {
            if (mirror.ownerAt(tokenId) == account) return tokenId;
        }
        return 0;
    }

    function _buyer(uint256 seed) internal view returns (address) {
        return _buyers[seed % _buyers.length];
    }

    function _nextBuyer(uint256 seed) internal view returns (address) {
        return _buyers[((seed % _buyers.length) + 1) % _buyers.length];
    }

    function _marketShell(uint256 seed) internal view returns (uint256) {
        uint256 count = mirror.balanceOf(address(market));
        uint256 index = seed % count;
        uint256 seen;
        for (uint256 tokenId = 1; tokenId <= 888; ++tokenId) {
            if (mirror.ownerAt(tokenId) == address(market)) {
                if (seen == index) return tokenId;
                ++seen;
            }
        }
        revert("MARKET_SHELL_NOT_FOUND");
    }

    function _mintSource(uint256 seed) internal view returns (uint256) {
        uint256 start = creatorMagic.getMintPoolStart();
        uint256 end = creatorMagic.getMintPoolEnd();
        uint256 range = end - start;
        uint256 candidate = start + (seed % range);
        for (uint256 i; i < range; ++i) {
            uint256 tokenId = start + ((candidate - start + i) % range);
            if (creatorMagic.isTokenInMintPool(tokenId)) return tokenId;
        }
        revert("MINT_SOURCE_NOT_FOUND");
    }

    function _burnSource() internal view returns (uint256) {
        uint256 totalSupply = creatorMagic.getTotalNFTSupply();
        for (uint256 tokenId = 1; tokenId <= totalSupply; ++tokenId) {
            if (creatorMagic.isTokenInBurnedPool(tokenId)) return tokenId;
        }
        revert("BURN_SOURCE_NOT_FOUND");
    }
}

contract UniversalPoolArtMarketplaceInvariantTest is StdInvariant, UniversalPoolArtMarketplaceTestBase {
    UniversalPoolArtMarketplaceHandler internal handler;
    uint256 internal initialArtPoolNext;
    address internal constant PROVIDER_ONE = address(0xC001);
    address internal constant PROVIDER_TWO = address(0xC002);

    function setUp() public override {
        super.setUp();

        address burnHolder = address(0xB001);
        address ballastHolder = address(0xB002);
        uint256 unit = fame.unit();
        fame.transfer(burnHolder, 180 * unit);
        _seedShells(market, 84);
        fame.transfer(ballastHolder, 116 * unit);
        vm.prank(burnHolder);
        fame.transfer(feeRecipient, 180 * unit);
        assertTrue(creatorMagic.isTokenInBurnedPool(1));
        assertTrue(creatorMagic.isTokenInBurnedPool(180));
        _depositUnits(market, PROVIDER_ONE, 1);
        _depositUnits(market, PROVIDER_TWO, 2);

        creatorMagic.grantRoles(address(market), CREATOR_MAGIC_BANISHER_ROLE);

        address[3] memory buyers = [address(0xA001), address(0xA002), address(0xA003)];
        address[2] memory feeRecipients = [feeRecipient, address(0xF002)];
        vm.prank(feeRecipients[1]);
        fame.setSkipNFT(true);

        handler = new UniversalPoolArtMarketplaceHandler(fame, mirror, creatorMagic, market, buyers, feeRecipients);
        market.transferOwnership(address(handler));
        fame.transfer(address(handler), 400 * fame.unit());
        initialArtPoolNext = creatorMagic.artPoolNext();

        bytes4[] memory selectors = new bytes4[](10);
        selectors[0] = handler.fundBuyer.selector;
        selectors[1] = handler.purchaseHeld.selector;
        selectors[2] = handler.purchaseMint.selector;
        selectors[3] = handler.purchaseBurn.selector;
        selectors[4] = handler.purchaseAndForward.selector;
        selectors[5] = handler.configureMarket.selector;
        selectors[6] = handler.attemptInvalidPurchase.selector;
        selectors[7] = handler.depositProvider.selector;
        selectors[8] = handler.withdrawProvider.selector;
        selectors[9] = handler.depositProviderBatch.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_MarketInventoryNeverDropsBelowCampaignFloor() public view {
        assertGe(market.inventory(), handler.campaignInventoryFloor());
        assertGe(handler.minimumObservedInventory(), handler.campaignInventoryFloor());
    }

    function invariant_MarketRetainsNoPremiumRevenue() public view {
        assertEq(
            fame.balanceOf(address(market)), handler.campaignFameFloor() + market.totalProviderUnits() * fame.unit()
        );
    }

    function invariant_EverySuccessCompletedItsImmediateChecks() public view {
        uint256 purchaseSuccesses = handler.directSuccesses() + handler.mintSuccesses() + handler.burnSuccesses()
            + handler.forwardingSuccesses();
        assertEq(handler.handoffChecks(), purchaseSuccesses);
        assertEq(handler.poolPlacementChecks(), handler.mintSuccesses() + handler.burnSuccesses());
        assertEq(handler.callbackChecks(), handler.forwardingSuccesses());
    }

    function invariant_ArtPoolAndSkipPostureRemainUntouched() public view {
        assertEq(creatorMagic.artPoolNext(), initialArtPoolNext);
        assertEq(creatorMagic.rolesOf(address(market)), CREATOR_MAGIC_BANISHER_ROLE);
        assertFalse(fame.getSkipNFT(address(market)));
        // Fee recipient skipNFT is not required; market must stay non-skip.
    }

    function invariant_ProviderPositionsRemainIndexedAndCheckoutNeutral() public view {
        uint256 providerCount = market.activeProviderCount();
        assertLe(providerCount, market.activeProviderCap());
        uint256 summedUnits;
        for (uint256 i; i < providerCount; ++i) {
            address provider = market.activeProviderAt(i);
            (uint256 units, uint256 indexPlusOne) = market.providerPosition(provider);
            assertGt(units, 0);
            assertEq(indexPlusOne, i + 1);
            for (uint256 j; j < i; ++j) {
                assertNotEq(market.activeProviderAt(j), provider);
            }
            summedUnits += units;
        }
        assertEq(summedUnits, market.totalProviderUnits());
        assertLe(market.totalProviderUnits(), market.inventory());
    }

    function testHandlerExercisesEveryLane() public {
        handler.fundBuyer(0, 1);
        handler.configureMarket(1, 1, false);
        handler.purchaseHeld(0, 0, true, true);
        handler.purchaseMint(1, 0, 0, false);
        handler.purchaseBurn(2, 0, true);
        handler.purchaseAndForward(0, 0);
        handler.attemptInvalidPurchase(1, 0, 0);
        handler.depositProvider(2);
        handler.withdrawProvider(2, 0);
        handler.depositProviderBatch(0, 7);
        handler.depositProvider(3);
        handler.withdrawProvider(3, 0);

        assertGt(handler.fundingSuccesses(), 0);
        assertGt(handler.adminSuccesses(), 0);
        assertGt(handler.directSuccesses(), 0);
        assertGt(handler.mintSuccesses(), 0);
        assertGt(handler.burnSuccesses(), 0);
        assertGt(handler.forwardingSuccesses(), 0);
        assertGt(handler.expectedFailures(), 0);
        assertGt(handler.poolPlacementChecks(), 0);
        assertGt(handler.callbackChecks(), 0);
        assertGt(handler.buyerMinimumChecks(), 0);
        assertGt(handler.providerDeposits(), 0);
        assertGt(handler.providerBatchDeposits(), 0);
        assertGt(handler.withdrawals(), 0);
    }
}
