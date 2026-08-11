// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {CreatorArtistMagic} from "../src/CreatorArtistMagic.sol";
import {Fame} from "../src/Fame.sol";
import {FameMirror} from "../src/FameMirror.sol";
import {UniversalPoolArtMarketplace} from "../src/UniversalPoolArtMarketplace.sol";
import {MigrateCreatorArtistMagicV3} from "../script/MigrateCreatorArtistMagicV3.s.sol";

contract MigrateCreatorArtistMagicV3Harness is MigrateCreatorArtistMagicV3 {
    function runForTest(bool execute, bool broadcast) external returns (CutoverResult memory result) {
        result = _run(execute, broadcast);
    }

    function assertNoStaticMintPoolFrontier(address target) external view {
        _assertNoStaticMintPoolFrontier(target);
    }
}

contract StaticMintPoolFrontierMock {
    uint256 public mintPoolStartTokenId = 592;
}

contract MigrateCreatorArtistMagicV3ForkBaseTest is Test {
    MigrateCreatorArtistMagicV3Harness internal migration;

    function setUp() public {
        string memory rpc = vm.envOr("BASE_RPC", string(""));
        require(bytes(rpc).length != 0, "BASE_RPC required");
        vm.createSelectFork(rpc);
        migration = new MigrateCreatorArtistMagicV3Harness();
    }

    function testInspectionIsReadOnly() public {
        UniversalPoolArtMarketplace oldMarket = UniversalPoolArtMarketplace(migration.OLD_MARKETPLACE());
        uint256 unitsBefore = oldMarket.totalProviderUnits();

        MigrateCreatorArtistMagicV3.CutoverResult memory result = migration.runForTest(false, false);

        assertEq(address(result.creatorMagic), address(0));
        assertFalse(oldMarket.paused());
        assertEq(oldMarket.totalProviderUnits(), unitsBefore);
    }

    function testCutoverPreservesLegacyPositionAndWithdrawalStillWorks() public {
        UniversalPoolArtMarketplace oldMarket = UniversalPoolArtMarketplace(migration.OLD_MARKETPLACE());
        Fame fame = Fame(payable(migration.FAME()));
        FameMirror mirror = FameMirror(payable(migration.FAME_MIRROR()));
        address provider = migration.LEGACY_PROVIDER();

        MigrateCreatorArtistMagicV3.CutoverResult memory result = migration.runForTest(true, false);

        assertTrue(oldMarket.paused());
        assertFalse(result.marketplace.paused());
        assertEq(result.marketplace.inventory(), 0);
        assertEq(result.marketplace.totalProviderUnits(), 0);
        assertEq(result.creatorMagic.getMintPoolStart(), result.creatorMagic.getTotalNFTSupply() + 1);
        assertEq(result.creatorMagic.nextTokenId(), 651);
        assertEq(result.creatorMagic.rolesOf(provider), 2);
        assertEq(result.creatorMagic.rolesOf(address(result.marketplace)), 4);
        assertEq(result.creatorMagic.rolesOf(migration.V2()), 1);

        (uint256 providerUnits,) = oldMarket.providerPosition(provider);
        assertEq(providerUnits, 1);
        uint256 tokenId = _marketToken(mirror, address(oldMarket));
        uint256 premium = oldMarket.withdrawalPremium(provider);
        if (premium != 0) {
            address feeRecipient = oldMarket.feeRecipient();
            vm.prank(feeRecipient);
            fame.transfer(provider, premium);
            vm.prank(provider);
            fame.approve(address(oldMarket), premium);
        }

        vm.prank(provider);
        oldMarket.withdrawInventory(tokenId, premium);

        assertEq(mirror.ownerOf(tokenId), provider);
        (providerUnits,) = oldMarket.providerPosition(provider);
        assertEq(providerUnits, 0);
        assertEq(result.marketplace.totalProviderUnits(), 0);
    }

    function testCreatorCanReleaseWithoutOwningSocietyAfterCutover() public {
        MigrateCreatorArtistMagicV3.CutoverResult memory result = migration.runForTest(true, false);
        address creator = migration.CREATOR_3();
        FameMirror mirror = FameMirror(payable(migration.FAME_MIRROR()));
        assertEq(mirror.balanceOf(creator), 0);

        uint256 expectedTokenId = result.creatorMagic.nextTokenId();
        string memory metadataUri = "https://gateway.irys.xyz/v3-fork-release";
        vm.prank(creator);
        uint256 released = result.creatorMagic.releaseArtwork(expectedTokenId, metadataUri);

        assertEq(released, expectedTokenId);
        assertEq(result.creatorMagic.nextTokenId(), expectedTokenId + 1);
        assertEq(result.creatorMagic.tokenURI(expectedTokenId), metadataUri);
        assertTrue(result.creatorMagic.isTokenInMintPool(expectedTokenId));
    }

    function testReadOnlyVerifierReconcilesCompletedCutover() public {
        MigrateCreatorArtistMagicV3.CutoverResult memory result = migration.runForTest(true, false);
        vm.setEnv("BASE_CREATOR_ARTIST_MAGIC_V3_ADDRESS", vm.toString(address(result.creatorMagic)));
        vm.setEnv("BASE_UNIVERSAL_MARKETPLACE_V3_ADDRESS", vm.toString(address(result.marketplace)));
        vm.setEnv("BASE_FAME_MARKETPLACE_CHECKOUT_V3_ADDRESS", vm.toString(address(result.checkout)));

        migration.verifyDeployed();
    }

    function testBroadcastApprovalIsEnabledForFinalManifest() public view {
        assertTrue(migration.BROADCAST_APPROVED());
    }

    function testVerifierRejectsResumedStaticFrontierBytecode() public {
        StaticMintPoolFrontierMock stale = new StaticMintPoolFrontierMock();
        vm.expectRevert(
            abi.encodeWithSelector(MigrateCreatorArtistMagicV3.StaticMintPoolFrontierPresent.selector, address(stale))
        );
        migration.assertNoStaticMintPoolFrontier(address(stale));
    }

    function testInspectionRejectsAdvancedDn404FrontierEvenWhenLiveSupplyIsUnchanged() public {
        bytes32 slot = bytes32(migration.DN404_STORAGE_SLOT());
        uint256 packed = uint256(vm.load(migration.FAME(), slot));
        uint256 nextMask = uint256(type(uint32).max) << 32;
        uint256 advanced = migration.EXPECTED_DN404_PACKED_NEXT_TOKEN_ID() + 1;
        vm.store(migration.FAME(), slot, bytes32((packed & ~nextMask) | (advanced << 32)));

        vm.expectRevert(
            abi.encodeWithSelector(
                MigrateCreatorArtistMagicV3.ValueMismatch.selector,
                "DN404 packed next token",
                migration.EXPECTED_DN404_PACKED_NEXT_TOKEN_ID(),
                advanced
            )
        );
        migration.runForTest(false, false);
    }

    function _marketToken(FameMirror mirror, address market) internal view returns (uint256 tokenId) {
        for (tokenId = 1; tokenId <= 888; ++tokenId) {
            if (mirror.ownerAt(tokenId) == market) return tokenId;
        }
        revert("LEGACY_MARKET_TOKEN_NOT_FOUND");
    }
}
