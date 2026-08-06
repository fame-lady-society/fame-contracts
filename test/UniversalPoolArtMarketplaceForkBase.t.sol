// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {UniversalPoolArtMarketplace} from "../src/UniversalPoolArtMarketplace.sol";
import {CreatorArtistMagic} from "../src/CreatorArtistMagic.sol";
import {Fame} from "../src/Fame.sol";
import {FameMirror} from "../src/FameMirror.sol";

abstract contract UniversalPoolArtMarketplaceForkBaseTestBase is Test {
    uint256 internal constant BASE_CHAIN_ID = 8453;
    uint256 internal constant BANISHER_ROLE = 1 << 2;
    uint256 internal constant EXPECTED_UNIT = 1_000_000 ether;
    uint256 internal constant EXPECTED_PREMIUM = 30_000 ether;

    address internal constant EXPECTED_FAME = 0xf307e242BfE1EC1fF01a4Cef2fdaa81b10A52418;
    address internal constant EXPECTED_MIRROR = 0xBB5ED04dD7B207592429eb8d599d103CCad646c4;
    address internal constant EXPECTED_CREATOR_MAGIC = 0xC8268c2aa571F3C88044C2959F73DdB8eB9e139F;
    address internal constant EXPECTED_CHILD_RENDERER = 0x8091D00A25ebE87A2A1Ef19e1d33689FCAdC3fA5;
    address internal constant DEPLOYER = 0xD52E2A6bBcEba9673440e4D7843Db6713E9B6FD9;
    address internal constant SAFE = 0xC952C53D8B63919e372caa2E6FEe605ee24E4D3D;

    address internal constant BUYER_ONE = address(0xB001);
    address internal constant BUYER_TWO = address(0xB002);
    address internal constant HELD_RECIPIENT = address(0xCA01);
    address internal constant MINT_RECIPIENT = address(0xCA02);
    address internal constant BURN_RECIPIENT = address(0xCA03);
    address internal constant DISTINCT_RECIPIENT = address(0xCA04);
    bytes32 internal constant ARTWORK_PURCHASED_TOPIC =
        keccak256("ArtworkPurchased(address,address,uint256,uint8,uint256,bytes32,uint256,uint256,uint256,uint256)");

    Fame internal fame;
    FameMirror internal mirror;
    CreatorArtistMagic internal creatorMagic;

    error MissingBaseRpc();
    error PoolCandidateUnavailable(string pool);

    function _selectLatestBaseFork() internal returns (uint256 forkBlock, bytes32 forkHash) {
        string memory rpc = vm.envOr("BASE_RPC", string(""));
        if (bytes(rpc).length == 0) revert MissingBaseRpc();

        vm.createSelectFork(rpc);
        assertEq(block.chainid, BASE_CHAIN_ID, "wrong fork chain");

        forkBlock = block.number;
        vm.roll(forkBlock + 1);
        forkHash = blockhash(forkBlock);
        vm.roll(forkBlock);
        assertNotEq(forkHash, bytes32(0), "latest Base block hash unavailable");
        assertEq(block.number, forkBlock, "selected Base block drift");

        emit log_named_uint("latest Base fork block", forkBlock);
        emit log_named_bytes32("latest Base fork hash", forkHash);

        fame = Fame(payable(vm.envAddress("BASE_FAME_ADDRESS")));
        mirror = FameMirror(payable(vm.envAddress("BASE_FAME_NFT_ADDRESS")));
        creatorMagic = CreatorArtistMagic(vm.envAddress("BASE_CREATOR_ARTIST_MAGIC_ADDRESS"));

        assertEq(address(fame), EXPECTED_FAME, "FAME address drift");
        assertEq(address(mirror), EXPECTED_MIRROR, "mirror address drift");
        assertEq(address(creatorMagic), EXPECTED_CREATOR_MAGIC, "CreatorMagic address drift");
        assertEq(address(fame.fameMirror()), address(mirror), "FAME mirror drift");
        assertEq(address(fame.renderer()), address(creatorMagic), "FAME renderer drift");
        assertEq(address(creatorMagic.fame()), address(fame), "CreatorMagic FAME drift");
        assertEq(address(creatorMagic.childRenderer()), EXPECTED_CHILD_RENDERER, "child renderer drift");
        assertEq(creatorMagic.owner(), DEPLOYER, "CreatorMagic owner drift");
        assertEq(fame.name(), "Society", "FAME name drift");
        assertEq(fame.symbol(), "FAME", "FAME symbol drift");
        assertEq(fame.unit(), EXPECTED_UNIT, "FAME unit drift");
        // Fee recipient skipNFT is optional; no assertion required.
    }

    function _deployOneShellMarket() internal returns (UniversalPoolArtMarketplace market) {
        vm.prank(DEPLOYER, DEPLOYER);
        market = new UniversalPoolArtMarketplace(
            payable(address(fame)), address(creatorMagic), EXPECTED_PREMIUM, 0, SAFE, DEPLOYER, 16
        );

        _seedOneShellMarket(market);
    }

    function _seedOneShellMarket(UniversalPoolArtMarketplace market) internal {
        uint256 unit = fame.unit();
        uint256 safeBefore = fame.balanceOf(SAFE);
        uint256 deployerBefore = fame.balanceOf(DEPLOYER);

        vm.prank(SAFE);
        fame.transfer(DEPLOYER, unit);
        assertEq(safeBefore - fame.balanceOf(SAFE), unit, "fixture transfer was not one unit");
        assertEq(fame.balanceOf(DEPLOYER) - deployerBefore, unit, "deployer did not receive one unit");

        vm.startPrank(DEPLOYER);
        creatorMagic.grantRoles(address(market), BANISHER_ROLE);
        fame.transfer(address(market), unit);
        vm.stopPrank();

        assertEq(market.owner(), DEPLOYER);
        assertEq(market.feeRecipient(), SAFE);
        assertEq(market.premium(), EXPECTED_PREMIUM);
        assertTrue(market.paused());
        assertEq(market.inventory(), 1, "market must start with one shell");
        assertEq(fame.balanceOf(address(market)), unit, "market seed must be one unit");
        assertTrue(creatorMagic.hasAnyRole(address(market), BANISHER_ROLE));
    }

    function _fundAndApprove(address account, UniversalPoolArtMarketplace market, uint256 amount) internal {
        vm.prank(account);
        fame.setSkipNFT(true);
        vm.prank(SAFE);
        fame.transfer(account, amount);
        vm.prank(account);
        fame.approve(address(market), amount);
    }

    function _findBurnPoolToken() internal view returns (uint256) {
        for (uint256 tokenId = 1; tokenId <= 888; ++tokenId) {
            if (creatorMagic.isTokenInBurnedPool(tokenId)) return tokenId;
        }
        revert PoolCandidateUnavailable("Burn");
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

    function _ownedTokenIds(address account, uint256 count) internal view returns (uint256[] memory tokenIds) {
        tokenIds = new uint256[](count);
        uint256 found;
        for (uint256 tokenId = 1; tokenId <= 888 && found < count; ++tokenId) {
            if (mirror.ownerAt(tokenId) == account) tokenIds[found++] = tokenId;
        }
        if (found != count) revert PoolCandidateUnavailable("owned shells");
    }

    function _purchaseEventCount(Vm.Log[] memory logs, address market) internal pure returns (uint256 count) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == market && logs[i].topics.length != 0 && logs[i].topics[0] == ARTWORK_PURCHASED_TOPIC)
            {
                ++count;
            }
        }
    }

    function _revertSelector(bytes memory revertData) internal pure returns (bytes4 selector) {
        if (revertData.length < 4) return bytes4(0);
        assembly {
            selector := mload(add(revertData, 0x20))
        }
    }

    function _purchaseHeldPath(UniversalPoolArtMarketplace market, uint256 premium) internal {
        uint256 shellId = _ownedTokenAt(address(market), 0);
        bytes32 artwork = market.artworkHash(shellId);
        vm.recordLogs();
        vm.prank(BUYER_ONE);
        market.purchaseHeld(shellId, artwork, premium, 0, HELD_RECIPIENT);
        assertEq(_purchaseEventCount(vm.getRecordedLogs(), address(market)), 1, "held event mismatch");
        assertEq(mirror.ownerAt(shellId), HELD_RECIPIENT, "held recipient mismatch");
        assertEq(market.inventory(), 1, "held path lost the one shell");
    }

    function _purchaseMintPath(UniversalPoolArtMarketplace market, uint256 premium) internal {
        uint256 shellId = _ownedTokenAt(address(market), 0);
        uint256 sourceId = _findMintPoolToken();
        bytes32 artwork = market.artworkHash(sourceId);
        vm.recordLogs();
        vm.prank(BUYER_ONE);
        market.purchasePool(shellId, sourceId, artwork, premium, 0, MINT_RECIPIENT);
        assertEq(_purchaseEventCount(vm.getRecordedLogs(), address(market)), 1, "Mint event mismatch");
        assertEq(mirror.ownerAt(shellId), MINT_RECIPIENT, "Mint recipient mismatch");
        assertEq(market.artworkHash(shellId), artwork, "Mint artwork mismatch");
        assertEq(market.inventory(), 1, "Mint path lost the one shell");
    }

    function _purchaseBurnPath(UniversalPoolArtMarketplace market, uint256 premium) internal {
        uint256 sourceId = _findBurnPoolToken();
        uint256 shellId = _ownedTokenAt(address(market), 0);
        bytes32 artwork = market.artworkHash(sourceId);
        vm.recordLogs();
        vm.prank(BUYER_ONE);
        market.purchasePool(shellId, sourceId, artwork, premium, 0, BURN_RECIPIENT);
        assertEq(_purchaseEventCount(vm.getRecordedLogs(), address(market)), 1, "Burn event mismatch");
        assertEq(mirror.ownerAt(shellId), BURN_RECIPIENT, "Burn recipient mismatch");
        assertEq(market.artworkHash(shellId), artwork, "Burn artwork mismatch");
        assertEq(market.inventory(), 1, "Burn path lost the one shell");
    }

    function _assertArtPoolRejected(UniversalPoolArtMarketplace market, uint256 premium) internal {
        uint256 shellId = _ownedTokenAt(address(market), 0);
        uint256 sourceId = creatorMagic.artPoolStartIndex();
        bytes32 artwork = market.artworkHash(sourceId);
        uint256 feeBefore = fame.balanceOf(SAFE);
        vm.expectRevert(abi.encodeWithSelector(UniversalPoolArtMarketplace.ArtPoolSourceExcluded.selector, sourceId));
        vm.prank(BUYER_ONE);
        market.purchasePool(shellId, sourceId, artwork, premium, 0, DISTINCT_RECIPIENT);
        assertEq(fame.balanceOf(SAFE), feeBefore, "Art Pool rejection charged a fee");
        assertEq(market.inventory(), 1, "Art Pool rejection changed inventory");
    }
}

contract UniversalPoolArtMarketplaceForkBaseTest is UniversalPoolArtMarketplaceForkBaseTestBase {
    function testBenchmarkLatestBaseFreeExitTraversesFull888IdScan() public {
        _selectLatestBaseFork();
        uint256 candidateCap = vm.envUint("BASE_UNIVERSAL_MARKETPLACE_BENCHMARK_CANDIDATE_CAP");
        uint256 gasBudget = vm.envUint("BASE_UNIVERSAL_MARKETPLACE_FREE_EXIT_GAS_BUDGET");
        UniversalPoolArtMarketplace market;
        vm.prank(DEPLOYER, DEPLOYER);
        market = new UniversalPoolArtMarketplace(
            payable(address(fame)), address(creatorMagic), 0, 0, SAFE, DEPLOYER, candidateCap
        );

        address provider = address(0xBEEF01);
        uint256 unit = fame.unit();
        vm.prank(SAFE);
        fame.transfer(provider, unit);
        uint256 depositedId = _ownedTokenAt(provider, 0);
        vm.startPrank(provider);
        mirror.approve(address(market), depositedId);
        market.depositInventory(depositedId);
        vm.stopPrank();

        uint256 wantedStart = depositedId == 888 ? 1 : depositedId + 1;
        bytes32 selectedRandao;
        for (uint256 seed = 1; seed < 100_000; ++seed) {
            bytes32 candidate = bytes32(seed);
            if (uint256(keccak256(abi.encode(candidate, provider, uint256(0), uint256(0)))) % 888 + 1 == wantedStart) {
                selectedRandao = candidate;
                break;
            }
        }
        assertNotEq(selectedRandao, bytes32(0), "full-scan randao fixture unavailable");
        vm.prevrandao(selectedRandao);

        vm.recordLogs();
        uint256 gasBefore = gasleft();
        vm.prank(provider);
        uint256 withdrawnId = market.withdrawInventory();
        uint256 gasUsed = gasBefore - gasleft();

        emit log_named_uint("candidate active-provider cap", candidateCap);
        emit log_named_uint("full 888-ID free-exit gas", gasUsed);
        emit log_named_uint("Base block gas limit", block.gaslimit);
        assertEq(withdrawnId, depositedId, "full-scan exit selected wrong live unit");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 withdrawalTopic = keccak256("InventoryWithdrawn(address,uint256,bool,uint256,uint256,uint256)");
        uint256 scanSteps;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(market) && logs[i].topics[0] == withdrawalTopic) {
                (,,, scanSteps) = abi.decode(logs[i].data, (bool, uint256, uint256, uint256));
            }
        }
        assertEq(scanSteps, 888, "free-exit benchmark did not traverse all Society IDs");
        assertLt(gasUsed, gasBudget, "full-scan free exit exceeds configured gas budget");
        assertLt(gasUsed, (block.gaslimit * 8) / 10, "full-scan free exit lacks Base gas headroom");
    }

    function testLatestBaseOneShellHeldMintBurnAndArtPoolMatrix() public {
        _selectLatestBaseFork();
        UniversalPoolArtMarketplace market = _deployOneShellMarket();
        uint256 unit = fame.unit();
        uint256 premium = market.premium();
        _fundAndApprove(BUYER_ONE, market, 3 * (unit + premium));

        vm.prank(DEPLOYER);
        market.unpause();

        uint256 feeBefore = fame.balanceOf(SAFE);
        _purchaseHeldPath(market, premium);
        _purchaseMintPath(market, premium);
        _purchaseBurnPath(market, premium);
        assertEq(fame.balanceOf(SAFE) - feeBefore, 3 * premium, "premium routing mismatch");
        _assertArtPoolRejected(market, premium);
    }

    function testLatestBaseRejectsPausedStaleArtworkPremiumAndShellRaces() public {
        _selectLatestBaseFork();
        UniversalPoolArtMarketplace market = _deployOneShellMarket();
        uint256 shellId = _ownedTokenAt(address(market), 0);
        bytes32 artwork = market.artworkHash(shellId);
        uint256 originalPremium = market.premium();
        _fundAndApprove(BUYER_ONE, market, 3 * (fame.unit() + originalPremium));

        vm.expectRevert(UniversalPoolArtMarketplace.PurchasesPaused.selector);
        vm.prank(BUYER_ONE);
        market.purchaseHeld(shellId, artwork, originalPremium, 0, DISTINCT_RECIPIENT);

        vm.prank(DEPLOYER);
        market.unpause();
        bytes32 staleArtwork = bytes32(uint256(artwork) ^ 1);
        vm.expectRevert(
            abi.encodeWithSelector(UniversalPoolArtMarketplace.ArtworkMismatch.selector, shellId, staleArtwork, artwork)
        );
        vm.prank(BUYER_ONE);
        market.purchaseHeld(shellId, staleArtwork, originalPremium, 0, DISTINCT_RECIPIENT);

        vm.prank(DEPLOYER);
        market.setCommunityFee(originalPremium + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                UniversalPoolArtMarketplace.PremiumExceedsMaximum.selector, originalPremium + 1, originalPremium
            )
        );
        vm.prank(BUYER_ONE);
        market.purchaseHeld(shellId, artwork, originalPremium, 0, DISTINCT_RECIPIENT);

        uint256 lowerPremium = originalPremium / 2;
        vm.prank(DEPLOYER);
        market.setCommunityFee(lowerPremium);
        uint256 feeBefore = fame.balanceOf(SAFE);
        vm.prank(BUYER_ONE);
        market.purchaseHeld(shellId, artwork, originalPremium, 0, DISTINCT_RECIPIENT);
        assertEq(fame.balanceOf(SAFE) - feeBefore, lowerPremium, "decreased premium was not used");
        assertEq(mirror.ownerAt(shellId), DISTINCT_RECIPIENT, "distinct recipient did not receive shell");
        assertEq(market.inventory(), 1, "successful stale-max purchase lost inventory");

        vm.expectRevert(abi.encodeWithSelector(UniversalPoolArtMarketplace.UnavailableShell.selector, shellId));
        vm.prank(BUYER_ONE);
        market.purchaseHeld(shellId, artwork, originalPremium, 0, BUYER_ONE);

        uint256 replacementShell = _ownedTokenAt(address(market), 0);
        bytes32 replacementArtwork = market.artworkHash(replacementShell);
        vm.prank(DEPLOYER);
        market.pause();
        vm.expectRevert(UniversalPoolArtMarketplace.PurchasesPaused.selector);
        vm.prank(BUYER_ONE);
        market.purchaseHeld(replacementShell, replacementArtwork, originalPremium, 0, DISTINCT_RECIPIENT);
        assertEq(fame.balanceOf(SAFE) - feeBefore, lowerPremium, "failed races charged additional fees");
        assertEq(market.inventory(), 1, "failed races changed inventory");
    }
}
