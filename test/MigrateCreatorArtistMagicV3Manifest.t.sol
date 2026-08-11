// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MigrateCreatorArtistMagicV3} from "../script/MigrateCreatorArtistMagicV3.s.sol";

contract MigrateCreatorArtistMagicV3ManifestTest is Test {
    MigrateCreatorArtistMagicV3 internal migration;

    function setUp() public {
        migration = new MigrateCreatorArtistMagicV3();
    }

    function testManifestMatchesPinnedCutoverState() public view {
        string memory manifest =
            vm.readFile(string.concat(vm.projectRoot(), "/script/manifests/creator-artist-magic-v3-base.json"));

        assertEq(vm.parseJsonUint(manifest, ".chainId"), migration.BASE_CHAIN_ID());
        assertEq(vm.parseJsonAddress(manifest, ".contracts.fame"), migration.FAME());
        assertEq(vm.parseJsonAddress(manifest, ".contracts.fameMirror"), migration.FAME_MIRROR());
        assertEq(vm.parseJsonAddress(manifest, ".contracts.creatorArtistMagicV2"), migration.V2());
        assertEq(vm.parseJsonAddress(manifest, ".contracts.legacyMarketplace"), migration.OLD_MARKETPLACE());
        assertEq(vm.parseJsonAddress(manifest, ".contracts.legacyCheckout"), migration.OLD_CHECKOUT());
        assertEq(vm.parseJsonUint(manifest, ".pinnedState.nextTokenId"), migration.EXPECTED_NEXT_TOKEN_ID());
        assertEq(vm.parseJsonUint(manifest, ".pinnedState.artPoolNext"), migration.EXPECTED_ART_POOL_NEXT());
        assertEq(
            vm.parseJsonUint(manifest, ".pinnedState.dn404TotalNftSupply"), migration.EXPECTED_DN404_TOTAL_NFT_SUPPLY()
        );
        assertEq(vm.parseJsonString(manifest, ".poolClassification.mode"), "v2-live-total-nft-supply-best-effort");
        assertTrue(vm.parseJsonBool(manifest, ".poolClassification.advancesWithFreshMints"));
        assertTrue(vm.parseJsonBool(manifest, ".poolClassification.canMoveBackwardAfterBurns"));
        assertFalse(vm.parseJsonBool(manifest, ".poolClassification.historicalMintClassificationExact"));
        assertEq(
            vm.parseJsonUint(manifest, ".cutoverGuards.dn404PackedNextTokenId"),
            migration.EXPECTED_DN404_PACKED_NEXT_TOKEN_ID()
        );
        assertEq(
            vm.parseJsonUint(manifest, ".predictedContracts.operatorStartingNonce"), migration.EXPECTED_OPERATOR_NONCE()
        );
        assertEq(
            vm.parseJsonAddress(manifest, ".predictedContracts.creatorArtistMagicV3"),
            migration.EXPECTED_CREATOR_MAGIC_V3()
        );
        assertEq(
            vm.parseJsonAddress(manifest, ".predictedContracts.replacementMarketplace"),
            migration.EXPECTED_MARKETPLACE_V3()
        );
        assertEq(
            vm.parseJsonAddress(manifest, ".predictedContracts.replacementCheckout"), migration.EXPECTED_CHECKOUT_V3()
        );
        assertEq(vm.parseJsonAddress(manifest, ".pinnedState.legacyProvider"), migration.LEGACY_PROVIDER());
        assertEq(vm.parseJsonUint(manifest, ".pinnedState.legacyProviderUnits"), 1);
        assertFalse(vm.parseJsonBool(manifest, ".providerMigration"));
        assertFalse(vm.parseJsonBool(manifest, ".broadcastApproved"));

        address[3] memory creators = migration.creatorWallets();
        for (uint256 i; i < creators.length; ++i) {
            assertEq(vm.parseJsonAddress(manifest, string.concat(".roles.creators[", vm.toString(i), "]")), creators[i]);
        }
    }
}
