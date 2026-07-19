// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {LibString} from "solady/utils/LibString.sol";
import {CreatorArtistMagic} from "../src/CreatorArtistMagic.sol";
import {MigrateCreatorArtistMagic} from "../script/MigrateCreatorArtistMagic.s.sol";

contract MigrateCreatorArtistMagicHarness is MigrateCreatorArtistMagic {
    function runForTest(bool execute, bool broadcast) external returns (address deployed) {
        deployed = address(_run(execute, broadcast));
    }
}

contract CreatorArtistMagicMigrationLegacyMock {
    using LibString for uint256;

    address public owner;
    address public fame;
    address public childRenderer;
    uint16 public nextTokenId;
    uint256 public artPoolNext;
    mapping(address => uint256) internal roles;
    mapping(uint256 => uint16) internal metadataIds;
    mapping(uint256 => string) internal tokenUris;

    function configure(address owner_, address fame_, address childRenderer_, uint16 nextTokenId_, uint256 artPoolNext_)
        external
    {
        owner = owner_;
        fame = fame_;
        childRenderer = childRenderer_;
        nextTokenId = nextTokenId_;
        artPoolNext = artPoolNext_;
    }

    function setRoles(address user, uint256 roleMask) external {
        roles[user] = roleMask;
    }

    function setTokenMetadata(uint256 tokenId, uint16 metadataId, string calldata uri) external {
        metadataIds[tokenId] = metadataId;
        tokenUris[tokenId] = uri;
    }

    function rolesOf(address user) external view returns (uint256) {
        return roles[user];
    }

    function revokeRoles(address user, uint256 roleMask) external {
        require(msg.sender == owner, "NOT_OWNER");
        roles[user] &= ~roleMask;
    }

    function getTokenMetadataId(uint256 tokenId) external view returns (uint16) {
        return metadataIds[tokenId];
    }

    function tokenURI(uint256 tokenId) external view returns (string memory) {
        if (bytes(tokenUris[tokenId]).length != 0) return tokenUris[tokenId];
        return string.concat("legacy:", tokenId.toString());
    }
}

contract CreatorArtistMagicMigrationFameMock {
    uint256 internal constant RENDERER = 1;
    uint256 internal constant METADATA = 2;

    address public renderer;
    mapping(address => uint256) internal roles;
    address[3] internal expectedCreators;
    address internal expectedLegacy;

    function configure(address renderer_, address operator, address expectedLegacy_, address[3] memory creators)
        external
    {
        renderer = renderer_;
        expectedLegacy = expectedLegacy_;
        roles[renderer_] = RENDERER;
        roles[operator] = METADATA;
        expectedCreators = creators;
    }

    function setRendererForDriftTest(address renderer_) external {
        renderer = renderer_;
    }

    function rolesOf(address user) external view returns (uint256) {
        return roles[user];
    }

    function setRenderer(address newRenderer) external {
        require(roles[msg.sender] & METADATA != 0, "NOT_METADATA");
        for (uint256 i; i < expectedCreators.length; ++i) {
            require(CreatorArtistMagic(newRenderer).rolesOf(expectedCreators[i]) == 2, "CREATORS_NOT_READY");
            require(
                CreatorArtistMagicMigrationLegacyMock(expectedLegacy).rolesOf(expectedCreators[i]) == 0,
                "LEGACY_NOT_REVOKED"
            );
        }
        roles[renderer] &= ~RENDERER;
        renderer = newRenderer;
        roles[newRenderer] |= RENDERER;
    }
}

contract MigrateCreatorArtistMagicTest is Test {
    MigrateCreatorArtistMagicHarness internal migration;
    CreatorArtistMagicMigrationLegacyMock internal legacy;
    CreatorArtistMagicMigrationFameMock internal fame;

    address internal constant OPERATOR = 0xD52E2A6bBcEba9673440e4D7843Db6713E9B6FD9;
    address internal constant CREATOR_1 = 0xF11Ce547ff948a03570B20Eac4a4d7b648693324;
    address internal constant CREATOR_2 = 0x750ea1c5ad297278665f2f8332a8876d6f95E19c;
    address internal constant CREATOR_3 = 0xaE30c908C41407877fE764B5f864eb0F5e536A72;
    address internal constant LEGACY_RENDERER_WALLET = 0x1De45d6811d6796178C0adE37516E510C1E07f77;

    function setUp() public {
        vm.chainId(8453);
        migration = new MigrateCreatorArtistMagicHarness();

        vm.etch(migration.LEGACY(), address(new CreatorArtistMagicMigrationLegacyMock()).code);
        vm.etch(migration.FAME(), address(new CreatorArtistMagicMigrationFameMock()).code);

        legacy = CreatorArtistMagicMigrationLegacyMock(migration.LEGACY());
        fame = CreatorArtistMagicMigrationFameMock(migration.FAME());

        legacy.configure(
            OPERATOR,
            migration.FAME(),
            migration.LEGACY_CHILD_RENDERER(),
            migration.EXPECTED_NEXT_TOKEN_ID(),
            migration.EXPECTED_ART_POOL_NEXT()
        );

        address[3] memory creators = [CREATOR_1, CREATOR_2, CREATOR_3];
        fame.configure(migration.LEGACY(), OPERATOR, migration.LEGACY(), creators);

        legacy.setRoles(migration.LEGACY_CHILD_RENDERER(), 1);
        legacy.setRoles(CREATOR_1, 3);
        legacy.setRoles(CREATOR_2, 3);
        legacy.setRoles(CREATOR_3, 3);
        legacy.setRoles(LEGACY_RENDERER_WALLET, 1);
        for (uint256 tokenId = 645; tokenId <= 649; ++tokenId) {
            legacy.setTokenMetadata(tokenId, uint16(tokenId - 599), migration.expectedRepairedUri(tokenId));
        }
    }

    function testDefaultModeOnlyInspects() public {
        address deployed = migration.runForTest(false, false);

        assertEq(deployed, address(0));
        assertEq(fame.renderer(), migration.LEGACY());
        assertEq(legacy.rolesOf(CREATOR_1), 3);
    }

    function testForkMigrationDeploysCutsOverAndLocksLegacy() public {
        address deployed = migration.runForTest(true, false);
        CreatorArtistMagic next = CreatorArtistMagic(deployed);

        assertTrue(deployed.code.length > 0);
        assertEq(next.owner(), OPERATOR);
        assertEq(address(next.fame()), migration.FAME());
        assertEq(address(next.childRenderer()), migration.LEGACY());
        assertEq(next.nextTokenId(), migration.EXPECTED_NEXT_TOKEN_ID());
        assertEq(next.artPoolNext(), migration.EXPECTED_ART_POOL_NEXT());
        assertEq(next.rolesOf(migration.LEGACY()), 1);
        assertEq(next.rolesOf(CREATOR_1), 2);
        assertEq(next.rolesOf(CREATOR_2), 2);
        assertEq(next.rolesOf(CREATOR_3), 2);

        assertEq(fame.renderer(), deployed);
        assertEq(fame.rolesOf(deployed), 1);
        assertEq(fame.rolesOf(migration.LEGACY()), 0);

        assertEq(legacy.rolesOf(migration.LEGACY_CHILD_RENDERER()), 0);
        assertEq(legacy.rolesOf(CREATOR_1), 0);
        assertEq(legacy.rolesOf(CREATOR_2), 0);
        assertEq(legacy.rolesOf(CREATOR_3), 0);
        assertEq(legacy.rolesOf(LEGACY_RENDERER_WALLET), 0);
    }

    function testRejectsCreatorRoleSnapshotDrift() public {
        legacy.setRoles(CREATOR_2, 1);

        vm.expectRevert(abi.encodeWithSelector(MigrateCreatorArtistMagic.LegacyRoleMismatch.selector, CREATOR_2, 3, 1));
        migration.runForTest(false, false);
    }

    function testRejectsMissingMetadataRepair() public {
        legacy.setTokenMetadata(648, 0, "broken");

        vm.expectRevert(abi.encodeWithSelector(MigrateCreatorArtistMagic.RepairPrerequisiteMismatch.selector, 648));
        migration.runForTest(false, false);
    }

    function testRejectsRendererDrift() public {
        fame.setRendererForDriftTest(address(0xBAD));

        vm.expectRevert(
            abi.encodeWithSelector(
                MigrateCreatorArtistMagic.RendererMismatch.selector, migration.LEGACY(), address(0xBAD)
            )
        );
        migration.runForTest(false, false);
    }

    function testRejectsBroadcastWithoutExecution() public {
        vm.expectRevert(MigrateCreatorArtistMagic.BroadcastFlagRequiresExecution.selector);
        migration.runForTest(false, true);
    }

    function testBroadcastApprovalGateIsEnabled() public view {
        assertTrue(migration.BROADCAST_APPROVED());
    }

    function testManifestMatchesScriptConstants() public view {
        string memory manifest =
            vm.readFile(string.concat(vm.projectRoot(), "/script/manifests/creator-artist-magic-migration-base.json"));

        assertEq(vm.parseJsonUint(manifest, ".chainId"), 8453);
        assertEq(vm.parseJsonAddress(manifest, ".contracts.fame"), migration.FAME());
        assertEq(vm.parseJsonAddress(manifest, ".contracts.legacyCreatorArtistMagic"), migration.LEGACY());
        assertEq(vm.parseJsonAddress(manifest, ".contracts.legacyChildRenderer"), migration.LEGACY_CHILD_RENDERER());
        assertEq(vm.parseJsonUint(manifest, ".expectedState.nextTokenId"), migration.EXPECTED_NEXT_TOKEN_ID());
        assertEq(vm.parseJsonUint(manifest, ".expectedState.artPoolNext"), migration.EXPECTED_ART_POOL_NEXT());

        address[3] memory creators = migration.creatorWallets();
        for (uint256 i; i < creators.length; ++i) {
            assertEq(
                vm.parseJsonAddress(manifest, string.concat(".creatorRoleAssignments[", vm.toString(i), "].address")),
                creators[i]
            );
        }

        MigrateCreatorArtistMagic.LegacyRoleRevocation[5] memory revocations = migration.legacyRoleRevocations();
        for (uint256 i; i < revocations.length; ++i) {
            string memory prefix = string.concat(".legacyRoleRevocations[", vm.toString(i), "]");
            assertEq(vm.parseJsonAddress(manifest, string.concat(prefix, ".address")), revocations[i].holder);
            assertEq(vm.parseJsonUint(manifest, string.concat(prefix, ".roleMask")), revocations[i].roleMask);
        }

        assertTrue(vm.parseJsonBool(manifest, ".broadcastApproved"));
    }
}
